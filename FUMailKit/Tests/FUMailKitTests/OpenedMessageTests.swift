import Foundation
import Testing
@testable import FUMailKit

/// Which message a thread card was opened from (the Mac's ThreadCard.isOpened).
struct OpenedMessageTests {
    private func message(_ id: String, _ from: String = "bob@example.com", header: String? = nil) -> String {
        #"{"id":"\#(id)","from":{"email":"\#(from)"},"to":[],"cc":[],"subject":"Q4","unread":false,"attachments":[],"body":"Hi","#
            + #""bodyTruncated":false,"quotedRemoved":false\#(header.map { #","headerMessageID":"\#($0)""# } ?? "")}"#
    }

    /// Oldest first, opened as number 40, in my mailbox.
    private func thread(header: String? = nil, _ messages: String...) throws -> ThreadCard {
        try decode(ThreadCard.self, #"{"ref":{"server":"tb","id":40\#(header.map { #","headerMessageID":"\#($0)""# } ?? "")},"#
                   + #""subject":"Q4","mailbox":"me@example.com","fullText":false,"side":"original","messages":[\#(messages.joined(separator: ","))]}"#)
    }

    private func open(_ thread: ThreadCard) -> [String] { thread.messages.filter { thread.isOpenByDefault($0) }.map(\.id) }

    @Test func itsNumberMatches() throws {
        let thread = try thread(header: "a@x", message("40", header: "a@x"), message("41", header: "b@x"), message("42", header: "c@x"))
        #expect(open(thread) == ["40", "42"])
        #expect(thread.replyTarget?.id == "40")
    }

    @Test func onlyItsMessageIDMatches() throws {
        // Its number changed.
        let thread = try thread(header: "a@x", message("77", header: "a@x"), message("41", header: "b@x"), message("42", header: "c@x"))
        #expect(open(thread) == ["77", "42"])
        #expect(!thread.canFoldAgain(thread.messages[0]))
        #expect(thread.replyTarget?.id == "77")
    }

    @Test func neitherMatches() throws {
        let thread = try thread(header: "z@x", message("77", header: "a@x"), message("41", header: "b@x"), message("42", header: "c@x"))
        #expect(open(thread) == ["42"])
        #expect(thread.replyTarget?.id == "42")
    }

    @Test func twoMissingOrEmptyMessageIDsNeverMatch() throws {
        #expect(try open(thread(message("77"), message("42"))) == ["42"])
        #expect(try open(thread(header: "a@x", message("77"), message("42"))) == ["42"])
        #expect(try open(thread(message("77", header: "a@x"), message("42"))) == ["42"])
        let empty = try thread(header: "", message("77", header: ""), message("41", header: ""), message("42"))
        #expect(open(empty) == ["42"])
        #expect(empty.replyTarget?.id == "42")
        #expect(try json(empty.ref) == #"{"headerMessageID":"","id":40,"server":"tb"}"#)  // still back as received
    }

    @Test func anotherFoldersCopy() throws {
        // The card shows one of two copies: not the one it was opened from.
        let copy = try thread(header: "a@x", message("90", header: "a@x"), message("41", "me@example.com", header: "b@x"))
        #expect(open(copy) == ["90"])
        #expect(copy.replyTarget?.id == "90")
        // With both, a reply answers the one with the number, though the copy comes later.
        let both = try thread(header: "a@x", message("40", header: "a@x"), message("90", header: "a@x"), message("42", header: "c@x"))
        #expect(open(both) == ["40", "90", "42"])
        #expect(both.replyTarget?.id == "40")
        // And without it, the last copy.
        let copies = try thread(header: "a@x", message("90", header: "a@x"), message("91", header: "a@x"), message("42", header: "c@x"))
        #expect(copies.replyTarget?.id == "91")
    }

    @Test func everyMessageIsYours() throws {
        let opened = try thread(header: "a@x", message("77", "me@example.com", header: "a@x"), message("41", "me@example.com", header: "b@x"))
        #expect(open(opened) == ["77"])  // not the newest as well
        let neither = try thread(header: "z@x", message("77", "me@example.com", header: "a@x"), message("41", "me@example.com"))
        #expect(open(neither) == ["41"])
    }

    @Test func oldCardsWithoutTheField() throws {
        let old = try thread(message("40"), message("41"), message("42"))
        #expect(old.messages.allSatisfy { $0.headerMessageID == nil })
        #expect(open(old) == ["40", "42"])
        #expect(old.replyTarget?.id == "40")
        #expect(try json(old.messages[0]).contains("headerMessageID") == false)
    }
}
