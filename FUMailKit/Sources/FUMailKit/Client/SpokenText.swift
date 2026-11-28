import Foundation

/// What Speak (`AVSpeechSynthesizer`) and Siri say for a Quick Look or Shortcuts answer: the text as
/// shown, with words mapped to IPA (`SpokenText.ipa`) for `AVSpeechSynthesizer` (`AVSpeechSynthesisIPANotationAttribute`).
/// Only the voice uses it; what's shown and what a shortcut gets keep the real spelling.
public enum SpokenText {
    /// Word → IPA notation for `AVSpeechSynthesizer` (`AVSpeechSynthesisIPANotationAttribute`).
    /// Matched as whole words, ignoring case. Manage with `make say WORD=… IPA="…"`.
    public static let ipa: [String: String] = [:]

    public struct IPARange: Sendable, Equatable {
        public let range: NSRange
        public let ipa: String

        public init(range: NSRange, ipa: String) {
            self.range = range
            self.ipa = ipa
        }
    }

    /// The summary when there is one, else the text; line breaks as pauses.
    public static func spoken(summary: String?, else text: String) -> String {
        (summary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } ?? text)
            .replacingOccurrences(of: "\n", with: ". ")
    }

    /// What `Speaker` (`AVSpeechSynthesizer`) says: the prepared text and `NSRange`s for words in
    /// `ipa` so `AVSpeechSynthesisIPANotationAttribute` can be attached.
    public static func utteranceParts(summary: String?, else text: String,
                                      ipa: [String: String] = SpokenText.ipa) -> (text: String, ipaRanges: [IPARange]) {
        let prepared = spoken(summary: summary, else: text)
        guard !ipa.isEmpty else { return (prepared, []) }

        var ranges: [IPARange] = []
        let nsText = prepared as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for (word, notation) in ipa {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: prepared, range: fullRange) {
                ranges.append(IPARange(range: match.range, ipa: notation))
            }
        }
        return (prepared, ranges)
    }
}
