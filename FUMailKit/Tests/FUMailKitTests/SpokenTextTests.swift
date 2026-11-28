import Foundation
import Testing
@testable import FUMailKit

struct SpokenTextTests {
    @Test func traceforceIsSaidAsItSounds() {
        #expect(SpokenText.spoken(from: "14:00–15:00 Traceforce review") == "14:00–15:00 Trace force review")
        #expect(SpokenText.spoken(from: "To Bob: TRACEFORCE plan (work)") == "To Bob: Trace force plan (work)")
        #expect(SpokenText.spoken(from: "Traceforce's roadmap") == "Trace force's roadmap")
    }

    @Test func onlyWholeWordsAndNothingElse() {
        #expect(SpokenText.spoken(from: "Traceforces2 and NoTraceforce") == "Traceforces2 and NoTraceforce")
        #expect(SpokenText.spoken(from: "Nothing more on today.") == "Nothing more on today.")
    }

    @Test func ipaRangesMatchWholeWordsAndSkipSoundsReplacement() {
        let result = SpokenText.utteranceParts(
            summary: nil,
            else: "Call ignivo\nThen Traceforce",
            sounds: ["ignivo": "ig-ni-vo", "Traceforce": "Trace force"],
            ipa: ["ignivo": "ɪɡˈniːvoʊ"]
        )
        #expect(result.text == "Call ignivo. Then Trace force")
        #expect(result.ipaRanges.count == 1)
        let match = result.ipaRanges[0]
        #expect(match.ipa == "ɪɡˈniːvoʊ")
        #expect((result.text as NSString).substring(with: match.range) == "ignivo")
    }
}
