import Foundation
import Synchronization
import Testing
@testable import FUMailKit

/// Home Screen quick actions (as the Android app's long-press shortcuts), against a stand-in Mac.
@MainActor
struct QuickLookTests {
    final class Stub: DesktopTransport {
        let display = "http://fake-mac:8765"
        let answers: [String: Result<String, RemoteProblem>]
        let asked = Mutex<[String]>([])
        init(_ answers: [String: Result<String, RemoteProblem>]) { self.answers = answers }

        func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
            asked.withLock { $0.append("\(method) \(path)" + (body.map { " " + String(decoding: $0, as: UTF8.self) } ?? "")) }
            switch answers["\(method) \(path)"] ?? .success(#"{"ok":true}"#) {
            case .success(let text): return Data(text.utf8)
            case .failure(let problem): throw problem
            }
        }
        func health() async throws {}
        func events() -> AsyncThrowingStream<StreamItem, Error> { AsyncThrowingStream { _ in } }
    }

    private let draft = #"{"server":"tb","account":"work","draftID":"9","to":[{"email":"bob@x.com"}],"subject":"Re: Q4","headerMessageID":"<d@x>"}"#

    @Test func theTypesMatchInfoPlist() {
        #expect(QuickLook.allCases.map(\.rawValue) == ["rest-of-today", "pending-drafts"])
        #expect(QuickLook.allCases.map(\.title) == ["Rest of today", "Pending drafts"])
    }

    @Test func restOfTodayAsksForTheCalendarCard() async {
        let stub = Stub(["GET /v1/calendar/now": .success(#"{"kind":{"days":{"_0":1}},"events":[],"problems":[],"duplicatesRemoved":0}"#)])
        guard case .card(.events(let card)) = await QuickLook.restOfToday.fetch(stub) else { Issue.record("no card"); return }
        #expect(card.events.isEmpty)
        #expect(stub.asked.withLock { $0 } == ["GET /v1/calendar/now"])
    }

    @Test func pendingDraftsAsksForTheDrafts() async {
        let stub = Stub(["GET /v1/drafts?limit=10": .success(#"{"items":[\#(draft)],"problems":[]}"#)])
        guard case .card(.draftList(let card)) = await QuickLook.pendingDrafts.fetch(stub) else { Issue.record("no card"); return }
        #expect(card.items.map(\.draftID) == ["9"])
        #expect(stub.asked.withLock { $0 } == ["GET /v1/drafts?limit=10"])
    }

    @Test func aProblemIsSaidAsSiriSaysIt() async {
        let refused = RemoteProblem(.unreachable, "Can't reach it.")
        let stub = Stub(["GET /v1/calendar/now": .failure(refused)])
        let answer = await QuickLook.restOfToday.fetch(stub)
        #expect(answer == .problem(RestOfToday.sentence(for: refused, url: stub.display)))
        #expect(QuickLook.siriSummary(answer) == RestOfToday.sentence(for: refused, url: stub.display))
    }

    @Test func siriSummaryReportsCountsOnly() throws {
        let noEvents = try decode(EventListCard.self, #"{"kind":{"days":{"_0":1}},"events":[],"problems":[],"duplicatesRemoved":0}"#)
        #expect(QuickLook.siriSummary(.card(.events(noEvents))) == "Nothing more on today.")
        let oneEvent = try decode(EventListCard.self, #"{"kind":{"days":{"_0":1}},"events":[{"server":"google","eventID":"1","title":"Standup","allDay":false,"organizedByMe":false,"recurring":false}],"problems":[],"duplicatesRemoved":0}"#)
        #expect(QuickLook.siriSummary(.card(.events(oneEvent))) == "You have 1 event left today.")
        let twoEvents = try decode(EventListCard.self, #"{"kind":{"days":{"_0":1}},"events":[{"server":"google","eventID":"1","title":"Standup","allDay":false,"organizedByMe":false,"recurring":false},{"server":"google","eventID":"2","title":"Lunch","allDay":false,"organizedByMe":false,"recurring":false}],"problems":[],"duplicatesRemoved":0}"#)
        #expect(QuickLook.siriSummary(.card(.events(twoEvents))) == "You have 2 events left today.")

        let noDrafts = try decode(DraftListCard.self, #"{"items":[],"problems":[]}"#)
        #expect(QuickLook.siriSummary(.card(.draftList(noDrafts))) == "No drafts waiting.")
        let oneDraft = try decode(DraftListCard.self, #"{"items":[\#(draft)],"problems":[]}"#)
        #expect(QuickLook.siriSummary(.card(.draftList(oneDraft))) == "You have 1 pending draft.")
        let twoDrafts = try decode(DraftListCard.self, #"{"items":[\#(draft),\#(draft)],"problems":[]}"#)
        #expect(QuickLook.siriSummary(.card(.draftList(twoDrafts))) == "You have 2 pending drafts.")
    }

    @Test func aDraftOpensInANewChat() async throws {
        let stub = Stub(["POST /v1/conversations": .success(#"{"id":"\#(id("NEW").uuidString)"}"#)])
        let client = RemoteClient(transport: stub)
        let summary = try decode(DraftSummary.self, draft)
        #expect(await client.openDraftInNewChat(summary) == id("NEW"))
        await eventually("opened") { stub.asked.withLock { $0 }.count == 2 }
        #expect(stub.asked.withLock { $0 } == [
            "POST /v1/conversations",
            #"POST /v1/conversations/\#(id("NEW"))/open {"draft":{"account":"work","draftID":"9","headerMessageID":"<d@x>","server":"tb","#
                + #""subject":"Re: Q4","to":[{"email":"bob@x.com"}]}}"#,
        ])
        client.close()
    }
}
