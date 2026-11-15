import Foundation

/// One way to reach the Mac: its API, and what to call it in the app ("Home", "Tailscale"; nil when
/// there's only one address).
public struct Endpoint: Sendable {
    public let label: String?
    public let transport: any DesktopTransport

    public init(label: String?, transport: any DesktopTransport) {
        self.label = label
        self.transport = transport
    }
}

/// Two addresses for the same Mac: one on the home Wi-Fi, one over Tailscale. The same rule as the
/// Android app's `EndpointPicker`, so both phones agree:
/// 1. with only one address, that one;
/// 2. off Wi-Fi, Tailscale, without contacting the home address at all;
/// 3. on Wi-Fi, Home when FU Mail answers its `/health` (no token, within 2 seconds), else Tailscale.
/// The client asks again on every (re)connect, so a home address that stops answering falls over to
/// Tailscale on the next attempt. The token never goes to the home address until FU Mail itself has
/// answered there, so another network using the same 192.168.x range doesn't get it.
public struct EndpointPicker: Sendable {
    public static let homeLabel = "Home"
    public static let tailscaleLabel = "Tailscale"

    public let home: Endpoint?
    public let tailscale: Endpoint?
    private let onWifi: @Sendable () -> Bool
    private let probeTimeout: Duration

    /// nil when neither address is set. Labels only when there's a choice to show.
    public init?(home: (any DesktopTransport)?, tailscale: (any DesktopTransport)?,
                 onWifi: @escaping @Sendable () -> Bool, probeTimeout: Duration = .seconds(2)) {
        guard home != nil || tailscale != nil else { return nil }
        let both = home != nil && tailscale != nil
        self.home = home.map { Endpoint(label: both ? Self.homeLabel : nil, transport: $0) }
        self.tailscale = tailscale.map { Endpoint(label: both ? Self.tailscaleLabel : nil, transport: $0) }
        self.onWifi = onWifi
        self.probeTimeout = probeTimeout
    }

    /// One address only, always used.
    public init(only transport: any DesktopTransport) {
        home = Endpoint(label: nil, transport: transport)
        tailscale = nil
        onWifi = { true }
        probeTimeout = .seconds(2)
    }

    /// Both addresses are set, so Wi-Fi coming or going matters.
    public var hasBoth: Bool { home != nil && tailscale != nil }

    /// The likely one before anything's been asked (for showing an address straight away).
    public var first: Endpoint { ((onWifi() ? home : tailscale) ?? home ?? tailscale)! }

    public func pick() async -> Endpoint {
        guard let home else { return tailscale! }
        guard let tailscale else { return home }
        guard onWifi() else { return tailscale }
        return await home.transport.answersHealth(timeout: probeTimeout) ? home : tailscale
    }
}

/// The addresses saved in Settings.
public enum SavedAddresses {
    /// The one address saved before there were two, into the right field: Tailscale when its host is
    /// in 100.64.0.0/10, ends in .ts.net, or is a bare name with no dots (a MagicDNS name like
    /// "desktop"); At home otherwise.
    public static func upgrade(_ old: String) -> (home: String, tailscale: String) {
        let text = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ("", "") }
        guard let settings = try? ServerSettings.parse(url: text, token: "x").get() else { return (text, "") }
        return ServerSettings.isTailscale(settings.host) ? ("", text) : (text, "")
    }
}
