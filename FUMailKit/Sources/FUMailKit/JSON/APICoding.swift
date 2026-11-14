import Foundation

/// The Mac's JSON: Swift's own `Codable`, with dates as ISO 8601 without fractions (`.iso8601`).
/// Field names are the Mac's (camelCase), and enums with values are `{"case":{"_0":value}}`.
public enum APICoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// A value as a request body.
    public static func body<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONValue.parse(encoder.encode(value))
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
