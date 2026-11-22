import Foundation

/// What arrives on the event stream.
public enum StreamItem: Sendable, Equatable {
    /// The stream is open (fetch what's shown now that events will follow).
    case opened
    /// One event's data (JSON text).
    case data(String)
}

/// The requests the client makes. `DesktopAPI` sends them to the Mac; tests use a pretend one.
public protocol DesktopTransport: Sendable {
    /// The address in Settings, for messages.
    var display: String { get }
    /// A request with an optional JSON body. Throws a `RemoteProblem` for anything but 2xx.
    func send(_ method: String, _ path: String, body: Data?) async throws -> Data
    /// `GET /health`, which needs no token. Throws unless it's FU Mail answering (`{"ok":true}`).
    func health() async throws
    /// `GET /v1/events`. Ends by throwing when the connection closes.
    func events() -> AsyncThrowingStream<StreamItem, Error>
}

/// The Mac's HTTP API over URLSession. Requests go only to the address in Settings (redirects are
/// refused), and the token goes only in the Authorization header.
public final class DesktopAPI: DesktopTransport {
    public let settings: ServerSettings
    public let auth: WorkerAuthStore?
    /// The device's time zone right now ("Europe/London"), read for every request so it follows the
    /// phone to a new zone; FU Mail counts `/now`'s day there. Replaceable for tests.
    private let timeZone: @Sendable () -> String
    /// One session for the requests and the event stream, so they share one connection (HTTP/2
    /// through Cloudflare or tailscale serve): set up once, not twice, as the Android app does.
    private let http: URLSession

    /// Short, so a Mac that doesn't answer shows as a problem soon; the API answers at once
    /// (anything slow, like a summary, arrives later as events).
    static let requestTimeout: TimeInterval = 15
    /// The event stream: the Mac pings every 25 seconds, so this long without a byte means the
    /// connection is gone (and it's inside Cloudflare's ~100-second idle limit).
    static let streamTimeout: TimeInterval = 75

    public var display: String { settings.display }
    private var authBaseURL: URL { WorkerAuth.baseURL(for: settings.url) ?? settings.url }

    /// `configuration` is for tests (a pretend server through `protocolClasses`).
    public init(settings: ServerSettings, configuration: URLSessionConfiguration = .ephemeral,
                auth: WorkerAuthStore? = nil,
                timeZone: @escaping @Sendable () -> String = { TimeZone.autoupdatingCurrent.identifier }) {
        self.settings = settings
        self.auth = auth
        self.timeZone = timeZone
        let shared = configuration.copy() as! URLSessionConfiguration
        // Each request sets its own timeout (`request(…)`); the stream has no overall limit.
        shared.timeoutIntervalForRequest = Self.streamTimeout
        shared.timeoutIntervalForResource = .infinity
        shared.httpAdditionalHeaders = ["Accept": "application/json"]
        shared.urlCache = nil
        http = URLSession(configuration: shared, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit {
        http.invalidateAndCancel()
    }

    func request(_ method: String, _ path: String, token: Bool = true, edgeToken: String? = nil) throws -> URLRequest {
        guard let url = URL(string: display + path) else { throw RemoteProblem(.server, "Bad path \(path).") }
        // Every request is built from the address in Settings, so this holds; checked anyway, since the
        // token must never go anywhere else.
        guard url.host()?.lowercased() == settings.host.lowercased() else {
            throw RemoteProblem(.cleartextBlocked, "Requests go only to the Mac in Settings (\(settings.host)), not \(url.host() ?? path).")
        }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeout)
        request.httpMethod = method
        if token { request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization") }
        request.setValue(timeZone(), forHTTPHeaderField: "X-FUMail-Time-Zone")
        // Cloudflare Worker edge token and Access headers: never over plain HTTP.
        if settings.isHTTPS {
            if let edgeToken {
                request.setValue(edgeToken, forHTTPHeaderField: "X-Edge-Token")
            }
            if let access = settings.access {
                request.setValue(access.clientID, forHTTPHeaderField: "CF-Access-Client-Id")
                request.setValue(access.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
            }
        }
        return request
    }

    public func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        func makeRequest(edgeToken: String?) throws -> URLRequest {
            var req = try request(method, path, edgeToken: edgeToken)
            if let body {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            return req
        }
        do {
            let edgeToken = settings.isHTTPS ? try await auth?.validAccessToken(using: http, authBaseURL: authBaseURL) : nil
            var (data, response) = try await http.data(for: makeRequest(edgeToken: edgeToken))
            if (response as? HTTPURLResponse)?.statusCode == 401, settings.isHTTPS, let edgeToken, let auth {
                let refreshed = try await auth.refreshAfterUnauthorized(failedAccessToken: edgeToken, using: http, authBaseURL: authBaseURL)
                (data, response) = try await http.data(for: makeRequest(edgeToken: refreshed))
            }
            try check(response, body: data)
            return data
        } catch {
            throw Problems.describe(error, url: display)
        }
    }

    public func health() async throws {
        let data: Data
        let response: URLResponse
        do {
            let edgeToken = settings.isHTTPS ? try await auth?.validAccessToken(using: http, authBaseURL: authBaseURL) : nil
            var result = try await http.data(for: try request("GET", "/health", token: false, edgeToken: edgeToken))
            if (result.1 as? HTTPURLResponse)?.statusCode == 401, settings.isHTTPS, let edgeToken, let auth {
                let refreshed = try await auth.refreshAfterUnauthorized(failedAccessToken: edgeToken, using: http, authBaseURL: authBaseURL)
                result = try await http.data(for: try request("GET", "/health", token: false, edgeToken: refreshed))
            }
            (data, response) = result
            try check(response, body: data)
        } catch {
            throw Problems.describe(error, url: display)
        }
        guard Self.isFUMailHealth(data, response) else { throw Problems.notFUMail(url: display) }
    }

    /// FU Mail's own answer to `/health`: a 2xx with `{"ok":true}`. Anything else on that address and
    /// port (a router's page, another app) doesn't count.
    static func isFUMailHealth(_ data: Data, _ response: URLResponse) -> Bool {
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { return false }
        return (try? JSONValue.parse(data))?["ok"] == .bool(true)
    }

    public func events() -> AsyncThrowingStream<StreamItem, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func makeStreamRequest(edgeToken: String?) throws -> URLRequest {
                    var req = try request("GET", "/v1/events", edgeToken: edgeToken)
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = Self.streamTimeout
                    return req
                }
                do {
                    let edgeToken = settings.isHTTPS ? try await auth?.validAccessToken(using: http, authBaseURL: authBaseURL) : nil
                    var (bytes, response) = try await http.bytes(for: makeStreamRequest(edgeToken: edgeToken))
                    if (response as? HTTPURLResponse)?.statusCode == 401, settings.isHTTPS, let edgeToken, let auth {
                        let refreshed = try await auth.refreshAfterUnauthorized(failedAccessToken: edgeToken, using: http, authBaseURL: authBaseURL)
                        (bytes, response) = try await http.bytes(for: makeStreamRequest(edgeToken: refreshed))
                    }
                    try check(response, body: nil)
                    continuation.yield(.opened)
                    // Lines split here, not with `bytes.lines`, which drops the blank lines that end events.
                    var parser = EventStreamParser()
                    var line: [UInt8] = []
                    for try await byte in bytes {
                        guard byte == UInt8(ascii: "\n") else {
                            line.append(byte)
                            continue
                        }
                        if line.last == UInt8(ascii: "\r") { line.removeLast() }
                        if let data = parser.feed(String(decoding: line, as: UTF8.self)) { continuation.yield(.data(data)) }
                        line.removeAll(keepingCapacity: true)
                    }
                    continuation.finish(throwing: RemoteProblem(.unreachable, "The connection to \(display) closed."))
                } catch {
                    continuation.finish(throwing: error is CancellationError ? error : Problems.describe(error, url: display))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func check(_ response: URLResponse, body: Data?) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return }
        let reason = body.flatMap { try? JSONValue.parse($0) }?["error"]?.stringValue
        // FU Mail never answers 403, so one without its own {"error": …} is Cloudflare Access (its HTML
        // page, or the event stream, whose body isn't read). A redirect to *.cloudflareaccess.com is
        // Access too: a policy that sends people to log in rather than checking a service token.
        let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location")
            .flatMap { URL(string: $0)?.host()?.lowercased() }
        if (status == 403 && reason == nil)
            || ((300..<400).contains(status) && (location == "cloudflareaccess.com" || location?.hasSuffix(".cloudflareaccess.com") == true)) {
            throw Problems.accessRefused(tokenSaved: settings.access != nil && settings.isHTTPS)
        }
        throw Problems.forStatus(status, reason: reason, url: display)
    }
}

/// Refuses redirects, so nothing can lead a request (and its token) to another address.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

/// Server-sent events: `data:` lines make up an event and a blank line ends it; comments (`: ping`)
/// and other fields are skipped.
struct EventStreamParser {
    private var data: [String] = []

    /// Feeds one line; returns an event's data when `line` ends one.
    mutating func feed(_ line: String) -> String? {
        if line.isEmpty {
            guard !data.isEmpty else { return nil }
            defer { data = [] }
            return data.joined(separator: "\n")
        }
        if line.hasPrefix(":") { return nil }
        let field = line.prefix { $0 != ":" }
        guard field == "data" else { return nil }
        var value = line.dropFirst(field.count)
        if value.hasPrefix(":") { value = value.dropFirst() }
        if value.hasPrefix(" ") { value = value.dropFirst() }
        data.append(String(value))
        return nil
    }
}
