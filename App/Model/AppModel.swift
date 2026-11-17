import FUMailKit
import Foundation
import Observation

/// The app: one connection to the Mac, over Tailscale, at a time. Its event stream is open while the
/// app is on screen and closed in the background (nothing runs there); coming back reconnects and
/// fetches again.
@MainActor
@Observable
final class AppModel {
    /// nil until Settings has an address and a token.
    private(set) var client: RemoteClient?
    private(set) var tailscaleURL: String
    private(set) var hasToken: Bool

    @ObservationIgnored private var onScreen = false

    private static let tailscaleKey = "tailscaleURL"
    /// Left over from before 3.1 (the home address, and the one address of 0.7 and earlier).
    private static let oldKeys = ["homeURL", "macURL"]

    /// Settings has what's needed to connect.
    var isConfigured: Bool { hasToken && !tailscaleURL.isEmpty }

    init() {
        let defaults = UserDefaults.standard
        Self.oldKeys.forEach(defaults.removeObject(forKey:))
        tailscaleURL = defaults.string(forKey: Self.tailscaleKey) ?? ""
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
        if let token { connect(token: token) }
    }

    /// The token saved on this device, for checking new settings that leave the token field empty.
    func savedToken() -> String? { TokenStore.load() }

    /// The Cloudflare Access service token saved on this device, if any.
    func savedAccess() -> ServiceToken? { TokenStore.loadAccess() }

    /// `GET /health`, then `GET /v1/info`, at one address with settings not saved yet.
    func check(_ settings: ServerSettings) async throws -> APIInfo {
        try await RemoteClient.check(DesktopAPI(settings: settings))
    }

    /// Saves the address (a nil token keeps the saved one) and the service token (nil: none), and
    /// connects with them.
    func save(tailscale: String, newToken: String?, access: ServiceToken?) throws {
        if let newToken { try TokenStore.save(newToken) }
        try TokenStore.saveAccess(access)
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
        guard !tailscaleURL.isEmpty, case .success(var settings) = ServerSettings.parse(url: tailscaleURL, token: token)
        else { return }
        settings.access = TokenStore.loadAccess()
        let fresh = RemoteClient(transport: DesktopAPI(settings: settings))
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
