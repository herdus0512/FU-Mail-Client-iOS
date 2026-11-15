import FUMailKit
import Foundation
import Observation

/// The app: one connection to the Mac at a time. Its event stream is open while the app is on screen
/// and closed in the background (nothing runs there); coming back reconnects and fetches again.
///
/// With two addresses (at home and Tailscale) it uses the home one on Wi-Fi when FU Mail answers
/// there and Tailscale otherwise, picks again on every reconnect, and reconnects at once (after the
/// network settles) when Wi-Fi comes or goes.
@MainActor
@Observable
final class AppModel {
    /// nil until Settings has an address and a token.
    private(set) var client: RemoteClient?
    private(set) var homeURL: String
    private(set) var tailscaleURL: String
    private(set) var hasToken: Bool

    @ObservationIgnored private var onScreen = false
    @ObservationIgnored private let wifi = WiFiState()
    @ObservationIgnored private var watcher: NetworkWatcher?
    /// The first Wi-Fi reading is in (or waiting for it took too long): connecting may start.
    @ObservationIgnored private var knowsWifi = false
    @ObservationIgnored private var wifiSettle: Task<Void, Never>?
    @ObservationIgnored private var changeSettle: Task<Void, Never>?

    private static let homeKey = "homeURL"
    private static let tailscaleKey = "tailscaleURL"
    /// The one address saved before there were two (0.7 and earlier).
    private static let oldKey = "macURL"

    /// Settings has what's needed to connect.
    var isConfigured: Bool { hasToken && !(homeURL.isEmpty && tailscaleURL.isEmpty) }

    init() {
        let defaults = UserDefaults.standard
        Self.upgradeSavedAddress(defaults)
        homeURL = defaults.string(forKey: Self.homeKey) ?? ""
        tailscaleURL = defaults.string(forKey: Self.tailscaleKey) ?? ""
        var token = TokenStore.load()
        var forcedWifi: Bool?
        #if DEBUG
        // `make run-fake`: the simulator against tools/fake_mac.py, without typing into Settings, and
        // (FUMAIL_WIFI) pretending to be on Wi-Fi or not, which the Simulator can't switch. Debug only;
        // nothing is saved.
        let environment = ProcessInfo.processInfo.environment
        if let fake = environment["FUMAIL_TOKEN"] {
            homeURL = environment["FUMAIL_HOME"] ?? environment["FUMAIL_URL"] ?? ""
            tailscaleURL = environment["FUMAIL_TAILSCALE"] ?? ""
            token = fake
        }
        forcedWifi = environment["FUMAIL_WIFI"].map { $0 == "1" }
        #endif
        hasToken = token != nil
        if let token { connect(token: token) }
        watchWifi(forced: forcedWifi)
    }

    /// Moves the one address saved by 0.7 and earlier into the right field, once.
    private static func upgradeSavedAddress(_ defaults: UserDefaults) {
        guard let old = defaults.string(forKey: oldKey) else { return }
        if defaults.string(forKey: homeKey) == nil, defaults.string(forKey: tailscaleKey) == nil {
            let (home, tailscale) = SavedAddresses.upgrade(old)
            defaults.set(home, forKey: homeKey)
            defaults.set(tailscale, forKey: tailscaleKey)
        }
        defaults.removeObject(forKey: oldKey)
    }

    /// The token saved on this device, for checking new settings that leave the token field empty.
    func savedToken() -> String? { TokenStore.load() }

    /// `GET /health`, then `GET /v1/info`, at one address with settings not saved yet.
    func check(_ settings: ServerSettings) async throws -> APIInfo {
        try await RemoteClient.check(DesktopAPI(settings: settings))
    }

    /// Saves the addresses ("" for none; a nil token keeps the saved one) and connects with them.
    func save(home: String, tailscale: String, newToken: String?) throws {
        if let newToken { try TokenStore.save(newToken) }
        UserDefaults.standard.set(home, forKey: Self.homeKey)
        UserDefaults.standard.set(tailscale, forKey: Self.tailscaleKey)
        homeURL = home
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

    /// The app came on screen or went away. Coming back while not connected tries again at once,
    /// picking the address again (e.g. after answering iOS's Local Network question).
    func setOnScreen(_ visible: Bool) {
        onScreen = visible
        guard let client else { return }
        if !visible {
            client.stop()
        } else if knowsWifi, !client.state.connection.connected {
            client.stop()
            client.start()
        }
    }

    private func connect(token: String) {
        client?.close()
        client = nil
        func transport(_ text: String) -> DesktopAPI? {
            guard !text.isEmpty, case .success(let settings) = ServerSettings.parse(url: text, token: token) else { return nil }
            return DesktopAPI(settings: settings)
        }
        let wifi = self.wifi
        guard let picker = EndpointPicker(home: transport(homeURL), tailscale: transport(tailscaleURL),
                                          onWifi: { wifi.onWifi }) else { return }
        let fresh = RemoteClient(picker: picker)
        client = fresh
        // Not before the first Wi-Fi reading, so it doesn't start on Tailscale and switch a moment later.
        if onScreen, knowsWifi { fresh.start() }
    }

    // MARK: Wi-Fi

    private func watchWifi(forced: Bool?) {
        if let forced {
            reading(forced)
            return
        }
        let watcher = NetworkWatcher(onWifiReading: { [weak self] onWifi in self?.reading(onWifi) },
                                     onChange: { [weak self] in self?.networkChanged() })
        self.watcher = watcher
        watcher.start()
        // The first reading comes within moments; don't hold the connection for longer than a second.
        Task {
            try? await Task.sleep(for: .seconds(1))
            if !knowsWifi { firstReading() }
        }
    }

    private func reading(_ onWifi: Bool) {
        let was = wifi.onWifi
        wifi.set(onWifi)
        guard knowsWifi else {
            firstReading()
            return
        }
        // Only a change of "on Wi-Fi" counts, and only with both addresses set; wait for the network
        // to settle (addresses, routes) before asking the home address.
        guard was != onWifi, client?.picker.hasBoth == true else { return }
        wifiSettle?.cancel()
        wifiSettle = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            client?.reconnect()
        }
    }

    /// Something else about the network changed, e.g. the VPN (Tailscale) came or went while Wi-Fi
    /// stayed. On Wi-Fi and not using the home address, check it (no token) once the network has
    /// settled, and move to it if FU Mail answers there, rather than keep retrying Tailscale.
    private func networkChanged() {
        guard knowsWifi, wifi.onWifi, client?.picker.hasBoth == true else { return }
        changeSettle?.cancel()
        changeSettle = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await client?.switchHomeIfItAnswers()
        }
    }

    private func firstReading() {
        knowsWifi = true
        if onScreen { client?.start() }
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
