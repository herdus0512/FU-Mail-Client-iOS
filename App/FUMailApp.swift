import SwiftUI

/// FU Mail for iPhone and iPad: a thin client of the Mac's FU Mail API. The mail servers, LLMs,
/// notes, CRM and history stay on the Mac; this shows its conversations and cards.
@main
struct FUMailApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .fontDesign(.monospaced)
        }
    }
}
