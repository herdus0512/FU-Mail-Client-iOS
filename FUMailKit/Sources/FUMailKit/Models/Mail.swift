import Foundation

// Copied from the Mac app (Sources/FUMailCore/Mail/MailModels.swift). Keep in step with it. One
// change: `Card` reads a kind this version doesn't know (or can't read) as `.unsupported`, so a newer
// Mac never stops a whole conversation from loading.

public struct EmailAddress: Codable, Sendable, Hashable {
    public var name: String?
    public var email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }

    /// The name when there is one, otherwise the address.
    public var display: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return email
    }
}

/// Enough to fetch an email again: which server, which account, and the server's own IDs.
public struct EmailRef: Codable, Sendable, Hashable {
    public var server: String
    public var account: String?
    /// As the server gave it: a string for Gmail, a number for Apple Mail (MacIA). Sent back exactly so.
    public var id: JSONValue
    public var threadID: String?
    /// The email's own Message-ID, when the Mac sends it, which stays the same when its number doesn't.
    /// Sent back exactly as received.
    public var headerMessageID: String?

    public init(server: String, account: String?, id: JSONValue, threadID: String?, headerMessageID: String? = nil) {
        self.server = server
        self.account = account
        self.id = id
        self.threadID = threadID
        self.headerMessageID = headerMessageID
    }

    public var idString: String { id.stringValue ?? id.intValue.map(String.init) ?? id.serialized() }
}

/// One row of an email list.
public struct EmailSummary: Codable, Sendable, Hashable, Identifiable {
    public var ref: EmailRef
    public var received: Date?
    public var from: EmailAddress?
    public var subject: String
    /// Gmail gives a short preview; Apple Mail doesn't.
    public var snippet: String?
    public var unread: Bool

    public var id: String { "\(ref.server)/\(ref.account ?? "")/\(ref.idString)" }
}

public struct EmailListCard: Codable, Sendable, Hashable {
    public enum Kind: Codable, Sendable, Hashable {
        case unread
        case inbox
        case search(String)
        /// `/archive` and the chat's search_archive. The text describes the search ("" for the newest).
        case archive(String)
    }

    public var kind: Kind
    public var items: [EmailSummary]
    /// Servers or accounts that couldn't be reached, as readable lines.
    public var problems: [String]
    /// Account exclusions a server reported applying, by server name.
    public var exclusions: [String: [String]]
    /// Archive lists only: how to fetch the next page ("Show more"). nil when there's no more.
    public var more: ArchivePaging?

    public init(kind: Kind, items: [EmailSummary], problems: [String], exclusions: [String: [String]],
                more: ArchivePaging? = nil) {
        self.kind = kind
        self.items = items
        self.problems = problems
        self.exclusions = exclusions
        self.more = more
    }

    public var title: String {
        switch kind {
        case .unread: "Unread"
        case .inbox: "Inbox"
        case .search(let query): "Search: \(query)"
        case .archive(let text): text.isEmpty ? "Archive" : "Archive: \(text)"
        }
    }

    public var emptyText: String {
        switch kind {
        case .unread: "No unread email."
        case .inbox: "The inbox is empty."
        case .search: "Nothing matched."
        case .archive(let text): text.isEmpty ? "The archive is empty." : "Nothing in the archive matched."
        }
    }
}

/// One attachment on a message, with metadata for downloading on the Mac.
public struct EmailAttachment: Codable, Sendable, Hashable, Identifiable {
    public var filename: String
    public var attachmentID: String?
    public var mimeType: String?
    public var sizeBytes: Int?

    public var id: String { "\(attachmentID ?? "")/\(filename)" }

    public init(filename: String, attachmentID: String? = nil, mimeType: String? = nil, sizeBytes: Int? = nil) {
        self.filename = filename
        self.attachmentID = attachmentID
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}

/// One message as the server returned it. The body is never touched by an LLM.
public struct EmailMessage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var from: EmailAddress?
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var received: Date?
    public var subject: String
    public var unread: Bool
    public var attachments: [String]
    /// Structured attachment metadata when the server supports downloading attachments.
    public var attachmentItems: [EmailAttachment]? = nil
    public var body: String
    public var bodyTruncated: Bool
    public var bodyTotalChars: Int?
    public var quotedRemoved: Bool
    /// The server's note when there's no readable text (e.g. images only).
    public var bodyNote: String?
    /// Sanitized HTML body from the server, when available.
    public var bodyHTML: String? = nil
    /// The email's own Message-ID, when the Mac sends it.
    public var headerMessageID: String? = nil

    /// The start of the text on one line, for a folded message.
    public var preview: String {
        let text = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.isEmpty { return bodyNote ?? "(no text)" }
        return text.count > 140 ? String(text.prefix(140)) + "…" : text
    }
}

/// A thread (Gmail) or a single email (Apple Mail, which has no threads).
public struct ThreadCard: Codable, Sendable, Hashable {
    public enum Side: String, Codable, Sendable, Hashable {
        case original
        case summary
    }

    /// An LLM summary of the thread, kept with the card so switching sides doesn't regenerate it.
    public struct Summary: Codable, Sendable, Hashable {
        public enum State: Codable, Sendable, Hashable {
            case writing
            case done
            case failed(String)
        }

        public var text: String
        public var state: State
        /// e.g. "local · gemma-4-E4B-it-Q4_K_M"
        public var by: String
        /// The memory.md notes sent with the prompt, by name (never their text).
        public var notes: [String]?

        public init(text: String, state: State, by: String, notes: [String]? = nil) {
            self.text = text
            self.state = state
            self.by = by
            self.notes = notes
        }
    }

    public var ref: EmailRef
    public var subject: String
    /// Oldest first.
    public var messages: [EmailMessage]
    /// A link to open it in the web app, when the server gives one.
    public var link: String?
    /// True when this was fetched with the full text (no length cap, quotes kept).
    public var fullText: Bool
    /// The mailbox's own address, when the server says (google-mcp does), for "reply all".
    public var mailbox: String?
    public var side: Side = .original
    public var summary: Summary?
    /// Older messages the reader unfolded (by message id).
    public var unfolded: Set<String>?
    /// From an archive (BCC-MCP): read-only, so no Reply or Reply all. nil for live mail.
    public var archived: Bool?
    /// The email's server can move it to Trash (`delete_email`) and it isn't archived; left out otherwise.
    public var canDelete: Bool?
    /// Moved to Trash (Delete); left out otherwise.
    public var deleted: Bool?
    /// The email's server can archive it (`archive_email`) and it isn't archived; left out otherwise.
    public var canArchive: Bool?
    /// Moved to Archive (`archive_email`); left out otherwise.
    public var movedToArchive: Bool?
    /// The server can return sanitized HTML for this thread; left out otherwise.
    public var canShowHTML: Bool?
    /// HTML view is active on this thread; left out otherwise.
    public var showingHTML: Bool?
    /// The server can save attachments from this thread to the Mac's download folder; left out otherwise.
    public var canDownloadAttachments: Bool?

    /// Whether a message is shown in full: the one the card was opened from, the newest from someone
    /// else, and any the reader unfolded. Your own messages fold, even when they're the newest.
    public func isOpen(_ message: EmailMessage) -> Bool {
        isOpenByDefault(message) || unfolded?.contains(message.id) == true
    }

    /// Open without the reader unfolding it (so it can't be folded either).
    public func isOpenByDefault(_ message: EmailMessage) -> Bool {
        if isOpened(message) { return true }
        if let newest = messages.last(where: { !isFromMailbox($0) }) { return message.id == newest.id }
        // Every message is yours: the one opened from, else the newest.
        return !messages.contains(where: isOpened) && message.id == messages.last?.id
    }

    /// The message the card was opened from, or another folder's copy of it (a card shows one of them).
    /// An empty Message-ID counts as none.
    func isOpened(_ message: EmailMessage) -> Bool {
        if message.id == ref.idString { return true }
        guard let opened = ref.headerMessageID?.nilIfEmpty else { return false }
        return message.headerMessageID == opened
    }

    /// Sent from this mailbox (the address the server reports for the account).
    public func isFromMailbox(_ message: EmailMessage) -> Bool {
        guard let mailbox = mailbox?.lowercased(), let from = message.from?.email.lowercased() else { return false }
        return from == mailbox
    }

    /// How many messages are folded to one line.
    public var foldedCount: Int { messages.filter { !isOpen($0) }.count }

    /// Folds or unfolds one older message (the change `toggle_fold` makes on the Mac, shown at once).
    public mutating func toggle(_ messageID: String) {
        var set = unfolded ?? []
        if set.remove(messageID) == nil { set.insert(messageID) }
        unfolded = set.isEmpty ? nil : set
    }

    /// Whether "Show full text" would show more.
    public var canShowMore: Bool {
        !fullText && messages.contains { $0.bodyTruncated || $0.quotedRemoved }
    }

    /// The message a reply answers: the one the card was opened from, else the newest.
    public var replyTarget: EmailMessage? {
        messages.last { $0.id == ref.idString } ?? messages.last(where: isOpened) ?? messages.last
    }
}

public struct DraftSummary: Codable, Sendable, Hashable, Identifiable {
    public var server: String
    public var account: String?
    public var draftID: String
    public var to: [EmailAddress]
    public var subject: String
    public var snippet: String?
    public var threadID: String?
    /// The draft's own Message-ID, when the Mac sends it. Sent back exactly as received.
    public var headerMessageID: String? = nil

    public var id: String { "\(server)/\(account ?? "")/\(draftID)" }
}

public struct DraftListCard: Codable, Sendable, Hashable {
    public var items: [DraftSummary]
    public var problems: [String]
}

public struct DraftCard: Codable, Sendable, Hashable {
    public var server: String
    public var account: String?
    public var draftID: String
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    public var body: String
    public var isReply: Bool
    public var link: String?
    /// The draft was sent or deleted (found by `refresh_draft`); left out otherwise.
    public var gone: Bool?
    /// What the mail server warned about when saving it (since FU Mail 3.7.0), e.g. "The new body
    /// replaced the draft's formatting, including any signature added in Google Mail."; left out otherwise.
    public var warning: String?

    /// A Google Mail link, which goes stale whenever the draft is saved (its autosave included).
    public var hasGmailLink: Bool { link?.contains("mail.google.com") == true }
}

public enum Card: Sendable, Hashable {
    case emailList(EmailListCard)
    case thread(ThreadCard)
    case draftList(DraftListCard)
    case draft(DraftCard)
    case events(EventListCard)
    case suggestedNote(SuggestedNoteCard)
    case notes(NotesCard)
    case crm(CRMCard)
    case noteView(NoteViewCard)
    case tasks(TaskListCard)
    case taskDraft(TaskDraftCard)
    case taskChange(TaskChangeCard)
    /// The triage review cards: the Mac sends them only to a device in its `api.full_triage`.
    case spam(SpamCard)
    case clean(CleanCard)
    case repliedArchive(RepliedArchiveCard)
    /// A kind this version doesn't know (from a newer Mac), or one it couldn't read. Shown as a note
    /// instead of failing the message.
    case unsupported(String)
}

/// The same JSON as Swift's synthesized `Codable` on the Mac: `{"thread":{"_0":{…}}}`.
extension Card: Codable {
    private struct CaseKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private enum ValueKey: String, CodingKey { case _0 }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A card with no kind."))
        }
        func value<T: Decodable>(_ type: T.Type) -> T? {
            try? container.nestedContainer(keyedBy: ValueKey.self, forKey: key).decode(type, forKey: ._0)
        }
        let card: Card? = switch key.stringValue {
        case "emailList": value(EmailListCard.self).map(Card.emailList)
        case "thread": value(ThreadCard.self).map(Card.thread)
        case "draftList": value(DraftListCard.self).map(Card.draftList)
        case "draft": value(DraftCard.self).map(Card.draft)
        case "events": value(EventListCard.self).map(Card.events)
        case "suggestedNote": value(SuggestedNoteCard.self).map(Card.suggestedNote)
        case "notes": value(NotesCard.self).map(Card.notes)
        case "crm": value(CRMCard.self).map(Card.crm)
        case "noteView": value(NoteViewCard.self).map(Card.noteView)
        case "tasks": value(TaskListCard.self).map(Card.tasks)
        case "taskDraft": value(TaskDraftCard.self).map(Card.taskDraft)
        case "taskChange": value(TaskChangeCard.self).map(Card.taskChange)
        case "spam": value(SpamCard.self).map(Card.spam)
        case "clean": value(CleanCard.self).map(Card.clean)
        case "repliedArchive": value(RepliedArchiveCard.self).map(Card.repliedArchive)
        default: nil
        }
        self = card ?? .unsupported(key.stringValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        func put<T: Encodable>(_ name: String, _ value: T) throws {
            var nested = container.nestedContainer(keyedBy: ValueKey.self, forKey: CaseKey(stringValue: name))
            try nested.encode(value, forKey: ._0)
        }
        switch self {
        case .emailList(let card): try put("emailList", card)
        case .thread(let card): try put("thread", card)
        case .draftList(let card): try put("draftList", card)
        case .draft(let card): try put("draft", card)
        case .events(let card): try put("events", card)
        case .suggestedNote(let card): try put("suggestedNote", card)
        case .notes(let card): try put("notes", card)
        case .crm(let card): try put("crm", card)
        case .noteView(let card): try put("noteView", card)
        case .tasks(let card): try put("tasks", card)
        case .taskDraft(let card): try put("taskDraft", card)
        case .taskChange(let card): try put("taskChange", card)
        case .spam(let card): try put("spam", card)
        case .clean(let card): try put("clean", card)
        case .repliedArchive(let card): try put("repliedArchive", card)
        case .unsupported(let name):
            _ = container.nestedContainer(keyedBy: ValueKey.self, forKey: CaseKey(stringValue: name))
        }
    }
}
