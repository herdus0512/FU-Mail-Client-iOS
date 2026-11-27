import Foundation

/// What a Home Screen quick action (long-press on the icon) opens, as the Android app's long-press
/// shortcuts: a card asked for at once, without making a chat. The same requests as the Siri actions.
public enum QuickLook: String, Sendable, Identifiable, CaseIterable {
    /// The quick action's type in Info.plist (UIApplicationShortcutItemType).
    case restOfToday = "rest-of-today"
    case pendingDrafts = "pending-drafts"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .restOfToday: "Rest of today"
        case .pendingDrafts: "Pending drafts"
        }
    }

    var path: String {
        switch self {
        case .restOfToday: RestOfToday.path
        case .pendingDrafts: PendingDrafts.path
        }
    }

    /// The card, or why there isn't one (the same sentences as Siri's).
    public enum Answer: Sendable, Equatable {
        case card(Card)
        case problem(String)
    }

    public func fetch(_ transport: any DesktopTransport) async -> Answer {
        do {
            let data = try await transport.send("GET", path, body: nil)
            return switch self {
            case .restOfToday: .card(.events(try APICoding.decoder.decode(EventListCard.self, from: data)))
            case .pendingDrafts: .card(.draftList(try APICoding.decoder.decode(DraftListCard.self, from: data)))
            }
        } catch {
            return .problem(RestOfToday.sentence(for: error, url: transport.display))
        }
    }
}
