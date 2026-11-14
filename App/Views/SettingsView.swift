import FUMailKit
import SwiftUI

/// The Mac's address and this device's token. Save and connect checks both first (the address with
/// `/health`, the token with `/v1/info`) and says which one is wrong; Save anyway keeps settings that
/// can't be checked right now, e.g. while away from home.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system

    @State private var url = ""
    @State private var token = ""
    @State private var showToken = false
    @State private var checking = false
    @State private var result: String?
    @State private var problem: String?
    @State private var canSaveAnyway = false
    @State private var confirmForget = false

    private var parsedURL: ServerSettings? { try? ServerSettings.parse(url: url, token: "x").get() }
    private var canSave: Bool {
        !checking && !url.trimmingCharacters(in: .whitespaces).isEmpty
            && (!token.trimmingCharacters(in: .whitespaces).isEmpty || app.hasToken)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.5:8765", text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                    if let warning = parsedURL?.cleartextWarning {
                        WarningText(warning)
                    }
                } header: {
                    Text("Mac")
                } footer: {
                    Text("At home: http://<Mac's IP>:8765. On the tailnet: http://<mac>:8765, or "
                         + "https://<mac>.<tailnet>.ts.net with tailscale serve.")
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

                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
            .onAppear { if url.isEmpty { url = app.savedURL } }
            .onChange(of: url) { canSaveAnyway = false }
            .onChange(of: token) { canSaveAnyway = false }
        }
    }

    private func save(check: Bool) {
        result = nil
        problem = nil
        canSaveAnyway = false
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : token
        let settings: ServerSettings
        switch ServerSettings.parse(url: url, token: typed ?? app.savedToken() ?? "") {
        case .success(let parsed): settings = parsed
        case .failure(let invalid):
            problem = invalid.message
            return
        }
        Task {
            if check {
                checking = true
                defer { checking = false }
                do {
                    let info = try await app.check(settings)
                    let device = info.device.map { ", as “\($0)”" } ?? ""
                    result = "Connected to FU Mail \(info.version) on \(settings.display)\(device)."
                } catch {
                    problem = (error as? RemoteProblem)?.message ?? error.localizedDescription
                    canSaveAnyway = true
                    return
                }
            }
            do {
                try app.save(settings, newToken: typed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            } catch {
                problem = error.localizedDescription
                return
            }
            token = ""
            showToken = false
            if !check { result = "Saved. Connecting to \(settings.display)…" }
        }
    }
}
