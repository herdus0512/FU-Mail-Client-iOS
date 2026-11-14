# Plan

FU Mail for iPhone and iPad: a thin client of the Mac's FU Mail API, at parity with the Android app
0.6.0 (Mac 2.6.0). Decided on 2026-11-14:

- **Separate repositories.** The Mac app's Swift types are copied here, not shared through a package.
  Drift is accepted: when the Mac's API changes, this follows it, as Android and Windows do.
- **iOS 27 and later only**, iPhone and iPad.
- **TestFlight** (paid developer account, internal testing) to install on this and other Apple IDs.
- **Like Android:** the connection is open only while the app is on screen; text typed in sheets and
  the draft editor is sent on Done, Write or Save, never per keystroke. Not in this version: push
  notifications, offline mail, attachments.

## What's different from Android

| | Android | iOS |
|---|---|---|
| JSON | hand-written serializers for Swift's shapes | the Mac's own `Codable` types, copied |
| Token | Android Keystore | Keychain, this device only, not backed up |
| Plain HTTP | allowed, guarded in the app | App Transport Security: local addresses only, plus the same guard |
| Local network | Android 17 "nearby devices" | iOS Local Network prompt (`NSLocalNetworkUsageDescription`) |
| Font | JetBrains Mono | SF Mono (the system's) |
| Rename / delete | long-press | swipe to delete, context menu to rename |
| Install | sideloaded APK | TestFlight |

## Milestones

1. **Groundwork** (0.1.0) ✓: FUMailKit (models, rules, state, client) with the Android core's tests
   ported, the Xcode project, the app icon, signing, and `make testflight`.
2. **Connect** (0.2.0) ✓: Settings (Save and connect, Save anyway, the plain HTTP warning,
   Appearance, Forget token), the token in the Keychain, the indicator, problem banners,
   reconnecting when the app comes back on screen; the conversations listed read-only.
3. **Chat** (0.3.0) ✓: the conversation list (new, rename, delete), sending, `/` command
   suggestions, Stop, the provider line, history search, cards as text, Text size. iPad: list and
   chat side by side.
4. **Mail cards** (0.4.0) ✓: lists (with archive Show more), threads (folding, Original | Summary,
   Show full text, Reply, Reply all, Open in browser), drafts, events. Reply and Edit show a stand-in
   until the editor.
5. **Draft editor** (0.5.0) ✓: over the chat, Write / Rewrite streaming in, Reply all, Save, Copy
   text, Cancel (asking first if anything was typed).
6. **Notes and CRM** (0.6.0) ✓: Add to note, note cards (Catch me up, Post CRM update), Send to
   CRM, suggested notes, Open in Obsidian.
7. **Tasks:** the tasks card, new task, Confirm for changes asked in chat, Add task on emails.
