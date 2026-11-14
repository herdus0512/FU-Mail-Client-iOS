import Foundation

/// Where the Mac is, and this device's token.
public struct ServerSettings: Equatable, Sendable, CustomStringConvertible {
    public let url: URL
    public let token: String

    /// The address without a trailing slash, for requests and messages ("http://192.168.1.5:8765").
    public var display: String {
        let text = url.absoluteString
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    public var host: String { url.host() ?? "" }
    public var isHTTPS: Bool { url.scheme?.lowercased() == "https" }

    /// For logs and the screen: never the token itself.
    public var description: String { "ServerSettings(url: \(display), token: …)" }

    public struct Invalid: Error, Equatable, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Checks what was typed in Settings: the settings, or why they can't be used.
    public static func parse(url urlText: String, token tokenText: String) -> Result<ServerSettings, Invalid> {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(Invalid(message: "Enter the Mac's address, e.g. http://192.168.1.5:8765.")) }
        let withScheme = text.contains("://") ? text : "http://\(text)"
        guard let components = URLComponents(string: withScheme), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = components.host, !host.isEmpty,
              let url = components.url else {
            return .failure(Invalid(message: "“\(text)” isn't a web address. It looks like http://192.168.1.5:8765."))
        }
        guard components.query == nil, components.fragment == nil else {
            return .failure(Invalid(message: "Leave out anything after ? or # in the address."))
        }
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return .failure(Invalid(message: "Paste the device token made on the Mac (API → New Device Token…)."))
        }
        guard token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
            return .failure(Invalid(message: "The token has spaces or unusual characters in it. Copy it again from the Mac."))
        }
        return .success(ServerSettings(url: url, token: token))
    }

    /// A warning for plain HTTP on a network Tailscale doesn't encrypt (home Wi-Fi): anyone on it who is
    /// looking could read the mail and the token. nil when there's nothing to warn about.
    public var cleartextWarning: String? {
        if isHTTPS || Self.isTailscale(host) { return nil }
        return "Plain HTTP on this network isn't encrypted: anyone on it who's looking could read your mail and the token. "
            + "Over Tailscale (http://<mac>:8765, or HTTPS with tailscale serve) it is."
    }

    /// Whether the Mac may be on the local network, which iOS lets the app reach only after asking
    /// ("Local Network"): a private or link-local IPv4 address, a `.local` name, or a name without dots.
    /// Tailscale's 100.x and *.ts.net go through its VPN instead.
    public static func mayBeLocalNetwork(_ host: String) -> Bool {
        let host = host.lowercased()
        if host.hasSuffix(".ts.net") { return false }
        if let (a, b) = ipv4Start(host) {
            return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        if host.contains(":") { return host.hasPrefix("fe80") || host.hasPrefix("fd") || host.hasPrefix("fc") }
        return host.hasSuffix(".local") || !host.contains(".")
    }

    /// A tailnet address: 100.64.0.0/10, a *.ts.net name, or a MagicDNS short name (no dots).
    public static func isTailscale(_ host: String) -> Bool {
        let host = host.lowercased()
        if host.hasSuffix(".ts.net") { return true }
        if let (a, b) = ipv4Start(host) { return a == 100 && (64...127).contains(b) }
        return !host.contains(":") && !host.contains(".") && host != "localhost"
    }

    /// The first two parts of a dotted IPv4 address.
    private static func ipv4Start(_ host: String) -> (Int, Int)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ $0.map { (0...255).contains($0) } ?? false }) else { return nil }
        return (parts[0]!, parts[1]!)
    }
}
