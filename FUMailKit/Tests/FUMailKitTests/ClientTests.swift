import Foundation
import Synchronization
import Testing
@testable import FUMailKit

private let token = "fum_test-token"
private let editorID = UUID(uuidString: "9F1C2B3A-0000-4000-8000-000000000001")!

/// A pretend Mac: answers the API's requests, records them, and sends events when told to.
private final class FakeDesktop: DesktopTransport {
    struct Recorded: Sendable {
        var requests: [String] = []
        var bodies: [String] = []
        var streams = 0
        var editors = "[]"
        var status = 200
        var tokenSent = token
        var commandsMissing = false
        var stream: AsyncThrowingStream<StreamItem, Error>.Continuation?
    }

    let display = "http://fake-mac:8765"
    let recorded = Mutex(Recorded())

    var requests: [String] { recorded.withLock { $0.requests } }
    var bodies: [String] { recorded.withLock { $0.bodies } }
    var streams: Int { recorded.withLock { $0.streams } }

    func set(_ change: (inout Recorded) -> Void) { recorded.withLock { change(&$0) } }

    /// Sends one event on the open stream.
    func push(_ event: String) {
        _ = recorded.withLock { $0.stream }?.yield(.data(event))
    }

    /// Ends the open stream (the connection dropped).
    func drop() {
        recorded.withLock { $0.stream }?.finish(throwing: URLError(.networkConnectionLost))
    }

    private let message = #"{"id":"\#(id("FIRST"))","role":"user","text":"/unread","createdAt":"2026-11-13T08:00:00Z"}"#

    func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let (status, wrongToken, commandsMissing, editors) = recorded.withLock { state in
            state.requests.append("\(method) \(path)")
            if let body { state.bodies.append("\(method) \(path) \(String(decoding: body, as: UTF8.self))") }
            return (state.status, state.tokenSent != token, state.commandsMissing, state.editors)
        }
        if wrongToken { throw Problems.forStatus(401, reason: "Unauthorized", url: display) }
        if status != 200 { throw Problems.forStatus(status, reason: "nope", url: display) }
        let c1 = id("C1").uuidString
        let answer: String = switch "\(method) \(path)" {
        case "GET /v1/info": try fixture("info.json")
        case "GET /v1/conversations":
            #"[{"id":"\#(c1)","title":"Unread","createdAt":"2026-11-13T08:00:00Z","updatedAt":"2026-11-13T08:00:00Z"}]"#
        case "GET /v1/conversations/\(c1)":
            #"{"conversation":{"id":"\#(c1)","title":"Unread","createdAt":"2026-11-13T08:00:00Z","updatedAt":"2026-11-13T08:00:00Z","messages":[\#(message)]},"answering":false,"busyMessages":[]}"#
        case "GET /v1/editors": editors
        case "GET /v1/commands" where commandsMissing: throw Problems.forStatus(404, reason: nil, url: display)
        case "GET /v1/commands": #"[{"name":"/unread","args":"[n]","summary":"newest unread email"}]"#
        case "POST /v1/conversations": #"{"id":"\#(id("NEW").uuidString)"}"#
        case "POST /v1/editors/\(editorID.uuidString)/reply-all":
            try fixture("editor-reply.json").replacingOccurrences(of: #""cc":"""#, with: #""cc":"Carol <carol@example.com>""#)
                .replacingOccurrences(of: #""replyAll":false"#, with: #""replyAll":true"#)
        default: #"{"ok":true}"#
        }
        return Data(answer.utf8)
    }

    func health() async throws {
        recorded.withLock { $0.requests.append("GET /health") }
    }

    func events() -> AsyncThrowingStream<StreamItem, Error> {
        let (stream, continuation) = AsyncThrowingStream<StreamItem, Error>.makeStream()
        let refused: RemoteProblem? = recorded.withLock { state in
            state.requests.append("GET /v1/events")
            state.streams += 1
            if state.tokenSent != token { return Problems.unauthorized }
            if state.status == 429 { return Problems.lockedOut }
            state.stream = continuation
            return nil
        }
        if let refused { continuation.finish(throwing: refused) } else { continuation.yield(.opened) }
        return stream
    }
}

/// The client against a pretend Mac (the Android app's RemoteClientTest, case for case).
@MainActor
struct ClientTests {
    private let desktop = FakeDesktop()

    private func client() -> RemoteClient {
        RemoteClient(transport: desktop, backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)),
                     typedHold: .milliseconds(50))
    }

    @Test func connectsFetchesEverythingAndShowsTheMacsDetails() async {
        let client = client()
        client.start()
        await eventually("connected") { client.state.connection.connected }
        #expect(client.state.info?.device == "phone")
        #expect(client.state.commands.map(\.name) == ["/unread"])
        #expect(client.state.conversations.map(\.id) == [id("C1")])
        #expect(client.state.unloaded.contains(id("C1")))  // fetched when opened
        desktop.push(#"{"type":"chat_status","conversationID":"\#(id("C1"))","status":"Checking mail…"}"#)
        await eventually("the chat status") { client.state.chatStatus[id("C1")] == "Checking mail…" }
        client.loadMessages(id("C1"))
        await eventually("messages") { !client.state.unloaded.contains(id("C1")) }
        #expect(client.state.conversation(id("C1"))?.messages.first?.text == "/unread")
        client.close()
    }

    @Test func aDroppedStreamReconnectsAndFetchesAgain() async {
        let client = client()
        client.start()
        await eventually("connected") { client.state.connection.connected }
        desktop.drop()
        await eventually("a problem shown") { client.state.connection.problem != nil }
        await eventually("reconnected") { desktop.streams >= 2 && client.state.connection.connected }
        #expect(desktop.requests.filter { $0 == "GET /v1/editors" }.count >= 2)
        #expect(client.state.connection.problem == nil)
        client.close()
    }

    @Test func stoppingClosesTheStreamAndStartingFetchesAgain() async {
        let client = client()
        client.start()
        await eventually("connected") { client.state.connection.connected }
        client.stop()
        #expect(!client.state.connection.connected)
        client.start()
        await eventually("connected again") { desktop.streams == 2 && client.state.connection.connected }
        client.close()
    }

    @Test func anEditorOpenedWhileDisconnectedIsFoundOnReconnect() async throws {
        let client = client()
        client.start()
        await eventually("connected") { client.state.connection.connected }
        let editor = try fixture("editor-reply.json")
        desktop.set { $0.editors = "[\(editor)]" }
        desktop.drop()
        await eventually("the editor") { !client.state.editors.isEmpty }
        #expect(Array(client.state.editors.keys) == [editorID])
        desktop.set { $0.editors = "[]" }
        desktop.drop()
        await eventually("the editor closed elsewhere") { client.state.editors.isEmpty }
        client.close()
    }

    @Test func aWrongTokenSaysSo() async {
        desktop.set { $0.tokenSent = "fum_wrong" }
        let client = client()
        client.start()
        await eventually("a problem") { client.state.connection.problem != nil }
        #expect(client.state.connection.problem?.contains("didn't accept this device's token") == true)
        #expect(client.state.connection.indicator == .failed)
        client.close()
    }

    @Test func lockedOutSaysSo() async {
        desktop.set { $0.status = 429 }
        let client = client()
        client.start()
        await eventually("a problem") { client.state.connection.problem != nil }
        #expect(client.state.connection.problem?.contains("locked this device out") == true)
        client.close()
    }

    @Test func aMacWithoutTheCommandListStillConnects() async {
        desktop.set { $0.commandsMissing = true }
        let client = client()
        client.start()
        await eventually("connected") { client.state.connection.connected }
        #expect(client.state.commands.isEmpty)
        #expect(client.state.connection.problem == nil)
        client.close()
    }

    @Test func settingsCheckTellsTheTokenApartFromTheAddress() async throws {
        let info = try await RemoteClient.check(desktop)
        #expect(info.version == "2.2.1")
        #expect(desktop.requests == ["GET /health", "GET /v1/info"])
        desktop.set { $0.tokenSent = "fum_wrong" }
        await #expect(throws: Problems.unauthorized) { try await RemoteClient.check(desktop) }
    }

    @Test func typedTextGoesBeforeTheButtonPressedAfterIt() async {
        let client = client()
        client.updateSuggestion("- Bob: short replies.", on: id("M1"), in: id("C1"))
        client.cardAction(.addSuggestion, on: id("M1"), in: id("C1"))
        await eventually("both actions") { desktop.bodies.filter { $0.contains("/action") }.count == 2 }
        let actions = desktop.bodies.filter { $0.contains("/action") }
        #expect(actions[0].contains("update_suggestion"))
        #expect(actions[1].contains("add_suggestion"))
        await eventually("typed text let go") { client.state.typed.isEmpty }
        client.close()
    }

    @Test func nothingIsSentWhileTypingInTheEditor() async throws {
        let client = client()
        var opened = try decode(EditorState.self, try fixture("editor-reply.json"))
        opened.status = .idle
        client.apply(APIEvent(type: "editor_opened", editor: opened))
        client.editForm(editorID) { $0.body = "Thanks Bob" }
        client.editInstructions(editorID, "shorter")
        try await Task.sleep(for: .milliseconds(100))
        #expect(desktop.requests.isEmpty)
        // Reply all: the Mac fills in Cc.
        client.setReplyAll(editorID, true)
        await eventually("Cc") { client.state.editors[editorID]?.form.cc.isEmpty == false }
        #expect(client.state.editors[editorID]?.form.cc == "Carol <carol@example.com>")
        #expect(client.state.editors[editorID]?.form.body == "Thanks Bob")  // still what was typed
        // Save sends the form as typed.
        client.save(editorID)
        #expect(client.state.editors[editorID]?.status == .saving)
        await eventually("save") { desktop.requests.contains("POST /v1/editors/\(editorID.uuidString)/save") }
        let saved = try #require(desktop.bodies.first { $0.contains("/save") })
        #expect(saved.contains(#""body":"Thanks Bob""#))
        #expect(saved.contains(#""instructions":"shorter""#))
        #expect(saved.contains(#""replyAll":true"#))
        client.close()
    }

    @Test func aFailedSaveShowsInTheEditor() async throws {
        let client = client()
        var opened = try decode(EditorState.self, try fixture("editor-reply.json"))
        opened.status = .idle
        client.apply(APIEvent(type: "editor_opened", editor: opened))
        desktop.set { $0.status = 409 }
        client.save(editorID)
        await eventually("failed") { if case .failed = client.state.editors[editorID]?.status { true } else { false } }
        #expect(client.state.editors[editorID]?.status == .failed("nope"))
        client.close()
    }

    @Test func aNewChatIsMadeOnceAndReused() async {
        let client = client()
        #expect(await client.startConversation() == id("NEW"))
        #expect(await client.startConversation() == id("NEW"))  // the empty one there already is
        #expect(desktop.requests.filter { $0 == "POST /v1/conversations" }.count == 1)
        client.close()
    }

    @Test func historySearchSendsTheQuery() async throws {
        let client = client()
        _ = try? await client.searchHistory("bob & co+1")
        #expect(desktop.requests.contains("GET /v1/history/search?q=bob%20%26%20co%2B1"))
        #expect(try await client.searchHistory("  ").isEmpty)
        client.close()
    }

    @Test func cardsArriveAsEvents() async throws {
        let client = client()
        client.start()
        await eventually("listed") { !client.state.conversations.isEmpty }
        client.loadMessages(id("C1"))
        await eventually("loaded") { !client.state.unloaded.contains(id("C1")) }
        let message = try fixture("thread-message.json").replacingOccurrences(of: "\n", with: " ")
        desktop.push(#"{"type":"message_appended","conversationID":"\#(id("C1"))","message":\#(message)}"#)
        await eventually("the thread card") {
            client.state.conversation(id("C1"))?.messages.contains { if case .thread = $0.card { true } else { false } } == true
        }
        #expect(client.state.conversation(id("C1"))?.messages.count == 2)
        client.close()
    }

    @Test func renameAndDeleteShowAtOnce() async {
        let client = client()
        client.start()
        await eventually("listed") { !client.state.conversations.isEmpty }
        client.rename(id("C1"), to: "  Bob's mail  ")
        #expect(client.state.conversation(id("C1"))?.title == "Bob's mail")
        client.delete(id("C1"))
        #expect(client.state.conversations.isEmpty)
        await eventually("both sent") { desktop.requests.contains("DELETE /v1/conversations/\(id("C1").uuidString)") }
        #expect(desktop.bodies.contains { $0.contains(#"{"title":"Bob's mail"}"#) })
        client.close()
    }
}
