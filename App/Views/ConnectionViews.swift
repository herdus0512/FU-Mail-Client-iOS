import FUMailKit
import SwiftUI

/// The Mac with a status: green connected, orange connecting, red can't connect. Tap for the address,
/// this device's name, the Mac's version, and what's wrong.
struct ConnectionIndicator: View {
    var client: RemoteClient?
    var onSettings: () -> Void
    @State private var open = false
    @State private var settingsAfterClose = false

    private var connection: Connection { client?.state.connection ?? Connection() }

    private var color: Color {
        guard client != nil else { return StatusColors.failed }
        return switch connection.indicator {
        case .connected: StatusColors.connected
        case .connecting: StatusColors.connecting
        case .failed: StatusColors.failed
        }
    }

    private var label: String {
        guard client != nil else { return "Not set up" }
        if connection.connected { return "Connected" }
        return connection.problem != nil ? "Can't connect" : "Connecting…"
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "desktopcomputer")
                Circle().frame(width: 7, height: 7)
                Text(label).font(.caption.weight(.medium))
            }
            .foregroundStyle(color)
        }
        .accessibilityLabel("Mac: \(label)")
        .popover(isPresented: $open) {
            details
                .presentationCompactAdaptation(.popover)
        }
        // Settings opens once the popover has gone: iOS won't show a sheet while it's still closing,
        // and the app would be left thinking Settings was open (so the gear did nothing either).
        .onChange(of: open) { _, isOpen in
            guard !isOpen, settingsAfterClose else { return }
            settingsAfterClose = false
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                onSettings()
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: "desktopcomputer")
                .font(.headline)
                .foregroundStyle(color)
            if let client {
                Detail(label: "Mac", value: client.display)
                if let skipped = connection.homeSkipped {
                    Detail(label: "Home not used", value: skipped)
                }
                if let info = client.state.info {
                    Detail(label: "This device", value: info.device.flatMap { $0.isEmpty ? nil : $0 } ?? "(unnamed token)")
                    Detail(label: "FU Mail there",
                           value: [info.version, info.build.map { "(\($0))" }, info.commit.map { "· \($0)" }]
                               .compactMap { $0 }.joined(separator: " "))
                }
                if let problem = connection.problem {
                    Text(problem).font(.footnote).foregroundStyle(StatusColors.failed)
                }
            } else {
                Text("Add the Mac's address and a device token in Settings.").font(.footnote)
            }
            Detail(label: "This app", value: AppVersion.text)
            Button("Settings…") {
                settingsAfterClose = true
                open = false
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 360, alignment: .leading)
    }
}

private struct Detail: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote).textSelection(.enabled)
        }
    }
}

/// A problem across the top: can't reach, token rejected, history or config trouble.
struct Banner: View {
    var text: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .accessibilityLabel("Dismiss")
            }
        }
        .foregroundStyle(StatusColors.bannerText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(StatusColors.bannerBackground)
    }
}

/// Every problem worth a banner, newest worry first.
struct Banners: View {
    var client: RemoteClient?

    var body: some View {
        if let client {
            VStack(spacing: 1) {
                if let problem = client.state.connection.problem {
                    Banner(text: problem, onDismiss: { client.dismissProblem() })
                }
                if let error = client.state.configError {
                    Banner(text: "The Mac's config: \(error)")
                }
                if let error = client.state.storeError {
                    Banner(text: "The Mac's history: \(error)")
                }
            }
        }
    }
}
