import FUMailKit
import SwiftUI

/// The conversations and the open chat: side by side on the iPad (and a wide iPhone), one at a time
/// on the iPhone.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    /// The window's width class (inside the split view, each column reports compact).
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Conversation.ID?
    @State private var showSettings = false
    @State private var askedOnce = false

    var body: some View {
        NavigationSplitView {
            ConversationListView(selection: $selection, sideBySide: sizeClass == .regular) { showSettings = true }
        } detail: {
            if let id = selection, let client = app.client {
                ChatView(id: id, client: client, sideBySide: sizeClass == .regular) { showSettings = true }
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
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            // First run: nothing to connect to yet, so start in Settings.
            if app.client == nil, !askedOnce {
                askedOnce = true
                showSettings = true
            }
        }
        .onChange(of: app.client == nil) { selection = nil }
        #if DEBUG
        // `make run-fake OPEN=1`: opens the first conversation, for screenshots. Debug builds only.
        .onChange(of: app.client?.state.conversations.first?.id) { _, first in
            if selection == nil, ProcessInfo.processInfo.environment["FUMAIL_OPEN"] != nil { selection = first }
        }
        #endif
    }
}
