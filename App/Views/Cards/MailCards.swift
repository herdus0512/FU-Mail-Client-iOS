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
                Text(card.emptyText).appFont(.footnote).foregroundStyle(.secondary).padding(12)
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
                .appFont(.subheadline)
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
                    Text(CardDates.short(item.received)).appFont(.caption).foregroundStyle(.secondary)
                }
                Text(item.subject.isEmpty ? "(no subject)" : item.subject)
                    .fontWeight(item.unread ? .medium : .regular)
                    .lineLimit(1)
                if let snippet = item.snippet, !snippet.isEmpty {
                    Text(snippet).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let account = item.ref.account {
                    Text(account).appFont(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .appFont(.subheadline)
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
    @State private var confirmDelete = false

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.subject.isEmpty ? "(no subject)" : card.subject).appFont(.subheadline, weight: .semibold)
                let detail = [card.ref.account, card.messages.count > 1 ? "\(card.messages.count) messages" : nil].compactMap { $0 }
                if !detail.isEmpty {
                    Text(detail.joined(separator: " · ")).appFont(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            SegmentedChoice(options: card.headerTabs.map { ($0, $0.label) },
                            selection: Binding(get: { card.activeHeaderTab }, set: { tab in
                                switch tab {
                                case .original:
                                    if card.side != .original { scope.act(.setSide(.original)) }
                                    if card.showingHTML == true { scope.act(.showHTML(on: false)) }
                                case .html:
                                    if card.side != .original { scope.act(.setSide(.original)) }
                                    if card.showingHTML != true { scope.act(.showHTML(on: true)) }
                                case .summary:
                                    if card.side != .summary { scope.act(.setSide(.summary)) }
                                }
                            }))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            switch card.side {
            case .original:
                ForEach(card.newestFirst) { message in
                    Divider()
                    if card.isOpen(message) {
                        let emailID = message.id.isEmpty ? card.ref.idString : message.id
                        MessageView(message: message,
                                    showingHTML: card.showingHTML == true,
                                    canDownloadAttachments: card.offersAttachmentDownload,
                                    busy: scope.busy,
                                    canFold: card.canFoldAgain(message),
                                    onFold: { scope.act(.toggleFold(emailID: message.id)) },
                                    onDownloadAttachment: { attachment in
                                        scope.act(.downloadAttachment(emailID: emailID,
                                                                      attachmentID: attachment.attachmentID,
                                                                      filename: attachment.filename))
                                    })
                    } else {
                        FoldedMessage(message: message) { scope.act(.toggleFold(emailID: message.id)) }
                    }
                }
            case .summary:
                Divider()
                SummaryView(summary: card.summary) { scope.act(.summarize(again: true)) }
            }

            if card.deleted == true {
                Text("Moved to Trash.").appFont(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
            CardActions {
                if card.canDelete == true, !archived {
                    Button("Delete", role: .destructive) { confirmDelete = true }.disabled(scope.busy)
                }
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
            .confirmationDialog("Move this email to Trash?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Move to Trash", role: .destructive) { scope.act(.deleteEmail) }
                Button("Cancel", role: .cancel) {}
            }
            }
            Text(card.side == .original
                 ? "Original text from \(card.ref.server)\(archived ? " (archive, read-only)" : "")"
                 : "Written by an LLM")
                .appFont(.caption2)
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
                    Text(summary.text).appFont(.subheadline).copyable(summary.text)
                }
                switch summary.state {
                case .writing:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Summarising with \(summary.by)…").appFont(.caption).foregroundStyle(.secondary)
                    }
                case .done:
                    HStack {
                        Text("Summary by \(summary.by)").appFont(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Rewrite", action: onRewrite).appFont(.subheadline).buttonStyle(.borderless)
                    }
                    if let notes = summary.notes, !notes.isEmpty {
                        Text("With your notes: \(notes.joined(separator: ", "))").appFont(.caption).foregroundStyle(.secondary)
                    }
                case .failed(let reason):
                    WarningText(reason)
                    Button("Try again", action: onRewrite).appFont(.subheadline).buttonStyle(.borderless)
                }
            } else {
                Text("No summary yet.").appFont(.footnote).foregroundStyle(.secondary)
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
                Text(message.from?.display ?? "(no sender)").appFont(.caption, weight: .semibold).lineLimit(1)
                Text(message.preview).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(CardDates.short(message.received)).appFont(.caption).foregroundStyle(.secondary)
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
    var showingHTML: Bool
    var canDownloadAttachments: Bool
    var busy: Bool
    var canFold: Bool
    var onFold: () -> Void
    var onDownloadAttachment: (EmailAttachment) -> Void

    private static func formattedSize(_ bytes: Int?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.from?.display ?? "(no sender)").appFont(.subheadline, weight: .semibold)
                    if let from = message.from, from.name != nil {
                        Text(from.email).appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(CardDates.full(message.received)).appFont(.caption).foregroundStyle(.secondary)
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
                .appFont(.caption)
                .foregroundStyle(.secondary)
            }
            if canDownloadAttachments, let items = message.attachmentItems, !items.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    ForEach(items) { attachment in
                        Button {
                            onDownloadAttachment(attachment)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text(attachment.filename)
                                    .lineLimit(1)
                                if let size = Self.formattedSize(attachment.sizeBytes) {
                                    Text("(\(size))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .appFont(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }
            } else if !message.attachments.isEmpty {
                Label(message.attachments.joined(separator: ", "), systemImage: "paperclip")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if showingHTML, let html = message.bodyHTML, !html.isEmpty {
                HTMLMessageView(html: html)
            } else if message.body.isEmpty {
                Text(message.bodyNote ?? "(no text)").appFont(.footnote).foregroundStyle(.secondary)
            } else {
                Text(message.body).appFont(.subheadline).copyable(message.body)
            }
            let notes = [message.bodyTruncated ? "Shortened" + (message.bodyTotalChars.map { " (\($0) characters in all)" } ?? "") : nil,
                         message.quotedRemoved ? "Quoted replies and signature hidden" : nil].compactMap { $0 }
            if !notes.isEmpty {
                Text(notes.joined(separator: " · ")).appFont(.caption2).foregroundStyle(.secondary)
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
                Text("No drafts.").appFont(.footnote).foregroundStyle(.secondary).padding(12)
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
                                .appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let snippet = draft.snippet, !snippet.isEmpty {
                                Text(snippet).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let account = draft.account {
                                Text(account).appFont(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        .appFont(.subheadline)
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

/// One draft, with Edit (which opens it in the draft editor on this device) and Open in browser
/// (a Google Mail draft is fetched again first, for its current link).
struct DraftCardView: View {
    var card: DraftCard
    var scope: CardScope
    @Environment(\.openURL) private var openURL
    @State private var opening = false

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
                .appFont(.caption)
                .foregroundStyle(.secondary)
                Text(card.body.isEmpty ? "(empty)" : card.body).appFont(.subheadline).copyable(card.body)
                if let warning = card.warning, card.gone != true {
                    WarningText(warning)
                }
            }
            .padding(12)
            if card.gone == true {
                Text("This draft no longer exists (sent or deleted).")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                CardActions {
                    Button("Edit") { scope.act(.editDraft) }
                    if card.link.flatMap(URL.init(string:)) != nil {
                        Button {
                            opening = true
                            Task {
                                let link = await scope.client.draftLinkToOpen(on: scope.messageID, in: scope.conversationID)
                                opening = false
                                if let link { openURL(link) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Open in browser")
                                if opening { ProgressView().controlSize(.mini) }
                            }
                        }
                        .disabled(opening)
                    }
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
                Text(card.emptyText).appFont(.footnote).foregroundStyle(.secondary).padding(12)
            }
            ForEach(days, id: \.0) { day, events in
                Text(Self.title(day))
                    .appFont(.caption, weight: .semibold)
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
            Text(time).appFont(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(width: 124, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title).appFont(.subheadline).strikethrough(event.myResponse == "declined")
                    if let response { Text(response).appFont(.caption2).foregroundStyle(.purple) }
                }
                let details = [event.location,
                               event.organizedByMe ? "you organise" : nil,
                               event.attendeeCount.flatMap { $0 > 1 ? "\($0) people" : nil },
                               event.recurring ? "repeats" : nil].compactMap { $0 }.filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).appFont(.caption).foregroundStyle(.secondary)
                }
                if let account = event.account {
                    Text([account, event.calendar].compactMap { $0 }.joined(separator: " · "))
                        .appFont(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            if let link = event.videoLink.flatMap(URL.init(string:)) {
                Button("Join") { openURL(link) }.appFont(.subheadline).buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
