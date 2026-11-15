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
    /// Whether FU Mail answers `/health` here within `timeout`, without the token. Never throws: for
    /// choosing between the home and Tailscale addresses.
    func answersHealth(timeout: Duration) async -> Bool
    /// `GET /v1/events`. Ends by throwing when the connection closes.
    func events() -> AsyncThrowingStream<StreamItem, Error>
}

/// The Mac's HTTP API over URLSession. Requests go only to the address in Settings (redirects are
/// refused), and the token goes only in the Authorization header.
public final class DesktopAPI: DesktopTransport {
    public let settings: ServerSettings
    private let http: URLSession
    private let stream: URLSession

    public var display: String { settings.display }

    /// `configuration` is for tests (a pretend server through `protocolClasses`).
    public init(settings: ServerSettings, configuration: URLSessionConfiguration = .ephemeral) {
        self.settings = settings
        let requests = configuration.copy() as! URLSessionConfiguration
        // Short, so a Mac that doesn't answer shows as a problem soon; the API answers at once
        // (anything slow, like a summary, arrives later as events).
        requests.timeoutIntervalForRequest = 15
        requests.httpAdditionalHeaders = ["Accept": "application/json"]
        requests.urlCache = nil
        http = URLSession(configuration: requests, delegate: NoRedirects(), delegateQueue: nil)
        let streaming = configuration.copy() as! URLSessionConfiguration
        // The Mac pings every 25 seconds; this long without a byte means the connection is gone.
        streaming.timeoutIntervalForRequest = 75
        streaming.timeoutIntervalForResource = .infinity
        streaming.urlCache = nil
        stream = URLSession(configuration: streaming, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit {
        http.invalidateAndCancel()
        stream.invalidateAndCancel()
    }

    func request(_ method: String, _ path: String, token: Bool = true) throws -> URLRequest {
        guard let url = URL(string: display + path) else { throw RemoteProblem(.server, "Bad path \(path).") }
        // Every request is built from the address in Settings, so this holds; checked anyway, since the
        // token must never go anywhere else.
        guard url.host()?.lowercased() == settings.host.lowercased() else {
            throw RemoteProblem(.cleartextBlocked, "Requests go only to the Mac in Settings (\(settings.host)), not \(url.host() ?? path).")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if token { request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    public func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        var request = try request(method, path)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await http.data(for: request)
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
            (data, response) = try await http.data(for: try request("GET", "/health", token: false))
            try check(response, body: data)
        } catch {
            throw Problems.describe(error, url: display)
        }
        guard Self.isFUMailHealth(data, response) else { throw Problems.notFUMail(url: display) }
    }

    public func answersHealth(timeout: Duration) async -> Bool {
        guard var request = try? request("GET", "/health", token: false) else { return false }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        request.timeoutInterval = seconds
        let probe = request
        let http = self.http
        // The request's own timeout covers a silent address; the race covers a slow answer too.
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                guard let (data, response) = try? await http.data(for: probe) else { return false }
                return Self.isFUMailHealth(data, response)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
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
                do {
                    var request = try request("GET", "/v1/events")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await stream.bytes(for: request)
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
