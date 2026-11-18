import FUMailKit
import SwiftUI

/// The Mac's address, this device's token and an optional Cloudflare Access service token. Save and connect checks them (`/health`, then
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
    /// Cloudflare Access: the Client ID as saved (it isn't secret); the secret only when typed.
    @State private var accessID = ""
    @State private var accessSecret = ""
    @State private var hasAccessSecret = false
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
                    AddressRow(label: "Address", placeholder: "http://mac:8765", text: $tailscaleURL)
                } header: {
                    Text("Mac")
                } footer: {
                    Text("Over Tailscale (which needs to be on): http://<mac>:8765, http://100.x.y.z:8765, or "
                         + "https://<mac>.<tailnet>.ts.net with tailscale serve. Or a Cloudflare Tunnel: "
                         + "https://<hostname>, with its service token below.")
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
                    TextField("Client ID (….access)", text: $accessID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(hasAccessSecret ? "Client Secret: saved, paste to replace" : "Client Secret", text: $accessSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    if let hint = ServiceToken.clientIDHint(accessID) { WarningText(hint) }
                    if !trimmed(accessID).isEmpty, !trimmed(tailscaleURL).lowercased().hasPrefix("https://") {
                        WarningText("The service token is only sent to https:// addresses, not this one.")
                    }
                } header: {
                    Text("Cloudflare Access (optional)")
                } footer: {
                    Text("Only for a Mac reached through a Cloudflare Tunnel guarded by Cloudflare Access: the "
                         + "service token's Client ID and Secret. Fill in both, or leave both empty. Kept in this "
                         + "device's Keychain, and sent only to https:// addresses.")
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
                        Text(result).appFont(.footnote).foregroundStyle(StatusColors.connected)
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
                    Text("Every text 12% smaller or 15% larger than the size set for iOS (Settings → Display & Brightness → "
                         + "Text Size), as in the Android app.")
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
                if accessID.isEmpty, let saved = app.savedAccess() {
                    accessID = saved.clientID
                    hasAccessSecret = true
                }
            }
            .onChange(of: tailscaleURL) { canSaveAnyway = false }
            .onChange(of: token) { canSaveAnyway = false }
            .onChange(of: accessID) { canSaveAnyway = false }
            .onChange(of: accessSecret) { canSaveAnyway = false }
        }
    }

    private func save(check: Bool) {
        result = nil
        problem = nil
        canSaveAnyway = false
        let typed = trimmed(token).isEmpty ? nil : trimmed(token)
        var settings: ServerSettings
        switch ServerSettings.parse(url: trimmed(tailscaleURL), token: typed ?? app.savedToken() ?? "") {
        case .success(let parsed): settings = parsed
        case .failure(let invalid):
            problem = invalid.message
            return
        }
        // An empty Secret field keeps the saved secret while the Client ID stays filled in; emptying
        // the Client ID removes the service token.
        let keptSecret = trimmed(accessID).isEmpty ? "" : (app.savedAccess()?.clientSecret ?? "")
        switch ServiceToken.parse(clientID: accessID, clientSecret: trimmed(accessSecret).isEmpty ? keptSecret : accessSecret) {
        case .success(let access): settings.access = access
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
                try app.save(tailscale: settings.display, newToken: typed, access: settings.access)
            } catch {
                problem = error.localizedDescription
                return
            }
            token = ""
            showToken = false
            accessSecret = ""
            hasAccessSecret = settings.access != nil
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
            Text(label).appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
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
