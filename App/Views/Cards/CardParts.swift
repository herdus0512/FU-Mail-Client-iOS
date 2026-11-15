import FUMailKit
import SwiftUI

/// What a card needs to act: whose message it is, and the connection to send its buttons over.
@MainActor
struct CardScope {
    var client: RemoteClient
    var conversationID: Conversation.ID
    var messageID: ChatMessage.ID
    var busy: Bool

    var info: APIInfo? { client.state.info }

    func act(_ action: CardAction) {
        client.cardAction(action, on: messageID, in: conversationID)
    }
}

/// The rounded box every card sits in.
struct CardBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator).opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CardHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            if let detail, !detail.isEmpty {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Problems and notes at the bottom of a card.
struct CardFooter: View {
    var problems: [String] = []
    var notes: [String] = []

    var body: some View {
        if !problems.isEmpty || !notes.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                ForEach(problems, id: \.self) { WarningText($0) }
                ForEach(notes, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// A row of a card's buttons, wrapping onto more lines on a narrow phone.
struct CardActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Divider()
        FlowLayout(spacing: 18) { content }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

/// Lays its views out in rows, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, needed > width {
                rows.append(current)
                current = Row(y: current.y + current.height + lineSpacing)
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(index)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

/// The number in front of a list row, which commands like `/open 2` refer to.
struct RowNumber: View {
    var number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 22, alignment: .leading)
    }
}

enum CardDates {
    /// "14:05" today, "Mon 14:05" this week, "3 Nov" this year, else "3 Nov 2025" (as the Mac).
    static func short(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if (0..<6).contains(days) {
            return date.formatted(.dateTime.weekday(.abbreviated)) + " " + date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "6 Nov 2026, 21:20".
    static func full(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}

extension Array where Element == EmailAddress {
    /// "Bob <bob@example.com>, carol@example.com".
    var line: String {
        map { address in address.name.map { "\($0) <\(address.email)>" } ?? address.email }.joined(separator: ", ")
    }
}

/// The view for a message's card.
struct CardView: View {
    var card: Card
    var scope: CardScope

    var body: some View {
        switch card {
        case .emailList(let list): EmailListCardView(card: list, scope: scope)
        case .thread(let thread): ThreadCardView(card: thread, scope: scope)
        case .draftList(let drafts): DraftListCardView(card: drafts, scope: scope)
        case .draft(let draft): DraftCardView(card: draft, scope: scope)
        case .events(let events): EventListCardView(card: events)
        case .suggestedNote(let suggestion): SuggestedNoteCardView(card: suggestion, scope: scope)
        case .notes(let notes): NotesCardView(card: notes, scope: scope)
        case .crm(let crm): CRMCardView(card: crm, scope: scope)
        case .noteView(let view): NoteViewCardView(card: view, scope: scope)
        case .tasks(let tasks): TaskListCardView(card: tasks, scope: scope)
        case .taskDraft(let draft): TaskDraftCardView(card: draft, scope: scope)
        case .taskChange(let change): TaskChangeCardView(card: change, scope: scope)
        case .unsupported(let name):
            CardBox {
                Text("A “\(name)” card this version of the app can't show. It's on the Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }
}
