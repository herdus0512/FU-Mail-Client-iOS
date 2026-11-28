import Foundation

/// What Siri and Speak say for a Shortcuts or Quick Look answer: the text as shown, with words it
/// gets wrong spelt the way they sound (for Siri) or mapped to IPA (for `AVSpeechSynthesizer`).
/// Only the voice uses it; what's shown and what a shortcut gets keep the real spelling.
public enum SpokenText {
    /// Word → how to spell it for Siri's voice. Matched as whole words, ignoring case. Add more here.
    public static let sounds: [String: String] = [
        "Traceforce": "Trace force",
        "neoine": "neo-ein",
        "ignivo": "ig-ni-vo",
    ]

    /// Word → IPA notation for `AVSpeechSynthesizer` (`AVSpeechSynthesisIPANotationAttribute`).
    /// Matched as whole words, ignoring case. Words listed here skip `sounds` replacement in Speak.
    public static let ipa: [String: String] = [:]

    public struct IPARange: Sendable, Equatable {
        public let range: NSRange
        public let ipa: String

        public init(range: NSRange, ipa: String) {
            self.range = range
            self.ipa = ipa
        }
    }

    /// What Siri says: the summary when there is one, else the text; line breaks as pauses.
    public static func spoken(summary: String?, else text: String) -> String {
        spoken(from: summary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } ?? text)
            .replacingOccurrences(of: "\n", with: ". ")
    }

    public static func spoken(from text: String) -> String {
        applySounds(sounds, to: text)
    }

    /// What `Speaker` (`AVSpeechSynthesizer`) says: applies `sounds` for words without an `ipa` entry,
    /// and returns `NSRange`s for words in `ipa` so `AVSpeechSynthesisIPANotationAttribute` can be attached.
    public static func utteranceParts(summary: String?, else text: String,
                                      sounds: [String: String] = SpokenText.sounds,
                                      ipa: [String: String] = SpokenText.ipa) -> (text: String, ipaRanges: [IPARange]) {
        let base = (summary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty } ?? text)
            .replacingOccurrences(of: "\n", with: ". ")
        let ipaKeys = Set(ipa.keys.map { $0.lowercased() })
        let fallbackSounds = sounds.filter { !ipaKeys.contains($0.key.lowercased()) }
        let prepared = applySounds(fallbackSounds, to: base)
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

    private static func applySounds(_ sounds: [String: String], to text: String) -> String {
        sounds.reduce(text) { text, sound in
            text.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: sound.key))\\b", with: sound.value,
                                      options: [.regularExpression, .caseInsensitive])
        }
    }
}
