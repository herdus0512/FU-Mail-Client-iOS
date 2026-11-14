# FU Mail for iPhone and iPad

A phone and tablet client for [FU Mail](../FU-Mail-Client), the chat-style email client. Like the
[Android](../FU-Mail-Client-Android) and [Windows](../FU-Mail-Client-Windows) apps, it's a thin client
of the Mac's HTTP API: the mail servers, LLMs, Obsidian notes, CRM and history all stay on the Mac,
and this shows the same conversations and cards. For personal use: installed through TestFlight.

- **The Mac's own types.** The models are copied from the Mac app's Swift code, so the JSON is
  Swift's `Codable` on both ends. They're copies, not shared code: this repository stands alone, and
  follows the Mac's API ([docs/API.md](../FU-Mail-Client/docs/API.md)) when it changes.
- **iOS 27 and later**, iPhone and iPad. SwiftUI, SF Mono throughout, no third-party code.

> **Status: 0.1.0, milestone 1.** The core (models, rules, state, client) and its tests, and the
> app shell, signed and uploaded to TestFlight. Settings and connecting are next. See
> [docs/PLAN.md](docs/PLAN.md).

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
make testflight   # test, archive, sign and upload to TestFlight
```

Each upload gets a new build number (minutes since 1970), so it always goes up. A build shows in
TestFlight 5–15 minutes after uploading, and goes to the internal testing group by itself.

## Installing

On the iPhone or iPad, install **TestFlight** from the App Store, signed in with an Apple ID in the
internal testing group, and install FU Mail from there. Builds expire after 90 days; a newer build
replaces the old one and keeps its settings.

## Connecting to the Mac

*(From milestone 2.)* As for the Android app: the Mac's `api` must be on with `allow_from` covering
the home network and/or Tailscale (`100.64.0.0/10`), and each device gets its own token
(**API → New Device Token…**).

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
