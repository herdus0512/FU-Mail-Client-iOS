import Foundation

// Copied from the Mac app (Sources/FUMailCore/Mail/CopyableAddresses.swift). Keep in step with it.

/// A thread message's addresses for its copy menu: From, To and Cc, each without empty addresses or
/// repeats (ignoring case; the first spelling wins), and the groups with nobody in them left out.
public struct CopyableAddresses: Sendable, Equatable {
    public struct Group: Sendable, Equatable, Identifiable {
        public var id: String { title }
        public var title: String
        public var addresses: [EmailAddress]
    }

    public let groups: [Group]

    public init(_ message: EmailMessage) {
        groups = [("From", message.from.map { [$0] } ?? []), ("To", message.to), ("Cc", message.cc)].compactMap { title, list in
            var seen = Set<String>()
            let addresses = list.filter { !$0.email.isEmpty && seen.insert($0.email.lowercased()).inserted }
            return addresses.isEmpty ? nil : Group(title: title, addresses: addresses)
        }
    }

    /// "Copy all addresses": every address once, From, To then Cc, separated by ", ".
    public var all: String {
        var seen = Set<String>()
        return groups.flatMap(\.addresses).map(\.email).filter { seen.insert($0.lowercased()).inserted }.joined(separator: ", ")
    }

    /// "Copy all addresses" is offered only for more than one.
    public var hasSeveral: Bool { all.contains(", ") }

    /// "Name — address", or the address alone when there's no name (or a blank one).
    public static func label(_ address: EmailAddress) -> String {
        address.display == address.email ? address.email : "\(address.display) — \(address.email)"
    }
}
