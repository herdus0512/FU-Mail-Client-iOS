import Foundation
import Synchronization
import Testing
@testable import FUMailKit

/// A stand-in Mac with a chat of no interest, then one with a triage card, whose event stream stays open and says what it's told to.
final class TriageDesktop: DesktopTransport {
    struct State: Sendable {
        var requests: [String] = []
        /// Whether this device's token is in `api.full_triage`.
        var listed = true
        var card: String
        var refusal: String?
        var brokenEditors = false
        var editors = "[]"
        var brokenFirstChat = false
        /// A triage card in the first chat too.
        var firstChatHasCard = false
        var brokenInfo = false
        var brokenTriageChat = false
        /// The list no longer has the triage chat.
        var unlisted = false
        /// The triage chat's other messages, and whether its card is busy.
        var extra: [String] = []
        var busy = false
        /// How many times the triage chat was asked for, and which of them (from 1) are held back.
        var chatFetches = 0
        var holding: Set<Int> = []
        /// The new chats made here that it still has, how many were made, and what asking for another answers.
        var newChats: Set<String> = []
        var made = 0
        var missing = 404
        var triageChatGone = false
        /// Holds back the answer to an action while it's true.
        var held = false
        /// Holds back the (already written) answer to fetching the chat while it's true.
        var heldChat = false
        var stream: AsyncThrowingStream<StreamItem, Error>.Continuation?
    }

    let display = "http://fake-mac:8765"
    let spamCard: String
    let state: Mutex<State>

    init() throws {
        guard case .array(let cards) = try JSONValue.parse(Data(fixture("triage-cards.json").utf8)) else { throw CancellationError() }
        spamCard = cards[0].serialized()
        state = Mutex(State(card: spamCard))
    }

    var requests: [String] { state.withLock { $0.requests } }
    var actions: [String] { requests.filter { $0.hasPrefix("POST") } }
    func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
    func count(_ request: String) -> Int { requests.filter { $0 == request }.count }

    func message(_ card: String, _ name: String = "M1") -> String {
        #"{"id":"\#(id(name))","role":"assistant","text":"","createdAt":"2026-11-24T09:00:00Z","card":\#(card)}"#
    }
    func push(_ event: String) { _ = state.withLock { $0.stream }?.yield(.data(event)) }
    func drop() { state.withLock { $0.stream }?.finish(throwing: URLError(.networkConnectionLost)) }
    func updateCard(_ card: String) {
        set { $0.card = card }
        push(#"{"type":"message_updated","conversationID":"\#(id("C1"))","message":\#(message(card))}"#)
    }
    func busy(_ on: Bool) { push(#"{"type":"busy","messageID":"\#(id("M1"))","busy":\#(on)}"#) }

    func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let request = "\(method) \(path)" + (body.map { " " + String(decoding: $0, as: UTF8.self) } ?? "")
        let now = state.withLock { state in
            state.requests.append(request)
            if request == "GET /v1/conversations/\(id("C1").uuidString)" { state.chatFetches += 1 }
            return state
        }
        let (c0, c1) = (id("C0").uuidString, id("C1").uuidString)
        let chat = #"{"id":"\#(c1)","title":"Triage","createdAt":"2026-11-24T09:00:00Z","updatedAt":"2026-11-24T09:00:00Z""#
        let answer: String
        func detail(_ id: String, _ messages: String, busy: String = "") -> String {
            #"{"conversation":\#(chat.replacingOccurrences(of: c1, with: id)),"messages":[\#(messages)]},"answering":false,"busyMessages":[\#(busy)]}"#
        }
        /// Whatever happens to the request meanwhile (a cancelled one's answer can still arrive).
        func held(_ is: @escaping @Sendable (State) -> Bool) async {
            while state.withLock({ `is`($0) }) { await Task.detached { try? await Task.sleep(for: .milliseconds(5)) }.value }
        }
        switch "\(method) \(path)" {
        case "GET /v1/info":
            if now.brokenInfo { throw Problems.forStatus(500, reason: "info broke", url: display) }
            answer = try fixture("info.json")
        case "GET /v1/conversations":
            answer = "[\(chat.replacingOccurrences(of: c1, with: c0))}" + (now.unlisted ? "]" : ",\(chat)}]")
        case "GET /v1/conversations/\(c0)":
            if now.brokenFirstChat { throw Problems.forStatus(500, reason: "the first chat broke", url: display) }
            answer = detail(c0, now.firstChatHasCard ? message(now.card, "M0") : "")
        case "GET /v1/conversations/\(c1)":
            if now.triageChatGone { throw Problems.forStatus(404, reason: "No such conversation.", url: display) }
            if now.brokenTriageChat { throw Problems.forStatus(500, reason: "the triage chat broke", url: display) }
            answer = detail(c1, ((now.listed ? [message(now.card)] : []) + now.extra).joined(separator: ","),
                            busy: now.busy ? "\"\(id("M1"))\"" : "")
            await held { $0.holding.contains(now.chatFetches) }
            // The others' failures come first.
            if now.brokenFirstChat { try await Task.sleep(for: .milliseconds(50)) }
            await held { $0.heldChat }
        case "GET /v1/editors":
            if now.brokenEditors { throw Problems.forStatus(500, reason: "editors broke", url: display) }
            answer = now.editors
        case "POST /v1/conversations":
            let new = state.withLock { state in
                state.made += 1
                let new = id("NEW\(state.made)").uuidString
                state.newChats.insert(new)
                return new
            }
            answer = #"{"id":"\#(new)"}"#
        case let request where request.hasPrefix("GET /v1/conversations/"):
            let asked = String(path.dropFirst("/v1/conversations/".count))
            guard now.newChats.contains(asked) else {
                throw Problems.forStatus(now.missing, reason: "No such conversation.", url: display)
            }
            answer = detail(asked, "")
        case "GET /v1/commands":
            // Slower than the rest, so the failing request is over first.
            if now.brokenEditors { try await Task.sleep(for: .milliseconds(50)) }
            answer = #"[{"name":"/triage","args":"\#(now.listed ? "status|run|clean|spam" : "status|run")","summary":""}]"#
        case "POST /v1/conversations/\(c1)/messages/\(id("M1").uuidString)/action":
            while state.withLock({ $0.held }) { try await Task.sleep(for: .milliseconds(5)) }
            if let refusal = now.refusal { throw Problems.forStatus(400, reason: refusal, url: display) }
            answer = #"{"ok":true}"#
        default: answer = #"{"ok":true}"#
        }
        return Data(answer.utf8)
    }

    func health() async throws {}

    func events() -> AsyncThrowingStream<StreamItem, Error> {
        let (stream, continuation) = AsyncThrowingStream<StreamItem, Error>.makeStream()
        set {
            $0.requests.append("GET /v1/events")
            $0.stream = continuation
        }
        continuation.yield(.opened)
        return stream
    }
}

/// Triage's cards over the connection (the Android app's TriageClientTest, case for case).
@MainActor
struct TriageClientTests {
    private let desktop: TriageDesktop
    private let client: RemoteClient
    private let c1 = id("C1")
    private let m1 = id("M1")

    init() throws {
        desktop = try TriageDesktop()
        client = RemoteClient(transport: desktop, backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)),
                              retryPauses: [.seconds(60)])
    }

    private var card: Card? { client.state.conversation(c1)?.messages.first { $0.id == m1 }?.card }
    private var view: TriageView? {
        card.flatMap {
            TriageRules.view($0, busy: client.state.busyMessages.contains(m1), connected: client.state.connection.connected) { _ in "" }
        }
    }
    private func delete() throws -> TriageConfirmation { try #require(view?.rows.first?.buttons.first).confirmation }
    private func all() throws -> TriageConfirmation { try #require(view?.all).confirmation }

    private func open() async {
        client.start()
        await eventually("connected") { client.state.connection.connected && !client.state.commands.isEmpty }
        client.loadMessages(c1)
        await eventually("the chat") { !client.state.unloaded.contains(c1) }
    }

    /// Anything sent by now would have been.
    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    private func changeTheCard() async {
        desktop.updateCard(desktop.spamCard.replacingOccurrences(of: "50% off everything", with: "60% off everything"))
        await eventually("the change") { view?.rows.first?.subject == "60% off everything" }
    }

    @Test func aRowActionAndAnOpenAsSent() async throws {
        await open()
        client.triageAction(try delete(), on: m1, in: c1)
        await eventually("the action") { desktop.actions.count == 1 }
        #expect(desktop.actions.first
                == #"POST /v1/conversations/\#(c1)/messages/\#(m1)/action {"action":"spam_delete","email_key":"gmail-mcp|fanda|18c2a"}"#)
        client.openEmail(try #require(view).rows[1].ref, in: c1)
        await eventually("the open") { desktop.actions.count == 2 }
        #expect(desktop.actions.last
                == #"POST /v1/conversations/\#(c1)/open {"ref":{"headerMessageID":"<a+b/c=@x.example>","id":40213,"server":"macia"}}"#)
        #expect(view?.rows.count == 4)  // the phone takes no row off itself
        client.close()
    }

    @Test func moveAllIsSentWhenTheCardIsStillTheOneConfirmed() async throws {
        await open()
        client.triageAction(try all(), on: m1, in: c1)
        await eventually("the action") { desktop.actions.count == 1 }
        #expect(desktop.actions.first?.hasSuffix(#" {"action":"spam_delete_all"}"#) == true)
        client.close()
    }

    @Test func aCardChangingDuringTheConfirmationSendsNothing() async throws {
        await open()
        let asked = try all()
        await changeTheCard()
        #expect(!asked.holds(client.state, on: m1, in: c1))  // the question closes
        client.triageAction(asked, on: m1, in: c1)
        await eventually("the reason") { client.state.connection.problem == TriageConfirmation.changed }
        #expect(desktop.actions.isEmpty)
        client.close()
    }

    @Test func aCardChangingWhileTheActionWaitsItsTurnSendsNothing() async throws {
        await open()
        desktop.set { $0.held = true }
        client.cardAction(.spamRefresh, on: m1, in: c1)
        await eventually("the refresh") { desktop.actions.count == 1 }
        client.triageAction(try all(), on: m1, in: c1)  // waits for the refresh's answer
        await changeTheCard()
        desktop.set { $0.held = false }
        await eventually("the reason") { client.state.connection.problem == TriageConfirmation.changed }
        #expect(desktop.actions.count == 1)
        client.close()
    }

    @Test func nothingIsSentWhileTheCardIsBusy() async throws {
        await open()
        let asked = try delete()
        desktop.busy(true)
        await eventually("busy") { client.state.busyMessages.contains(m1) }
        #expect(view?.rows.flatMap(\.buttons).contains { $0.enabled } == false)
        client.triageAction(asked, on: m1, in: c1)
        await settle()
        #expect(desktop.actions.isEmpty)
        desktop.busy(false)
        await eventually("not busy") { view?.rows[0].buttons[0].enabled == true }
        client.close()
    }

    @Test func nothingIsSentWhileDisconnected() async throws {
        await open()
        let asked = try all()
        client.stop()
        client.triageAction(asked, on: m1, in: c1)
        await settle()
        #expect(desktop.actions.isEmpty)
        client.close()
    }

    @Test func aRefusalShowsAsSentAndABackgroundRefreshLeavesIt() async throws {
        await open()
        let refusal = "Placeholder: the Mac's own words, (exactly)."
        desktop.set { $0.refusal = refusal }
        client.triageAction(try delete(), on: m1, in: c1)
        await eventually("the refusal") { client.state.connection.problem == refusal }
        let before = desktop.count("GET /v1/conversations")
        desktop.push(#"{"type":"conversations_changed"}"#)
        await eventually("the refresh") { desktop.count("GET /v1/conversations") > before }
        await settle()
        #expect(client.state.connection.problem == refusal)
        // Something asked for that works does clear it.
        desktop.set { $0.refusal = nil }
        client.triageAction(try delete(), on: m1, in: c1)
        await eventually("cleared") { client.state.connection.problem == nil }
        client.close()
    }

    @Test func beingListedLaterBringsTheCardsAndCommandsAtOnce() async {
        desktop.set { $0.listed = false }
        await open()
        #expect(card == nil)
        #expect(client.state.commands.map(\.args) == ["status|run"])
        desktop.set { $0.listed = true }
        desktop.push(#"{"type":"config_changed"}"#)
        await eventually("the card") { view?.title == "Caught Spam & Marketing" }
        await eventually("the commands") { client.state.commands.map(\.args) == ["status|run|clean|spam"] }
        desktop.set { $0.listed = false }
        desktop.push(#"{"type":"config_changed"}"#)
        await eventually("the card gone") { card == nil }
        #expect(desktop.count("GET /v1/events") == 1)  // without reconnecting
        client.close()
    }

    @Test func anEventDuringTheRefetchIsntUndoneByItsOlderAnswer() async {
        await open()
        let fetches = desktop.count("GET /v1/conversations/\(c1.uuidString)")
        desktop.set { $0.heldChat = true }
        desktop.push(#"{"type":"config_changed"}"#)
        // The answer is written (with the old card), then the card changes, then the answer arrives.
        await eventually("the fetch") { desktop.count("GET /v1/conversations/\(c1.uuidString)") == fetches + 1 }
        desktop.updateCard(desktop.spamCard.replacingOccurrences(of: "50% off everything", with: "60% off everything"))
        await settle()
        desktop.set { $0.heldChat = false }
        await eventually("the change") { view?.rows.first?.subject == "60% off everything" }
        await settle()
        #expect(view?.rows.first?.subject == "60% off everything")
        client.close()
    }

    @Test func commandsRefreshOnReconnectEvenWhenSomethingElseFails() async {
        desktop.set { $0.listed = false }
        await open()
        desktop.set {
            $0.listed = true
            $0.brokenEditors = true
        }
        desktop.drop()
        await eventually("the commands") { client.state.commands.map(\.args) == ["status|run|clean|spam"] }
        await eventually("reconnected") { client.state.connection.connected }
        #expect(client.state.connection.problem == "editors broke")
        #expect(view?.title == "Caught Spam & Marketing")
        client.close()
    }

    // MARK: Reconnecting

    private func reconnect() async {
        let (before, editors) = (desktop.count("GET /v1/events"), desktop.count("GET /v1/editors"))
        desktop.drop()
        await eventually("reconnected") {
            desktop.count("GET /v1/events") > before && desktop.count("GET /v1/editors") > editors && client.state.connection.connected
        }
    }

    private func shown(_ name: String) -> Bool { client.state.conversation(id(name)) != nil }

    @Test func aChatThatFailsOnReconnectDoesntStopTheRest() async throws {
        await open()
        client.loadMessages(id("C0"))
        await eventually("the first chat") { client.state.unloaded.isEmpty }
        let editor = try fixture("editor-reply.json")
        let card = desktop.spamCard.replacingOccurrences(of: "50% off everything", with: "60% off everything")
        desktop.set {
            $0.brokenFirstChat = true
            $0.editors = "[\(editor)]"
            $0.card = card
        }
        await reconnect()
        // All fetched before connected said so: nothing to wait for.
        #expect(view?.rows.first?.subject == "60% off everything")
        #expect(client.state.editors.count == 1)
        #expect(client.state.connection.problem == "the first chat broke")
        client.close()
    }

    @Test func theFirstFailureIsTheOneShown() async {
        await open()
        client.loadMessages(id("C0"))
        await eventually("the first chat") { client.state.unloaded.isEmpty }
        desktop.set {
            $0.brokenFirstChat = true
            $0.brokenEditors = true
        }
        await reconnect()
        #expect(client.state.connection.problem == "the first chat broke")
        client.close()
    }

    @Test func anEmptyChatTheMacLostIsDroppedWithoutABanner() async {
        await open()
        #expect(await client.startConversation() == id("NEW1"))
        await reconnect()
        #expect(shown("NEW1"))  // the Mac still has it
        desktop.set { $0.newChats = [] }  // the Mac restarted
        await reconnect()
        #expect(!shown("NEW1"))
        #expect(client.state.connection.problem == nil)
        #expect(desktop.count("POST /v1/conversations") == 1)  // not asked for by reconnecting
        // The pencil asks the Mac, rather than giving back the dead one.
        #expect(await client.startConversation() == id("NEW2"))
        client.send("/unread", in: id("NEW2"))
        await eventually("the command") {
            desktop.actions.contains { $0.hasPrefix("POST /v1/conversations/\(id("NEW2").uuidString)/send") }
        }
        client.close()
    }

    @Test func aConfigReloadDropsItToo() async {
        await open()
        _ = await client.startConversation()
        desktop.set { $0.newChats = [] }
        desktop.push(#"{"type":"config_changed"}"#)
        await eventually("dropped") { !shown("NEW1") }
        #expect(client.state.connection.problem == nil)
        #expect(desktop.count("GET /v1/events") == 1)  // without reconnecting
        client.close()
    }

    @Test func anEmptyChatIsKeptOnAnyOtherFailure() async {
        await open()
        _ = await client.startConversation()
        desktop.set {
            $0.newChats = []
            $0.missing = 500
        }
        await reconnect()
        #expect(shown("NEW1"))
        #expect(client.state.connection.problem == "No such conversation.")
        client.close()
    }

    @Test func aChatWithMessagesIsNeverDroppedForA404() async {
        await open()
        desktop.set { $0.triageChatGone = true }
        await reconnect()
        #expect(view?.title == "Caught Spam & Marketing")
        #expect(client.state.connection.problem == "No such conversation.")
        #expect(client.state.outOfDate[c1] == .updating)  // its card may be old
        #expect(view?.all?.confirmation.holds(client.state, on: m1, in: c1) == false)
        client.close()
    }

    @Test func aChatNotLoadedYetIsKeptAndSaysWhy() async {
        desktop.set { $0.triageChatGone = true }
        client.start()
        await eventually("connected") { client.state.connection.connected }
        client.loadMessages(c1)
        await eventually("the reason") { client.state.connection.problem == "No such conversation." }
        #expect(shown("C1") && client.state.unloaded.contains(c1))
        client.close()
    }

    @Test func commandsAreSentAsTyped() async {
        await open()
        client.send("/triage spam", in: c1)
        await eventually("the command") { desktop.actions.count == 1 }
        #expect(desktop.actions.first == #"POST /v1/conversations/\#(c1)/send {"text":"/triage spam"}"#)
        client.close()
    }

    @Test func whyAnActionCouldntBeDoneIsShownWhenItArrives() async throws {
        await open()
        _ = client.takeExpectedReply(in: c1)
        client.triageAction(try delete(), on: m1, in: c1)
        #expect(client.takeExpectedReply(in: c1))
        client.close()
    }
}
