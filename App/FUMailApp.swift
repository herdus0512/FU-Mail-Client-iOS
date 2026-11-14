import SwiftUI

/// FU Mail for iPhone and iPad: a thin client of the Mac's FU Mail API. The mail servers, LLMs,
/// notes, CRM and history stay on the Mac; this shows its conversations and cards.
@main
struct FUMailApp: App {
    @State private var app = AppModel()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(app)
                .fontDesign(.monospaced)
                .preferredColorScheme(appearance.colorScheme)
        }
        // The connection is open only while the app is on screen: nothing runs in the background.
        .onChange(of: scenePhase, initial: true) { _, phase in
            app.setOnScreen(phase == .active)
        }
    }
}
