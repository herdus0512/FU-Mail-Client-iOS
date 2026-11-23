import FUMailKit
import SwiftUI
import UIKit

/// The draft editor, over the chat, when the Mac opens one for this device (Reply, Edit, `/draft`).
/// To, Cc, Bcc, Subject, the body and the instructions are typed here and stay here; Write / Rewrite,
/// Reply all and Save send them. While the body is being written it streams in from the Mac (and
/// can't be typed into). Nothing is ever sent as email: Save puts it in the account's Drafts.
struct DraftEditorView: View {
    var editor: EditorState
    var client: RemoteClient

    // This device's copy of what's typed.
    @State private var to: String
    @State private var cc: String
    @State private var bcc: String
    @State private var subject: String
    @State private var text: String
    @State private var replyAll: Bool
    @State private var instructions: String
    @State private var wasWriting: Bool
    @State private var copied = false
    @State private var confirmCancel = false
    @State private var contacts: [ContactEntry] = []
    @FocusState private var focusedField: RecipientField?

    private enum RecipientField: Hashable { case to, cc, bcc }

    init(editor: EditorState, client: RemoteClient) {
        self.editor = editor
        self.client = client
        _to = State(initialValue: editor.form.to)
        _cc = State(initialValue: editor.form.cc)
        _bcc = State(initialValue: editor.form.bcc)
        _subject = State(initialValue: editor.form.subject)
        _text = State(initialValue: editor.form.body)
        _replyAll = State(initialValue: editor.form.replyAll)
        _instructions = State(initialValue: editor.instructions)
        _wasWriting = State(initialValue: Self.isWriting(editor.status))
    }

    private var busy: Bool { editor.status.isBusy }
    private var form: DraftForm { DraftForm(to: to, cc: cc, bcc: bcc, subject: subject, body: text, replyAll: replyAll) }
    /// Typed here since it opened (so Cancel asks first).
    private var changed: Bool { form != editor.form || instructions != editor.instructions }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The title here too: the toolbar's buttons leave it little room on an iPhone.
                    Text(editor.title.isEmpty ? "Draft" : editor.title)
                        .appFont(.headline)
                        .lineLimit(2)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                    Divider()
                    if case .compose(let accounts, let selected) = editor.mode, !accounts.isEmpty {
                        HStack(spacing: 8) {
                            Text("From:").foregroundStyle(.secondary)
                            Picker("From", selection: Binding(
                                get: { selected?.id ?? accounts.first?.id ?? "" },
                                set: { newID in
                                    guard let chosen = accounts.first(where: { $0.id == newID }),
                                          chosen.id != selected?.id else { return }
                                    client.selectAccount(editor.id, account: chosen)
                                }
                            )) {
                                ForEach(accounts) { account in
                                    Text(account.display).tag(account.id)
                                }
                            }
                            .labelsHidden()
                            .disabled(busy)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                    AddressField(label: "To", text: $to, enabled: !busy, contacts: contacts, isFocused: focusedField == .to)
                        .focused($focusedField, equals: .to)
                    Divider()
                    AddressField(label: "Cc", text: $cc, enabled: !busy, contacts: contacts, isFocused: focusedField == .cc)
                        .focused($focusedField, equals: .cc)
                    Divider()
                    AddressField(label: "Bcc", text: $bcc, enabled: !busy, contacts: contacts, isFocused: focusedField == .bcc)
                        .focused($focusedField, equals: .bcc)
                    Divider()
                    HStack(spacing: 8) {
                        Text("Subject:").foregroundStyle(.secondary)
                        TextField("", text: $subject).disabled(busy)
                    }
                    .padding(.vertical, 10)
                    Divider()
                    if editor.isReply {
                        Toggle("Reply all", isOn: Binding(get: { replyAll }, set: { on in
                            replyAll = on
                            client.setReplyAll(editor.id, on)
                        }))
                        .disabled(busy)
                        .padding(.vertical, 6)
                        Divider()
                    }
                    bodyEditor
                    if let signature = editor.signature?.trimmingCharacters(in: .whitespacesAndNewlines), !signature.isEmpty {
                        Text("The Mac adds your signature: \(signature.components(separatedBy: "\n").first ?? "")…")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    if editor.supportsWrite { instructionsSection }
                    buttons
                    statusLine.padding(.top, 10)
                    Text("Nothing is ever sent: Save puts it in the account's Drafts.")
                        .appFont(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editor.title.isEmpty ? "Draft" : editor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if changed { confirmCancel = true } else { client.closeEditor(editor.id) }
                    }
                }
                if editor.canSave {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(editor.supportsWrite ? "Save to Drafts" : "Update draft") {
                            client.save(editor.id, form: form, instructions: instructions)
                        }
                        .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .confirmationDialog("Close without saving?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Close without saving", role: .destructive) { client.closeEditor(editor.id) }
            } message: {
                Text("What you typed here is lost.")
            }
        }
        .interactiveDismissDisabled()
        // The body comes from the Mac while it's being written, and once more when that ends.
        .onChange(of: editor.form.body) { syncBody() }
        .onChange(of: editor.status) { syncBody() }
        // Reply all: the Mac fills in Cc (and only then does the copy here change).
        .onChange(of: editor.form.cc) { cc = editor.form.cc }
        .onChange(of: editor.form.replyAll) { replyAll = editor.form.replyAll }
        .task { contacts = (try? await client.contacts()) ?? [] }
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(editor.supportsWrite ? "Write it here, or give instructions below and Write." : "The draft's text")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .disabled(busy)
                .opacity(Self.isWriting(editor.status) ? 0.7 : 1)
        }
        .padding(.top, 8)
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 10)
            Text("Instructions").appFont(.caption, weight: .semibold).foregroundStyle(.secondary)
            TextField("e.g. decline politely and suggest next Tuesday", text: $instructions, axis: .vertical)
                .lineLimit(1...4)
                .disabled(busy)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Write / Rewrite (replies) and Copy text.
    private var buttons: some View {
        HStack(spacing: 10) {
            if editor.supportsWrite {
                Button(text.isEmpty ? "Write" : "Rewrite") {
                    client.write(editor.id, form: form, instructions: instructions)
                }
                .disabled(busy)
            }
            Button(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = text
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .disabled(text.isEmpty)
        }
        .buttonStyle(.bordered)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch editor.status {
        case .writing(let by):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Writing with \(by)…").appFont(.caption).foregroundStyle(.secondary)
            }
        case .saving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Saving to \(editor.server)…").appFont(.caption).foregroundStyle(.secondary)
            }
        case .failed(let reason):
            WarningText(reason)
        case .idle:
            if !editor.canSave {
                Text("\(editor.server) can't save drafts, so copy the text into your mail app instead.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func syncBody() {
        let writing = Self.isWriting(editor.status)
        if writing || wasWriting { text = editor.form.body }
        wasWriting = writing
    }

    private static func isWriting(_ status: EditorStatus) -> Bool {
        if case .writing = status { true } else { false }
    }
}

/// "To:", "Cc:", "Bcc:" with the addresses as comma-separated text and contact autocomplete chips.
private struct AddressField: View {
    var label: String
    @Binding var text: String
    var enabled: Bool
    var contacts: [ContactEntry]
    var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(label):").foregroundStyle(.secondary)
                TextField("", text: $text, axis: .vertical)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(!enabled)
            }
            let suggestions = isFocused && enabled ? ContactEntry.suggestions(for: text, from: contacts) : []
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions) { contact in
                            Button {
                                text = ContactEntry.applying(contact, to: text)
                            } label: {
                                Text(contact.name.map { "\($0) <\(contact.email)>" } ?? contact.email)
                                    .appFont(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}
