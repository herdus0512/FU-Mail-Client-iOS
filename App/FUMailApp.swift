import SwiftUI
import UIKit

/// FU Mail for iPhone and iPad: a thin client of the Mac's FU Mail API. The mail servers, LLMs,
/// notes, CRM and history stay on the Mac; this shows its conversations and cards.
@main
struct FUMailApp: App {
    @State private var app = AppModel()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Titles in SF Mono too, as the rest of the app (scaled with the text size).
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: Self.mono(.largeTitle, weight: .bold)]
        bar.titleTextAttributes = [.font: Self.mono(.headline, weight: .semibold)]
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(app)
                .fontDesign(.monospaced)
                .modifier(TextSizing())
                .preferredColorScheme(appearance.colorScheme)
        }
        // The connection is open only while the app is on screen: nothing runs in the background.
        .onChange(of: scenePhase, initial: true) { _, phase in
            app.setOnScreen(phase == .active)
        }
    }

    private static func mono(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .monospacedSystemFont(ofSize: size, weight: weight))
    }
}
