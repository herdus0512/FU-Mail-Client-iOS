# FU Mail for iPhone and iPad

A phone and tablet client for [FU Mail](../FU-Mail-Client), the chat-style email client. Like the
[Android](../FU-Mail-Client-Android) and [Windows](../FU-Mail-Client-Windows) apps, it's a thin client
of the Mac's HTTP API: the mail servers, LLMs, Obsidian notes, CRM and history all stay on the Mac,
and this shows the same conversations and cards. For personal use: installed through TestFlight.

- **The Mac's own types.** The models are copied from the Mac app's Swift code, so the JSON is
  Swift's `Codable` on both ends. They're copies, not shared code: this repository stands alone, and
  follows the Mac's API ([docs/API.md](../FU-Mail-Client/docs/API.md)) when it changes.
- **iOS 27 and later**, iPhone and iPad. SwiftUI, SF Mono for the chat and cards (the standard iOS
  font where you type: the message bar and search), no third-party code.

> **Status: 3.7.0, for FU Mail 3.7.0 on the Mac. Connects over Tailscale only.** Connecting, the
> conversations, the chat, every card with its buttons (mail,
> drafts, events, notes, CRM, tasks) and the draft editor, side by side on the iPad. See
> [docs/PLAN.md](docs/PLAN.md) and [Versions](#versions).

## Setting up the Mac (once)

1. **Xcode** from the App Store, opened once with the **iOS** platform installed. Nothing else changes:
   the Makefile points at Xcode itself, so `xcode-select` and the Mac app's Command Line Tools build
   are left alone.
2. **Xcode → Settings → Accounts:** sign in with the developer account's Apple ID (the Account
   Holder). `make testflight` signs and uploads through it; Xcode needn't be open.
3. `cp local.mk.example local.mk` and fill in the Team ID.

The archive is built unsigned and signed for distribution when it's uploaded: signing for
development would need a registered iPhone or iPad, and TestFlight doesn't.

## Building

```sh
make test         # the core's tests, against a pretend Mac (no simulator)
make build        # the app for the simulator
make run          # build and open it in the iPhone simulator
make sim-ipad     # the same on an iPad
make fake-mac     # a pretend Mac with sample cards on http://127.0.0.1:8799 (leave it running;
                  #   python3 tools/fake_mac.py --editor starts with a draft editor open, --long makes
                  #   the chat long; Summary and Add to note on a thread answer as the Mac does)
make run-fake     # the simulator connected to it (debug builds only; nothing is saved)
                  #   OPEN=2 opens the second conversation; UPTO=4 shows only its first 4 messages
make testflight   # test, archive, sign and upload to TestFlight
```

Each upload gets a new build number (minutes since 1970), so it always goes up. A build shows in
TestFlight 5–15 minutes after uploading, and goes to the internal testing group by itself.

## Installing

On the iPhone or iPad, install **TestFlight** from the App Store, signed in with an Apple ID in the
internal testing group, and install FU Mail from there. Builds expire after 90 days; a newer build
replaces the old one and keeps its settings.

## Connecting to the Mac

The app connects over **Tailscale only** (since 3.1.0): Tailscale has to be on on the iPhone or
iPad. The Mac's `api` must be on with `allow_from` covering Tailscale (`100.64.0.0/10`, or
`127.0.0.1/32` with `tailscale serve`), and each device gets its own token (**API → New Device
Token…**). In the app, **Settings** (the gear; it opens by itself the first time) takes the Mac's
Tailscale address and the token:

| Address | |
| ------- | - |
| `https://<mac>.<tailnet>.ts.net` | with `tailscale serve` on the Mac |
| `http://<mac>:8765` | MagicDNS name |
| `http://100.x.y.z:8765` | the Mac's Tailscale IP |

**Save and connect** checks the address (`/health`, then the token with `/v1/info`) and saves when
it works ("Connected to FU Mail 3.7.0 as "iphone". Saved."); **Save anyway** keeps settings that
can't be checked right now. The connection indicator shows Connected, Connecting… or Can't connect.

- **`/health`** must be FU Mail's own answer. If something else answers (another app on that port),
  Settings says "Something answered at <url>, but not FU Mail's API. Check the address and the port."
- **Plain HTTP** is allowed by iOS only to IP addresses, `.local` names and names without dots
  (MagicDNS). A `*.ts.net` name needs HTTPS. Requests go only to the address's own host, with
  redirects refused.
- **Cloudflare Tunnel:** the address can instead be `https://<hostname>` for a tunnel (cloudflared →
  the Mac's `127.0.0.1:8765`) guarded by a Cloudflare Access application with a Service Auth
  policy. Fill in **Cloudflare Access** in Settings with the service token's Client ID (ends in
  `.access`) and Client Secret: both, or neither. They're kept in the Keychain like the device
  token and sent (`CF-Access-Client-Id`, `CF-Access-Client-Secret`) with every request, `/health`
  and the event stream included, but only to `https://` addresses. If Access turns the app away
  (a 403 page, or a redirect to `*.cloudflareaccess.com` when the policy is Allow rather than
  Service Auth), it says so: the service token is missing, or its Client ID and Secret weren't
  accepted (check them, and that the token hasn't expired). The event stream's 75-second timeout
  sits well above the Mac's 25-second pings, inside Cloudflare's ~100-second idle limit, and a
  dropped stream reconnects (1 s, doubling, up to 30 s).
- **No Local Network permission** is asked for. A home-network address (192.168.x) can't be reached,
  and the app says to use the Tailscale address.
- **The token** is kept in the Keychain on this device only: not synced to iCloud and not backed up.
  **Forget token** in Settings removes it.
- **The indicator** at the top right is green when connected, orange while connecting, and red
  when it can't connect. With two addresses it says **Home** or **Tailscale** instead of
  "Connected". Tap it for the address in use ("(via Home)" / "(via Tailscale)"), this device's name,
  the Mac's version and what's wrong. Problems also show in a banner across the top.
- **The connection** is open only while the app is on screen. When it comes back, or the
  connection drops, it reconnects (1 s, doubling up to 30 s) and fetches everything again.

## Using it

- **Conversations:** newest first. The pencil starts a new one. Swipe left to delete; touch and hold
  to rename. **Search history** searches the Mac's history, by
  words and meaning.
- **Chat:** type a command (`/unread`, `/search bob`, `/today`, `/help`) or a question, as on the
  Mac. **Type `/` and the commands appear** above the box, narrowing as you type; tap one to put it in
  the box. While the chat model works, its status shows above the box, with **Stop**.
- **Long chats** open with their newest 10 messages; **Show earlier messages** at the top adds 10
  more at a time.
- **History search:** opening a result goes to the message that matched, showing earlier messages
  back to it, and lights it up for a moment (with FU Mail 3.3.0 or later on the Mac).
- **The chat** follows new messages while you're at the bottom; scrolled up, it stays put and
  **Latest** jumps down. What you asked for yourself (an email opened from a list, a command, Add to
  note, Add task) is always shown when it arrives, a card from its start. Tap or scroll the messages,
  or tap **Done** above the keyboard, to put the keyboard away.
- **Cards** have the Mac's buttons:
  - **Lists:** tap a row to open it. An archive list (`/archive`) has **Show more (N left)**.
  - **Threads:** newest first, folded by the Mac's rule (your own replies fold too): tap a folded
    message to open it, ⌃ to fold it again. Original | Summary (with Rewrite), Expand all / Fold
    older, Show full text, Reply, Reply all (only when it reaches someone more), Add to note, Add
    task (with Google Tasks) and Open in browser.
    A thread from the archive is read-only: no Reply or Reply all.
  - **Drafts:** tap a row to open it; Edit and Open in browser on a draft. A Google Mail draft's
    link changes whenever the draft is saved, so Open in browser first has the Mac fetch the draft
    again (a spinner on the button, a few seconds at most) and opens its current link; other links
    open at once. A draft that was sent or deleted says so instead of offering either button.
    When the mail server warned about saving the draft (say, a new body replaced a signature added
    in Google Mail or Outlook), the warning shows under the body.
  - **Events:** by day, with Join for video calls.
  - **Add to note** (`/note [n]`, or the thread's button): the note (None of these… lists every note,
    filtered as you type), Edit…, Insert / Insert anyway / Replace, Change note, Skip, then Undo and
    Open in Obsidian.
  - **Note cards** (`/obsidian [name] [summary|crm|correspondence]`): pick the note, then its
    Summary, CRM and Correspondence, read-only (the newest 5 entries, with Show all). **Catch me
    up**, **Post CRM update**, **Refresh** and Open in Obsidian.
  - **Send to CRM:** Write… / Edit… with Rewrite professionally, None of these…, Change note, Post /
    Post anyway, and the sync status. It's visible to your team.
  - **Suggested notes:** Edit…, Add to my memory.md, Dismiss.
  - **Tasks** (`/tasks [list]`, only when the Mac has Google Tasks set up): grouped by when they're
    due against today on this device (Overdue in red, Today, Upcoming, No date). Each task has Done
    (or Undo once done, struck through), **Reschedule** (Today, Tomorrow, Next Monday, In a week,
    Pick a date…, No date), Edit (title, due date, details) and Open in Google Tasks; ↻ reads them
    again.
  - **New task** (`/task <text>`, Add task on an email, or by asking): Create, Edit… (title, list,
    due date, details, sent once on Done) or Cancel. Create waits while a title is being suggested.
  - **Task changes asked for in chat** ("move the dentist to Monday") wait for **Confirm**.
  - What's typed in a card's sheet stays on this device until Done.
  - **Open in Obsidian** opens the note in Obsidian here, if the vault is synced to this device under
    the same name.
- **The draft editor** opens when the Mac opens one for this device (Reply, Reply all, Edit, or
  `/draft`), also if that happened while the app was in the background.
  - To, Cc, Bcc, Subject, the body and the instructions are edited here, and stay here until you
    press something: nothing is sent per keystroke.
  - **Write / Rewrite** has the Mac's `draft` model write the body (it streams in). The **Reply
    all** switch has the Mac fill in Cc.
  - **Save to Drafts** (or **Update draft**) puts it in the account's Drafts. **Copy text** copies
    the body. **Cancel** closes it without saving (asking first if you typed anything).
  - Nothing is ever sent as email.
- **The provider line** at the top shows which model each role uses on the Mac (a globe: off the
  Mac). Tap one for the details.
- **iPad:** the conversations and the chat side by side. ⌘N starts a new one, ⌘Return sends.
- **Settings → Text size:** a step smaller or larger than iOS's own text size.

Not in this version: push notifications, offline mail, attachments.

## Versions

The version is in [`VERSION`](VERSION) and the project's `MARKETING_VERSION` (bumped by hand);
`make testflight` gives each upload its own build number. Settings and the indicator's details show
it. From 3.0.0 the first two numbers match FU Mail on the Mac (3.0.x ↔ 3.0.0), as the Android app's do; the last
one counts this app's own fixes.

| Version | Date | What changed |
| ------- | ---- | ------------ |
| 3.7.0 | 2026-11-17 | Version matched to FU Mail 3.7.0 (3.5.0 and 3.6.0 needed nothing here). **Draft cards show the mail server's warning** about saving the draft, such as a new body replacing formatting or a signature added in Google Mail or Outlook, under the body (not on a draft that's gone). |
| 3.4.0 | 2026-11-17 | Version matched to FU Mail 3.4.0. **Open in browser on a Google Mail draft** opens the draft as it is now: the Mac fetches it again first (`refresh_draft`), as its link changes whenever the draft is saved, autosave included; a spinner shows meanwhile (at most 5 s, or about 1.5 s with an older Mac). Other links open at once. A draft sent or deleted since (`gone`) says so instead of Edit and Open in browser. |
| 3.3.0 | 2026-11-16 | Version matched to FU Mail 3.3.0. **Long chats** open with their newest 10 messages, and **Show earlier messages** adds 10 (was 20). **History search** results go to the message that matched (the Mac's new `messageID`), showing earlier messages back to it and lighting it up for a moment. |
| 3.2.0 | 2026-11-16 | Version matched to FU Mail 3.2.0. New chats are titled the Mac's new way, the day then what it's about ("Mon 16 Nov · Unread"); the app's stand-in title until the Mac's arrives uses the same form. No API changes. |
| 3.1.1 | 2026-11-16 | Clean-up after 3.1.0: the home address, Wi-Fi watching and address picking are gone from the code too (a saved home address is forgotten), and Save and connect checks the one address. |
| 3.1.0 | 2026-11-15 | **Tailscale only.** The home (Wi-Fi) address and the automatic switching are gone: Settings has one address, the Tailscale one, and the indicator just says Connected, Connecting… or Can't connect. No Local Network permission is asked for any more. |
| 3.0.1 | 2026-11-15 | Fix: **back to Home sooner** after Tailscale's VPN is switched off at home. Wi-Fi is now watched on its own interface (a VPN could hide it, so the app thought it was off Wi-Fi and kept to Tailscale), and any network change, the VPN coming or going included, re-checks the home address (token-less `/health`) and moves to it when FU Mail answers, rather than retrying Tailscale. When Tailscale is used on Wi-Fi, the indicator's details say why Home wasn't. |
| 3.0.0 | 2026-11-15 | Version matched to FU Mail 3.0.0 on the Mac (the API is the same since 2.6.0; the Mac's 2.7.0–3.0.0 additions need nothing here: an auto Bcc arrives in the draft editor's Bcc field, where it shows and can be removed). **Long chats are quick again:** a chat opens with its newest 20 messages, and **Show earlier messages** adds 20 more. **Fonts:** the message bar and the search fields use the standard iOS font; Original \| Summary and Settings' Appearance and Text size switches are in the app's font and follow Text size; card buttons match the card text's size. |
| 0.8.0 | 2026-11-15 | **Two addresses**, picked by themselves: **At home (Wi-Fi)** and **Tailscale**. On Wi-Fi the home one is used when FU Mail answers there (a quick `/health`, no token), otherwise Tailscale; it picks again on every reconnect and when Wi-Fi comes or goes, and the indicator says which. Save and connect checks each address. The one address from before moves into the right field. `/health` must now be FU Mail's own answer. Matches the Android app 0.8.0 and FU Mail 2.8.0 (no Mac changes needed). |
| 0.7.2 | 2026-11-15 | An email opened from a list, a command's answer, Add to note and Add task come into view when they arrive (a card from its start), even scrolled up. The keyboard hides on a tap or scroll of the messages, or Done. Settings… in the connection popover opens Settings (and no longer leaves the gear stuck). Unchanged messages aren't rebuilt when another changes. |
| 0.7.1 | 2026-11-14 | Fix: the chat could go blank after Summary or Add to note in a long chat (until it was opened again). |
| 0.7.0 | 2026-11-14 | Milestone 7: the tasks card (Done / Undo, Reschedule, Edit, Open, refresh), new task (Create, Edit…, Cancel), Confirm for task changes asked in chat, Add task on emails. Everything the Android app 0.6.0 does. |
| 0.6.0 | 2026-11-14 | Milestone 6: Add to note, note cards (Catch me up, Post CRM update, Refresh), Send to CRM (Rewrite professionally), suggested notes, Open in Obsidian. |
| 0.5.0 | 2026-11-14 | Milestone 5: the draft editor (Write / Rewrite streaming in, Reply all, Save to Drafts, Copy text, Cancel). |
| 0.4.0 | 2026-11-14 | Milestone 4: mail cards (lists with archive Show more, threads with folding, Summary, Reply, Reply all, Open in browser; drafts; events with Join). A message that can't be read no longer blanks the conversation. |
| 0.3.0 | 2026-11-14 | Milestone 3: conversations (new, rename, delete, history search) and the chat (commands, `/` suggestions, Stop, provider line), cards as text, side by side on the iPad, Settings → Text size. |
| 0.2.0 | 2026-11-14 | Milestone 2: Settings, the token in the Keychain, the connection indicator, problem banners, reconnecting; conversations listed read-only. |
| 0.1.0 | 2026-11-14 | Milestone 1: the core (the Mac's models, state, client) with the Android core's tests, the app shell, signing and `make testflight`. |

## Where things are

```
FUMailKit/              the client side of the Mac's API (a Swift package; builds for iOS and macOS)
  Sources/FUMailKit/
    JSON/               JSONValue (copied from the Mac) and the API's date format
    Models/             cards, mail, notes, tasks, editors, events: copied from the Mac's FUMailCore
    Rules/              how cards show what the Mac sent (folding, Reply all, note entries)
    State/RemoteState   this device's copy of the Mac's state: a pure function of the events
    Client/             settings, problems in plain words, the HTTP API and event stream, the client
  Tests/                the Android core's tests, ported case for case, with the same JSON fixtures
App/                    the SwiftUI app (every file in it is part of the app target)
Support/Info.plist      plain HTTP to local addresses, Obsidian links, export compliance
FUMail.xcodeproj        the Xcode project (open it to run under the debugger)
```

When the Mac's API changes, the Android core, the Windows core and `FUMailKit` each follow it.
