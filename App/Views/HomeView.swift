import FUMailKit
import SwiftUI

/// The conversations and the open chat: one at a time on the iPhone (side by side on a wide one). On the
/// iPad as in TestFlight: beside each other in landscape (hiding the list widens the chat); in portrait
/// the chat is full screen and the list slides over it, until a tap on the chat or picking one.
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

    /// Which way the window is, once it's known.
    @State private var isPortrait: Bool?

    /// The error banners are the chat's to show when the list, which has them, is hidden or over it.
    private var listShowsBanners: Bool {
        sizeClass == .regular && !(Self.isPad && (isPortrait != false || columns == .detailOnly))
    }

    private static let isPad = UIDevice.current.userInterfaceIdiom == .pad

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ConversationListView(selection: $selection, jumpTo: $jumpTo, sideBySide: sizeClass == .regular) { showSettings = true }
                .modifier(ListWidth(on: Self.isPad))
        } detail: {
            if let id = selection, let client = app.client {
                ChatView(id: id, client: client, jumpTo: $jumpTo, sideBySide: listShowsBanners) { showSettings = true }
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
        .onChange(of: selection) { _, chosen in
            if Self.isPad, isPortrait == true, chosen != nil { columns = .detailOnly }
        }
        // The whole window, so the keyboard doesn't count as turning.
        .background {
            Color.clear
                .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { _, portrait in
                    guard Self.isPad, portrait != isPortrait else { return }
                    let turned = isPortrait != nil
                    isPortrait = portrait
                    // Landscape opens the list, turning to portrait hides it. Just opened: there's no chat yet.
                    columns = portrait && (turned || selection != nil) ? .detailOnly : .doubleColumn
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
