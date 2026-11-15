import FUMailKit
import SwiftUI

/// The Mac's two addresses (either can be left empty) and this device's token. Save and connect checks
/// each filled address on its own (`/health`, then `/v1/info` with the token) and says how each went;
/// it saves when at least one works, so it can be set up at home with Tailscale off. Save anyway keeps
/// settings that can't be checked right now.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("textSize") private var textSize: TextSize = .standard

    @State private var homeURL = ""
    @State private var tailscaleURL = ""
    @State private var token = ""
    @State private var showToken = false
    @State private var checking = false
    /// One line per address checked, and how it went.
    @State private var lines: [(text: String, ok: Bool)] = []
    @State private var result: String?
    @State private var problem: String?
    @State private var canSaveAnyway = false
    @State private var confirmForget = false

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !checking && !(trimmed(homeURL).isEmpty && trimmed(tailscaleURL).isEmpty)
            && (!trimmed(token).isEmpty || app.hasToken)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AddressRow(label: "At home (Wi-Fi)", placeholder: "http://192.168.1.5:8765", text: $homeURL)
                    AddressRow(label: "Tailscale", placeholder: "http://mac:8765", text: $tailscaleURL)
                } header: {
                    Text("Mac")
                } footer: {
                    Text("Either can be left empty. At home: http://<Mac's IP>:8765. Tailscale: http://<mac>:8765, "
                         + "http://100.x.y.z:8765, or https://<mac>.<tailnet>.ts.net with tailscale serve. "
                         + "With both, FU Mail picks by itself: on Wi-Fi the home address when FU Mail answers there, "
                         + "otherwise Tailscale.")
                }

                Section {
                    HStack {
                        Group {
                            if showToken {
                                TextField(app.hasToken ? "Saved: paste to replace" : "fum_…", text: $token)
                            } else {
                                SecureField(app.hasToken ? "Saved: paste to replace" : "fum_…", text: $token)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(showToken ? "Hide token" : "Show token")
                    }
                } header: {
                    Text("Device token")
                } footer: {
                    Text("Make one on the Mac: API → New Device Token…, named for this device. It's shown once. "
                         + "It's kept in this device's Keychain, never synced or backed up.")
                }

                Section {
                    Button {
                        save(check: true)
                    } label: {
                        HStack {
                            Text("Save and connect")
                            if checking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canSave)
                    if canSaveAnyway {
                        Button("Save anyway") { save(check: false) }
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        if line.ok {
                            Text(line.text).font(.footnote).foregroundStyle(StatusColors.connected)
                        } else {
                            WarningText(line.text)
                        }
                    }
                    if let result {
                        Text(result).font(.footnote).foregroundStyle(StatusColors.connected)
                    }
                    if let problem {
                        WarningText(problem)
                    }
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Appearance")
                }

                Section {
                    Picker("Text size", selection: $textSize) {
                        ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Text size")
                } footer: {
                    Text("A step either side of the size set for iOS (Settings → Display & Brightness → Text Size).")
                }

                if app.hasToken {
                    Section {
                        Button("Forget token", role: .destructive) { confirmForget = true }
                    } footer: {
                        Text("Removes the token from this device. Revoke it on the Mac too (API → Revoke Device Token).")
                    }
                }

                Section {
                } footer: {
                    Text("FU Mail for iOS \(AppVersion.text)")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Forget the token?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget token", role: .destructive) {
                    app.forgetToken()
                    result = "Token removed from this device. Revoke it on the Mac too (API → Revoke Device Token)."
                    problem = nil
                }
            } message: {
                Text("FU Mail stops connecting until a new token is pasted.")
            }
            .onAppear {
                if homeURL.isEmpty, tailscaleURL.isEmpty {
                    homeURL = app.homeURL
                    tailscaleURL = app.tailscaleURL
                }
            }
            .onChange(of: homeURL) { canSaveAnyway = false }
            .onChange(of: tailscaleURL) { canSaveAnyway = false }
            .onChange(of: token) { canSaveAnyway = false }
        }
    }

    private func save(check: Bool) {
        lines = []
        result = nil
        problem = nil
        canSaveAnyway = false
        let typed = trimmed(token).isEmpty ? nil : trimmed(token)
        let effectiveToken = typed ?? app.savedToken() ?? ""
        // Each filled address on its own; a wrong one stops here with why.
        var addresses: [(label: String, settings: ServerSettings)] = []
        for (label, text) in [("At home", trimmed(homeURL)), ("Tailscale", trimmed(tailscaleURL))] where !text.isEmpty {
            switch ServerSettings.parse(url: text, token: effectiveToken) {
            case .success(let settings): addresses.append((label, settings))
            case .failure(let invalid):
                problem = "\(label): \(invalid.message)"
                return
            }
        }
        let home = addresses.first { $0.label == "At home" }?.settings.display ?? ""
        let tailscale = addresses.first { $0.label == "Tailscale" }?.settings.display ?? ""
        Task {
            if check {
                checking = true
                var anyWorked = false
                for (label, settings) in addresses {
                    do {
                        let info = try await app.check(settings)
                        let device = info.device.map { " as “\($0)”" } ?? ""
                        lines.append(("\(label): connected to FU Mail \(info.version)\(device).", true))
                        anyWorked = true
                    } catch {
                        lines.append(("\(label): \(Self.describe(error, home: label == "At home"))", false))
                    }
                }
                checking = false
                // Saved when at least one works (e.g. set up at home with Tailscale off).
                guard anyWorked else {
                    canSaveAnyway = true
                    return
                }
            }
            do {
                try app.save(home: home, tailscale: tailscale, newToken: typed)
            } catch {
                problem = error.localizedDescription
                return
            }
            token = ""
            showToken = false
            if !home.isEmpty, !tailscale.isEmpty {
                result = "Saved. On Wi-Fi it uses the home address when FU Mail answers there, otherwise Tailscale."
            } else if !check {
                result = "Saved. Connecting to \(home.isEmpty ? tailscale : home)…"
            } else {
                result = "Saved."
            }
        }
    }

    /// Why an address didn't work, in plain words. The home address can be blocked by iOS's Local
    /// Network setting, and Tailscale is the way round that.
    private static func describe(_ error: Error, home: Bool) -> String {
        guard let problem = error as? RemoteProblem else { return error.localizedDescription }
        if home, problem.kind == .localNetworkDenied {
            return "iOS isn't letting FU Mail reach your local network, so the home address can't be reached. "
                + "Allow it in Settings → Privacy & Security → Local Network → FU Mail, or use the Tailscale address."
        }
        return problem.message
    }
}

/// One address with its label, and the plain-HTTP warning when it applies.
private struct AddressRow: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    private var warning: String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (try? ServerSettings.parse(url: text, token: "x").get())?.cleartextWarning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let warning { WarningText(warning) }
        }
        .padding(.vertical, 2)
    }
}
