import AuthenticationServices
import FUMailKit
import UIKit

/// Runs `ASWebAuthenticationSession` for the Cloudflare Worker's Google OAuth login.
@MainActor
enum GoogleWebAuth {
    static func signIn(url: URL, callbackScheme: String = WorkerAuth.callbackScheme) async throws -> URL {
        let presenter = PresentationContextProvider()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: RemoteProblem(.unauthorized, "Google sign-in did not complete."))
                }
            }
            session.presentationContextProvider = presenter
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: RemoteProblem(.server, "Couldn't open the Google sign-in window."))
            }
        }
    }
}

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        return UIWindow(windowScene: scenes[0])
    }
}
