import FUMailKit
import SwiftUI

/// The conversations and the open chat: one at a time on the iPhone (side by side on a wide one). On the
/// iPad the chat keeps its full width, and the list slides over it: a tap on the chat, picking one or
/// turning to portrait hides it.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    /// The window's width class (inside the split view, each column reports compact).
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Conversation.ID?
    /// A history search result's message, to scroll to once its chat is open.
    @State private var jumpTo: MessageJump?
    @State private var showSettings = false
    @State private var askedOnce = false
    @State private var columns = isPad ? NavigationSplitViewVisibility.doubleColumn : .automatic

    private static let isPad = UIDevice.current.userInterfaceIdiom == .pad

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ConversationListView(selection: $selection, jumpTo: $jumpTo, sideBySide: sizeClass == .regular) { showSettings = true }
                .modifier(ListWidth(on: Self.isPad))
        } detail: {
            if let id = selection, let client = app.client {
                // On the iPad the list (and its banners) is usually hidden: the chat shows them too.
                ChatView(id: id, client: client, jumpTo: $jumpTo, sideBySide: sizeClass == .regular && !Self.isPad) { showSettings = true }
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No conversation open", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(app.client == nil ? "Connect to your Mac in Settings first." : "Pick one, or start a new one with the pencil.")
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ConnectionIndicator(client: app.client) { showSettings = true }
                    }
                }
            }
        }
        .modifier(ListOverChat(on: Self.isPad))
        .onChange(of: selection) { _, chosen in
            if Self.isPad, chosen != nil { columns = .detailOnly }
        }
        // The whole window, so the keyboard doesn't count as turning.
        .background {
            Color.clear
                .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { was, portrait in
                    if Self.isPad, portrait, !was { columns = .detailOnly }
                }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Sign in with Google again", isPresented: Binding(get: { app.needsGoogleSignIn }, set: { app.needsGoogleSignIn = $0 })) {
            Button("Open Settings") { showSettings = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Google sign-in expired. Open Settings to sign in with Google again.")
        }
        // A draft editor the Mac opened for this device opens over whatever is showing, and closes
        // on editor_closed (saved, closed here, or closed on the Mac).
        .sheet(item: Binding(get: { app.client?.state.editors.values.first }, set: { _ in })) { editor in
            if let client = app.client { DraftEditorView(editor: editor, client: client) }
        }
        .onAppear {
            // First run: nothing to connect to yet, so start in Settings.
            if !app.isConfigured, !askedOnce {
                askedOnce = true
                showSettings = true
            }
        }
        .onChange(of: app.client == nil) { selection = nil }
        #if DEBUG
        // `make run-fake OPEN=2`: opens the second conversation, for screenshots. Debug builds only.
        .onChange(of: app.client?.state.conversations.map(\.id)) { _, ids in
            guard selection == nil, let ids, let open = ProcessInfo.processInfo.environment["FUMAIL_OPEN"] else { return }
            let index = (Int(open) ?? 1) - 1
            if ids.indices.contains(index) { selection = ids[index] }
        }
        #endif
    }
}

/// The list slides over the chat instead of sharing the width with it.
private struct ListOverChat: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on {
            content.navigationSplitViewStyle(.prominentDetail)
        } else {
            content
        }
    }
}

private struct ListWidth: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on {
            content.navigationSplitViewColumnWidth(320)
        } else {
            content
        }
    }
}
