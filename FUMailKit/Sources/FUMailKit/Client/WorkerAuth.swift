import Foundation

/// A Cloudflare Worker Google OAuth session, kept in the Keychain alongside the Mac's `fum_…` device token.
public struct WorkerSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var sub: String?
    public var email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, sub: String? = nil, email: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.sub = sub
        self.email = email
    }

    /// True when `expiresAt` is within `leeway` seconds of `now`.
    public func needsRefresh(now: Date = .now, leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

/// JSON returned by `POST /auth/token` and `POST /auth/refresh`.
public struct WorkerTokenResponse: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresIn: TimeInterval
    public var sub: String?
    public var email: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case sub
        case email
    }

    public func session(now: Date = .now) -> WorkerSession {
        WorkerSession(accessToken: accessToken,
                      refreshToken: refreshToken,
                      expiresAt: now.addingTimeInterval(expiresIn),
                      sub: sub,
                      email: email)
    }
}

/// Endpoints and helpers for the Cloudflare Worker's Google OAuth flow.
public enum WorkerAuth {
    public static let callbackScheme = "fumail"
    public static let redirectURI = "fumail://auth/callback"

    /// Returns the `https://` origin of `serverURL`, or `nil` when not `https://`.
    public static func baseURL(for serverURL: URL?) -> URL? {
        guard let serverURL,
              serverURL.scheme?.lowercased() == "https",
              let host = serverURL.host, !host.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = serverURL.port
        return components.url
    }

    public static func loginURL(baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "/auth/login"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "redirect_uri", value: redirectURI)]
        return components.url!
    }

    /// Extracts the one-time authorization code from `fumail://auth/callback?code=…`.
    public static func authorizationCode(from callbackURL: URL) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw RemoteProblem(.unauthorized, "Google sign-in failed (\(error)).")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw RemoteProblem(.badResponse, "Google sign-in didn't return an authorization code.")
        }
        return code
    }

    /// Exchanges the one-time authorization code at `POST /auth/token` for Worker tokens.
    public static func exchangeCode(_ code: String, baseURL: URL, using http: URLSession = .shared,
                                    now: Date = .now) async throws -> WorkerSession {
        var request = URLRequest(url: baseURL.appending(path: "/auth/token"), timeoutInterval: DesktopAPI.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["code": code])
        let (data, response) = try await http.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = (try? JSONValue.parse(data))?["error"]?.stringValue
            if status == 403 {
                throw RemoteProblem(.unauthorized, reason ?? "This Google account isn't on the Worker's allowlist.")
            }
            throw Problems.forStatus(status, reason: reason, url: baseURL.absoluteString)
        }
        let decoded = try JSONDecoder().decode(WorkerTokenResponse.self, from: data)
        return decoded.session(now: now)
    }

    /// Best-effort revocation on sign out (`POST /auth/logout`).
    public static func logout(refreshToken: String, baseURL: URL, using http: URLSession = .shared) async {
        var request = URLRequest(url: baseURL.appending(path: "/auth/logout"), timeoutInterval: DesktopAPI.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])
        _ = try? await http.data(for: request)
    }
}

/// Holds the active Worker session and coalesces concurrent `POST /auth/refresh` calls into one.
public actor WorkerAuthStore {
    private var session: WorkerSession?
    private var refreshTask: Task<WorkerSession, Error>?
    private let now: @Sendable () -> Date
    /// Called when the session rotates or is cleared; `expired` is true only when `/auth/refresh` returned 401.
    private var onChange: @Sendable (WorkerSession?, Bool) -> Void

    public init(session: WorkerSession?,
                onChange: @escaping @Sendable (WorkerSession?, Bool) -> Void = { _, _ in },
                now: @escaping @Sendable () -> Date = { .now }) {
        self.session = session
        self.onChange = onChange
        self.now = now
    }

    public func setOnChange(_ handler: @escaping @Sendable (WorkerSession?, Bool) -> Void) {
        onChange = handler
    }

    public func currentSession() -> WorkerSession? { session }

    public func replaceSession(_ newSession: WorkerSession?) {
        refreshTask?.cancel()
        refreshTask = nil
        session = newSession
    }

    /// Returns a non-expiring access token, refreshing once if `expiresAt` is within 60 seconds.
    public func validAccessToken(using http: URLSession, authBaseURL: URL) async throws -> String? {
        guard let session else { return nil }
        if !session.needsRefresh(now: now()) {
            return session.accessToken
        }
        return try await refresh(using: http, authBaseURL: authBaseURL).accessToken
    }

    /// Refreshes after a `401` unless another concurrent request already rotated the token.
    public func refreshAfterUnauthorized(failedAccessToken: String, using http: URLSession, authBaseURL: URL) async throws -> String {
        guard let session else { throw Problems.googleSignInRequired }
        if session.accessToken != failedAccessToken, !session.needsRefresh(now: now()) {
            return session.accessToken
        }
        return try await refresh(using: http, authBaseURL: authBaseURL).accessToken
    }

    private func refresh(using http: URLSession, authBaseURL: URL) async throws -> WorkerSession {
        if let existing = refreshTask {
            return try await existing.value
        }
        guard let current = session else { throw Problems.googleSignInRequired }
        let nowProvider = now
        let task = Task<WorkerSession, Error> {
            var request = URLRequest(url: authBaseURL.appending(path: "/auth/refresh"), timeoutInterval: DesktopAPI.requestTimeout)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(["refresh_token": current.refreshToken])
            let (data, response) = try await http.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                throw Problems.googleSignInRequired
            }
            guard (200..<300).contains(status) else {
                let reason = (try? JSONValue.parse(data))?["error"]?.stringValue
                throw Problems.forStatus(status, reason: reason, url: authBaseURL.absoluteString)
            }
            let decoded = try JSONDecoder().decode(WorkerTokenResponse.self, from: data)
            var updated = decoded.session(now: nowProvider())
            if updated.email == nil { updated.email = current.email }
            if updated.sub == nil { updated.sub = current.sub }
            return updated
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let updated = try await task.value
            session = updated
            onChange(updated, false)
            return updated
        } catch let problem as RemoteProblem where problem == Problems.googleSignInRequired {
            session = nil
            onChange(nil, true)
            throw problem
        }
    }
}
