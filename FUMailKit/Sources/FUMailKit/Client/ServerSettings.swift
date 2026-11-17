import Foundation

/// A Cloudflare Access service token, for a Mac reached through a Cloudflare Tunnel guarded by an
/// Access application with a Service Auth policy. Sent only to https:// addresses.
public struct ServiceToken: Equatable, Sendable, CustomStringConvertible {
    /// Ends in ".access".
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// For logs and the screen: never the secret.
    public var description: String { "ServiceToken(clientID: \(clientID), clientSecret: …)" }

    /// What was typed in Settings: nil when both are empty (no Access), the token when both are
    /// filled, or why not when only one is.
    public static func parse(clientID idText: String, clientSecret secretText: String) -> Result<ServiceToken?, ServerSettings.Invalid> {
        let id = idText.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secretText.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty, secret.isEmpty { return .success(nil) }
        guard !id.isEmpty, !secret.isEmpty else {
            return .failure(.init(message: "Fill in both the Cloudflare Access Client ID and Client Secret, or neither."))
        }
        guard (id + secret).unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else {
            return .failure(.init(message: "The Cloudflare Access Client ID or Secret has spaces or unusual characters in it. "
                                  + "Copy them again from Cloudflare."))
        }
        return .success(ServiceToken(clientID: id, clientSecret: secret))
    }

    /// A gentle hint when the Client ID doesn't look like one (they end in ".access"); nil when it does.
    public static func clientIDHint(_ text: String) -> String? {
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.hasSuffix(".access") else { return nil }
        return "Cloudflare's Client IDs end in “.access”. Check it's the Client ID, not the Secret."
    }
}

/// Where the Mac is, this device's token, and the Cloudflare Access service token if there is one.
public struct ServerSettings: Equatable, Sendable, CustomStringConvertible {
    public let url: URL
    public let token: String
    /// Sent (as CF-Access-Client-Id / CF-Access-Client-Secret) only when the address is https://.
    public var access: ServiceToken?

    public init(url: URL, token: String, access: ServiceToken? = nil) {
        self.url = url
        self.token = token
        self.access = access
    }

    /// The address without a trailing slash, for requests and messages ("http://192.168.1.5:8765").
    public var display: String {
        let text = url.absoluteString
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    public var host: String { url.host() ?? "" }
    public var isHTTPS: Bool { url.scheme?.lowercased() == "https" }

    /// For logs and the screen: never the token itself.
    public var description: String {
        "ServerSettings(url: \(display), token: …\(access.map { ", access: \($0)" } ?? ""))"
    }

    /// A service token is saved but the address is plain http://, where it isn't sent (it would travel
    /// unencrypted). nil otherwise.
    public var accessNotSentWarning: String? {
        access != nil && !isHTTPS ? "The Cloudflare Access service token is only sent to https:// addresses, not this one." : nil
    }

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
