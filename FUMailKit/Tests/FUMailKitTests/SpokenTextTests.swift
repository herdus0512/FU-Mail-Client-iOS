import Foundation
import Testing
@testable import FUMailKit

struct SpokenTextTests {
    @Test func ipaMatchesWholeWordsIgnoringCase() {
        let ipa = ["Traceforce": "ˈtreɪsfɔːs"]
        let result = SpokenText.utteranceParts(
            summary: nil,
            else: "14:00–15:00 Traceforce review\nTo Bob: TRACEFORCE plan\nTraceforce's roadmap",
            ipa: ipa
        )
        #expect(result.text == "14:00–15:00 Traceforce review. To Bob: TRACEFORCE plan. Traceforce's roadmap")
        #expect(result.ipaRanges.count == 3)
        let ns = result.text as NSString
        #expect(result.ipaRanges.map { ns.substring(with: $0.range) } == ["Traceforce", "TRACEFORCE", "Traceforce"])
        #expect(result.ipaRanges.allSatisfy { $0.ipa == "ˈtreɪsfɔːs" })
    }

    @Test func onlyWholeWordsAndNothingElse() {
        let result = SpokenText.utteranceParts(
            summary: nil,
            else: "Traceforces2 and NoTraceforce",
            ipa: ["Traceforce": "ˈtreɪsfɔːs"]
        )
        #expect(result.text == "Traceforces2 and NoTraceforce")
        #expect(result.ipaRanges.isEmpty)
        #expect(SpokenText.utteranceParts(summary: nil, else: "Nothing more on today.", ipa: [:]).ipaRanges.isEmpty)
    }
}
