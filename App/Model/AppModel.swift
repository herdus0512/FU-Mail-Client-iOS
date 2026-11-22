import FUMailKit
import Foundation
import Observation

/// The app: one connection to the Mac, over Tailscale or a Cloudflare Worker, at a time. Its event
/// stream is open while the app is on screen and closed in the background (nothing runs there);
/// coming back reconnects and fetches again.
@MainActor
@Observable
final class AppModel {
    /// nil until Settings has an address and a token.
    private(set) var client: RemoteClient?
    private(set) var tailscaleURL: String
    private(set) var hasToken: Bool
    private(set) var workerSession: WorkerSession?
    var needsGoogleSignIn = false

    @ObservationIgnored private var onScreen = false
    @ObservationIgnored private let workerAuth: WorkerAuthStore

    private static let tailscaleKey = "tailscaleURL"
    /// Left over from before 3.1 (the home address, and the one address of 0.7 and earlier).
    private static let oldKeys = ["homeURL", "macURL"]

    /// Settings has what's needed to connect.
    var isConfigured: Bool { hasToken && !tailscaleURL.isEmpty }

    init() {
        let defaults = UserDefaults.standard
        Self.oldKeys.forEach(defaults.removeObject(forKey:))
        tailscaleURL = defaults.string(forKey: Self.tailscaleKey) ?? ""
        TokenStore.removeLegacyAccess()
        TokenStore.upgradeAccessibility()
        let savedSession = TokenStore.loadWorkerSession()
        workerSession = savedSession
        var token = TokenStore.load()
        #if DEBUG
        // `make run-fake`: the simulator against tools/fake_mac.py, without typing into Settings.
        // Debug only; nothing is saved.
        let environment = ProcessInfo.processInfo.environment
        if let fake = environment["FUMAIL_TOKEN"] {
            tailscaleURL = environment["FUMAIL_URL"] ?? ""
            token = fake
        }
        #endif
        hasToken = token != nil

        workerAuth = WorkerAuthStore(session: savedSession) { newSession, _ in
            try? TokenStore.saveWorkerSession(newSession)
        }
        Task { [weak self] in
            await self?.workerAuth.setOnChange { [weak self] newSession, expired in
                try? TokenStore.saveWorkerSession(newSession)
                Task { @MainActor [weak self] in
                    self?.workerSession = newSession
                    if expired { self?.needsGoogleSignIn = true }
                }
            }
        }

        if let token { connect(token: token) }
    }

    /// The token saved on this device, for checking new settings that leave the token field empty.
    func savedToken() -> String? { TokenStore.load() }

    /// `GET /health`, then `GET /v1/info`, at one address with settings not saved yet.
    func check(_ settings: ServerSettings) async throws -> APIInfo {
        try await RemoteClient.check(DesktopAPI(settings: settings, auth: workerAuth))
    }

    /// Saves the address (a nil token keeps the saved one) and connects with them.
    func save(tailscale: String, newToken: String?) throws {
        if let newToken { try TokenStore.save(newToken) }
        UserDefaults.standard.set(tailscale, forKey: Self.tailscaleKey)
        tailscaleURL = tailscale
        hasToken = true
        if let token = newToken ?? TokenStore.load() { connect(token: token) }
    }

    func forgetToken() {
        TokenStore.delete()
        hasToken = false
        client?.close()
        client = nil
    }

    func authBaseURL(for urlText: String? = nil) -> URL? {
        let raw = (urlText ?? tailscaleURL).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let parsed = URL(string: raw) else { return nil }
        return WorkerAuth.baseURL(for: parsed)
    }

    func signInWithGoogle(serverURL: String? = nil) async throws -> WorkerSession {
        guard let baseURL = authBaseURL(for: serverURL) else {
            throw RemoteProblem(.server, "Enter an https:// address in Settings first.")
        }
        let callbackURL = try await GoogleWebAuth.signIn(url: WorkerAuth.loginURL(baseURL: baseURL))
        let code = try WorkerAuth.authorizationCode(from: callbackURL)
        let session = try await WorkerAuth.exchangeCode(code, baseURL: baseURL)
        try TokenStore.saveWorkerSession(session)
        await workerAuth.replaceSession(session)
        workerSession = session
        needsGoogleSignIn = false
        if let token = TokenStore.load(), isConfigured {
            connect(token: token)
        }
        return session
    }

    func signOutGoogle(serverURL: String? = nil) async {
        if let baseURL = authBaseURL(for: serverURL), let refreshToken = workerSession?.refreshToken {
            await WorkerAuth.logout(refreshToken: refreshToken, baseURL: baseURL)
        }
        try? TokenStore.saveWorkerSession(nil)
        await workerAuth.replaceSession(nil)
        workerSession = nil
        needsGoogleSignIn = false
        if let token = TokenStore.load(), isConfigured {
            connect(token: token)
        }
    }

    /// The app came on screen or went away. Coming back while not connected tries again at once.
    func setOnScreen(_ visible: Bool) {
        onScreen = visible
        guard let client else { return }
        if !visible {
            client.stop()
        } else if !client.state.connection.connected {
            client.stop()
            client.start()
        }
    }

    private func connect(token: String) {
        client?.close()
        client = nil
        guard !tailscaleURL.isEmpty, case .success(let settings) = ServerSettings.parse(url: tailscaleURL, token: token)
        else { return }
        let fresh = RemoteClient(transport: DesktopAPI(settings: settings, auth: workerAuth))
        client = fresh
        if onScreen { fresh.start() }
    }
}

enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
