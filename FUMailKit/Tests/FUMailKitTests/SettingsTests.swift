import Foundation
import Testing
@testable import FUMailKit

/// What's typed in Settings, problems in plain words, command suggestions and the event stream's lines.
struct SettingsTests {
    private func parse(_ url: String, _ token: String = "fum_abc") -> ServerSettings? {
        try? ServerSettings.parse(url: url, token: token).get()
    }

    @Test func addressesAreChecked() {
        #expect(parse(" http://192.168.107.138:8765 ")?.display == "http://192.168.107.138:8765")
        #expect(parse("desktop:8765")?.display == "http://desktop:8765")
        #expect(parse("https://desktop.tail1234.ts.net/")?.display == "https://desktop.tail1234.ts.net")
        #expect(parse("") == nil)
        #expect(parse("http://") == nil)
        #expect(parse("ftp://desktop") == nil)
        #expect(parse("http://desktop:8765/?x=1") == nil)
        #expect(parse("http://desktop:8765", " ") == nil)
        #expect(parse("http://desktop:8765", "fum_a b") == nil)
        #expect(parse("http://desktop:8765", "fum_é") == nil)
    }

    @Test func theTokenIsNeverInTheText() throws {
        let settings = try #require(parse("http://desktop:8765", "fum_secret"))
        #expect(!settings.description.contains("fum_secret"))
        #expect(!String(describing: settings).contains("fum_secret"))
    }

    @Test func plainHTTPOnHomeWiFiIsWarnedAbout() {
        #expect(parse("http://192.168.107.138:8765")?.cleartextWarning != nil)
        #expect(parse("http://desktop.local:8765")?.cleartextWarning != nil)
        #expect(parse("http://desktop:8765")?.cleartextWarning == nil)  // MagicDNS
        #expect(parse("http://100.101.102.103:8765")?.cleartextWarning == nil)
        #expect(parse("http://100.200.1.1:8765")?.cleartextWarning != nil)  // outside 100.64/10
        #expect(parse("https://desktop.tail1234.ts.net")?.cleartextWarning == nil)
        #expect(parse("https://192.168.1.5")?.cleartextWarning == nil)
    }

    @Test func whichAddressesNeedLocalNetworkAccess() {
        for host in ["192.168.107.138", "10.0.2.2", "172.20.1.1", "169.254.1.1", "desktop.local", "desktop"] {
            #expect(ServerSettings.mayBeLocalNetwork(host), "\(host)")
        }
        for host in ["100.101.102.103", "desktop.tail1234.ts.net", "172.32.0.1", "example.com"] {
            #expect(!ServerSettings.mayBeLocalNetwork(host), "\(host)")
        }
    }

    @Test func statusesInPlainWords() {
        let url = "http://192.168.107.138:8765"
        #expect(Problems.forStatus(401, reason: "Unauthorized", url: url).kind == .unauthorized)
        #expect(Problems.forStatus(401, reason: nil, url: url).message.contains("New Device Token"))
        #expect(Problems.forStatus(429, reason: nil, url: url).kind == .lockedOut)
        #expect(Problems.forStatus(429, reason: nil, url: url).message.contains("few minutes"))
        #expect(Problems.forStatus(409, reason: "Already writing.", url: url).message == "Already writing.")
        #expect(Problems.forStatus(404, reason: "No such conversation.", url: url).kind == .notFound)
        #expect(Problems.forStatus(500, reason: nil, url: url).message == "\(url) answered 500.")
        #expect(Problems.forStatus(302, reason: nil, url: url).message.contains("redirect"))
    }

    @Test func unreachableShowsTheAddress() {
        let url = "http://192.168.107.138:8765"
        let refused = Problems.describe(URLError(.cannotConnectToHost), url: url)
        #expect(refused.kind == .unreachable)
        #expect(refused.message.hasPrefix("Can't reach \(url) (nothing answered)"))
        #expect(Problems.describe(URLError(.cannotFindHost), url: url).message.contains("isn't known"))
        let reset = Problems.describe(URLError(.networkConnectionLost), url: url)
        #expect(reset.message.contains("allow_from"))
        #expect(reset.message.hasPrefix(url))
    }

    @Test func localNetworkAndPlainHTTPRefusals() {
        let home = Problems.describe(URLError(.notConnectedToInternet), url: "http://192.168.107.138:8765")
        #expect(home.kind == .localNetworkDenied)
        #expect(home.message.contains("Local Network"))
        let tailnet = Problems.describe(URLError(.notConnectedToInternet), url: "http://100.101.102.103:8765")
        #expect(tailnet.kind == .unreachable)
        #expect(tailnet.message.contains("offline"))
        let ats = Problems.describe(URLError(.appTransportSecurityRequiresSecureConnection), url: "http://mac.example.com:8765")
        #expect(ats.kind == .cleartextBlocked)
        #expect(ats.message.contains("mac.example.com"))
        #expect(Problems.describe(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")), url: "u").kind == .badResponse)
    }

    @Test func commandSuggestionsWhileTypingASlash() {
        let commands = [Command(name: "/unread", args: "[n]", summary: "newest unread email"),
                        Command(name: "/today", summary: "today's events"),
                        Command(name: "/draft", args: "[n] [instructions]", summary: "write a reply"),
                        Command(name: "/drafts", args: "[n]", summary: "your drafts")]
        func names(_ typed: String) -> [String] { Command.suggestions(typed, from: commands).map(\.name) }
        #expect(names("/") == ["/unread", "/today", "/draft", "/drafts"])
        #expect(names("/u") == ["/unread"])
        #expect(names("/U") == ["/unread"])
        #expect(names("/draft") == ["/draft", "/drafts"])
        #expect(names("/today") == [])  // complete, and takes nothing
        #expect(names("/unread") == ["/unread"])  // complete, but takes a number: still shown with its args
        #expect(names("/unread 3") == [])
        #expect(names("anything unread?") == [])
        #expect(names("/x") == [])
    }

    @Test func serverSentEvents() {
        var parser = EventStreamParser()
        let lines = [": ping", "", "data: {\"type\":\"a\"}", "", "data: one", "data: two", "", "event: x", "id: 3", "", "data:tight", ""]
        let events = lines.compactMap { parser.feed($0) }
        #expect(events == ["{\"type\":\"a\"}", "one\ntwo", "tight"])
    }

    @Test func obsidianLinks() {
        #expect(Notes.obsidianURL(path: "ignivo/project/UOB.md", vault: "fusecond")?.absoluteString
                == "obsidian://open?vault=fusecond&file=ignivo/project/UOB")
    }
}
