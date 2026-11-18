import SwiftUI
import UIKit

/// FU Mail for iPhone and iPad: a thin client of the Mac's FU Mail API. The mail servers, LLMs,
/// notes, CRM and history stay on the Mac; this shows its conversations and cards.
@main
struct FUMailApp: App {
    @State private var app = AppModel()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("textSize") private var textSize: TextSize = .standard
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.styleTitles()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(app)
                .fontDesign(.monospaced)
                .appFont(.body)  // text without a style of its own
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: textSize) { Self.styleTitles() }
        }
        // The connection is open only while the app is on screen: nothing runs in the background.
        .onChange(of: scenePhase, initial: true) { _, phase in
            app.setOnScreen(phase == .active)
        }
    }

    /// Titles in SF Mono too, at the app's size (the reader's text size times Text size), for bars made
    /// from now on and the ones already showing.
    @MainActor
    private static func styleTitles() {
        let textSize = TextSize.current
        func mono(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            let size = UIFont.preferredFont(forTextStyle: style).pointSize * textSize.factor
            return .monospacedSystemFont(ofSize: size, weight: weight)
        }
        let large: [NSAttributedString.Key: Any] = [.font: mono(.largeTitle, .bold)]
        let inline: [NSAttributedString.Key: Any] = [.font: mono(.headline, .semibold)]
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = large
        bar.titleTextAttributes = inline
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                func restyle(_ view: UIView) {
                    if let bar = view as? UINavigationBar {
                        for appearance in [bar.standardAppearance, bar.compactAppearance, bar.scrollEdgeAppearance].compactMap({ $0 }) {
                            appearance.largeTitleTextAttributes = large
                            appearance.titleTextAttributes = inline
                        }
                        bar.largeTitleTextAttributes = large
                        bar.titleTextAttributes = inline
                    }
                    view.subviews.forEach(restyle)
                }
                restyle(window)
            }
        }
    }
}
