import FUMailKit
import SwiftUI

/// The first screen: the connection, problems, and (read-only for now) the Mac's conversations.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var showSettings = false
    @State private var askedOnce = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Banners(client: app.client)
                if let client = app.client {
                    ConversationTitles(client: client)
                } else {
                    NotSetUp { showSettings = true }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FU Mail")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionIndicator(client: app.client) { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
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
    }
}

private struct NotSetUp: View {
    var onSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Not set up", systemImage: "desktopcomputer")
        } description: {
            Text("FU Mail shows the conversations of FU Mail on your Mac. Add the Mac's address and a device token to connect.")
        } actions: {
            Button("Settings", action: onSettings).buttonStyle(.borderedProminent)
        }
    }
}

/// The Mac's conversations, newest first. Opening them comes in the next build.
private struct ConversationTitles: View {
    var client: RemoteClient

    var body: some View {
        let conversations = client.state.conversations
        if conversations.isEmpty {
            ContentUnavailableView {
                Label(client.state.connection.connected ? "No conversations" : "Connecting…",
                      systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(client.state.connection.connected ? "Conversations on the Mac show here." : client.display)
            }
        } else {
            List {
                Section {
                    ForEach(conversations) { conversation in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title).lineLimit(1)
                            Text(conversation.updatedAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Opening and starting conversations comes in the next build.")
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
        .fontDesign(.monospaced)
}
