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
    }
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

    /// The commands to suggest for what's typed in the composer: while it's a slash and the start of a
    /// name (no space yet), the commands whose names start with it, in `/help`'s order. Nothing once a
    /// command that takes nothing more is typed in full.
    public static func suggestions(_ typed: String, from commands: [Command]) -> [Command] {
        guard typed.hasPrefix("/"), !typed.contains(where: \.isWhitespace) else { return [] }
        let matches = commands.filter { $0.name.lowercased().hasPrefix(typed.lowercased()) }
        if matches.count == 1, matches[0].name.lowercased() == typed.lowercased(), matches[0].args.isEmpty { return [] }
        return matches
    }
}
