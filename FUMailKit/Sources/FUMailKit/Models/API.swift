import Foundation

// The API's own shapes, copied from the Mac app (Sources/FUMailCore/API/APIServer.swift,
// ProviderLine.swift, Store/ConversationStore.swift and Session/Session+Drafts.swift). Keep in step
// with them and with docs/API.md there.

/// A draft editor's state (the Mac's `DraftEditor.Status`).
public enum EditorStatus: Equatable, Sendable, Codable {
    case idle
    /// The body is being written; the text says by whom ("draft · gemini-3.5-flash-lite").
    case writing(String)
    case saving
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .writing, .saving: true
        default: false
        }
    }
}

/// An account available in `/compose` mode.
public struct ComposeAccount: Codable, Hashable, Identifiable, Sendable {
    public var server: String
    public var account: String?
    public var email: String?

    public var id: String { "\(server)/\(account ?? "")" }

    public var display: String {
        switch (account, email) {
        case let (a?, e?) where !a.isEmpty && !e.isEmpty && a.lowercased() != e.lowercased():
            "\(a) (\(e))"
        default:
            email ?? account ?? server
        }
    }

    public init(server: String, account: String? = nil, email: String? = nil) {
        self.server = server
        self.account = account
        self.email = email
    }
}

/// A recipient suggestion from `GET /v1/contacts`.
public struct ContactEntry: Codable, Hashable, Identifiable, Sendable {
    public var name: String?
    public var email: String

    public var id: String { email.lowercased() }

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    /// Formatted for a recipient field: `"Name <email>, "` or `"email, "`.
    public var recipientToken: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(name) <\(email)>, "
        }
        return "\(email), "
    }

    /// Trailing comma-separated token (text after the last `,`, trimmed).
    public static func trailingToken(in field: String) -> String {
        let afterComma = field.lastIndex(of: ",").map { field[field.index(after: $0)...] } ?? field[...]
        return afterComma.trimmingCharacters(in: .whitespaces)
    }

    /// Filters `contacts` for `field`'s trailing token: prefix matches on name or email first,
    /// then substring matches, capped at `limit`.
    public static func suggestions(for field: String, from contacts: [ContactEntry], limit: Int = 6) -> [ContactEntry] {
        let query = trailingToken(in: field).lowercased()
        guard !query.isEmpty else { return [] }
        var prefix: [ContactEntry] = []
        var substring: [ContactEntry] = []
        for contact in contacts {
            let name = contact.name?.lowercased() ?? ""
            let email = contact.email.lowercased()
            if name.hasPrefix(query) || email.hasPrefix(query) {
                prefix.append(contact)
            } else if name.contains(query) || email.contains(query) {
                substring.append(contact)
            }
        }
        return Array((prefix + substring).prefix(limit))
    }

    /// Replaces the trailing comma-separated token in `field` with `"Name <email>, "` (or `"email, "`).
    public static func applying(_ contact: ContactEntry, to field: String) -> String {
        let replacement = contact.recipientToken
        guard let comma = field.lastIndex(of: ",") else { return replacement }
        let head = field[...comma]
        return "\(head) \(replacement)"
    }
}

/// A draft editor as the API sends it. Editors belong to the device that opened them.
public struct EditorState: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var conversationID: Conversation.ID
    public var title: String
    public var isReply: Bool
    public var server: String
    /// Whether the server can save it (MacIA can't), else only copying is offered.
    public var canSave: Bool
    public var form: DraftForm
    public var instructions: String
    public var signature: String?
    public var status: EditorStatus
    public var mode: Mode

    public enum Mode: Codable, Sendable, Equatable {
        case reply(ReplyContext, ThreadCard)
        case existing(DraftCard, messageID: ChatMessage.ID)
        case compose(accounts: [ComposeAccount], selected: ComposeAccount?)
    }

    public var isCompose: Bool {
        if case .compose = mode { true } else { false }
    }

    /// Reply and compose editors both support Instructions + Write/Rewrite and "Save to Drafts".
    public var supportsWrite: Bool { isReply || isCompose }
}

/// One change, as the event stream sends it (`data: {…}` lines).
public struct APIEvent: Codable, Sendable {
    public var type: String
    public var conversationID: Conversation.ID?
    public var message: ChatMessage?
    public var messageID: ChatMessage.ID?
    public var status: String?
    public var busy: Bool?
    public var error: String?
    public var editor: EditorState?
    public var editorID: UUID?

    public init(type: String, conversationID: Conversation.ID? = nil, message: ChatMessage? = nil,
                messageID: ChatMessage.ID? = nil, status: String? = nil, busy: Bool? = nil, error: String? = nil,
                editor: EditorState? = nil, editorID: UUID? = nil) {
        self.type = type
        self.conversationID = conversationID
        self.message = message
        self.messageID = messageID
        self.status = status
        self.busy = busy
        self.error = error
        self.editor = editor
        self.editorID = editorID
    }
}

/// A conversation in the API's list.
public struct ConversationListItem: Codable, Sendable, Equatable {
    public var id: Conversation.ID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: Conversation.ID, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One conversation with its messages, and what's happening in it.
public struct ConversationDetail: Codable, Sendable {
    public var conversation: Conversation
    public var chatStatus: String?
    public var answering: Bool
    public var busyMessages: [ChatMessage.ID]

    public init(conversation: Conversation, chatStatus: String?, answering: Bool, busyMessages: [ChatMessage.ID]) {
        self.conversation = conversation
        self.chatStatus = chatStatus
        self.answering = answering
        self.busyMessages = busyMessages
    }
}

/// `GET /v1/info`. Everything but the version is optional here, so an older or newer Mac still reads.
public struct APIInfo: Codable, Sendable, Equatable {
    public var version: String
    public var build: String?
    public var commit: String?
    /// The device this token belongs to.
    public var device: String?
    public var providerLine: ProviderLine?
    public var configError: String?
    public var storeError: String?
    public var notesConfigured: Bool?
    /// Whether suggested notes can be added (FU Mail's own memory.md is set up).
    public var canAddSuggestions: Bool?
    /// The notes section entries go under, e.g. "Correspondence", when notes are set up.
    public var notesSection: String?
    /// The Obsidian vault's name, for obsidian:// links.
    public var obsidianVault: String?
    /// The Memos server, e.g. "https://memo.cooltym.net", when notes are kept there (FU Mail 4.5.0 and
    /// later): a note whose path starts with "memos/" opens at memosURL + "/" + path.
    public var memosURL: String?
    /// `/crm` is set up there.
    public var crmConfigured: Bool?
    /// The CRM section's name ("CRM"), when `/crm` is set up.
    public var crmSection: String?
    /// A task server (GTask-MCP) is configured: /tasks, /task and Add task.
    public var tasksConfigured: Bool?
}

/// The line under the title: which provider each role uses on the Mac, and the details for each.
public struct ProviderLine: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        /// "chat", "summary", "draft" or "embedding".
        public var key: String
        public var label: String
        /// Runs off the Mac (a globe), rather than on it.
        public var remote: Bool
        public var details: String
        public var id: String { key }
    }

    public var entries: [Entry]
}

/// One conversation matching a history search.
public struct SearchHit: Sendable, Equatable, Identifiable, Codable {
    public let conversationID: UUID
    public var title: String
    public var updatedAt: Date
    /// The matching text, with the matched words between « and ».
    public var snippet: String
    /// Found by meaning (semantic search) rather than by its words.
    public var byMeaning: Bool?
    /// The message that matched, to scroll to (since FU Mail 3.3.0; nil from an older Mac).
    public var messageID: UUID?
    public var id: UUID { conversationID }
}

/// A slash command, as `/help` lists it (`GET /v1/commands`).
public struct Command: Codable, Sendable, Equatable, Identifiable {
    /// "/unread"
    public var name: String
    /// "[n]", "<words>", or "" when it takes nothing.
    public var args: String
    public var summary: String
    public var id: String { name }

    public init(name: String, args: String = "", summary: String = "") {
        self.name = name
        self.args = args
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey { case name, args, summary }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        args = try container.decodeIfPresent(String.self, forKey: .args) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }

    /// The commands to suggest for what's typed in the composer, while it's one word (no space yet), in
    /// `/help`'s order: after a slash, those whose names start with it; without one (a "/" is awkward
    /// on a phone), those whose names start with the letters typed, so "u" offers /unread. Nothing
    /// once a command that takes nothing more is typed in full.
    public static func suggestions(_ typed: String, from commands: [Command]) -> [Command] {
        guard !typed.isEmpty, !typed.contains(where: \.isWhitespace) else { return [] }
        guard typed.hasPrefix("/") else {
            return commands.filter { $0.name.dropFirst().lowercased().hasPrefix(typed.lowercased()) }
        }
        let matches = commands.filter { $0.name.lowercased().hasPrefix(typed.lowercased()) }
        if matches.count == 1, matches[0].name.lowercased() == typed.lowercased(), matches[0].args.isEmpty { return [] }
        return matches
    }
}
