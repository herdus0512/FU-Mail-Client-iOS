import FUMailKit
import SwiftUI

/// The Mac's Tailscale address and this device's token. Save and connect checks them (`/health`, then
/// `/v1/info` with the token) and saves when that works; Save anyway keeps settings that can't be
/// checked right now.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("textSize") private var textSize: TextSize = .standard

    @State private var tailscaleURL = ""
    @State private var token = ""
    @State private var showToken = false
    @State private var checking = false
    @State private var result: String?
    @State private var problem: String?
    @State private var canSaveAnyway = false
    @State private var confirmForget = false

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !checking && !trimmed(tailscaleURL).isEmpty
            && (!trimmed(token).isEmpty || app.hasToken)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AddressRow(label: "Tailscale", placeholder: "http://mac:8765", text: $tailscaleURL)
                } header: {
                    Text("Mac")
                } footer: {
                    Text("http://<mac>:8765, http://100.x.y.z:8765, or https://<mac>.<tailnet>.ts.net "
                         + "with tailscale serve. Tailscale needs to be on.")
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
                    if let result {
                        Text(result).font(.footnote).foregroundStyle(StatusColors.connected)
                    }
                    if let problem {
                        WarningText(problem)
                    }
                }

                Section {
                    SegmentedChoice(options: Appearance.allCases.map { ($0, $0.label) }, selection: $appearance)
                } header: {
                    Text("Appearance")
                }

                Section {
                    SegmentedChoice(options: TextSize.allCases.map { ($0, $0.label) }, selection: $textSize)
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
                if tailscaleURL.isEmpty { tailscaleURL = app.tailscaleURL }
            }
            .onChange(of: tailscaleURL) { canSaveAnyway = false }
            .onChange(of: token) { canSaveAnyway = false }
        }
    }

    private func save(check: Bool) {
        result = nil
        problem = nil
        canSaveAnyway = false
        let typed = trimmed(token).isEmpty ? nil : trimmed(token)
        let settings: ServerSettings
        switch ServerSettings.parse(url: trimmed(tailscaleURL), token: typed ?? app.savedToken() ?? "") {
        case .success(let parsed): settings = parsed
        case .failure(let invalid):
            problem = invalid.message
            return
        }
        Task {
            var connected: String?
            if check {
                checking = true
                defer { checking = false }
                do {
                    let info = try await app.check(settings)
                    connected = "Connected to FU Mail \(info.version)" + (info.device.map { " as “\($0)”" } ?? "") + "."
                } catch {
                    problem = (error as? RemoteProblem)?.message ?? error.localizedDescription
                    canSaveAnyway = true
                    return
                }
            }
            do {
                try app.save(tailscale: settings.display, newToken: typed)
            } catch {
                problem = error.localizedDescription
                return
            }
            token = ""
            showToken = false
            result = connected.map { "\($0) Saved." } ?? "Saved. Connecting to \(settings.display)…"
        }
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
