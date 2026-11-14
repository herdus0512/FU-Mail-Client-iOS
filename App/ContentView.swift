import FUMailKit
import SwiftUI

/// Milestone 1: the app installs, opens and is signed. Settings and connecting to the Mac come next.
struct ContentView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("FU Mail")
                    .font(.largeTitle.weight(.semibold))
                Text(version)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Settings and connecting to FU Mail on your Mac come in the next build.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    ContentView()
        .fontDesign(.monospaced)
}
