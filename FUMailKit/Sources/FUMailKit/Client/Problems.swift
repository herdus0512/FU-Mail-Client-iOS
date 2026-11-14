import Foundation

/// A failure, already in plain words for the banner.
public struct RemoteProblem: Error, Equatable, LocalizedError {
    public enum Kind: Sendable, Equatable {
        /// No answer: wrong address, Mac asleep, app or API off, not on the same network or tailnet.
        case unreachable
        /// iOS hasn't been allowed to reach the local network (Settings → Privacy & Security → Local Network).
        case localNetworkDenied
        /// 401: the token was rejected.
        case unauthorized
        /// 429: too many wrong tokens from this address.
        case lockedOut
        /// 409: a draft editor is being written or saved.
        case busy
        /// 404: e.g. an editor that's already closed.
        case notFound
        /// Plain HTTP that iOS (App Transport Security) or this app won't send.
        case cleartextBlocked
        /// HTTPS failed (certificate, handshake).
        case secureConnection
        /// Any other answer from the Mac.
        case server
        /// An answer this version couldn't read.
        case badResponse
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum Problems {
    public static let unauthorized = RemoteProblem(
        .unauthorized,
        "The Mac didn't accept this device's token. Make a new one there (API → New Device Token…) and paste it in Settings.")

    public static let lockedOut = RemoteProblem(
        .lockedOut, "The Mac has locked this device out for a few minutes after wrong tokens. Wait, then try again.")

    /// A status other than 2xx, with the Mac's `{"error": "…"}` if it sent one. `url` is the address in Settings.
    public static func forStatus(_ status: Int, reason: String?, url: String) -> RemoteProblem {
        switch status {
        case 401: unauthorized
        case 429: lockedOut
        case 409: RemoteProblem(.busy, reason ?? "The draft is being written or saved. Try again when it's done.")
        case 404: RemoteProblem(.notFound, reason ?? "\(url) doesn't have that any more.")
        case 300..<400: RemoteProblem(.server, "\(url) answered with a redirect (\(status)), which this app doesn't follow. "
                                       + "Check the address in Settings.")
        default: RemoteProblem(.server, reason ?? "\(url) answered \(status).")
        }
    }

    /// Any failure, in plain words. `url` is the Mac's address as set in Settings.
    public static func describe(_ error: Error, url: String) -> RemoteProblem {
        if let problem = error as? RemoteProblem { return problem }
        if error is DecodingError {
            return RemoteProblem(.badResponse, "\(url) sent something this app couldn't read. The Mac may be a newer version.")
        }
        if let error = error as? URLError { return describe(error, url: url) }
        return RemoteProblem(.server, "\(url): \(error.localizedDescription)")
    }

    private static func describe(_ error: URLError, url: String) -> RemoteProblem {
        let host = URL(string: url)?.host() ?? url
        switch error.code {
        case .appTransportSecurityRequiresSecureConnection:
            return RemoteProblem(.cleartextBlocked,
                                 "iOS sends plain HTTP only to local addresses: an IP address, a .local name or a Tailscale "
                                 + "short name. For \(host), use HTTPS (tailscale serve) or one of those.")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired:
            return RemoteProblem(.secureConnection,
                                 "Couldn't make a secure connection to \(url) (\(error.localizedDescription)). "
                                 + "Check the address, or that tailscale serve is running.")
        case .networkConnectionLost:
            // The Mac closes connections from networks outside api.allow_from without an answer.
            return RemoteProblem(.unreachable,
                                 "\(url) closed the connection without answering. If it keeps happening: is this network "
                                 + "in the Mac's api.allow_from? (Tailscale is 100.64.0.0/10.)")
        case .notConnectedToInternet where ServerSettings.mayBeLocalNetwork(host):
            // What iOS reports when Local Network access is off, as well as when there's no network.
            return RemoteProblem(.localNetworkDenied,
                                 "Can't reach \(url). If you're on the same Wi-Fi as the Mac, FU Mail may not be allowed "
                                 + "on the local network: Settings → Privacy & Security → Local Network → FU Mail.")
        case .badServerResponse, .cannotParseResponse:
            return RemoteProblem(.badResponse, "\(url) sent something this app couldn't read. Is it FU Mail's API?")
        default:
            break
        }
        let why = switch error.code {
        case .cannotFindHost, .dnsLookupFailed: "the name isn't known on this network"
        case .cannotConnectToHost: "nothing answered"
        case .timedOut: "it didn't answer in time"
        case .notConnectedToInternet: "this device is offline"
        default: error.localizedDescription
        }
        return RemoteProblem(.unreachable,
                             "Can't reach \(url) (\(why)). Is the Mac awake, with FU Mail running and the API on, "
                             + "and is this device on the same Wi-Fi or tailnet?")
    }
}
