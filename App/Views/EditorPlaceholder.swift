import FUMailKit
import SwiftUI

/// What opens when the Mac opens a draft editor for this device (Reply, Edit, `/draft`), until the
/// editor itself arrives in the next build. Close closes it on the Mac too, so none is left open.
struct EditorPlaceholder: View {
    var editor: EditorState
    var client: RemoteClient

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(editor.title).font(.headline)
                if case .writing(let by) = editor.status {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Writing with \(by)…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if !editor.form.to.isEmpty { Text("To: \(editor.form.to)") }
                    if !editor.form.cc.isEmpty { Text("Cc: \(editor.form.cc)") }
                    Text("Subject: \(editor.form.subject)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ScrollView {
                    Text(editor.form.body.isEmpty ? "(empty)" : editor.form.body)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Editing and saving drafts on this device comes in the next build. Until then, finish it on the Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { client.closeEditor(editor.id) }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
