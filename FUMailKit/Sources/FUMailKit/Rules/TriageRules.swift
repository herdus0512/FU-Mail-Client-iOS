import Foundation

// What the triage cards show and offer, as the Mac's SpamCardView, CleanCardView and
// RepliedArchiveCardView (Sources/FUMail/Cards.swift), and word for word as the Android app's
// TriageRules.kt. One difference from the Mac: on a phone every button but Refresh asks first, since a
// stray tap is easy and nothing here can be undone.

/// A button's question, and the card (or row) as it was when asked. Once that's no longer what the card
/// shows, `holds` is false: the question closes, and nothing is sent.
public struct TriageConfirmation: Sendable, Equatable {
    /// The whole card for "move all" (so it can't cover rows not seen yet), or just the one row.
    enum Seen: Sendable, Equatable {
        case card(Card)
        case spamRow(SpamCard.Row)
        case cleanRow(CleanCard.Row)
        case repliedRow(RepliedArchiveCard.Row)
        /// One of an archive card's lists, as shown: its "Archive all" acts on that list only.
        case repliedList(complete: Bool, [RepliedArchiveCard.Row])
    }

    public var action: CardAction
    public var title: String
    public var text: String
    public var confirmLabel: String
    public var destructive: Bool
    var seen: Seen

    /// What's said when the card changed before a confirmed action was sent.
    public static let changed = "The card changed or was out of date before that was sent, so nothing was done. Check it and try again."

    /// Whether `card` still shows what was asked about and can take the action now.
    public func holds(_ card: Card?, busy: Bool, connected: Bool) -> Bool {
        guard !busy, connected, let card else { return false }
        if case .card(card) = seen { return true }
        return switch (seen, card) {
        case (.spamRow(let row), .spam(let current)): current.rows.contains(row)
        case (.cleanRow(let row), .clean(let current)): current.rows.contains(row)
        case (.repliedRow(let row), .repliedArchive(let current)): (current.rows + (current.complete ?? [])).contains(row)
        case (.repliedList(let complete, let rows), .repliedArchive(let current)):
            (complete ? current.complete ?? [] : current.rows) == rows
        default: false
        }
    }

    public func holds(_ state: RemoteState, on messageID: ChatMessage.ID, in id: Conversation.ID) -> Bool {
        holds(state.conversation(id)?.messages.first { $0.id == messageID }?.card,
              busy: false, connected: state.canAct(on: messageID, in: id))
    }
}

public struct TriageButton: Sendable, Equatable {
    public var label: String
    public var confirmation: TriageConfirmation
    public var enabled: Bool
    /// A line under it in the menu, saying what else it does.
    public var detail: String?

    public var action: CardAction { confirmation.action }
    public var destructive: Bool { confirmation.destructive }
}

public struct TriageRow: Sendable, Equatable, Identifiable {
    public var emailKey: String
    /// What tapping the row opens.
    public var ref: EmailRef
    public var sender: String
    public var subject: String
    public var received: Date?
    /// Account, then why it's here.
    public var details: [String]
    /// "Already deleted" or "Already archived".
    public var mark: String?
    public var buttons: [TriageButton]
    /// The buttons behind ⋯, kept apart from the ones they could be mistaken for.
    public var menu: [TriageButton] = []

    /// By email, not by place: an open menu must not pass to the row that moves up.
    public var id: String { emailKey }
}

/// One list of a card. The archive card has two, with titles; the others one, without.
public struct TriageSection: Sendable, Equatable {
    public var title: String?
    public var rows: [TriageRow]
    /// "Move all to Trash (n)" or "Archive all (n)": this list only; nil when there's nothing to move.
    public var all: TriageButton?
    /// Shown when a titled list is empty.
    public var emptyText: String?
}

public struct TriageView: Sendable, Equatable {
    public var title: String
    public var sections: [TriageSection]
    /// Every row, and the first list's "all" button.
    public var rows: [TriageRow] { sections.flatMap(\.rows) }
    public var all: TriageButton? { sections.first?.all }
    public var refresh: CardAction
    public var refreshEnabled: Bool
    public var statusNote: String?
    /// What the scan found (the archive card).
    public var scanNote: String? = nil
    /// Why the buttons are off, while the chat is out of date.
    public var notice: String?
    /// Shown instead of rows when there are none (the status note, if there is one).
    public var emptyText: String
}

public enum TriageRules {
    /// A triage card's view; nil for any other card. A chat that's out of date counts as disconnected, and
    /// the card says so (while connected: otherwise the connection does). `date` words a date, as the rows
    /// show it.
    public static func view(_ card: Card, busy: Bool, connected: Bool, outOfDate: OutOfDate? = nil,
                            date: (Date) -> String) -> TriageView? {
        let current = connected && outOfDate == nil
        var view: TriageView? = switch card {
        case .spam(let spam): self.view(spam, busy: busy, connected: current)
        case .clean(let clean): self.view(clean, busy: busy, connected: current)
        case .repliedArchive(let replied): self.view(replied, busy: busy, connected: current, date: date)
        default: nil
        }
        if connected { view?.notice = outOfDate?.notice }
        return view
    }

    public static func view(_ card: SpamCard, busy: Bool, connected: Bool) -> TriageView {
        let on = enabled(busy, connected)
        let rows = card.rows.map { row -> TriageRow in
            let item = row.item
            func ask(_ label: String, _ action: CardAction, _ title: String, _ text: String, confirm: String,
                     destructive: Bool, detail: String? = nil) -> TriageButton {
                button(label, action, title, what(item.from, item.subject, text), confirm: confirm, destructive: destructive,
                       seen: .spamRow(row), on, detail: detail)
            }
            let key = item.emailKey
            var buttons: [TriageButton] = []
            var menu: [TriageButton] = []
            if row.canDelete {
                buttons.append(ask("Delete", .spamDelete(emailKey: key), "Move this email to Trash?", "",
                                   confirm: "Move to Trash", destructive: true))
            }
            buttons.append(ask("Not spam", .spamDismiss(emailKey: key), "Not spam?",
                               "Takes it off this list. The email stays, and triage keeps checking this sender.",
                               confirm: "Not spam", destructive: false))
            if let from = item.from {
                if row.canDelete, !item.fromSpamList {
                    menu.append(ask("Add to Spam list & Delete", .spamConfirmAndDelete(emailKey: key),
                                    "Add to the Spam list and delete?",
                                    "Moves this email to Trash, and triage treats \(from.email) as spam from now on.",
                                    confirm: "Add & Delete", destructive: true,
                                    detail: "Also treats this sender as spam from now on"))
                }
                menu.append(ask("Not spam (+ Skip list)", .spamKeepAndSkip(emailKey: key), "Not spam, and skip this sender?",
                                "The email stays. Triage stops checking \(from.email) from now on.",
                                confirm: "Add to Skip list", destructive: false,
                                detail: "Also stops triage checking this sender"))
            }
            return TriageRow(emailKey: key, ref: item.ref, sender: sender(item.from), subject: subject(item.subject),
                             received: item.received, details: details(item.ref, item.reason),
                             mark: row.alreadyDeleted ? "Already deleted" : nil, buttons: buttons, menu: menu)
        }
        return TriageView(title: "Caught Spam & Marketing", sections: [TriageSection(rows: rows, all: moveAll(card.rows.filter(\.canDelete).count, "caught email", .spamDeleteAll, .spam(card), on))],
                          refresh: .spamRefresh, refreshEnabled: on, statusNote: card.statusNote,
                          emptyText: card.statusNote ?? "No caught spam or marketing emails waiting.")
    }

    public static func view(_ card: CleanCard, busy: Bool, connected: Bool) -> TriageView {
        let on = enabled(busy, connected)
        let rows = card.rows.map { row -> TriageRow in
            let item = row.item
            var buttons: [TriageButton] = []
            if row.canDelete {
                buttons.append(button("Delete", .cleanDelete(emailKey: item.emailKey), "Move this email to Trash?",
                                      what(item.from, item.subject), confirm: "Move to Trash", destructive: true,
                                      seen: .cleanRow(row), on))
            }
            buttons.append(button("Keep", .cleanKeep(emailKey: item.emailKey), "Keep this email?",
                                  what(item.from, item.subject, "Takes it off this list. The email stays."),
                                  confirm: "Keep", destructive: false, seen: .cleanRow(row), on))
            return TriageRow(emailKey: item.emailKey, ref: item.ref, sender: sender(item.from), subject: subject(item.subject),
                             received: item.received, details: details(item.ref, item.reason),
                             mark: row.alreadyDeleted ? "Already deleted" : nil, buttons: buttons)
        }
        return TriageView(title: "Inbox Cleanup", sections: [TriageSection(rows: rows, all: moveAll(card.rows.filter(\.canDelete).count, "cleanup item", .cleanDeleteAll, .clean(card), on))],
                          refresh: .cleanRefresh, refreshEnabled: on, statusNote: card.statusNote,
                          emptyText: card.statusNote ?? "No inbox cleanup items waiting.")
    }

    /// Two lists, "You replied last" and "Complete", each with its own "Archive all". A row is a conversation:
    /// Archive moves every Inbox email in it (`targets`).
    public static func view(_ card: RepliedArchiveCard, busy: Bool, connected: Bool, date: (Date) -> String) -> TriageView {
        let on = enabled(busy, connected)
        func emails(_ n: Int) -> String { "\(n) Inbox email\(plural(n))" }
        func list(_ rows: [RepliedArchiveCard.Row], complete: Bool) -> TriageSection {
            let shown = rows.map { row -> TriageRow in
                let item = row.item
                let n = item.emailCount
                let moved = n > 1 ? "\(emails(n)) will be moved to Archive. Sent mail stays where it is."
                    : "It will be moved out of Inbox to Archive."
                let remembered = "FU Mail also suggests a note for ## Archive in memory.md, to edit before it's added."
                func archive(_ remember: Bool) -> TriageButton {
                    button(remember ? "Archive & remember" : n > 1 ? "Archive \(n)" : "Archive",
                           .archiveRepliedOne(emailKey: item.emailKey, remember: remember),
                           n > 1 ? "Archive this conversation?" : "Archive this email?",
                           what(item.from, item.subject, moved + (remember ? " " + remembered : "")),
                           confirm: "Archive", destructive: false, seen: .repliedRow(row), on,
                           detail: remember ? "Also suggests a note to remember it by" : nil)
                }
                func keep(_ remember: Bool) -> TriageButton {
                    button(remember ? "Keep & remember" : "Keep", .archiveRepliedKeep(emailKey: item.emailKey, remember: remember),
                           "Keep this email?",
                           what(item.from, item.subject, "Takes it off this card. The email stays in Inbox."
                                + (remember ? " " + remembered : "")),
                           confirm: "Keep", destructive: false, seen: .repliedRow(row), on,
                           detail: remember ? "Also suggests a note to remember it by" : nil)
                }
                let why = item.reason?.nilIfEmpty ?? item.replied.map { "replied \(date($0))" }
                    ?? (complete ? nil : "you replied last")
                let details = [item.ref.account, n > 1 ? "\(n) emails in Inbox" : nil,
                               item.unread.map { "\($0) unread" }, why].compactMap { $0 }
                return TriageRow(emailKey: item.emailKey, ref: item.ref, sender: sender(item.from), subject: subject(item.subject),
                                 received: item.received, details: details,
                                 mark: row.alreadyArchived ? "Already archived" : nil,
                                 buttons: (row.alreadyArchived ? [] : [archive(false)]) + [keep(false)],
                                 menu: (row.alreadyArchived ? [] : [archive(true)]) + [keep(true)])
            }
            let left = rows.filter { !$0.alreadyArchived }
            let count = left.count
            let all = count == 0 ? nil : button(
                "Archive all (\(count))", complete ? .archiveCompleteAll : .archiveRepliedAll,
                "Archive \(count) conversation\(plural(count))?",
                "\(emails(left.map(\.item.emailCount).reduce(0, +))) will be moved to Archive. Sent mail stays where it "
                    + "is. A conversation with a new message is left alone.",
                confirm: "Archive all", destructive: false, seen: .repliedList(complete: complete, rows), on)
            return TriageSection(title: complete ? "Complete" : "You replied last", rows: shown, all: all,
                                 emptyText: complete ? "None judged complete." : "None.")
        }
        var view = TriageView(title: "Archive (last \(card.days)d)",
                              sections: [list(card.rows, complete: false), list(card.complete ?? [], complete: true)],
                              refresh: .archiveRepliedRefresh, refreshEnabled: on, statusNote: card.statusNote,
                              emptyText: card.statusNote ?? "None.")
        view.scanNote = card.scanNote
        return view
    }

    /// Buttons work unless the card's message is busy, or this device isn't connected (its copy may be old).
    private static func enabled(_ busy: Bool, _ connected: Bool) -> Bool { !busy && connected }

    private static func sender(_ from: EmailAddress?) -> String { from?.display ?? "(no sender)" }
    private static func subject(_ text: String) -> String { text.isEmpty ? "(no subject)" : text }
    private static func plural(_ count: Int) -> String { count == 1 ? "" : "s" }

    /// The email a question is about, then what the button does.
    private static func what(_ from: EmailAddress?, _ text: String, _ effect: String = "") -> String {
        "\(sender(from))\n\(subject(text))" + (effect.isEmpty ? "" : "\n\n\(effect)")
    }

    private static func details(_ ref: EmailRef, _ reason: String) -> [String] {
        [ref.account, reason.nilIfEmpty].compactMap { $0 }
    }

    private static func button(_ label: String, _ action: CardAction, _ title: String, _ text: String, confirm: String,
                               destructive: Bool, seen: TriageConfirmation.Seen, _ on: Bool,
                               detail: String? = nil) -> TriageButton {
        TriageButton(label: label,
                     confirmation: TriageConfirmation(action: action, title: title, text: text, confirmLabel: confirm,
                                                      destructive: destructive, seen: seen),
                     enabled: on, detail: detail)
    }

    private static func moveAll(_ count: Int, _ noun: String, _ action: CardAction, _ card: Card, _ on: Bool) -> TriageButton? {
        guard count > 0 else { return nil }
        return button("Move all to Trash (\(count))", action, "Move \(count) \(noun)\(plural(count)) to Trash?",
                      "Emails that were already deleted outside FU Mail will be skipped cleanly.",
                      confirm: "Move all to Trash", destructive: true, seen: .card(card), on)
    }
}
