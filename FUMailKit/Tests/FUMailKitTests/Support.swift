import Foundation
import Testing
@testable import FUMailKit

/// A fixture's text: JSON the Mac wrote, shared with the Android app's tests.
func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try APICoding.decoder.decode(type, from: Data(text.utf8))
}

/// Compact JSON with sorted keys, for comparing what's sent.
func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = APICoding.encoder
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

let t0 = Date(timeIntervalSince1970: 1_794_556_800)  // 2026-11-13T08:00:00Z

/// Fixed IDs, so a test reads like the Android one ("C1", "M1").
func id(_ name: String) -> UUID {
    let known = ["C1": "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A00", "M1": "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A01",
                 "M2": "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A02"]
    if let text = known[name] { return UUID(uuidString: text)! }
    var hex = Array(name.utf8.map { String(format: "%02X", $0) }.joined().prefix(12))
    while hex.count < 12 { hex.append("0") }
    return UUID(uuidString: "00000000-0000-4000-8000-" + String(hex))!
}

/// Waits until `condition` holds (or fails the test after `seconds`).
@MainActor
func eventually(_ what: String, seconds: Double = 5, _ condition: @MainActor () -> Bool,
                sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = Date.now.addingTimeInterval(seconds)
    while !condition() {
        if Date.now > deadline {
            Issue.record("Timed out waiting for \(what)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
