import FUMailKit
import SwiftUI

// MARK: - Email list

/// `/unread`, `/inbox`, `/search`, `/archive`: tap a row to open it in the chat.
struct EmailListCardView: View {
    var card: EmailListCard
    var scope: CardScope

    var body: some View {
        CardBox {
            CardHeader(title: card.title, detail: card.items.isEmpty ? nil : "\(card.items.count)")
            Divider()
            if card.items.isEmpty {
                Text(card.emptyText).font(.footnote).foregroundStyle(.secondary).padding(12)
            }
            ForEach(Array(card.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 44) }
                Button {
                    scope.client.openEmail(item.ref, in: scope.conversationID)
                } label: {
                    EmailRow(number: index + 1, item: item)
                }
                .buttonStyle(.plain)
            }
            // An archive list with more to show: the next page is added to this card.
            if card.more != nil {
                Divider()
                HStack {
                    Button(card.remainingCount.map { "Show more (\($0) left)" } ?? "Show more") { scope.act(.archiveMore) }
                        .disabled(scope.busy)
                    if scope.busy { ProgressView().controlSize(.small) }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            CardFooter(problems: card.problems)
        }
    }
}

private struct EmailRow: View {
    var number: Int
    var item: EmailSummary

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RowNumber(number: number)
            Circle()
                .fill(item.unread ? Color.accentColor : .clear)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
                .padding(.trailing, 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.from?.display ?? "(no sender)")
                        .fontWeight(item.unread ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(CardDates.short(item.received)).font(.caption).foregroundStyle(.secondary)
                }
                Text(item.subject.isEmpty ? "(no subject)" : item.subject)
                    .fontWeight(item.unread ? .medium : .regular)
                    .lineLimit(1)
                if let snippet = item.snippet, !snippet.isEmpty {
                    Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let account = item.ref.account {
                    Text(account).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Thread

/// An email or thread: newest first, folded by the Mac's rule, with Original | Summary and the buttons.
struct ThreadCardView: View {
    var card: ThreadCard
    var scope: CardScope
    @Environment(\.openURL) private var openURL

    private var archived: Bool { card.archived == true }

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.subject.isEmpty ? "(no subject)" : card.subject).font(.subheadline.weight(.semibold))
                let detail = [card.ref.account, card.messages.count > 1 ? "\(card.messages.count) messages" : nil].compactMap { $0 }
                if !detail.isEmpty {
                    Text(detail.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            SegmentedChoice(options: [(.original, "Original"), (.summary, "Summary")],
                            selection: Binding(get: { card.side }, set: { side in
                                if side != card.side { scope.act(.setSide(side)) }
                            }))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            switch card.side {
            case .original:
                ForEach(card.newestFirst) { message in
                    Divider()
                    if card.isOpen(message) {
                        MessageView(message: message, canFold: card.canFoldAgain(message)) {
                            scope.act(.toggleFold(emailID: message.id))
                        }
                    } else {
                        FoldedMessage(message: message) { scope.act(.toggleFold(emailID: message.id)) }
                    }
                }
            case .summary:
                Divider()
                SummaryView(summary: card.summary) { scope.act(.summarize(again: true)) }
            }

            CardActions {
                if !archived {
                    Button("Reply") { scope.act(.reply(instructions: "", blank: false, replyAll: false)) }
                }
                if card.offersReplyAll {
                    Button("Reply all") { scope.act(.reply(instructions: "", blank: false, replyAll: true)) }
                }
                if scope.info?.notesConfigured == true {
                    Button("Add to note") { scope.act(.addToNotes) }
                }
                if scope.info?.tasksConfigured == true {
                    Button("Add task") { scope.act(.addTask) }
                }
                switch card.foldAllButton {
                case .expandAll: Button("Expand all") { scope.act(.setAllUnfolded(true)) }
                case .foldOlder: Button("Fold older") { scope.act(.setAllUnfolded(false)) }
                case nil: EmptyView()
                }
                if card.side == .original, card.canShowMore {
                    if scope.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Show full text") { scope.act(.showFullText) }
                    }
                }
                if let link = card.link.flatMap(URL.init(string:)) {
                    Button("Open in browser") { openURL(link) }
                }
            }
            Text(card.side == .original
                 ? "Original text from \(card.ref.server)\(archived ? " (archive, read-only)" : "")"
                 : "Written by an LLM")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }
}

private struct SummaryView: View {
    var summary: ThreadCard.Summary?
    var onRewrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary {
                if !summary.text.isEmpty {
                    Text(summary.text).font(.subheadline).textSelection(.enabled)
                }
                switch summary.state {
                case .writing:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Summarising with \(summary.by)…").font(.caption).foregroundStyle(.secondary)
                    }
                case .done:
                    HStack {
                        Text("Summary by \(summary.by)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Rewrite", action: onRewrite).font(.subheadline).buttonStyle(.borderless)
                    }
                    if let notes = summary.notes, !notes.isEmpty {
                        Text("With your notes: \(notes.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    }
                case .failed(let reason):
                    WarningText(reason)
                    Button("Try again", action: onRewrite).font(.subheadline).buttonStyle(.borderless)
                }
            } else {
                Text("No summary yet.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An older message folded to one line: sender, the start of the text and the date. Tap to unfold.
private struct FoldedMessage: View {
    var message: EmailMessage
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(message.from?.display ?? "(no sender)").font(.caption.weight(.semibold)).lineLimit(1)
                Text(message.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(CardDates.short(message.received)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the whole message")
    }
}

private struct MessageView: View {
    var message: EmailMessage
    var canFold: Bool
    var onFold: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.from?.display ?? "(no sender)").font(.subheadline.weight(.semibold))
                    if let from = message.from, from.name != nil {
                        Text(from.email).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(CardDates.full(message.received)).font(.caption).foregroundStyle(.secondary)
                if canFold {
                    Button(action: onFold) { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Fold this message")
                }
            }
            if !message.to.isEmpty || !message.cc.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    if !message.to.isEmpty { Text("To: \(message.to.line)") }
                    if !message.cc.isEmpty { Text("Cc: \(message.cc.line)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !message.attachments.isEmpty {
                Label(message.attachments.joined(separator: ", "), systemImage: "paperclip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if message.body.isEmpty {
                Text(message.bodyNote ?? "(no text)").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(message.body).font(.subheadline).textSelection(.enabled)
            }
            let notes = [message.bodyTruncated ? "Shortened" + (message.bodyTotalChars.map { " (\($0) characters in all)" } ?? "") : nil,
                         message.quotedRemoved ? "Quoted replies and signature hidden" : nil].compactMap { $0 }
            if !notes.isEmpty {
                Text(notes.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Drafts

/// `/drafts`: tap a row to open the draft in the chat.
struct DraftListCardView: View {
    var card: DraftListCard
    var scope: CardScope

    var body: some View {
        CardBox {
            CardHeader(title: "Drafts", detail: card.items.isEmpty ? nil : "\(card.items.count)")
            Divider()
            if card.items.isEmpty {
                Text("No drafts.").font(.footnote).foregroundStyle(.secondary).padding(12)
            }
            ForEach(Array(card.items.enumerated()), id: \.element.id) { index, draft in
                if index > 0 { Divider().padding(.leading, 44) }
                Button {
                    scope.client.openDraft(draft, in: scope.conversationID)
                } label: {
                    HStack(alignment: .top, spacing: 0) {
                        RowNumber(number: index + 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.subject.isEmpty ? "(no subject)" : draft.subject).lineLimit(1)
                            Text(draft.to.isEmpty ? "(no recipients)" : draft.to.map(\.display).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let snippet = draft.snippet, !snippet.isEmpty {
                                Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let account = draft.account {
                                Text(account).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        .font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            CardFooter(problems: card.problems)
        }
    }
}

/// One draft, with Edit (which opens it in the draft editor on this device).
struct DraftCardView: View {
    var card: DraftCard
    var scope: CardScope
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardBox {
            CardHeader(title: card.subject.isEmpty ? "(no subject)" : card.subject,
                       detail: ["Draft", card.isReply ? "reply" : nil, card.account].compactMap { $0 }.joined(separator: " · "))
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("To: \(card.to.isEmpty ? "(none)" : card.to.line)")
                    if !card.cc.isEmpty { Text("Cc: \(card.cc.line)") }
                    if !card.bcc.isEmpty { Text("Bcc: \(card.bcc.line)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(card.body.isEmpty ? "(empty)" : card.body).font(.subheadline).textSelection(.enabled)
            }
            .padding(12)
            CardActions {
                Button("Edit") { scope.act(.editDraft) }
                if let link = card.link.flatMap(URL.init(string:)) {
                    Button("Open in browser") { openURL(link) }
                }
            }
        }
    }
}

// MARK: - Calendar

/// `/today`, `/week`, event searches: grouped by day, with Join for video calls.
struct EventListCardView: View {
    var card: EventListCard

    private var days: [(Date?, [CalendarEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: card.events) { $0.start.map { calendar.startOfDay(for: $0) } }
        return groups.sorted { a, b in
            switch (a.key, b.key) {
            case let (x?, y?): x < y
            case (nil, _): false
            case (_, nil): true
            }
        }
    }

    var body: some View {
        CardBox {
            CardHeader(title: card.title, detail: card.events.isEmpty ? nil : "\(card.events.count)")
            Divider()
            if card.events.isEmpty {
                Text(card.emptyText).font(.footnote).foregroundStyle(.secondary).padding(12)
            }
            ForEach(days, id: \.0) { day, events in
                Text(Self.title(day))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(events) { EventRow(event: $0) }
            }
            let removed = card.duplicatesRemoved
            CardFooter(problems: card.problems,
                       notes: removed > 0 ? ["\(removed) duplicate\(removed == 1 ? "" : "s") from another calendar left out"] : [])
        }
    }

    static func title(_ day: Date?) -> String {
        guard let day else { return "No date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

private struct EventRow: View {
    var event: CalendarEvent
    @Environment(\.openURL) private var openURL

    private var time: String {
        guard let start = event.start else { return "" }
        if event.allDay { return "all day" }
        guard let end = event.end else { return CardDates.time(start) }
        return "\(CardDates.time(start))–\(CardDates.time(end))"
    }

    private var response: String? {
        switch event.myResponse {
        case "tentative": "maybe"
        case "not_responded": "not answered"
        case "declined": "declined"
        default: event.status == "tentative" ? "tentative" : nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(time).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(width: 124, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title).font(.subheadline).strikethrough(event.myResponse == "declined")
                    if let response { Text(response).font(.caption2).foregroundStyle(.purple) }
                }
                let details = [event.location,
                               event.organizedByMe ? "you organise" : nil,
                               event.attendeeCount.flatMap { $0 > 1 ? "\($0) people" : nil },
                               event.recurring ? "repeats" : nil].compactMap { $0 }.filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if let account = event.account {
                    Text([account, event.calendar].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if let link = event.videoLink.flatMap(URL.init(string:)) {
                Button("Join") { openURL(link) }.font(.subheadline).buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
