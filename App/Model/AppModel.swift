import FUMailKit
import Foundation
import Observation

/// The app: one connection to the Mac at a time. Its event stream is open while the app is on screen
/// and closed in the background (nothing runs there); coming back reconnects and fetches again.
@MainActor
@Observable
final class AppModel {
    /// nil until Settings has an address and a token.
    private(set) var client: RemoteClient?
    private(set) var savedURL: String
    private(set) var hasToken: Bool
    @ObservationIgnored private var onScreen = false

    private static let urlKey = "macURL"

    init() {
        savedURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        var token = TokenStore.load()
        #if DEBUG
        // `make run-fake`: the simulator against tools/fake_mac.py, without typing into Settings.
        // Debug builds only; nothing is saved.
        let environment = ProcessInfo.processInfo.environment
        if let url = environment["FUMAIL_URL"], let fake = environment["FUMAIL_TOKEN"] {
            savedURL = url
            token = fake
        }
        #endif
        hasToken = token != nil
        if let token, case .success(let settings) = ServerSettings.parse(url: savedURL, token: token) {
            connect(settings)
        }
    }

    /// The token saved on this device, for checking new settings that leave the token field empty.
    func savedToken() -> String? { TokenStore.load() }

    /// `GET /health`, then `GET /v1/info`, with settings not saved yet.
    func check(_ settings: ServerSettings) async throws -> APIInfo {
        try await RemoteClient.check(DesktopAPI(settings: settings))
    }

    /// Saves the settings (a nil token keeps the saved one) and connects with them.
    func save(_ settings: ServerSettings, newToken: String?) throws {
        if let newToken { try TokenStore.save(newToken) }
        UserDefaults.standard.set(settings.display, forKey: Self.urlKey)
        savedURL = settings.display
        hasToken = true
        connect(settings)
    }

    func forgetToken() {
        TokenStore.delete()
        hasToken = false
        client?.close()
        client = nil
    }

    /// The app came on screen or went away. Coming back while not connected tries again at once,
    /// e.g. after answering iOS's Local Network question or turning it on in Settings.
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

    private func connect(_ settings: ServerSettings) {
        client?.close()
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
