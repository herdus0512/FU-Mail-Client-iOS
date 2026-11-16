import Foundation
import Observation

/// How long to wait before reconnecting: 1 s, doubling, at most 30 s (as the Mac's remote mode).
public struct Backoff: Sendable {
    public var first: Duration
    public var max: Duration

    public init(first: Duration = .seconds(1), max: Duration = .seconds(30)) {
        self.first = first
        self.max = max
    }

    public func next(after current: Duration) -> Duration { Swift.min(current * 2, max) }
}

/// Uses the Mac's FU Mail through its API. `state` is a copy of the Mac's state kept up to date from
/// the event stream, which is open between `start()` and `stop()` (the app on screen). Mirrors the
/// Mac's `RemoteBackend` and the Android app's `RemoteClient`; like Android, text typed into a card's
/// sheet or the draft editor is sent once (Done, Write, Save), never while typing.
@MainActor
@Observable
public final class RemoteClient {
    public private(set) var state = RemoteState()

    /// The Mac's API, at the address in Settings.
    @ObservationIgnored public let transport: any DesktopTransport
    @ObservationIgnored private let backoff: Backoff
    @ObservationIgnored private let typedHold: Duration
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    /// Set by `close()`: this connection is finished (Settings changed); nothing more is sent or shown.
    @ObservationIgnored private var closed = false
    /// Card actions and typed text go out one at a time, in order (Done, then Insert).
    @ObservationIgnored private var actionChain: Task<Void, Never>?

    public var display: String { transport.display }

    public init(transport: any DesktopTransport, backoff: Backoff = Backoff(), typedHold: Duration = .seconds(1),
                now: @escaping @Sendable () -> Date = { .now }) {
        self.transport = transport
        self.backoff = backoff
        self.typedHold = typedHold
        self.now = now
    }

    // MARK: Connection

    /// Opens the event stream (the app came on screen), fetching everything shown once it's open.
    public func start() {
        guard !closed, eventsTask == nil else { return }
        eventsTask = Task { await runEvents() }
    }

    /// Closes the event stream (the app went to the background). The copy is kept, and fetched again on `start()`.
    public func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        state.connection.connected = false
    }

    /// This connection is finished (Settings changed).
    public func close() {
        closed = true
        stop()
        actionChain?.cancel()
    }

    private func runEvents() async {
        var pause = backoff.first
        while !Task.isCancelled, !closed {
            do {
                for try await item in transport.events() {
                    switch item {
                    case .opened:
                        // Anything that changed while disconnected: fetch it now that events will follow.
                        await resync()
                        if !Task.isCancelled { state.connection.connected = true }
                        pause = backoff.first
                    case .data(let text):
                        receive(text)
                    }
                }
                throw RemoteProblem(.unreachable, "The connection to \(display) closed.")
            } catch {
                if Task.isCancelled || closed { break }
                state.connection.connected = false
                state.connection.problem = Problems.describe(error, url: display).message
                try? await Task.sleep(for: pause)
                pause = backoff.next(after: pause)
            }
        }
    }

    /// One event's data from the stream. Events this version can't read are skipped.
    func receive(_ text: String) {
        guard let event = try? APICoding.decoder.decode(APIEvent.self, from: Data(text.utf8)) else { return }
        apply(event)
    }

    func apply(_ event: APIEvent) {
        guard !closed else { return }
        for effect in state.apply(event) {
            switch effect {
            case .refreshList: run(quiet: true) { try await self.refreshList() }
            case .refreshInfo:
                run(quiet: true) {
                    try await self.refreshInfo()
                    try await self.refreshCommands()
                }
            }
        }
    }

    /// The details, the conversation list, every loaded conversation, and this device's draft editors.
    private func resync() async {
        do {
            try await refreshInfo()
            state.connection.problem = nil
            try await refreshList()
            for id in state.conversations.map(\.id) where !state.unloaded.contains(id) {
                try await fetchConversation(id)
            }
            let editors = try await get([EditorState].self, "/v1/editors")
            update { $0.setEditors(editors) }
            try await refreshCommands()
        } catch is CancellationError {
        } catch {
            update { $0.connection.problem = Problems.describe(error, url: display).message }
        }
    }

    /// The slash commands. A Mac from before `/v1/commands` answers 404: no suggestions then.
    private func refreshCommands() async throws {
        let commands: [Command]
        do {
            commands = try await get([Command].self, "/v1/commands")
        } catch let problem as RemoteProblem where problem.kind == .notFound {
            commands = []
        }
        update { $0.commands = commands }
    }

    private func refreshInfo() async throws {
        let info = try await get(APIInfo.self, "/v1/info")
        update { $0.setInfo(info) }
    }

    private func refreshList() async throws {
        let items = try await get([ConversationListItem].self, "/v1/conversations")
        update { $0.setList(items) }
    }

    private func fetchConversation(_ id: Conversation.ID) async throws {
        let detail = try await get(ConversationDetail.self, "/v1/conversations/\(id.uuidString)")
        update { $0.setDetail(detail) }
    }

    private func update(_ change: (inout RemoteState) -> Void) {
        guard !closed else { return }
        change(&state)
    }

    /// Runs a request in the background. A failure shows in the banner, or goes to `onFailure`; with
    /// `quiet`, a failure is dropped (the next resync fetches it anyway).
    @discardableResult
    private func run(quiet: Bool = false, onFailure: (@MainActor (String) -> Void)? = nil,
                     _ work: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        Task { await perform(quiet: quiet, onFailure: onFailure, work) }
    }

    private func perform(quiet: Bool = false, onFailure: (@MainActor (String) -> Void)? = nil,
                         _ work: @MainActor () async throws -> Void) async {
        do {
            try await work()
            // A request worked: a banner left over from an earlier one is stale once the stream is up.
            update { if $0.connection.connected { $0.connection.problem = nil } }
        } catch is CancellationError {
        } catch {
            guard !closed, !quiet else { return }
            let message = Problems.describe(error, url: display).message
            if let onFailure { onFailure(message) } else { update { $0.connection.problem = message } }
        }
    }

    /// Runs `work` after every action queued before it.
    private func enqueue(_ work: @escaping @MainActor () async throws -> Void) {
        let previous = actionChain
        actionChain = Task {
            await previous?.value
            await perform(work)
        }
    }

    /// Clears the banner (the user dismissed it).
    public func dismissProblem() {
        update { $0.connection.problem = nil }
    }

    // MARK: Conversations

    /// Fetches a saved conversation's messages the first time it's opened.
    public func loadMessages(_ id: Conversation.ID) {
        guard state.unloaded.contains(id) else { return }
        run { try await self.fetchConversation(id) }
    }

    /// A new chat (or the empty one there already is). nil when it couldn't be made (the banner says why).
    public func startConversation() async -> Conversation.ID? {
        if let empty = state.conversations.first(where: { $0.messages.isEmpty && !state.unloaded.contains($0.id) }) {
            return empty.id
        }
        do {
            let created = try await transport.send("POST", "/v1/conversations", body: nil)
            guard let id = (try? JSONValue.parse(created))?["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                throw RemoteProblem(.badResponse, "\(display) didn't say which chat it made.")
            }
            update { $0.addConversation(id, now: now()) }
            return id
        } catch {
            update { $0.connection.problem = Problems.describe(error, url: display).message }
            return nil
        }
    }

    public func delete(_ id: Conversation.ID) {
        update { $0.removeConversation(id) }
        run { _ = try await self.transport.send("DELETE", "/v1/conversations/\(id.uuidString)", body: nil) }
    }

    public func rename(_ id: Conversation.ID, to title: String) {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmed.isEmpty, state.conversation(id) != nil else { return }
        update { $0.rename(id, to: trimmed) }
        run { _ = try await self.post("PATCH", "/v1/conversations/\(id.uuidString)", ["title": .string(trimmed)]) }
    }

    /// What was typed in the composer: a slash command or a question.
    public func send(_ text: String, in id: Conversation.ID) {
        expectReply(in: id)
        run { _ = try await self.post("POST", "/v1/conversations/\(id.uuidString)/send", ["text": .string(text)]) }
    }

    /// Conversations where something was just asked for here (an email opened, a command sent, Add to
    /// note…), and when: the chat shows what arrives next even if it was scrolled up.
    @ObservationIgnored private var expecting: [Conversation.ID: Date] = [:]

    private func expectReply(in id: Conversation.ID) {
        expecting[id] = now()
    }

    /// Whether a new message in `id` answers something asked for here in the last 30 seconds. Answers
    /// once: the next message after it is shown only if the chat is following.
    public func takeExpectedReply(in id: Conversation.ID) -> Bool {
        guard let asked = expecting.removeValue(forKey: id) else { return false }
        return now().timeIntervalSince(asked) < 30
    }

    public func stopAnswering(in id: Conversation.ID) {
        run { _ = try await self.transport.send("POST", "/v1/conversations/\(id.uuidString)/stop", body: nil) }
    }

    /// A list row: opens the email in the chat.
    public func openEmail(_ ref: EmailRef, in id: Conversation.ID) {
        expectReply(in: id)
        run { _ = try await self.post("POST", "/v1/conversations/\(id.uuidString)/open", ["ref": try APICoding.body(ref)]) }
    }

    /// A drafts-list row: opens the draft in the chat.
    public func openDraft(_ draft: DraftSummary, in id: Conversation.ID) {
        expectReply(in: id)
        run { _ = try await self.post("POST", "/v1/conversations/\(id.uuidString)/open", ["draft": try APICoding.body(draft)]) }
    }

    // MARK: Cards

    public func cardAction(_ action: CardAction, on messageID: ChatMessage.ID, in id: Conversation.ID) {
        switch action {
        case .crmRewrite:
            // The rewrite streams into the card's text: what was typed before mustn't cover it.
            update { $0.typed[messageID]?.crmText = nil }
        case .addToNotes, .addTask, .noteViewPostCRM:
            expectReply(in: id)  // each adds a new card below
        default:
            break
        }
        enqueue { try await self.postAction(action, on: messageID, in: id) }
    }

    /// Open in browser on a draft card: the link to open, or nil (no link, or the draft is gone). A
    /// Google Mail link goes stale whenever the draft is saved, so the Mac fetches the draft again
    /// first (`refresh_draft`): this waits until the card has been busy and isn't any more, or the
    /// card changed, at most `timeout`, or `noBusyAfter` when it never goes busy (a Mac before 3.4.0),
    /// and then gives the card's link as it is by then. Other links come back at once.
    public func draftLinkToOpen(on messageID: ChatMessage.ID, in id: Conversation.ID, timeout: Duration = .seconds(5),
                                noBusyAfter: Duration = .milliseconds(1500)) async -> URL? {
        func draft() -> DraftCard? {
            guard case .draft(let card) = state.conversation(id)?.messages.first(where: { $0.id == messageID })?.card
            else { return nil }
            return card
        }
        guard let before = draft(), before.gone != true else { return nil }
        guard before.hasGmailLink else { return before.link.flatMap(URL.init(string:)) }
        cardAction(.refreshDraft, on: messageID, in: id)
        let clock = ContinuousClock()
        let started = clock.now
        var wasBusy = false
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            let busy = state.busyMessages.contains(messageID)
            wasBusy = wasBusy || busy
            if (wasBusy && !busy) || draft() != before { break }
            let waited = clock.now - started
            if waited >= timeout || (!wasBusy && waited >= noBusyAfter) { break }
        }
        guard let after = draft(), after.gone != true else { return nil }
        return after.link.flatMap(URL.init(string:))
    }

    /// Done in a notes card's Edit sheet: the entry's heading and lines.
    public func editNoteEntry(heading: String, body: String, on messageID: ChatMessage.ID, in id: Conversation.ID) {
        sendTyped(TypedEdit(heading: heading, body: body), .editNoteEntry(heading: heading, body: body), on: messageID, in: id)
    }

    /// Done in a suggested note's Edit sheet.
    public func updateSuggestion(_ text: String, on messageID: ChatMessage.ID, in id: Conversation.ID) {
        sendTyped(TypedEdit(suggestion: text), .updateSuggestion(text), on: messageID, in: id)
    }

    /// Done in a CRM card's Edit sheet.
    public func setCRMText(_ text: String, on messageID: ChatMessage.ID, in id: Conversation.ID) {
        sendTyped(TypedEdit(crmText: text), .crmSetText(text), on: messageID, in: id)
    }

    /// Shows typed text at once and sends it; it keeps showing a moment longer, until the Mac has caught up.
    private func sendTyped(_ edit: TypedEdit, _ action: CardAction, on messageID: ChatMessage.ID, in id: Conversation.ID) {
        update { $0.type(edit, on: messageID, in: id) }
        enqueue { try await self.postAction(action, on: messageID, in: id) }
        Task {
            await actionChain?.value
            try? await Task.sleep(for: typedHold)
            update { if $0.typed[messageID] == edit { $0.typed[messageID] = nil } }
        }
    }

    private func postAction(_ action: CardAction, on messageID: ChatMessage.ID, in id: Conversation.ID) async throws {
        _ = try await transport.send("POST", "/v1/conversations/\(id.uuidString)/messages/\(messageID.uuidString)/action",
                                     body: Data(action.json.serialized().utf8))
    }

    /// Every note in the configured folders, for "None of these…" on a notes card.
    public func vaultNotes() async throws -> [NoteFile] { try await get([NoteFile].self, "/v1/notes/vault") }

    /// Every note CRM updates can go in, for "None of these…" on a CRM card.
    public func crmNotes() async throws -> [NoteFile] { try await get([NoteFile].self, "/v1/crm/notes") }

    public func searchHistory(_ query: String) async throws -> [SearchHit] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        // Everything but letters and digits encoded, so `&`, `+` and `=` stay part of the words.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return try await get([SearchHit].self, "/v1/history/search?q=\(encoded)")
    }

    /// The obsidian:// link for a note, when the Mac says which vault it's in.
    public func obsidianURL(_ path: String) -> URL? {
        state.info?.obsidianVault.flatMap { Notes.obsidianURL(path: path, vault: $0) }
    }

    /// `GET /health`, then `GET /v1/info`: what Settings' Test shows. Throws a `RemoteProblem` saying
    /// which one failed (the address, or the token).
    public static func check(_ transport: any DesktopTransport) async throws -> APIInfo {
        try await transport.health()
        do {
            return try APICoding.decoder.decode(APIInfo.self, from: try await transport.send("GET", "/v1/info", body: nil))
        } catch {
            throw Problems.describe(error, url: transport.display)
        }
    }

    // MARK: Draft editors

    /// What's typed into the editor stays here until Write, Reply all or Save.
    public func editForm(_ editorID: UUID, _ change: (inout DraftForm) -> Void) {
        update { $0.editor(editorID) { change(&$0.form) } }
    }

    public func editInstructions(_ editorID: UUID, _ text: String) {
        update { $0.editor(editorID) { $0.instructions = text } }
    }

    /// Writes (or rewrites) the body with the instructions. `form` and `instructions`, when given, are
    /// what the editor screen has typed (it may keep its own copy while typing); else the copy here.
    public func write(_ editorID: UUID, form: DraftForm? = nil, instructions: String? = nil) {
        guard let editor = typedInto(editorID, form, instructions), !editor.status.isBusy else { return }
        update { $0.editor(editorID) { $0.status = .writing(display) } }
        run(onFailure: { self.failed(editorID, $0) }) {
            _ = try await self.post("POST", "/v1/editors/\(editorID.uuidString)/write", try Self.edits(editor))
        }
    }

    /// Reply all on or off; the Mac fills in Cc.
    public func setReplyAll(_ editorID: UUID, _ on: Bool) {
        update { $0.editor(editorID) { $0.form.replyAll = on } }
        run {
            let answer = try await self.post("POST", "/v1/editors/\(editorID.uuidString)/reply-all", ["on": .bool(on)])
            let fresh = try APICoding.decoder.decode(EditorState.self, from: answer)
            self.update {
                $0.editor(editorID) {
                    $0.form.cc = fresh.form.cc
                    $0.form.replyAll = fresh.form.replyAll
                }
            }
        }
    }

    /// Saves to the server's drafts; the Mac closes the editor (`editor_closed`) when it's done.
    public func save(_ editorID: UUID, form: DraftForm? = nil, instructions: String? = nil) {
        guard let editor = typedInto(editorID, form, instructions), editor.canSave, !editor.status.isBusy else { return }
        update { $0.editor(editorID) { $0.status = .saving } }
        run(onFailure: { self.failed(editorID, $0) }) {
            _ = try await self.post("POST", "/v1/editors/\(editorID.uuidString)/save", try Self.edits(editor))
        }
    }

    /// Closes the editor without saving.
    public func closeEditor(_ editorID: UUID) {
        guard state.editors[editorID] != nil else { return }
        update { $0.editors[editorID] = nil }
        run { _ = try await self.transport.send("DELETE", "/v1/editors/\(editorID.uuidString)", body: nil) }
    }

    private func typedInto(_ editorID: UUID, _ form: DraftForm?, _ instructions: String?) -> EditorState? {
        update {
            $0.editor(editorID) { editor in
                if let form { editor.form = form }
                if let instructions { editor.instructions = instructions }
            }
        }
        return state.editors[editorID]
    }

    private func failed(_ editorID: UUID, _ message: String) {
        update { $0.editor(editorID) { $0.status = .failed(message) } }
    }

    private static func edits(_ editor: EditorState) throws -> JSONValue {
        ["form": try APICoding.body(editor.form), "instructions": .string(editor.instructions)]
    }

    /// Asks the Mac to read its config file again.
    public func reloadConfig() {
        run { _ = try await self.transport.send("POST", "/v1/config/reload", body: nil) }
    }

    // MARK: HTTP

    private func post(_ method: String, _ path: String, _ body: JSONValue) async throws -> Data {
        try await transport.send(method, path, body: Data(body.serialized().utf8))
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T {
        let data = try await transport.send("GET", path, body: nil)
        do {
            return try APICoding.decoder.decode(type, from: data)
        } catch {
            throw Problems.describe(error, url: display)
        }
    }
}
