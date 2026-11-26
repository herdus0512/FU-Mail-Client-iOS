import Foundation
import Testing
@testable import FUMailKit

/// Drafts in a thread (FU Mail 6.1.1): the badge, and Reply asking first.
@MainActor
struct ThreadDraftTests {
    private func message(_ id: String, draft: String = "", header: String? = nil) -> String {
        #"{"id":"\#(id)","from":{"email":"me@example.com"},"to":[{"name":"Bob","email":"bob@example.com"}],"cc":[],"#
            + #""subject":"Re: Q4 \#(id)","unread":false,"attachments":[],"body":"Hi","bodyTruncated":false,"quotedRemoved":false"#
            + (header.map { #","headerMessageID":"\#($0)""# } ?? "") + draft + "}"
    }
    private func thread(_ messages: String...) -> String {
        #"{"thread":{"_0":{"ref":{"server":"tb","account":"work","id":"m1"},"subject":"Q4","fullText":false,"#
            + #""side":"original","mailbox":"me@example.com","messages":[\#(messages.joined(separator: ","))]}}}"#
    }
    private var withDrafts: String {
        thread(message("m1"), message("d1", draft: #","isDraft":true"#, header: "<d1@x>"),
               message("d2", draft: #","isDraft":true"#, header: "<d2@x>"))
    }
    private func card(_ text: String) throws -> ThreadCard {
        guard case .thread(let card) = try decode(Card.self, text) else { throw CancellationError() }
        return card
    }

    @Test func isDraftIsReadAndOnlyTrueCounts() throws {
        let card = try card(thread(message("a", draft: #","isDraft":true"#), message("b", draft: #","isDraft":false"#), message("c")))
        #expect(card.messages.map(\.isDraft) == [true, false, nil])
        #expect(card.messages.map(\.isUnsentDraft) == [true, false, false])  // the badge, open or folded
        #expect(card.drafts.map(\.id) == ["a"])
    }

    @Test func onlyAThreadWithADraftAsks() throws {
        #expect(try card(thread(message("m1"), message("m2"))).draftQuestion(replyAll: false) == nil)
        let question = try #require(try card(withDrafts).draftQuestion(replyAll: true))
        #expect(question.draft.draftID == "d2")  // the newest
        #expect(ThreadDraftQuestion.title == "This conversation already has a draft.")
        #expect(ThreadDraftQuestion.text == "Open the draft to edit it, or write a new reply as well.")
        #expect(question.reply == .reply(instructions: "", blank: false, replyAll: true))
    }

    private func open(_ thread: String) async throws -> (TriageDesktop, RemoteClient) {
        let desktop = try TriageDesktop()
        desktop.set { $0.card = thread }
        let client = RemoteClient(transport: desktop, retryPauses: [.seconds(60)])
        client.start()
        await eventually("connected") { client.state.connection.connected }
        client.loadMessages(id("C1"))
        await eventually("loaded") { !client.state.unloaded.contains(id("C1")) }
        return (desktop, client)
    }
    private func current(_ client: RemoteClient) throws -> ThreadCard {
        guard case .thread(let card) = client.state.conversation(id("C1"))?.messages.first?.card else { throw CancellationError() }
        return card
    }

    @Test func editDraftOpensTheNewestWithItsMessageID() async throws {
        let (desktop, client) = try await open(withDrafts)
        let question = try #require(try current(client).draftQuestion(replyAll: false))
        client.answerDraftQuestion(question, edit: true, on: id("M1"), in: id("C1"))
        await eventually("sent") { desktop.actions.count == 1 }
        #expect(desktop.actions[0] == #"POST /v1/conversations/\#(id("C1"))/open {"draft":{"account":"work","draftID":"d2","#
                + #""headerMessageID":"<d2@x>","server":"tb","subject":"Re: Q4 d2","to":[{"email":"bob@example.com","name":"Bob"}]}}"#)
        client.close()
    }

    @Test func editDraftWithoutAMessageIDLeavesItOut() async throws {
        let (desktop, client) = try await open(thread(message("m1"), message("d1", draft: #","isDraft":true"#)))
        client.answerDraftQuestion(try #require(try current(client).draftQuestion(replyAll: false)), edit: true, on: id("M1"), in: id("C1"))
        await eventually("sent") { desktop.actions.count == 1 }
        #expect(desktop.actions[0].hasSuffix(#"{"draft":{"account":"work","draftID":"d1","server":"tb","subject":"Re: Q4 d1","#
                + #""to":[{"email":"bob@example.com","name":"Bob"}]}}"#))
        client.close()
    }

    @Test func writeAnotherSendsTheReplyAsBefore() async throws {
        let (desktop, client) = try await open(withDrafts)
        for all in [false, true] {
            client.answerDraftQuestion(try #require(try current(client).draftQuestion(replyAll: all)), edit: false, on: id("M1"), in: id("C1"))
        }
        await eventually("sent") { desktop.actions.count == 2 }
        #expect(desktop.actions.map { $0.components(separatedBy: " ").dropFirst(2).joined(separator: " ") }
                == [#"{"action":"reply","blank":false,"instructions":"","reply_all":false}"#,
                    #"{"action":"reply","blank":false,"instructions":"","reply_all":true}"#])
        client.close()
    }

    @Test func theQuestionClosesOnChangeBusyOrDisconnect() async throws {
        let (desktop, client) = try await open(withDrafts)
        let card = try current(client)
        let question = try #require(card.draftQuestion(replyAll: false))
        #expect(question.holds(client.state, on: id("M1"), in: id("C1")))
        #expect(!question.holds(.thread(card), busy: true, connected: true))
        #expect(!question.holds(.thread(card), busy: false, connected: false))
        var folded = card
        folded.toggle("m1")
        #expect(!question.holds(.thread(folded), busy: false, connected: true))
        // Changed on the Mac before it's sent: nothing is.
        desktop.updateCard(thread(message("m1"), message("d1", draft: #","isDraft":true"#, header: "<d1@x>")))
        await eventually("changed") { (try? current(client))?.messages.count == 2 }
        client.answerDraftQuestion(question, edit: true, on: id("M1"), in: id("C1"))
        await eventually("the reason") { client.state.connection.problem == TriageConfirmation.changed }
        #expect(desktop.actions.isEmpty)
        client.close()
    }
}
