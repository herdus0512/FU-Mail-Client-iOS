import FUMailKit
import SwiftUI

/// Triage's review cards (`/triage spam`, `clean` and `archive`). What they show and offer is
/// `TriageRules`'; every button but Refresh asks first. Every row shows (so "move all" can't cover one
/// not seen), and rows go only when the Mac updates the card.
struct TriageCardView: View {
    var card: Card
    var scope: CardScope
    /// The question on screen. It closes when what it's about changes, the card goes busy or the
    /// connection drops; the client checks once more before sending.
    @State private var confirming: TriageConfirmation?

    private var holds: Bool { confirming?.holds(card, busy: scope.busy, connected: scope.connected) ?? false }

    var body: some View {
        if let view = TriageRules.view(card, busy: scope.busy, connected: scope.connected, date: { CardDates.short($0) }) {
            CardBox {
                HStack(spacing: 8) {
                    CardHeader(title: view.title, detail: view.rows.isEmpty ? nil : "\(view.rows.count)")
                    if scope.busy { ProgressView().controlSize(.small) }
                    Button("Refresh") { scope.act(view.refresh) }
                        .disabled(!view.refreshEnabled)
                        .buttonStyle(.borderless)
                        .appFont(.subheadline)
                        .padding(.trailing, 12)
                }
                Divider()
                if view.rows.isEmpty {
                    Text(view.emptyText).appFont(.footnote).foregroundStyle(.secondary).padding(12)
                } else {
                    ForEach(view.rows) { row in
                        if row.id != view.rows.first?.id { Divider() }
                        TriageRowView(row: row, onAsk: ask) { scope.client.openEmail(row.ref, in: scope.conversationID) }
                    }
                    if let all = view.all {
                        CardActions { TriageButtonView(button: all, onAsk: ask) }
                    }
                    if let note = view.statusNote {
                        if view.all == nil { Divider() }
                        Text(note)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
            }
            // Closed for good, even if what it asked about comes back.
            .onChange(of: holds) { _, now in if !now { confirming = nil } }
            .alert(confirming?.title ?? "", isPresented: Binding(get: { holds }, set: { if !$0 { confirming = nil } }),
                   presenting: confirming) { asked in
                Button(asked.confirmLabel, role: asked.destructive ? .destructive : nil) {
                    scope.client.triageAction(asked, on: scope.messageID, in: scope.conversationID)
                }
                Button("Cancel", role: .cancel) {}
            } message: { asked in
                Text(asked.text)
            }
        }
    }

    /// From a button or an open menu, which may be of the card as it was a moment ago.
    private func ask(_ question: TriageConfirmation) {
        if question.holds(scope.client.state, on: scope.messageID, in: scope.conversationID) { confirming = question }
    }
}

private struct TriageRowView: View {
    var row: TriageRow
    var onAsk: (TriageConfirmation) -> Void
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.sender).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(CardDates.short(row.received)).appFont(.caption).foregroundStyle(.secondary)
                    }
                    Text(row.subject).lineLimit(1)
                    if !row.details.isEmpty {
                        Text(row.details.joined(separator: " · ")).appFont(.caption).foregroundStyle(.secondary)
                    }
                    if let mark = row.mark {
                        Text(mark).appFont(.caption).foregroundStyle(StatusColors.warning)
                    }
                }
                .appFont(.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the email")

            FlowLayout(spacing: 22) {
                ForEach(row.buttons, id: \.label) { TriageButtonView(button: $0, onAsk: onAsk) }
                if !row.menu.isEmpty {
                    Menu {
                        ForEach(row.menu, id: \.label) { button in
                            Button(role: button.destructive ? .destructive : nil) {
                                onAsk(button.confirmation)
                            } label: {
                                Text(button.label)
                                if let detail = button.detail { Text(detail) }
                            }
                            .disabled(!button.enabled)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(!row.menu.contains { $0.enabled })
                    .accessibilityLabel("More for this email")
                }
            }
            .buttonStyle(.borderless)
            .appFont(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct TriageButtonView: View {
    var button: TriageButton
    var onAsk: (TriageConfirmation) -> Void

    var body: some View {
        Button(button.label, role: button.destructive ? .destructive : nil) { onAsk(button.confirmation) }
            .disabled(!button.enabled)
    }
}
