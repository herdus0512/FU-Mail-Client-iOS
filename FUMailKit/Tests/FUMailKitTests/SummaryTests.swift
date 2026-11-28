import Foundation
import Testing
@testable import FUMailKit

/// Summarise & Speak: what the on-device model is asked, and what's said (as the Android app).
struct SummaryTests {
    @Test func theInstructionsAreAndroidsWordForWord() {
        #expect(QuickLook.restOfToday.summaryInstruction == "Below is what's left on my calendar today, one event per line. "
                + "In one or two short, friendly sentences, tell me what's coming up and when I'm free. Don't invent anything.")
        #expect(QuickLook.pendingDrafts.summaryInstruction == "Below are my unsent email drafts, one per line (who it's to, "
                + "then the subject). In one or two short sentences, tell me how many there are and who they're to. Don't invent anything.")
        #expect(QuickLook.pendingDrafts.summaryPrompt("To Bob: Q4") == QuickLook.pendingDrafts.summaryInstruction + "\n\nTo Bob: Q4")
    }

    @Test func theModelGetsTheSiriLinesWithTheRealSpelling() throws {
        let drafts = try decode(DraftListCard.self, #"{"items":[{"server":"tb","account":"work","draftID":"9","#
                                + #""to":[{"name":"Bob","email":"bob@x"},{"email":"c@x"}],"subject":"Traceforce plan"}],"problems":[]}"#)
        #expect(QuickLook.lines(.card(.draftList(drafts))) == "To Bob +1: Traceforce plan (work)")
        let none = try decode(EventListCard.self, #"{"kind":{"days":{"_0":1}},"events":[],"problems":[],"duplicatesRemoved":0}"#)
        #expect(QuickLook.lines(.card(.events(none))) == RestOfToday.text(none))
        #expect(QuickLook.lines(.problem("Can't reach the Mac.")) == "Can't reach the Mac.")
    }

    @Test func theSummaryIsSaidWhenThereIsOneElseTheList() {
        let list = "14:00–15:00 Traceforce review\n16:00–16:30 Call Bob"
        #expect(SpokenText.spoken(summary: "Traceforce at 2, then you're free.", else: list) == "Traceforce at 2, then you're free.")
        #expect(SpokenText.spoken(summary: nil, else: list) == "14:00–15:00 Traceforce review. 16:00–16:30 Call Bob")
        #expect(SpokenText.spoken(summary: "  \n", else: list) == "14:00–15:00 Traceforce review. 16:00–16:30 Call Bob")
    }
}
