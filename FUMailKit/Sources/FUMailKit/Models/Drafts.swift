import Foundation

// Copied from the Mac app (Sources/FUMailCore/Mail/Drafts.swift), without the parts that only the
// Mac uses to save drafts. Keep in step with it.

/// What the draft editor shows. Address fields are comma-separated "Name <email>" text. The Mac needs
/// every field, so all of them are always sent.
public struct DraftForm: Sendable, Hashable, Codable {
    public var to: String
    public var cc: String
    public var bcc: String
    public var subject: String
    public var body: String
    public var replyAll: Bool

    public init(to: String = "", cc: String = "", bcc: String = "", subject: String = "", body: String = "",
                replyAll: Bool = false) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.replyAll = replyAll
    }
}

/// The email a new draft replies to.
public struct ReplyContext: Sendable, Hashable, Codable {
    public var ref: EmailRef
    public var original: EmailMessage
    public var threadSubject: String
    /// The mailbox's own address, left out of "reply all".
    public var mailbox: String?

    public init(thread: ThreadCard) {
        ref = thread.ref
        original = thread.replyTarget ?? EmailMessage(
            id: thread.ref.idString, from: nil, to: [], cc: [], received: nil, subject: thread.subject,
            unread: false, attachments: [], body: "", bodyTruncated: false, bodyTotalChars: nil,
            quotedRemoved: false, bodyNote: nil)
        threadSubject = thread.subject
        mailbox = thread.mailbox
    }
}

public enum Drafts {
    static func line(_ addresses: [EmailAddress]) -> String {
        addresses.map { address in address.name.map { "\($0) <\(address.email)>" } ?? address.email }
            .joined(separator: ", ")
    }

    /// The email addresses in a field, lowercased, for comparing.
    static func emails(_ field: String) -> [String] {
        field.split(separator: ",").compactMap { part in
            let text = part.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
                return String(text[text.index(after: open)..<close]).lowercased()
            }
            return text.lowercased()
        }
    }

    static func replySubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        return trimmed.lowercased().hasPrefix("re:") ? trimmed : "Re: \(trimmed)"
    }

    /// What a reply starts with: to the sender, "Re: …", and for reply all, everyone else on the
    /// original except the mailbox itself. When the mailbox sent the original, the reply goes to
    /// that message's recipients instead (and reply all adds its Cc).
    public static func replyDefaults(_ context: ReplyContext, replyAll: Bool) -> DraftForm {
        let original = context.original
        let me = context.mailbox?.lowercased()
        let sender = original.from.map { [$0] } ?? []
        let fromMe = me != nil && original.from?.email.lowercased() == me
        var to = sender
        if fromMe {
            var seen = Set<String>()
            let recipients = original.to.filter { $0.email.lowercased() != me && seen.insert($0.email.lowercased()).inserted }
            if !recipients.isEmpty { to = recipients }  // a note to yourself still goes to you
        }
        var cc: [EmailAddress] = []
        if replyAll {
            var skip = Set((to.map(\.email) + [me].compactMap { $0 }).map { $0.lowercased() })
            for address in fromMe ? original.cc : original.to + original.cc
            where skip.insert(address.email.lowercased()).inserted {
                cc.append(address)
            }
        }
        return DraftForm(to: line(to), cc: line(cc), subject: replySubject(original.subject.isEmpty
                                                                             ? context.threadSubject : original.subject),
                         replyAll: replyAll)
    }

    /// Whether reply all would reach anyone a plain reply doesn't (the thread card shows Reply all only then).
    public static func canReplyAll(_ context: ReplyContext) -> Bool {
        !emails(replyDefaults(context, replyAll: true).cc).isEmpty
    }
}
