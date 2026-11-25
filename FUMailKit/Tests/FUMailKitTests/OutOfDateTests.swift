import Foundation
import Testing
@testable import FUMailKit

/// A chat whose refetch hasn't worked yet: its triage buttons are off until it has.
@MainActor
struct OutOfDateTests {
    private let desktop: TriageDesktop
    private let c0 = id("C0")
    private let c1 = id("C1")
    private let m1 = id("M1")

    init() throws {
        desktop = try TriageDesktop()
        desktop.set { $0.firstChatHasCard = true }
    }

    /// `pause`: before each of five retries (a minute: none in a test).
    private func client(pause: Duration = .seconds(60)) -> RemoteClient {
        RemoteClient(transport: desktop, backoff: Backoff(first: .milliseconds(20), max: .milliseconds(100)),
                     retryPauses: Array(repeating: pause, count: 5))
    }

    /// Connected, with both chats (each has a spam card) loaded.
    private func open(_ client: RemoteClient, loading: [UUID]? = nil) async {
        client.start()
        await eventually("connected") { client.state.connection.connected && !client.state.commands.isEmpty }
        for chat in loading ?? [c0, c1] { client.loadMessages(chat) }
        await eventually("the chats") { (loading ?? [c0, c1]).allSatisfy { !client.state.unloaded.contains($0) } }
    }

    private func reconnect(_ client: RemoteClient) async {
        let (before, editors) = (desktop.count("GET /v1/events"), desktop.count("GET /v1/commands"))
        desktop.drop()
        await eventually("reconnected") {
            desktop.count("GET /v1/events") > before && desktop.count("GET /v1/commands") > editors && client.state.connection.connected
        }
    }

    /// Reconnected, with the triage chat's refetch failed.
    private func openOutOfDate(_ client: RemoteClient) async {
        await open(client)
        desktop.set { $0.brokenTriageChat = true }
        await reconnect(client)
    }

    private func card(_ client: RemoteClient, _ chat: UUID? = nil) -> Card? {
        client.state.conversation(chat ?? c1)?.messages.lazy.compactMap(\.card).first
    }
    private func view(_ client: RemoteClient, _ chat: UUID? = nil) -> TriageView? {
        let chat = chat ?? c1
        return card(client, chat).flatMap {
            TriageRules.view($0, busy: client.state.busyMessages.contains(chat == c1 ? m1 : id("M0")),
                             connected: client.state.connection.connected, outOfDate: client.state.outOfDate[chat]) { _ in "" }
        }
    }
    private func subject(_ client: RemoteClient) -> String? { view(client)?.rows.first?.subject }
    private func enabled(_ client: RemoteClient, _ chat: UUID? = nil) -> Set<Bool> {
        guard let view = view(client, chat) else { return [] }
        return Set((view.rows.flatMap { $0.buttons + $0.menu } + [view.all].compactMap { $0 }).map(\.enabled) + [view.refreshEnabled])
    }
    private var changedCard: String { desktop.spamCard.replacingOccurrences(of: "50% off everything", with: "60% off everything") }
    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    // MARK: Marking

    @Test func aFailedRefetchTurnsOffThatChatsButtonsOnly() async throws {
        let client = client()
        await open(client)
        let asked = try #require(view(client)?.all).confirmation
        let row = try #require(view(client)?.rows.first?.buttons.first).confirmation
        #expect(asked.holds(client.state, on: m1, in: c1))
        desktop.set { $0.brokenTriageChat = true }
        await reconnect(client)
        #expect(client.state.connection.connected)
        #expect(enabled(client) == [false])  // Refresh too
        #expect(view(client)?.notice == "Updating this chat. The buttons are off until it's done.")
        #expect(!asked.holds(client.state, on: m1, in: c1))  // an open question closes
        #expect(!row.holds(client.state, on: m1, in: c1))
        client.triageAction(asked, on: m1, in: c1)
        await eventually("the reason") { client.state.connection.problem == TriageConfirmation.changed }
        #expect(desktop.actions.isEmpty)
        // Opening a row still works.
        client.openEmail(try #require(view(client)).rows[1].ref, in: c1)
        await eventually("the open") { desktop.actions.count == 1 }
        #expect(desktop.actions[0].contains("/open "))
        // The other chat isn't affected.
        #expect(enabled(client, c0) == [true])
        #expect(view(client, c0)?.notice == nil)
        client.triageAction(try #require(view(client, c0)?.all).confirmation, on: id("M0"), in: c0)
        await eventually("the other chat's action") { desktop.actions.count == 2 }
        #expect(desktop.actions[1].hasSuffix(#"{"action":"spam_delete_all"}"#))
        client.close()
    }

    @Test func anEventDoesntClearItButAFetchDoes() async {
        let client = client()
        await openOutOfDate(client)
        desktop.updateCard(changedCard)
        desktop.busy(true)
        desktop.busy(false)
        await eventually("the event") { subject(client) == "60% off everything" }
        client.loadMessages(c0)  // nor does another chat
        await settle()
        #expect(enabled(client) == [false])
        desktop.set { $0.brokenTriageChat = false }
        client.loadMessages(c1)  // reopened
        await eventually("up to date") { client.state.outOfDate.isEmpty }
        #expect(enabled(client) == [true])
        #expect(view(client)?.notice == nil)
        client.close()
    }

    @Test func infoFailingMarksEveryLoadedChat() async {
        let client = client()
        await open(client)
        desktop.set { $0.brokenInfo = true }
        await reconnect(client)
        #expect(client.state.outOfDate == [c0: .updating, c1: .updating])
        #expect(enabled(client) == [false])
        #expect(enabled(client, c0) == [false])
        #expect(client.state.connection.problem == "info broke")
        client.close()
    }

    @Test func nothingIsSaidWhileDisconnected() async {
        let client = client()
        await openOutOfDate(client)
        client.stop()
        #expect(view(client)?.notice == nil)
        #expect(enabled(client) == [false])
        client.close()
    }

    @Test func aChatGoneFromTheListIsntMarkedAnyMore() async {
        let client = client()
        await openOutOfDate(client)
        desktop.set { $0.unlisted = true }
        desktop.push(#"{"type":"conversations_changed"}"#)
        await eventually("gone") { client.state.conversation(c1) == nil }
        #expect(client.state.outOfDate.isEmpty)
        client.close()
    }

    @Test func configChangedMarksBeforeTheNextEventAndASlowChatDoesntHoldUpEvents() async throws {
        let client = client()
        await open(client)
        let asked = try #require(view(client)?.all).confirmation
        desktop.set { $0.holding = [2] }
        desktop.push(#"{"type":"config_changed"}"#)
        desktop.push(#"{"type":"busy","messageID":"\#(id("X"))","busy":true}"#)
        await eventually("the next event") { client.state.busyMessages.contains(id("X")) }
        #expect(client.state.outOfDate[c1] == .updating)
        #expect(enabled(client) == [false])
        #expect(!asked.holds(client.state, on: m1, in: c1))
        desktop.set { $0.holding = [] }
        await eventually("up to date") { client.state.outOfDate.isEmpty }
        #expect(enabled(client) == [true])
        client.close()
    }

    @Test func queuedActionsAreCheckedAgain() async throws {
        let client = client()
        await open(client)
        desktop.set { $0.held = true }
        client.cardAction(.setSide(.summary), on: m1, in: c1)
        await eventually("the first") { desktop.actions.count == 1 }
        // Confirmed, and Refresh pressed, while it waits; then the chat may be old.
        client.triageAction(try #require(view(client)?.all).confirmation, on: m1, in: c1)
        client.cardAction(.spamRefresh, on: m1, in: c1)
        desktop.set { $0.brokenTriageChat = true }
        desktop.push(#"{"type":"config_changed"}"#)
        await eventually("marked") { client.state.outOfDate[c1] != nil }
        desktop.set { $0.held = false }
        await eventually("the reason") {
            client.state.connection.problem
                == "The card changed or was out of date before that was sent, so nothing was done. Check it and try again."
        }
        await settle()
        #expect(desktop.actions.count == 1)
        client.close()
    }

    @Test func aQueuedRefreshIsCheckedOnItsOwn() async {
        let client = client()
        await open(client)
        desktop.busy(true)
        await eventually("busy") { client.state.busyMessages.contains(m1) }
        client.cardAction(.spamRefresh, on: m1, in: c1)
        await eventually("the reason") { client.state.connection.problem == TriageConfirmation.changed }
        #expect(desktop.actions.isEmpty)
        client.close()
    }

    // MARK: Retries

    @Test func aRetryThatWorksClearsItAndLeavesTheBanner() async {
        let client = client(pause: .milliseconds(30))
        await openOutOfDate(client)
        desktop.set {
            $0.card = changedCard
            $0.brokenTriageChat = false
        }
        await eventually("up to date") { client.state.outOfDate.isEmpty }
        #expect(subject(client) == "60% off everything")
        #expect(enabled(client) == [true])
        #expect(client.state.connection.problem == "the triage chat broke")  // from the reconnect, still to be read
        #expect(desktop.actions.isEmpty)
        client.close()
    }

    @Test func retriesStopAtTheLimitAndStartOverOnReconnectAndReopening() async {
        let client = client(pause: .milliseconds(10))
        await open(client)
        desktop.set { $0.brokenTriageChat = true }
        let before = desktop.state.withLock { $0.chatFetches }
        func fetches() -> Int { desktop.state.withLock { $0.chatFetches } - before }
        await reconnect(client)
        await eventually("the limit") { client.state.outOfDate[c1] == .failed }
        #expect(fetches() == 6)  // the reconnect's, and five more
        #expect(view(client)?.notice == "Couldn't update this chat, so the buttons are off. Reopen it to try again.")
        #expect(enabled(client) == [false])
        await settle()
        #expect(fetches() == 6)
        client.loadMessages(c1)  // at once, and five more
        #expect(client.state.outOfDate[c1] == .updating)
        await eventually("the limit again") { client.state.outOfDate[c1] == .failed }
        #expect(fetches() == 12)
        await reconnect(client)
        await eventually("the limit after a reconnect") { client.state.outOfDate[c1] == .failed && fetches() == 18 }
        desktop.push(#"{"type":"config_changed"}"#)
        await eventually("the limit after config_changed") { client.state.outOfDate[c1] == .failed && fetches() == 24 }
        #expect(desktop.actions.isEmpty)
        client.close()
    }

    @Test func oneAtATimePerChat() async {
        let client = client(pause: .milliseconds(10))
        await openOutOfDate(client)
        desktop.set {
            $0.brokenTriageChat = false
            $0.heldChat = true
        }
        let before = desktop.state.withLock { $0.chatFetches }
        await eventually("a retry") { desktop.state.withLock { $0.chatFetches } == before + 1 }
        client.loadMessages(c1)
        client.loadMessages(c1)
        await settle()
        #expect(desktop.state.withLock { $0.chatFetches } == before + 1)
        desktop.set { $0.heldChat = false }
        await eventually("up to date") { client.state.outOfDate.isEmpty }
        client.close()
    }

    @Test func theBackgroundStopsRetries() async {
        let client = client(pause: .milliseconds(40))
        await openOutOfDate(client)
        client.stop()
        let fetches = desktop.state.withLock { $0.chatFetches }
        client.loadMessages(c1)  // not while disconnected either
        await settle()
        await settle()
        #expect(desktop.state.withLock { $0.chatFetches } == fetches)
        desktop.set { $0.brokenTriageChat = false }
        client.start()
        await eventually("up to date") { client.state.connection.connected && client.state.outOfDate.isEmpty }
        client.close()
    }

    // MARK: Late answers

    @Test func aFirstLoadFromBeforeAReconnectIsFetchedAgain() async {
        let client = client()
        await open(client, loading: [c0])
        desktop.set { $0.holding = [1] }
        client.loadMessages(c1)
        await eventually("asked for") { desktop.state.withLock { $0.chatFetches } == 1 }
        desktop.set { $0.card = changedCard }  // the event went out while disconnected
        await reconnect(client)
        desktop.set { $0.holding = [] }
        await eventually("the chat") { !client.state.unloaded.contains(c1) }
        #expect(subject(client) == "60% off everything")
        #expect(desktop.state.withLock { $0.chatFetches } == 2)
        client.close()
    }

    @Test func aRetryFromBeforeAReconnectDoesntClearIt() async {
        let client = client()
        await openOutOfDate(client)
        desktop.set {
            $0.brokenTriageChat = false
            $0.holding = [$0.chatFetches + 1]
        }
        client.loadMessages(c1)
        let asked = desktop.state.withLock { $0.holding.first ?? 0 }
        await eventually("asked for") { desktop.state.withLock { $0.chatFetches } == asked }
        desktop.set {
            $0.card = changedCard
            $0.brokenTriageChat = true
        }
        await reconnect(client)
        desktop.set { $0.holding = [] }  // the old answer arrives, though its request was cancelled
        await settle()
        #expect(client.state.outOfDate[c1] == .updating)
        #expect(enabled(client) == [false])
        client.close()
    }

    @Test func anEarlierFetchNeverReplacesALaterOne() async {
        let client = client()
        await open(client, loading: [c0])
        desktop.set { $0.holding = [1] }
        client.loadMessages(c1)
        await eventually("asked for") { desktop.state.withLock { $0.chatFetches } == 1 }
        desktop.set { $0.card = changedCard }
        client.loadMessages(c1)
        await eventually("the later answer") { subject(client) == "60% off everything" }
        desktop.set { $0.holding = [] }
        await settle()
        #expect(subject(client) == "60% off everything")
        client.close()
    }

    @Test func aChatDeletedDuringItsFetchDoesntComeBack() async {
        let client = client()
        await openFetch(client)
        client.delete(c1)
        desktop.set { $0.heldChat = false }
        await settle()
        #expect(client.state.conversation(c1) == nil)
        #expect(client.state.outOfDate.isEmpty)
        client.close()
    }

    @Test func aRecordedTriageCardIsntReappliedAfterConfigChanged() async {
        let client = client()
        await open(client, loading: [c0])
        desktop.set { $0.holding = [1] }
        client.loadMessages(c1)
        await eventually("asked for") { desktop.state.withLock { $0.chatFetches } == 1 }
        desktop.push(#"{"type":"message_appended","conversationID":"\#(c1)","message":\#(desktop.message(desktop.spamCard, "M2"))}"#)
        // No longer in full_triage: the Mac leaves the cards out from here on.
        desktop.set { $0.listed = false }
        desktop.push(#"{"type":"config_changed"}"#)
        await eventually("config_changed") { desktop.count("GET /v1/commands") == 2 }
        desktop.set { $0.holding = [] }
        await eventually("the chat") { !client.state.unloaded.contains(c1) }
        await settle()
        #expect(client.state.conversation(c1)?.messages.isEmpty == true)
        client.close()
    }

    // MARK: Events while a fetch is open

    /// Out of date, with a fetch open whose answer is already written.
    private func openFetch(_ client: RemoteClient) async {
        await openOutOfDate(client)
        desktop.set {
            $0.brokenTriageChat = false
            $0.heldChat = true
        }
        let before = desktop.state.withLock { $0.chatFetches }
        client.loadMessages(c1)
        await eventually("asked for") { desktop.state.withLock { $0.chatFetches } == before + 1 }
    }

    private func finishFetch(_ client: RemoteClient) async {
        desktop.set { $0.heldChat = false }
        await eventually("up to date") { client.state.outOfDate.isEmpty }
    }

    @Test func anUpdateDuringAFetchIsntUndone() async {
        let client = client()
        await openFetch(client)
        desktop.updateCard(changedCard)
        await eventually("shown at once") { subject(client) == "60% off everything" }
        await finishFetch(client)
        #expect(subject(client) == "60% off everything")
        client.close()
    }

    @Test func aMessageAppendedDuringAFetchStays() async {
        let client = client()
        await openFetch(client)
        desktop.push(#"{"type":"message_appended","conversationID":"\#(c1)","message":\#(desktop.message(desktop.spamCard, "M2"))}"#)
        desktop.push(#"{"type":"busy","messageID":"\#(id("M2"))","busy":true}"#)
        await eventually("shown at once") { client.state.busyMessages.contains(id("M2")) }
        await finishFetch(client)
        #expect(client.state.conversation(c1)?.messages.map(\.id) == [m1, id("M2")])
        #expect(client.state.busyMessages == [id("M2")])
        client.close()
    }

    @Test func anAppendAlreadyInTheAnswerIsntDoubled() async {
        let client = client()
        desktop.set { [desktop] in $0.extra = [desktop.message(desktop.spamCard, "M2")] }
        await open(client, loading: [c0])
        desktop.set { $0.holding = [1] }
        client.loadMessages(c1)
        await eventually("asked for") { desktop.state.withLock { $0.chatFetches } == 1 }
        desktop.push(#"{"type":"message_appended","conversationID":"\#(c1)","message":\#(desktop.message(desktop.spamCard, "M2"))}"#)
        desktop.push(#"{"type":"message_updated","conversationID":"\#(c1)","message":\#(desktop.message(changedCard, "M3"))}"#)
        desktop.push(#"{"type":"chat_status","conversationID":"\#(c1)","status":"Checking mail…"}"#)
        await eventually("the events") { client.state.chatStatus[c1] == "Checking mail…" }
        desktop.set { $0.holding = [] }
        await eventually("the chat") { !client.state.unloaded.contains(c1) }
        #expect(client.state.conversation(c1)?.messages.map(\.id) == [m1, id("M2")])  // and no M3, which nobody has
        #expect(client.state.chatStatus[c1] == "Checking mail…")
        client.close()
    }

    @Test func aBusyEndDuringAFetchIsntLost() async {
        let client = client()
        desktop.set { $0.busy = true }
        await openFetch(client)  // its answer says busy
        desktop.busy(true)
        desktop.busy(false)
        await eventually("not busy") { !client.state.busyMessages.contains(m1) }
        await finishFetch(client)
        #expect(!client.state.busyMessages.contains(m1))
        #expect(enabled(client) == [true])
        client.close()
    }

    @Test func aBusyStartDuringAFetchIsntLost() async {
        let client = client()
        await openFetch(client)
        desktop.busy(true)
        await eventually("busy") { client.state.busyMessages.contains(m1) }
        await finishFetch(client)
        #expect(client.state.busyMessages.contains(m1))
        #expect(enabled(client) == [false])
        client.close()
    }
}
