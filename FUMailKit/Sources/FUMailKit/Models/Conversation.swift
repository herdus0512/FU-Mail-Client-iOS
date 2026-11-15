import Foundation

// Copied from the Mac app (Sources/FUMailCore/Conversation.swift). One change: a role this version
// doesn't know reads as `.system` instead of failing the message.

/// One chat in the list.
public struct Conversation: Identifiable, Sendable, Equatable, Codable {
    public static let untitled = "New conversation"

    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [ChatMessage]

    public init(id: UUID = UUID(), title: String = Conversation.untitled, createdAt: Date = .now,
                updatedAt: Date? = nil, messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.messages = messages
    }

    /// Adds a message, bumps `updatedAt`, and names an untitled conversation after its first user
    /// message.
    public mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = message.createdAt
        if title == Conversation.untitled, message.role == .user {
            title = Conversation.title(from: message.text, at: message.createdAt)
        }
    }

    private enum CodingKeys: String, CodingKey { case id, title, createdAt, updatedAt, messages }

    /// As the Mac's, except that a message this version can't read is left out instead of failing
    /// the whole conversation.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        messages = try container.decode([Lossy<ChatMessage>].self, forKey: .messages).compactMap(\.value)
    }

    /// Changes a message in place.
    public mutating func update(_ messageID: ChatMessage.ID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&messages[index])
    }

    /// A new chat's title from its first message, as the Mac (3.2) names it: the day, then the
    /// question's first words, e.g. "Mon 16 Nov · what's new from Bob". Only a stand-in until the
    /// Mac's own title comes with the list (it announces it at once): a command stays untitled here,
    /// since only the Mac knows its short name ("Mon 16 Nov · Unread").
    public static func title(from text: String, at date: Date = .now, timeZone: TimeZone = .current,
                             maxLength: Int = 40) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty, !line.hasPrefix("/") else { return untitled }
        return "\(day(date, timeZone: timeZone)) · \(cut(line, maxLength))"
    }

    /// "Mon 16 Nov", always in English like the rest of the app.
    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    /// At most `maxLength` characters, cut at a word.
    static func cut(_ text: String, _ maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let prefix = text.prefix(maxLength)
        let trimmed = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return trimmed.trimmingCharacters(in: .whitespaces) + "…"
    }
}

public struct ChatMessage: Identifiable, Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        /// Notes from the app itself (errors, status), shown small and centred.
        case system

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Role(rawValue: raw) ?? .system
        }
    }

    public let id: UUID
    public var role: Role
    public var text: String
    /// Mail shown as a card instead of (or under) the text.
    public var card: Card?
    public let createdAt: Date

    public init(id: UUID = UUID(), role: Role, text: String = "", card: Card? = nil, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.card = card
        self.createdAt = createdAt
    }
}
