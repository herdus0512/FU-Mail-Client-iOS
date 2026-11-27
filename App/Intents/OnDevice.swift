import AVFoundation
import FoundationModels
import FUMailKit
import Observation

/// A sentence or two about a quick look, written by Apple Intelligence's model on this iPhone (as the
/// Android app's Gemini Nano): nothing is sent anywhere. Fails with words to show when it can't.
enum OnDeviceSummary {
    struct Problem: Error { var message: String }

    static func summarize(_ kind: QuickLook, lines: String) async -> Result<String, Problem> {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            return .failure(Problem(message: "This iPhone can't write summaries on the device (no Apple Intelligence)."))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .failure(Problem(message: "Apple Intelligence is off (Settings → Apple Intelligence & Siri)."))
        case .unavailable(.modelNotReady):
            return .failure(Problem(message: "Apple Intelligence isn't ready on this iPhone yet. Try again in a minute."))
        case .unavailable:
            return .failure(Problem(message: "Apple Intelligence can't write a summary right now."))
        }
        do {
            let text = try await LanguageModelSession().respond(to: kind.summaryPrompt(lines)).content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .failure(Problem(message: "Apple Intelligence couldn't write a summary: it gave no answer."))
                : .success(text)
        } catch {
            return .failure(Problem(message: "Apple Intelligence couldn't write a summary: \(error.localizedDescription)"))
        }
    }

    /// For Siri: the summary, or nil when there's none within `limit` (Siri then reads the list).
    static func summary(_ kind: QuickLook, lines: String, limit: Duration = .seconds(5)) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await summarize(kind, lines: lines).get() }
            group.addTask { try? await Task.sleep(for: limit); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Reads text aloud with the iPhone's own voice, only when asked; `make say` words are said as they sound.
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: SpokenText.spoken(summary: text, else: text))
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
