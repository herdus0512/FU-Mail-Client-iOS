import Foundation

/// Whether the event stream is open, and what's wrong if anything is.
public struct Connection: Equatable, Sendable {
    public var connected = false
    /// Plain words: can't reach, token rejected, locked out…
    public var problem: String?

    public init(connected: Bool = false, problem: String? = nil) {
        self.connected = connected
        self.problem = problem
    }

    public enum Indicator: Sendable { case connected, connecting, failed }

    public var indicator: Indicator {
        if connected { return .connected }  // even when one request failed: the stream is fine
        return problem != nil ? .failed : .connecting
    }
}

/// Text typed into a card's sheet here, sent with Done but not yet echoed back by the Mac. Shown over
/// the Mac's copy until then, so an older `message_updated` can't undo it.
public struct TypedEdit: Equatable, Sendable {
    public var heading: String?
    public var body: String?
    public var suggestion: String?
    public var crmText: String?

    public init(heading: String? = nil, body: String? = nil, suggestion: String? = nil, crmText: String? = nil) {
        self.heading = heading
        self.body = body
        self.suggestion = suggestion
        self.crmText = crmText
    }

    public func apply(to message: inout ChatMessage) {
        switch message.card {
        case .notes(var card):
            if let heading { card.entry.heading = heading }
            if let body { card.entry.lines = body.components(separatedBy: "\n") }
            message.card = .notes(card)
        case .suggestedNote(var card):
            if let suggestion { card.note = suggestion }
            message.card = .suggestedNote(card)
        case .crm(var card):
            // While a rewrite streams in, its text wins.
            if let crmText, !card.rewriting { card.text = crmText }
            message.card = .crm(card)
        default:
            break
        }
    }

    func applied(to message: ChatMessage) -> ChatMessage {
        var copy = message
        apply(to: &copy)
        return copy
    }
}

/// A loaded chat whose copy here may be old, until it's fetched again.
public enum OutOfDate: Equatable, Sendable {
    /// Being fetched, or about to be.
    case updating
    /// The tries ran out.
    case failed

    /// What a triage card says about its buttons being off.
    public var notice: String {
        switch self {
        case .updating: "Updating this chat. The buttons are off until it's done."
        case .failed: "Couldn't update this chat, so the buttons are off. Reopen it to try again."
        }
    }
}

/// Something the client has to fetch after applying an event.
public enum Effect: Equatable, Sendable { case refreshList, refreshInfo }

/// This device's copy of the Mac's state, kept up to date from the event stream. Everything here is a
/// pure function of the old state and what the Mac sent, so it's tested without a network. Mirrors the
/// Mac's `RemoteBackend` and the Android app's `RemoteState`.
public struct RemoteState: Equatable, Sendable {
    public var conversations: [Conversation] = []
    /// Conversations whose messages haven't been fetched yet.
    public var unloaded: Set<Conversation.ID> = []
    public var chatStatus: [Conversation.ID: String] = [:]
    public var busyMessages: Set<ChatMessage.ID> = []
    public var info: APIInfo?
    public var storeError: String?
    public var configError: String?
    /// Draft editors open on this device, with what's been typed here.
    public var editors: [UUID: EditorState] = [:]
    public var typed: [ChatMessage.ID: TypedEdit] = [:]
    public var connection = Connection()
    /// Loaded chats that may be old: marked as a refetch begins (a reconnect, config_changed), and cleared
    /// only by their own successful fetch.
    public var outOfDate: [Conversation.ID: OutOfDate] = [:]
    /// The Mac's slash commands, for suggestions while typing.
    public var commands: [Command] = []

    public init() {}

    public func conversation(_ id: Conversation.ID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Known to have no messages (rather than not fetched yet).
    public func isEmptyChat(_ id: Conversation.ID) -> Bool {
        !unloaded.contains(id) && conversation(id)?.messages.isEmpty == true
    }

    public func isAnswering(_ id: Conversation.ID) -> Bool { chatStatus[id] != nil }

    /// Whether a message's card is the Mac's current one and can take an action: connected, its chat not
    /// out of date, and not busy.
    public func canAct(on messageID: ChatMessage.ID, in id: Conversation.ID) -> Bool {
        connection.connected && outOfDate[id] == nil && !busyMessages.contains(messageID)
    }

    /// Every loaded chat may be old: a refetch begins.
    public mutating func markLoadedOutOfDate() {
        for conversation in conversations where !unloaded.contains(conversation.id) { outOfDate[conversation.id] = .updating }
    }

    /// One event from the Mac, applied to the copy here; returns what to fetch because of it.
    @discardableResult
    public mutating func apply(_ event: APIEvent) -> [Effect] {
        switch event.type {
        case "conversations_changed":
            return [.refreshList]
        case "message_appended":
            return appending(event)
        case "message_updated":
            updating(event)
        case "chat_status":
            guard let id = event.conversationID else { break }
            chatStatus[id] = event.status
        case "busy":
            guard let id = event.messageID else { break }
            if event.busy == true { busyMessages.insert(id) } else { busyMessages.remove(id) }
        case "store_error":
            storeError = event.error
        case "config_changed":
            return [.refreshInfo]
        case "editor_opened":
            if let editor = event.editor { editors[editor.id] = editor }
        case "editor_updated":
            // Only this device's editors: another device's is never in `editors`.
            if let fresh = event.editor, let mine = editors[fresh.id] { editors[fresh.id] = mine.updated(from: fresh) }
        case "editor_closed":
            if let id = event.editorID { editors[id] = nil }
        default:
            break
        }
        return []
    }

    private mutating func appending(_ event: APIEvent) -> [Effect] {
        guard let id = event.conversationID, let message = event.message else { return [] }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return [.refreshList] }
        // Not loaded yet: it's fetched in full when opened.
        guard !unloaded.contains(id), !conversations[index].messages.contains(where: { $0.id == message.id }) else { return [] }
        conversations[index].append(message)
        return []
    }

    private mutating func updating(_ event: APIEvent) {
        guard let id = event.conversationID, let incoming = event.message,
              let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let message = typed[incoming.id]?.applied(to: incoming) ?? incoming
        conversations[index].update(message.id) { $0 = message }
    }

    /// `GET /v1/conversations`: the list, keeping messages already loaded.
    public mutating func setList(_ items: [ConversationListItem]) {
        let known = Dictionary(conversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Conversation.ID>()
        var list: [Conversation] = []
        for item in items where seen.insert(item.id).inserted {
            var conversation = known[item.id] ?? Conversation(id: item.id, title: item.title, createdAt: item.createdAt,
                                                              updatedAt: item.updatedAt)
            if known[item.id] == nil { unloaded.insert(item.id) }
            conversation.title = item.title
            conversation.updatedAt = item.updatedAt
            list.append(conversation)
        }
        // A conversation made here that's still empty isn't saved over there yet: keep it.
        for conversation in conversations
        where conversation.messages.isEmpty && !unloaded.contains(conversation.id) && !seen.contains(conversation.id) {
            list.append(conversation)
        }
        let ids = Set(list.map(\.id))
        conversations = list
        unloaded = unloaded.filter { ids.contains($0) }
        outOfDate = outOfDate.filter { ids.contains($0.key) }
    }

    /// `GET /v1/conversations/{id}`: its messages and what's happening in it.
    public mutating func setDetail(_ detail: ConversationDetail) {
        var conversation = detail.conversation
        conversation.messages = conversation.messages.map { typed[$0.id]?.applied(to: $0) ?? $0 }
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        unloaded.remove(conversation.id)
        for message in conversation.messages {
            if detail.busyMessages.contains(message.id) { busyMessages.insert(message.id) } else { busyMessages.remove(message.id) }
        }
        chatStatus[conversation.id] = detail.chatStatus
    }

    /// A fetch's answer, then its chat's events that came while it was open, in order (the answer may be
    /// older than them), and only then the chat counts as up to date.
    public mutating func setDetail(_ detail: ConversationDetail, reapplying events: [APIEvent]) {
        let id = detail.conversation.id
        setDetail(detail)
        for event in events {
            if event.type == "busy" {
                // Recorded whichever chat it's for: only this chat's is older than what's shown.
                guard let messageID = event.messageID,
                      conversation(id)?.messages.contains(where: { $0.id == messageID }) == true else { continue }
            }
            apply(event)
        }
        outOfDate[id] = nil
    }

    /// `GET /v1/editors` after reconnecting: an editor opened while this device wasn't listening is
    /// added, and one saved or closed meanwhile is dropped. One already open here keeps what was typed.
    public mutating func setEditors(_ open: [EditorState]) {
        let ids = Set(open.map(\.id))
        editors = editors.filter { ids.contains($0.key) }
        for editor in open where editors[editor.id] == nil { editors[editor.id] = editor }
    }

    public mutating func setInfo(_ info: APIInfo) {
        self.info = info
        configError = info.configError
        storeError = info.storeError
    }

    /// A conversation just made with `POST /v1/conversations`.
    public mutating func addConversation(_ id: Conversation.ID, now: Date) {
        if !conversations.contains(where: { $0.id == id }) {
            conversations.append(Conversation(id: id, createdAt: now))
        }
        unloaded.remove(id)
    }

    public mutating func removeConversation(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        unloaded.remove(id)
        chatStatus[id] = nil
        outOfDate[id] = nil
    }

    public mutating func rename(_ id: Conversation.ID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
    }

    /// Shows typed text on its card at once (Done in a sheet), until the Mac has caught up.
    public mutating func type(_ edit: TypedEdit, on messageID: ChatMessage.ID, in conversationID: Conversation.ID) {
        typed[messageID] = edit
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].update(messageID) { edit.apply(to: &$0) }
        }
    }

    public mutating func editor(_ id: UUID, _ change: (inout EditorState) -> Void) {
        guard var editor = editors[id] else { return }
        change(&editor)
        editors[id] = editor
    }
}

extension EditorState {
    /// An editor update from the Mac. The body comes back while it's being written (and the update
    /// that ends the writing carries the finished body); otherwise what's typed here stands.
    func updated(from fresh: EditorState) -> EditorState {
        var copy = self
        let wasWriting = if case .writing = status { true } else { false }
        let writing = if case .writing = fresh.status { true } else { false }
        if writing || wasWriting { copy.form.body = fresh.form.body }
        copy.status = fresh.status
        return copy
    }
}
