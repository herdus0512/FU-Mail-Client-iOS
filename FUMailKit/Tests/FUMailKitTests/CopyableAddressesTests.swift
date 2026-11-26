import Foundation
import Testing
@testable import FUMailKit

/// A thread message's copy menu (the Mac's CopyableAddresses).
struct CopyableAddressesTests {
    private func message(from: EmailAddress?, to: [EmailAddress] = [], cc: [EmailAddress] = []) -> EmailMessage {
        EmailMessage(id: "m", from: from, to: to, cc: cc, received: nil, subject: "", unread: false, attachments: [], body: "",
                     bodyTruncated: false, bodyTotalChars: nil, quotedRemoved: false, bodyNote: nil)
    }
    private func a(_ email: String, _ name: String? = nil) -> EmailAddress { EmailAddress(name: name, email: email) }

    @Test func groupsInOrderWithoutEmptyOnes() {
        let copy = CopyableAddresses(message(from: a("bob@x.com", "Bob"), cc: [a("carol@x.com")]))
        #expect(copy.groups.map(\.title) == ["From", "Cc"])
        #expect(CopyableAddresses(message(from: a("b@x"), to: [a("t@x")], cc: [a("c@x")])).groups.map(\.title) == ["From", "To", "Cc"])
    }

    @Test func labels() {
        #expect(CopyableAddresses.label(a("bob@x.com", "Bob")) == "Bob — bob@x.com")
        #expect(CopyableAddresses.label(a("bob@x.com")) == "bob@x.com")
        #expect(CopyableAddresses.label(a("bob@x.com", "  ")) == "bob@x.com")
    }

    @Test func oneAddressIsItself() {
        let copy = CopyableAddresses(message(from: a("bob@x.com", "Bob")))
        #expect(copy.groups[0].addresses.map(\.email) == ["bob@x.com"])
        #expect(copy.all == "bob@x.com")
        #expect(!copy.hasSeveral)  // no "Copy all"
    }

    @Test func copyAllWithRepeatsAndEmpties() {
        let copy = CopyableAddresses(message(from: a("Bob@X.com", "Bob"),
                                             to: [a("carol@x.com"), a("CAROL@x.com"), a(""), a("bob@x.com")],
                                             cc: [a("dan@x.com"), a("Carol@X.com")]))
        #expect(copy.groups.map { $0.addresses.map(\.email) } == [["Bob@X.com"], ["carol@x.com", "bob@x.com"], ["dan@x.com", "Carol@X.com"]])
        #expect(copy.all == "Bob@X.com, carol@x.com, dan@x.com")
        #expect(copy.hasSeveral)
    }

    @Test func noAddressesNoMenu() {
        #expect(CopyableAddresses(message(from: nil)).groups.isEmpty)
        #expect(CopyableAddresses(message(from: a(""), to: [a("")])).groups.isEmpty)
    }

    @Test func everyoneOnTheLineCounts() {
        let many = (1...30).map { a("p\($0)@x.com") }
        #expect(CopyableAddresses(message(from: nil, to: many)).groups[0].addresses.count == 30)
    }
}
