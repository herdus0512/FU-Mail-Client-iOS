import SwiftUI
import UIKit

extension View {
    /// Touch and hold: **Copy** (all of `text`) and **Select Text…**, which opens it on its own with
    /// iOS's own selection (handles, Select All, Copy, Share, Look Up), as Messages' Select does.
    /// SwiftUI's `.textSelection` can only copy a whole block on iOS, and inside the chat a drag
    /// scrolls instead of moving the selection.
    func copyable(_ text: String) -> some View {
        modifier(CopyMenu(text: text))
    }
}

private struct CopyMenu: ViewModifier {
    var text: String
    @State private var selecting = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                Button("Select Text…", systemImage: "selection.pin.in.out") { selecting = true }
            }
            .sheet(isPresented: $selecting) { SelectTextSheet(text: text) }
    }
}

/// The text with all of it selected, ready for Copy, or for dragging the handles to pick a part.
private struct SelectTextSheet: View {
    var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Copy All") {
                            UIPasteboard.general.string = text
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// A read-only UITextView: real selection, in the app's monospaced font at the reader's text size.
private struct SelectableTextView: UIViewRepresentable {
    var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 17, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.text = text
        // Everything selected to start with, so Copy is one tap away; the handles pick a part.
        DispatchQueue.main.async {
            view.becomeFirstResponder()
            view.selectedRange = NSRange(location: 0, length: (text as NSString).length)
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
