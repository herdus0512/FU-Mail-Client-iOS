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

> **Status: 6.0.1, for FU Mail 6.1.1 on the Mac. Connects over Tailscale only.** Connecting, the
> conversations, the chat, every card with its buttons (mail,
> drafts, events, notes, CRM, tasks) and the draft editor, side by side on the iPad in landscape. See
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
                  #   LISTED=0 make fake-mac acts as a Mac whose api.full_triage leaves this device out
                  #   OPEN=2 opens the second conversation (4: the triage cards); UPTO=4 shows only its first 4 messages;
                  #   SEND=/unread sends it 2 s after the chat opens (the fake answers "Fetching…",
                  #   then a thread card in its place a second later); SEARCH=bob searches the history
                  #   and opens the first result as a tap does; FOCUS=1 puts the cursor
                  #   in the message box (turn off I/O → Keyboard → Connect Hardware Keyboard to
                  #   see the on-screen keyboard)
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
it works ("Connected to FU Mail 3.8.0 as "iphone". Saved."); **Save anyway** keeps settings that
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
- **Connecting** fetches everything it needs at once (the Mac's details, the chats, open editors,
  commands), over one connection shared with the event stream, so "Connected" comes after about
  one trip to the Mac and back. The connection stays open while Control Center or a notification is
  pulled over the app, and closes only when the app goes to the background.
- **Siri and Shortcuts:** **Rest of Today** ("What's left today in FU Mail") asks the Mac for what's
  left of today's calendar (`GET /v1/calendar/now`, FU Mail 4.6.0 and later) with the app's own saved
  connection, so no token goes into a shortcut, and without opening the app. It returns one line per
  event in the phone's time ("14:00–15:00 Board meeting (Level 3)", "All day: Public holiday"), or
  "Nothing more on today.", as text a shortcut can pass on (e.g. to Use Model); problems come back as
  a plain sentence. **Pending Drafts** ("Pending drafts in FU Mail") does the same for unsent
  drafts across accounts (`GET /v1/drafts?limit=10`): "To Bob Smith: Re: Q4 invoice (work)", or "No
  drafts waiting.". The tokens are readable after the phone's first unlock, so it works from a locked
  phone too.
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

- **Conversations:** newest first. The pencil starts a new one (an unused one goes if the Mac
  restarts). Swipe left to delete; touch and hold
  to rename. **Search history** searches the Mac's history, by
  words and meaning.
- **Chat:** type a command (`/unread`, `/search bob`, `/today`, `/help`) or a question, as on the
  Mac. **Tap into the empty box, or type `/`, and the commands appear** above it, narrowing as you
  type; tap one to put it in the box. **No slash needed:** start typing a command's name (`u`, `obs`)
  and the matching commands show too; tapping one makes it `/unread `, `/obsidian `. A question goes
  on as typed (the list goes at the first space). The box and the searches are in SF Mono, like the
  rest of the app. (After sending, the box keeps the cursor but the list stays
  closed, so it doesn't cover the answer; tap the box again for it.) While the chat model works, its status shows above the box, with **Stop**.
- **Long chats** open with their newest 10 messages; **Show earlier messages** at the top adds 10
  more at a time.
- **History search:** opening a result goes to the message that matched, showing earlier messages
  back to it, and lights it up for a moment (with FU Mail 3.3.0 or later on the Mac).
- **The chat** follows new messages while you're at the bottom; scrolled up, it stays put and
  **Latest** jumps down. What you asked for yourself (an email opened from a list, a command, Add to
  note, Add task) is always shown when it arrives. **A new card lands at its top:** the Mac first
  sends a short placeholder ("Opening…") and then the card in its place, so the chat keeps the new
  message's top at the top of the screen while it turns into the card and grows, until you scroll
  yourself. The keyboard goes away after sending, and when the chat is scrolled or the messages are
  tapped; in a new, empty chat, tap anywhere above the message box.
- **Copy and select:** touch and hold a message, an email, a summary, a draft or a note's text for
  **Copy** (all of it) or **Select Text…**, which opens it on its own with iOS's own selection
  (drag the handles, Select All, Copy, Share). It starts with everything selected.
- **Cards** have the Mac's buttons:
  - **Lists:** tap a row to open it. An archive list (`/archive`) has **Show more (N left)**.
  - **Threads:** newest first, folded by the Mac's rule (your own replies fold too): tap a folded
    message to open it, ⌃ to fold it again. Original | Summary (with Rewrite), Expand all / Fold
    older, Show full text, Reply, Reply all (only when it reaches someone more), Add to note, Add
    task (with Google Tasks) and Open in browser.
    A thread from the archive is read-only: no Reply or Reply all.
    An unsent draft in the thread has an orange **Draft** label (FU Mail 6.1.1 and later); then Reply and
    Reply all ask first: **Edit draft** opens the newest one, **Write another** writes a new reply.
    **Delete** (when the email's server can, e.g. Thunderbird-MCP) moves the opened email to Trash
    after a "Move this email to Trash?" confirmation; the card then says "Moved to Trash." instead of
    its buttons.
  - **Drafts:** tap a row to open it; Edit and Open in browser on a draft. A Google Mail draft's
    link changes whenever the draft is saved, so Open in browser first has the Mac fetch the draft
    again (a spinner on the button, a few seconds at most) and opens its current link; other links
    open at once. A draft that was sent or deleted says so instead of offering either button.
    When the mail server warned about saving the draft (say, a new body replaced a signature added
    in Google Mail or Outlook), the warning shows under the body.
  - **Events:** by day, with Join for video calls. **`/now`** (FU Mail 4.3.0 and later) shows
    what's left of today where you are: the app sends the phone's current time zone with every request
    (`X-FUMail-Time-Zone`, read each time, so it follows you after a flight), and the card is titled
    with it, e.g. "Now (Europe/London)". Event times show in the phone's own time.
  - **Add to note** (`/note [n]`, or the thread's button): the note (None of these… lists every note,
    filtered as you type), Edit…, Insert / Insert anyway / Replace, Change note, Skip, then Undo and
    Open in Obsidian.
  - **Note cards** (`/obsidian [name] [summary|crm|correspondence]`): pick the note, then its
    Summary, CRM and Correspondence, read-only (the newest 5 entries, with Show all).
    **Post CRM update**, **Refresh** and Open in Obsidian. A **Note | Summary** switch at the top, as
    on email cards: Summary is the Mac's catch-up of the note, written the first time you choose it
    (**Rewrite** asks again).
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
  - **Triage review cards** (`/triage spam`, `/triage clean`, `/triage archive [days]`), only when this
    device's token is named in the Mac's `api.full_triage`; otherwise the Mac leaves them out, and the
    app shows its refusal as sent. There's nothing to set here. Tap a row to open it.
    - **Caught Spam & Marketing:** Delete and Not spam on each row; **⋯** has Add to Spam list & Delete
      and Not spam (+ Skip list), which also stops triage checking that sender. Move all to Trash (n).
    - **Inbox Cleanup:** Delete or Keep. Move all to Trash (n).
    - **Archive** (FU Mail 6.1.0 and later): each row is a conversation. Two lists, You replied last and
      Complete, each with its own Archive all (n). Archive (Archive n for several emails) or Keep; **⋯** has
      Archive & remember and Keep & remember, which also suggest a note.
    - Every button but Refresh asks first. The question closes, and nothing is sent, if what it asked
      about changes, the card becomes busy or the connection drops. Rows go only when the Mac updates
      the card.
    - After a reconnect, the buttons (Refresh too) stay off until the chat has been fetched again, so
      they never act on an old card. If that fails, the card says so and the app keeps trying for about
      a minute; after that, reopen the chat to try again.
  - **Task changes asked for in chat** ("move the dentist to Monday") wait for **Confirm**.
  - What's typed in a card's sheet stays on this device until Done.
  - **Open in Obsidian** opens the note in Obsidian here, if the vault is synced to this device under
    the same name.
  - **Memos** (FU Mail 4.5.0 and later): a note kept in Memos (its path starts with `memos/`) has
    **Open in Memos** instead, which opens it in the browser at the Mac's Memos address (no button
    when the Mac doesn't say where Memos is). After Add to note or Post CRM update, the line says
    where the entry went, e.g. "Added to UOB (Memos)" or "Posted to UOB (## CRM, vault)". A warning
    line shows whenever Memos couldn't be reached and the vault was used, even before anything is
    written (the notes listed then come from the vault). `/memo` works like `/obsidian`.
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
- **iPad:** in landscape the conversations are beside the chat (the sidebar button hides them and widens
  the chat). In portrait the chat is full screen and they slide over it; a tap on the chat, or picking
  one, hides them. ⌘N starts a new one, ⌘Return sends.
- **Settings → Text size:** Smaller, Default or Larger, as in the Android app: every text (chat,
  cards, titles, labels) is iOS's own size for it times 0.88, 1 or 1.15, so they all change together
  and keep their proportions. iOS's own text size (Display & Brightness → Text Size) still counts.

Not in this version: push notifications, offline mail, attachments.

## Versions

The version is in [`VERSION`](VERSION) and the project's `MARKETING_VERSION` (bumped by hand);
`make testflight` gives each upload its own build number. Settings and the indicator's details show
it. From 3.0.0 the first two numbers match FU Mail on the Mac (3.0.x ↔ 3.0.0), as the Android app's do; the last
one counts this app's own fixes.

| Version | Date | What changed |
| ------- | ---- | ------------ |
| 6.0.1 | 2026-11-26 | **Drafts in threads** (FU Mail 6.1.1): an orange Draft label on an unsent draft, open or folded; on a thread with a draft, Reply and Reply all ask first: Edit draft opens the newest one, Write another writes a new reply. |
| 6.0.0 | 2026-11-26 | **Archive card** for FU Mail 6.1.0: each row is a conversation (Archive n moves its n Inbox emails), two lists (You replied last, Complete) each with its own Archive all, the scan's summary, and Archive & remember / Keep & remember in the row's menu. Older Macs' cards work as before. |
| 5.9.5 | 2026-11-25 | **iPad:** the conversations are beside the chat in landscape (hiding them widens the chat), and slide over it in portrait. Turning to landscape opens them; turning to portrait hides them. iPhone unchanged. |
| 5.9.4 | 2026-11-25 | **iPad:** the conversations slide over the chat, which keeps its full width; a tap on the chat, picking one, or turning to portrait hides them. Error banners show over the chat too. iPhone unchanged. |
| 5.9.3 | 2026-11-25 | Version matched to FU Mail 5.9.3 on the Mac and Android. |
| 4.11.1 | 2026-11-25 | **Triage buttons** are off until an out-of-date chat has been fetched again (tried five times; reopen the chat to try again). The message an email card was opened from is found by its Message-ID, so it isn't folded when its number changes. |
| 4.11.0 | 2026-11-25 | **Triage review cards** (`/triage spam`, `clean` and `archive`), when this device's token is in the Mac's `api.full_triage` (FU Mail 5.8.0 and later): delete, keep, archive, the spam and skip lists, Move all to Trash and Archive all. Every button but Refresh asks first, and the question closes if what it asked about changes. An email's permanent Message-ID goes back with it, so opening a row finds the right email. Being listed later shows the cards and commands at once, and a background refresh no longer clears a refused action's message. |
| 4.10.0 | 2026-11-23 | **Archive** button on thread cards, when the email's server supports it: moves the email to Archive without a confirmation dialog and appends the Mac's `"Archived."` confirmation. |
| 4.9.1 | 2026-11-23 | Fix in **`/compose`**: the **From** account selector now uses a full-width single-line menu so long addresses truncate cleanly instead of wrapping. |
| 4.9.0 | 2026-11-23 | **`/compose`** in the draft editor (with a **From** account picker, instructions, **Write / Rewrite**, and **Save to Drafts**) and recipient autocomplete chips from `GET /v1/contacts` on `To`, `Cc`, and `Bcc`. |
| 4.8.0 | 2026-11-23 | **Attachment downloads** on thread cards, when the server supports them (e.g. Thunderbird-MCP): tap an attachment chip to have the Mac save it to its configured download folder and reply with the confirmation. |
| 4.7.0 | 2026-11-22 | Version matched to Android 4.7.0. Removed Cloudflare Access Service Token (`CF-Access-Client-Id` / `CF-Access-Client-Secret`) support and its Keychain/Settings entries now that **Sign in with Google** handles remote `https://` authentication. |
| 4.6.1 | 2026-11-22 | **Sign in with Google** now uses only the `https://` address entered in Settings (no hardcoded URL) and greys out the button when the address is empty or not `https://`. |
| 4.6.0 | 2026-11-22 | **Sign in with Google** via Cloudflare Worker in Settings, sending `X-Edge-Token` on `https://` requests and `/v1/events` alongside the `fum_…` device token, with automatic coalesced token refresh and sign-out. Optional Cloudflare Access Service Auth fields moved under **Advanced**. |
| 4.5.2 | 2026-11-22 | Removed the 560 pt max height cap on HTML emails so long HTML emails expand inline and scroll smoothly with the chat, matching Android (minimum 40 pt). |
| 4.5.1 | 2026-11-22 | Fixes to HTML email display: renders on a solid white canvas (for light-authored emails in Dark Mode) and sizes dynamically to the email's body height (minimum 40 pt, no max height cap). |
| 4.5.0 | 2026-11-22 | **Original \| HTML \| Summary** tabs on thread cards, when the server supports HTML: shows sanitized HTML in a sandboxed web view with JavaScript off and external network requests blocked (tapped links open in the browser). |
| 4.4.0 | 2026-11-22 | **Delete** on thread cards, when the email's server can (e.g. Thunderbird-MCP): moves the opened email to Trash after a confirmation; the card then says "Moved to Trash." |
| 4.3.0 | 2026-11-20 | **Note \| Summary** switch on note cards, as on email cards and the Mac, in place of Catch me up: Summary is the Mac's catch-up of the note, written the first time you choose it; **Rewrite** asks again. |
| 4.2.0 | 2026-11-19 | **Pending Drafts** for Siri and Shortcuts: your unsent drafts across accounts (`GET /v1/drafts?limit=10`), one line each ("To Bob Smith: Re: Q4 invoice (work)"), with the app's own saved connection and without opening the app. |
| 4.1.0 | 2026-11-19 | For FU Mail 4.6.0 on the Mac. **Rest of Today** for Siri and Shortcuts: what's left of today's calendar (`GET /v1/calendar/now`), with the app's own saved connection and without opening the app, as plain lines a shortcut can pass on. The tokens are now readable after the phone's first unlock, so it works on a locked phone; existing ones are moved over on the next launch. |
| 4.0.1 | 2026-11-19 | Fixes to the Memos change. The warning that Memos couldn't be reached shows at every stage, also while choosing a note (the notes listed then come from the vault), not only after writing. The CRM line puts the place in its brackets, as on Android: "Posted to UOB (## CRM, Memos)". |
| 4.0.0 | 2026-11-19 | For FU Mail 4.5.1 on the Mac. **Memos:** a note kept in Memos opens with **Open in Memos** (in the browser, at the Mac's Memos address); vault notes keep Open in Obsidian. After Add to note or Post CRM update, the line says where the entry went, "(Memos)" or "(vault)", with a warning when Memos couldn't be reached and the vault was used. `/memo` works like `/obsidian`. |
| 3.9.0 | 2026-11-19 | For FU Mail 4.4.0 on the Mac (3.9.0–4.4.0 needed nothing else here). **`/now`:** what's left of today where you are. The phone's current time zone goes with every request (`X-FUMail-Time-Zone`, read each time, so it follows you after a flight), and the card is titled with it, e.g. "Now (Europe/London)", or says "Nothing more on today." Other events cards are unchanged. |
| 3.8.5 | 2026-11-18 | Fixes. **History search results open their chat again** on the iPhone (at the message that matched); tapping one did nothing. **The keyboard goes away** after sending and as soon as the chat is scrolled, a card dragged included (3.8.3 had made it go only when dragged down into the keyboard). |
| 3.8.4 | 2026-11-18 | **Commands without a slash:** start typing a command's name (`u`, `obs`) and the matching commands show above the box; tapping one makes it `/unread `, `/obsidian ` (a question goes on as typed). **SF Mono** in the message box and the search fields too, as in the Android app. |
| 3.8.3 | 2026-11-18 | Fixes. **Quicker to connect:** everything is fetched at once over one connection shared with the event stream (as the Android app shares one), and Control Center or a notification pulled over the app no longer drops the connection (it closes only in the background, like Android's). **Chat replies** are the cards' text size, a step under what you typed, as on Android. **No Done bar above the keyboard:** iOS floated it over the message bar and Send; drag the chat down or tap it (or an empty new chat) to put the keyboard away. |
| 3.8.2 | 2026-11-18 | Fix: **Text size** now changes every text by the same factor, as the Android app does (Smaller × 0.88, Larger × 1.15, of iOS's own size for each text): chat text, `/help` output, cards, labels and the chat titles all change together, where one Dynamic Type step before barely moved some and not others. |
| 3.8.1 | 2026-11-18 | Fixes, as in FU Mail for Android 3.8.1. **A new card lands at its top:** the chat keeps the newest message's top in view while the Mac's placeholder ("Opening…") turns into the card and grows, until you scroll yourself. **Commands show when you tap into the empty message box** (not right after sending). **Touch and hold** a message, email, summary, draft or note text for **Copy** or **Select Text…** (iOS's own selection, everything selected to start). |
| 3.8.0 | 2026-11-17 | Version matched to FU Mail 3.8.0. **Cloudflare Tunnel:** the address can be a tunnel's `https://<hostname>` guarded by Cloudflare Access; Settings takes the service token's Client ID and Secret (both or neither, kept in the Keychain), sent with every request but only to `https://` addresses. When Access turns the app away (a 403 page, or a redirect to its login), it says whether the service token is missing or wasn't accepted. |
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
