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
    private func api(url: String = "http://192.168.107.138:8765/", access: ServiceToken? = nil,
                     timeZone: @escaping @Sendable () -> String = { TimeZone.autoupdatingCurrent.identifier },
                     _ answer: @escaping @Sendable (URLRequest) -> StubProtocol.Answer?) -> DesktopAPI {
        StubProtocol.handler.withLock { $0 = answer }
        StubProtocol.seen.withLock { $0 = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        var settings = try! ServerSettings.parse(url: url, token: "fum_secret").get()
        settings.access = access
        return DesktopAPI(settings: settings, configuration: configuration, timeZone: timeZone)
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

    // MARK: Cloudflare Access

    private let serviceToken = ServiceToken(clientID: "abc.access", clientSecret: "s3cret")
    private let tunnel = "https://fumail.example.com"
    private let accessPage = Data("<!DOCTYPE html><html><title>Forbidden</title></html>".utf8)

    @Test func theServiceTokenGoesToHTTPSOnlyEvenToHealth() async throws {
        let ok: @Sendable (URLRequest) -> StubProtocol.Answer? = { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        let overTunnel = api(url: tunnel, access: serviceToken, ok)
        _ = try await overTunnel.send("GET", "/v1/info", body: nil)
        try await overTunnel.health()
        for request in StubProtocol.seen.withLock({ $0 }) {
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "abc.access")
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "s3cret")
        }
        let plain = api(access: serviceToken, ok)  // http://: the secret would travel in the clear
        _ = try await plain.send("GET", "/v1/info", body: nil)
        try await plain.health()
        for request in StubProtocol.seen.withLock({ $0 }) {
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
            #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
        }
        withExtendedLifetime(plain) {}
        withExtendedLifetime(overTunnel) {}
    }

    @Test func aHalfFilledServiceTokenIsRefusedAndAnEmptyOneIsNone() throws {
        #expect(try ServiceToken.parse(clientID: "", clientSecret: " ").get() == nil)
        #expect(try ServiceToken.parse(clientID: " abc.access ", clientSecret: "s").get() == ServiceToken(clientID: "abc.access", clientSecret: "s"))
        for (id, secret) in [("abc.access", ""), ("", "s3cret")] {
            guard case .failure(let invalid) = ServiceToken.parse(clientID: id, clientSecret: secret) else {
                Issue.record("half-filled accepted"); continue
            }
            #expect(invalid.message.contains("or neither"))
        }
        #expect(ServiceToken.clientIDHint("abc.access") == nil)
        #expect(ServiceToken.clientIDHint("s3cret") != nil)
        let settings = ServerSettings(url: URL(string: tunnel)!, token: "fum_secret", access: serviceToken)
        #expect(!settings.description.contains("s3cret") && !settings.description.contains("fum_secret"))
    }

    @Test func aForbiddenPageIsCloudflareAccessTurningUsAway() async {
        let page = accessPage
        let without = api(url: tunnel) { _ in .init(status: 403, body: page) }
        await #expect(throws: Problems.accessRefused(tokenSaved: false)) { _ = try await without.send("GET", "/v1/info", body: nil) }
        await #expect(throws: Problems.accessRefused(tokenSaved: false)) { try await without.health() }
        let wrong = api(url: tunnel, access: serviceToken) { _ in .init(status: 403, body: page) }
        await #expect(throws: Problems.accessRefused(tokenSaved: true)) { _ = try await wrong.send("GET", "/v1/info", body: nil) }
        #expect(Problems.accessRefused(tokenSaved: true).message.contains("hasn't expired"))
        #expect(Problems.accessRefused(tokenSaved: false).message.contains("needs a service token"))
        let login = api(url: tunnel, access: serviceToken) { _ in
            .init(status: 302, headers: ["Location": "https://team.cloudflareaccess.com/cdn-cgi/access/login"], body: Data())
        }
        await #expect(throws: Problems.accessRefused(tokenSaved: true)) { _ = try await login.send("GET", "/v1/info", body: nil) }
    }

    @Test func otherAnswersKeepTheirMessages() async {
        let page = accessPage
        let wrongToken = api(url: tunnel, access: serviceToken) { _ in .init(status: 401, body: page) }
        await #expect(throws: Problems.unauthorized) { _ = try await wrongToken.send("GET", "/v1/info", body: nil) }
        let lockedOut = api(url: tunnel, access: serviceToken) { _ in .init(status: 429, body: page) }
        await #expect(throws: Problems.lockedOut) { _ = try await lockedOut.send("GET", "/v1/info", body: nil) }
        let fuMail = api(url: tunnel, access: serviceToken) { _ in .init(status: 403, body: Data(#"{"error":"Not here."}"#.utf8)) }
        await #expect(throws: RemoteProblem(.server, "Not here.")) { _ = try await fuMail.send("GET", "/v1/info", body: nil) }
        let elsewhere = api(url: tunnel) { _ in .init(status: 302, headers: ["Location": "https://example.com/"], body: Data()) }
        await #expect(throws: RemoteProblem.self) {
            do { _ = try await elsewhere.send("GET", "/v1/info", body: nil) } catch let problem as RemoteProblem {
                #expect(problem.kind == .server && problem.message.contains("redirect"))
                throw problem
            }
        }
    }

    @Test func requestsAndTheStreamShareOneSessionWithTheirOwnTimeouts() async throws {
        let api = api { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        _ = try await api.send("GET", "/v1/info", body: nil)
        for try await _ in api.events() { break }  // opened
        let seen = StubProtocol.seen.withLock { $0 }
        #expect(seen.first { $0.url?.path() == "/v1/info" }?.timeoutInterval == DesktopAPI.requestTimeout)
        #expect(seen.first { $0.url?.path() == "/v1/events" }?.timeoutInterval == DesktopAPI.streamTimeout)
        #expect(DesktopAPI.requestTimeout == 15 && DesktopAPI.streamTimeout == 75)
    }

    @Test func everyRequestSaysTheDevicesTimeZoneAsItIsNow() async throws {
        let zone = Mutex("Europe/London")
        let api = api(timeZone: { zone.withLock { $0 } }) { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        _ = try await api.send("POST", "/v1/conversations/x/send", body: Data(#"{"text":"/now"}"#.utf8))
        try await api.health()
        for try await _ in api.events() { break }  // opened
        let seen = StubProtocol.seen.withLock { $0 }
        #expect(seen.count == 3)
        for request in seen { #expect(request.value(forHTTPHeaderField: "X-FUMail-Time-Zone") == "Europe/London") }
        zone.withLock { $0 = "Asia/Tokyo" }  // landed somewhere else
        _ = try await api.send("GET", "/v1/info", body: nil)
        #expect(StubProtocol.seen.withLock { $0 }.last?.value(forHTTPHeaderField: "X-FUMail-Time-Zone") == "Asia/Tokyo")
    }

    @Test func theDevicesOwnZoneByDefault() async throws {
        let api = api { _ in .init(status: 200, body: Data(#"{"ok":true}"#.utf8)) }
        try await api.health()
        #expect(StubProtocol.seen.withLock { $0 }.first?.value(forHTTPHeaderField: "X-FUMail-Time-Zone")
                == TimeZone.autoupdatingCurrent.identifier)
    }

    // MARK: Rest of Today (GET /v1/calendar/now)

    private static let utc = TimeZone(identifier: "UTC")!
    private static let british = Locale(identifier: "en_GB")  // 24-hour

    private func event(_ title: String, _ start: String?, _ end: String?, allDay: Bool = false,
                       location: String? = nil, video: Bool = false) -> String {
        let fields: [String] = [#""server":"google","eventID":"\#(title)","title":"\#(title)""#,
                                start.map { #""start":"\#($0)""# }, end.map { #""end":"\#($0)""# },
                                #""allDay":\#(allDay)"#, location.map { #""location":"\#($0)""# },
                                video ? #""videoLink":"https://meet.example/x""# : nil,
                                #""organizedByMe":false,"recurring":false"#].compactMap { $0 }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func nowCard(_ events: [String], problems: [String] = []) -> Data {
        let problemList = problems.map { #""\#($0)""# }.joined(separator: ",")
        return Data(#"{"kind":{"days":{"_0":1}},"events":[\#(events.joined(separator: ","))],"problems":[\#(problemList)],"duplicatesRemoved":0,"from":"2026-11-19T09:00:00Z","timeZone":"Australia/Sydney"}"#.utf8)
    }

    @Test func restOfTodayAsksWithTheAppsOwnConnection() async {
        let body = nowCard([event("Board meeting", "2026-11-19T14:00:00Z", "2026-11-19T15:00:00Z", location: "Level 3")])
        let api = api(url: tunnel, access: serviceToken, timeZone: { "Australia/Sydney" }) { _ in .init(status: 200, body: body) }
        let text = await RestOfToday.fetch(api, timeZone: Self.utc, locale: Self.british)
        #expect(text == "14:00–15:00 Board meeting (Level 3)")
        let request = StubProtocol.seen.withLock { $0 }.last
        #expect(request?.url?.absoluteString == "https://fumail.example.com/v1/calendar/now")
        #expect(request?.httpMethod == "GET")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer fum_secret")
        #expect(request?.value(forHTTPHeaderField: "CF-Access-Client-Id") == "abc.access")
        #expect(request?.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "s3cret")
        #expect(request?.value(forHTTPHeaderField: "X-FUMail-Time-Zone") == "Australia/Sydney")
    }

    @Test func restOfTodayLinesForTimedAllDayAndEmpty() throws {
        func text(_ data: Data) throws -> String {
            RestOfToday.text(try APICoding.decoder.decode(EventListCard.self, from: data), timeZone: Self.utc, locale: Self.british)
        }
        let day = nowCard([event("Board meeting", "2026-11-19T14:00:00Z", "2026-11-19T15:00:00Z", location: "Level 3"),
                           event("Call with Bob", "2026-11-19T16:30:00Z", "2026-11-19T17:00:00Z", video: true),
                           event("Public holiday", "2026-11-19T00:00:00Z", "2026-11-20T00:00:00Z", allDay: true)],
                          problems: ["Couldn't read the Outlook calendar."])
        #expect(try text(day) == """
            14:00–15:00 Board meeting (Level 3)
            16:30–17:00 Call with Bob (video call)
            All day: Public holiday
            Couldn't read the Outlook calendar.
            """)
        #expect(try text(nowCard([])) == "Nothing more on today.")
        // The phone's own clock style: 12-hour where that's the setting.
        let us = RestOfToday.text(try APICoding.decoder.decode(EventListCard.self, from: nowCard([event("Lunch", "2026-11-19T13:00:00Z", nil)])),
                                  timeZone: Self.utc, locale: Locale(identifier: "en_US"))
        #expect(us.hasPrefix("1:00") && us.hasSuffix("Lunch"))
    }

    @Test func restOfTodaySaysWhatWentWrongInPlainWords() async {
        let page = accessPage
        let refused = api(url: tunnel) { _ in .init(status: 401, body: Data(#"{"error":"Unauthorized"}"#.utf8)) }
        #expect(await RestOfToday.fetch(refused) == Problems.unauthorized.message)
        let access = api(url: tunnel, access: serviceToken) { _ in .init(status: 403, body: page) }
        #expect(await RestOfToday.fetch(access) == Problems.accessRefused(tokenSaved: true).message)
        let nobody = api(url: tunnel) { _ in nil }  // nothing answers
        #expect(await RestOfToday.fetch(nobody).hasPrefix("Can't reach https://fumail.example.com"))
        let older = api(url: tunnel) { _ in .init(status: 200, body: Data("[]".utf8)) }
        #expect(await RestOfToday.fetch(older).contains("4.6.0"))
        #expect(RestOfToday.notSetUp.contains("Open the app"))
    }
}
