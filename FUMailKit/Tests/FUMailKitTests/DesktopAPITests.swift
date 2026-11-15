import Foundation
import Synchronization
import Testing
@testable import FUMailKit

/// A pretend server inside URLSession: each test sets what it answers.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Answer: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data
    }

    static let handler = Mutex<(@Sendable (URLRequest) -> Answer?)?>(nil)
    static let seen = Mutex<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.withLock { $0.append(request) }
        guard let answer = Self.handler.withLock({ $0 })?(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The real HTTP client, through a pretend server. One suite, run in order: the stub is shared.
@Suite(.serialized)
struct DesktopAPITests {
    private func api(_ answer: @escaping @Sendable (URLRequest) -> StubProtocol.Answer?) -> DesktopAPI {
        StubProtocol.handler.withLock { $0 = answer }
        StubProtocol.seen.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let settings = try! ServerSettings.parse(url: "http://192.168.107.138:8765/", token: "fum_secret").get()
        return DesktopAPI(settings: settings, configuration: configuration)
    }

    @Test func theTokenGoesInTheHeaderAndOnlyThere() async throws {
        let api = api { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        _ = try await api.send("POST", "/v1/conversations/x/send", body: Data(#"{"text":"/unread"}"#.utf8))
        try await api.health()
        let seen = StubProtocol.seen.withLock { $0 }
        #expect(seen.map { $0.url?.absoluteString } == ["http://192.168.107.138:8765/v1/conversations/x/send",
                                                         "http://192.168.107.138:8765/health"])
        #expect(seen[0].value(forHTTPHeaderField: "Authorization") == "Bearer fum_secret")
        #expect(seen[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(seen[1].value(forHTTPHeaderField: "Authorization") == nil)  // /health needs none
    }

    @Test func healthMustBeFUMailsOwnAnswer() async throws {
        let fuMail = api { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        try await fuMail.health()
        for body in [#"{"ok":false}"#, #"{"ok":"true"}"#, "<html>Router</html>", "", #"[true]"#] {
            let other = api { _ in .init(status: 200, body: Data(body.utf8)) }
            await #expect(throws: Problems.notFUMail(url: "http://192.168.107.138:8765"), "\(body)") { try await other.health() }
        }
        #expect(Problems.notFUMail(url: "u").message == "Something answered at u, but not FU Mail's API. Check the address and the port.")
    }

    @Test func theQuickCheckSendsNoTokenAndWantsOkTrue() async {
        let fuMail = api { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        #expect(await fuMail.answersHealth(timeout: .seconds(2)))
        let seen = StubProtocol.seen.withLock { $0 }
        #expect(seen.map { $0.url?.path() } == ["/health"])
        #expect(seen.first?.value(forHTTPHeaderField: "Authorization") == nil)  // the token never goes there first
        let other = api { _ in .init(status: 200, body: Data(#"{"ok":false}"#.utf8)) }
        #expect(await !other.answersHealth(timeout: .seconds(2)))
        let error = api { _ in .init(status: 500, body: Data(#"{"ok":true}"#.utf8)) }
        #expect(await !error.answersHealth(timeout: .seconds(2)))
        let nothing = api { _ in nil }  // nothing answers: the stub fails the connection
        #expect(await !nothing.answersHealth(timeout: .seconds(2)))
    }

    @Test func theQuickCheckSaysWhyHomeDidntCount() async {
        let other = api { _ in .init(status: 200, body: Data("<html>Router</html>".utf8)) }
        #expect(await other.probeHealth(timeout: .seconds(2)) == Problems.notFUMail(url: "http://192.168.107.138:8765"))
        let nothing = api { _ in nil }
        #expect(await nothing.probeHealth(timeout: .seconds(2))?.kind == .unreachable)
        let slow = api { _ in
            Thread.sleep(forTimeInterval: 1.5)
            return .init(status: 200, body: Data(#"{"ok":true}"#.utf8))
        }
        #expect(await slow.probeHealth(timeout: .milliseconds(300))?.message.contains("didn't answer within") == true)
    }

    @Test func theQuickCheckGivesUpAfterItsTimeout() async {
        let slow = api { _ in
            Thread.sleep(forTimeInterval: 1.5)
            return .init(status: 200, body: Data(#"{"ok":true}"#.utf8))
        }
        let started = Date.now
        #expect(await !slow.answersHealth(timeout: .milliseconds(300)))
        #expect(Date.now.timeIntervalSince(started) < 1.2)
    }

    @Test func errorsComeBackInPlainWords() async {
        let api = api { _ in .init(status: 401, body: Data(#"{"error":"Unauthorized"}"#.utf8)) }
        await #expect(throws: Problems.unauthorized) { try await api.send("GET", "/v1/info", body: nil) }
        let busy = self.api { _ in .init(status: 409, body: Data(#"{"error":"Already writing."}"#.utf8)) }
        await #expect(throws: RemoteProblem(.busy, "Already writing.")) { try await busy.send("POST", "/v1/editors/e/write", body: nil) }
    }

    @Test func theEventStreamOpensThenSendsEachEvent() async throws {
        let body = ": ping\n\ndata: {\"type\":\"a\"}\n\ndata: {\"type\":\"b\"}\r\n\r\n"
        let api = api { _ in .init(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(body.utf8)) }
        var items: [StreamItem] = []
        do {
            for try await item in api.events() { items.append(item) }
            Issue.record("the stream should end by throwing")
        } catch let problem as RemoteProblem {
            #expect(problem.kind == .unreachable)
        }
        #expect(items == [.opened, .data(#"{"type":"a"}"#), .data(#"{"type":"b"}"#)])
        #expect(StubProtocol.seen.withLock { $0 }.first?.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test func aRejectedStreamSaysWhy() async {
        let api = api { _ in .init(status: 429, body: Data()) }
        await #expect(throws: Problems.lockedOut) {
            for try await _ in api.events() {}
        }
    }
}
