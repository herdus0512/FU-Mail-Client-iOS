import Foundation
import Synchronization
import Testing
@testable import FUMailKit

/// A stand-in Mac with one triage card, whose event stream stays open and says what it's told to.
private final class TriageDesktop: DesktopTransport {
    struct State: Sendable {
        var requests: [String] = []
        /// Whether this device's token is in `api.full_triage`.
        var listed = true
        var card: String
        var refusal: String?
        var brokenEditors = false
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

    private func message(_ card: String) -> String {
        #"{"id":"\#(id("M1"))","role":"assistant","text":"","createdAt":"2026-11-24T09:00:00Z","card":\#(card)}"#
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
            return state
        }
        let c1 = id("C1").uuidString
        let chat = #"{"id":"\#(c1)","title":"Triage","createdAt":"2026-11-24T09:00:00Z","updatedAt":"2026-11-24T09:00:00Z""#
        let answer: String
        switch "\(method) \(path)" {
        case "GET /v1/info": answer = try fixture("info.json")
        case "GET /v1/conversations": answer = "[\(chat)}]"
        case "GET /v1/conversations/\(c1)":
            answer = #"{"conversation":\#(chat),"messages":[\#(now.listed ? message(now.card) : "")]},"answering":false,"busyMessages":[]}"#
            while state.withLock({ $0.heldChat }) { try await Task.sleep(for: .milliseconds(5)) }
        case "GET /v1/editors":
            if now.brokenEditors { throw Problems.forStatus(500, reason: "editors broke", url: display) }
            answer = "[]"
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
        client = RemoteClient(transport: desktop, backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
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
