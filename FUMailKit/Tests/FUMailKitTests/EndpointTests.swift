import Foundation
import Synchronization
import Testing
@testable import FUMailKit

/// Choosing between the home and Tailscale addresses (the Android app's EndpointTest, case for case).
/// Two pretend Macs stand for the same Mac at its two addresses.
@MainActor
struct EndpointTests {
    private let home = FakeDesktop(display: "http://192.168.107.138:8765")
    private let tailscale = FakeDesktop(display: "http://desktop:8765")

    private func picker(onWifi: Bool, home: FakeDesktop?, tailscale: FakeDesktop?) -> EndpointPicker {
        EndpointPicker(home: home, tailscale: tailscale, onWifi: { onWifi })!
    }

    @Test func onWiFiWithHomeAnsweringItsHome() async {
        let chosen = await picker(onWifi: true, home: home, tailscale: tailscale).pick()
        #expect(chosen.label == "Home")
        #expect(chosen.transport.display == home.display)
        #expect(home.requests == ["probe /health"])  // only the token-less check
        #expect(tailscale.requests.isEmpty)
    }

    @Test func offWiFiItsTailscaleWithoutContactingHome() async {
        let chosen = await picker(onWifi: false, home: home, tailscale: tailscale).pick()
        #expect(chosen.label == "Tailscale")
        #expect(home.requests.isEmpty)  // not even the check
    }

    @Test func homeNotAnsweringMeansTailscale() async {
        home.set { $0.answersHealth = false }
        let chosen = await picker(onWifi: true, home: home, tailscale: tailscale).pick()
        #expect(chosen.label == "Tailscale")
        #expect(home.requests == ["probe /health"])
    }

    @Test func withOneAddressItsThatOneOnOrOffWiFi() async {
        for onWifi in [true, false] {
            let onlyHome = await picker(onWifi: onWifi, home: home, tailscale: nil).pick()
            #expect(onlyHome.transport.display == home.display)
            #expect(onlyHome.label == nil)  // nothing to choose between, nothing to show
            let onlyTailscale = await picker(onWifi: onWifi, home: nil, tailscale: tailscale).pick()
            #expect(onlyTailscale.transport.display == tailscale.display)
        }
        #expect(home.requests.isEmpty)  // one address: no check needed
        #expect(EndpointPicker(home: nil, tailscale: nil, onWifi: { true }) == nil)
    }

    @Test func theLikelyAddressBeforeAnythingIsAsked() {
        #expect(picker(onWifi: true, home: home, tailscale: tailscale).first.label == "Home")
        #expect(picker(onWifi: false, home: home, tailscale: tailscale).first.label == "Tailscale")
        #expect(picker(onWifi: false, home: home, tailscale: nil).first.transport.display == home.display)
        #expect(home.requests.isEmpty && tailscale.requests.isEmpty)
    }

    @Test func aConnectedClientMovesFromHomeToTailscaleWhenHomeGoesAway() async {
        let client = RemoteClient(picker: picker(onWifi: true, home: home, tailscale: tailscale),
                                  backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
        client.start()
        await eventually("connected via Home") { client.state.connection.connected && client.state.connection.via == "Home" }
        #expect(client.display == home.display)
        // Home goes away (left the house, the Mac's Wi-Fi dropped): the next connection picks again.
        home.set { $0.answersHealth = false }
        home.drop()
        await eventually("connected via Tailscale") {
            client.state.connection.connected && client.state.connection.via == "Tailscale"
        }
        #expect(client.display == tailscale.display)
        #expect(tailscale.requests.contains("GET /v1/info"))
        client.close()
    }

    @Test func pickingAgainWhenWiFiComesBack() async {
        let wifi = Mutex(false)
        let picker = EndpointPicker(home: home, tailscale: tailscale, onWifi: { wifi.withLock { $0 } })!
        let client = RemoteClient(picker: picker, backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
        client.start()
        await eventually("connected via Tailscale") { client.state.connection.connected && client.state.connection.via == "Tailscale" }
        #expect(home.requests.isEmpty)
        wifi.withLock { $0 = true }
        client.reconnect()
        await eventually("connected via Home") { client.state.connection.connected && client.state.connection.via == "Home" }
        client.close()
    }

    @Test func whyHomeWasntUsedIsKept() async {
        home.set { $0.answersHealth = false }
        let onWifi = await picker(onWifi: true, home: home, tailscale: tailscale).choose()
        #expect(onWifi.endpoint.label == "Tailscale")
        #expect(onWifi.homeProblem?.message == "\(home.display) didn't answer within 2 seconds.")
        let offWifi = await picker(onWifi: false, home: home, tailscale: tailscale).choose()
        #expect(offWifi.homeProblem == nil)  // not on Wi-Fi: Home wasn't even tried, nothing to explain
    }

    @Test func theClientShowsWhyHomeWasntUsed() async {
        home.set { $0.answersHealth = false }
        let client = RemoteClient(picker: picker(onWifi: true, home: home, tailscale: tailscale),
                                  backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
        client.start()
        await eventually("connected via Tailscale") { client.state.connection.connected && client.state.connection.via == "Tailscale" }
        #expect(client.state.connection.homeSkipped?.contains("didn't answer") == true)
        client.close()
    }

    /// The VPN switched off at home: Wi-Fi didn't change, and on iOS the Tailscale connection can hang
    /// instead of failing. A network change checks Home and moves to it as soon as FU Mail answers.
    @Test func aNetworkChangeMovesBackToHomeWhenItAnswers() async {
        home.set { $0.answersHealth = false }
        let client = RemoteClient(picker: picker(onWifi: true, home: home, tailscale: tailscale),
                                  backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
        client.start()
        await eventually("connected via Tailscale") { client.state.connection.connected && client.state.connection.via == "Tailscale" }
        await client.switchHomeIfItAnswers()  // Home still not answering: stays on Tailscale
        #expect(client.state.connection.via == "Tailscale")
        home.set { $0.answersHealth = true }
        await client.switchHomeIfItAnswers()
        await eventually("connected via Home") { client.state.connection.connected && client.state.connection.via == "Home" }
        #expect(client.state.connection.homeSkipped == nil)
        client.close()
    }

    @Test func offWiFiANetworkChangeDoesntTouchHome() async {
        let client = RemoteClient(picker: picker(onWifi: false, home: home, tailscale: tailscale),
                                  backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
        client.start()
        await eventually("connected via Tailscale") { client.state.connection.connected && client.state.connection.via == "Tailscale" }
        await client.switchHomeIfItAnswers()
        #expect(home.requests.isEmpty)
        #expect(client.state.connection.via == "Tailscale")
        client.close()
    }

    @Test func oneAddressShowsNoLabel() async {
        let client = RemoteClient(transport: home, backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)))
        client.start()
        await eventually("connected") { client.state.connection.connected }
        #expect(client.state.connection.via == nil)
        #expect(!home.requests.contains("probe /health"))
        client.close()
    }

    @Test func theUpgradePutsTheOldAddressInTheRightField() {
        #expect(SavedAddresses.upgrade("http://192.168.107.138:8765") == ("http://192.168.107.138:8765", ""))
        #expect(SavedAddresses.upgrade("http://desktop.local:8765") == ("http://desktop.local:8765", ""))
        #expect(SavedAddresses.upgrade("http://desktop:8765") == ("", "http://desktop:8765"))  // MagicDNS
        #expect(SavedAddresses.upgrade("http://100.101.102.103:8765") == ("", "http://100.101.102.103:8765"))
        #expect(SavedAddresses.upgrade("https://desktop.tail1234.ts.net") == ("", "https://desktop.tail1234.ts.net"))
        #expect(SavedAddresses.upgrade("http://100.200.1.1:8765") == ("http://100.200.1.1:8765", ""))  // outside 100.64/10
        #expect(SavedAddresses.upgrade("") == ("", ""))
    }
}
