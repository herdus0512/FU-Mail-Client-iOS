import Foundation

/// What Siri says for a Shortcuts answer: the text as shown, with words it gets wrong spelt the way they
/// sound. Only the voice uses it; what's shown and what a shortcut gets keep the real spelling.
public enum SpokenText {
    /// Word → how to spell it for Siri's voice. Matched as whole words, ignoring case. Add more here.
    public static let sounds: [String: String] = [
        "Traceforce": "Trace force",
    ]

    public static func spoken(from text: String) -> String {
        sounds.reduce(text) { text, sound in
            text.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: sound.key))\\b", with: sound.value,
                                      options: [.regularExpression, .caseInsensitive])
        }
    }
}
