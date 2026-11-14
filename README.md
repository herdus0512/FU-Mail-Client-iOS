# FU Mail for iPhone and iPad

A phone and tablet client for [FU Mail](../FU-Mail-Client), the chat-style email client. Like the
[Android](../FU-Mail-Client-Android) and [Windows](../FU-Mail-Client-Windows) apps, it's a thin client
of the Mac's HTTP API: the mail servers, LLMs, Obsidian notes, CRM and history all stay on the Mac,
and this shows the same conversations and cards. For personal use: installed through TestFlight.

- **The Mac's own types.** The models are copied from the Mac app's Swift code, so the JSON is
  Swift's `Codable` on both ends. They're copies, not shared code: this repository stands alone, and
  follows the Mac's API ([docs/API.md](../FU-Mail-Client/docs/API.md)) when it changes.
- **iOS 27 and later**, iPhone and iPad. SwiftUI, SF Mono throughout, no third-party code.

> **Status: 0.6.0, milestone 6.** Connecting, the conversations, the chat, the mail cards, the
> draft editor and the notes and CRM cards work, side by side on the iPad. Task cards still show as
> text; they're next. See [docs/PLAN.md](docs/PLAN.md).

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
                  #   python3 tools/fake_mac.py --editor starts with a draft editor open)
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

As for the Android app: the Mac's `api` must be on with `allow_from` covering the home network
and/or Tailscale (`100.64.0.0/10`), and each device gets its own token (**API → New Device
Token…**). In the app, **Settings** (the gear; it opens by itself the first time) takes the address
and the token. **Save and connect** checks the address (`/health`) and the token (`/v1/info`) first
and says which one is wrong; **Save anyway** keeps settings it can't check right now, e.g. while
you're away from home.

| Where | Address |
| ----- | ------- |
| Home Wi-Fi | `http://192.168.107.138:8765` (the Mac's IP) |
| Tailnet | `http://<mac>:8765` (MagicDNS name) or `http://100.x.y.z:8765` |
| Tailnet, HTTPS | `https://<mac>.<tailnet>.ts.net` (with `tailscale serve`) |

- **Plain HTTP** is allowed by iOS only to local addresses: IP addresses, `.local` names and names
  without dots (MagicDNS). Any other name needs HTTPS. The app also sends requests only to the host
  in Settings, with redirects refused.
- **Local Network:** iOS asks the first time the address is on your home network. If it was
  declined: **Settings → Privacy & Security → Local Network → FU Mail**. Tailscale addresses don't
  need it.
- **The token** is kept in the Keychain on this device only: not synced to iCloud and not backed up.
  **Forget token** in Settings removes it.
- **The indicator** at the top right is green when connected, orange while connecting, and red
  when it can't connect. Tap it for the address, this device's name, the Mac's version and what's
  wrong. Problems also show in a banner across the top.
- **The connection** is open only while the app is on screen. When it comes back, or the
  connection drops, it reconnects (1 s, doubling up to 30 s) and fetches everything again.

## Using it

- **Conversations:** newest first. The pencil starts a new one. Swipe left to delete; touch and hold
  to rename. **Search history** searches the Mac's history, by
  words and meaning.
- **Chat:** type a command (`/unread`, `/search bob`, `/today`, `/help`) or a question, as on the
  Mac. **Type `/` and the commands appear** above the box, narrowing as you type; tap one to put it in
  the box. While the chat model works, its status shows above the box, with **Stop**.
- **Cards** have the Mac's buttons:
  - **Lists:** tap a row to open it. An archive list (`/archive`) has **Show more (N left)**.
  - **Threads:** newest first, folded by the Mac's rule (your own replies fold too): tap a folded
    message to open it, ⌃ to fold it again. Original | Summary (with Rewrite), Expand all / Fold
    older, Show full text, Reply, Reply all (only when it reaches someone more) and Open in browser.
    A thread from the archive is read-only: no Reply or Reply all.
  - **Drafts:** tap a row to open it; Edit on a draft.
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
