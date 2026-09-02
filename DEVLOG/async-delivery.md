# Async delivery fork — never wait on the transcription

Branch: `feat/async-target-paste`
Worktree: `/Users/personal/Documents/code/other/freeflow-fork-wt-async`
Base: `a8d2334` (main, "durable prefetch transcripts + default prefetch on")

## Goal

Two things the old behaviour could not do:

1. The transcript lands in the text field you were writing in when you released
   the key, even after you switched app, window or Desktop. Your focus is never
   pulled back.
2. You can start the next dictation while the previous one is still
   transcribing. Each transcript still finds its own field.

## Why the previous attempt did not work

`P11` (commit f2eb538) already tried "async paste": it stored the frontmost
`NSRunningApplication` at stop time, then called `activate()` and sent Cmd-V.
That is exactly the focus steal we are trying to remove. It also pulls you back
to the app's Desktop, and it only ever knew the *app*, not the field, so a
different window or tab of the same app would receive the text.

## Design

### Delivery ladder (`Sources/TextDelivery.swift`)

`DeliveryTarget` pins, at stop time: process id, bundle id, app name, and the
live `AXUIElement` that had keyboard focus. Delivery then tries, in order:

| Tier | Mechanism | Focus steal | Works for |
|------|-----------|-------------|-----------|
| 1 `ax-insert` | `AXUIElementSetAttributeValue(el, kAXSelectedText, text)` on the pinned element | none | native Cocoa apps; Electron only when it accepts the write |
| 2 `pid-keystroke` | `CGEvent.postToPid()` with `keyboardSetUnicodeString`, chunked to 16 UTF-16 units | none | terminals and anything that refuses AX writes but processes background key events |
| 3 `activate-paste` | `activate()` + poll frontmost + Cmd-V | yes | last resort, **off by default** |
| 4 `clipboard` | text stays on the clipboard, status line says so | none | always |

Every attempt is recorded. `lastDeliveryDiagnostics` shows the whole ladder for
the last transcript in Settings → Clipboard, so a failure says *why* it went
where it went instead of failing silently.

### Rejected: TIOCSTI

Injecting characters straight into the target terminal's tty would have been
the cleanest terminal path. macOS refuses it: `ioctl(fd, TIOCSTI)` returns
`EPERM` (errno 13) for a non-root process, verified with a pty round-trip
probe. Tier 2 exists because of this.

### Overlapping dictations

`isTranscribing` was a single boolean and `transcriptionTask` a single task, so
starting a second dictation cancelled the first. Replaced with:

- `liveTranscriptionSessions: Set<UUID>` — one id per stop.
- `transcriptionTasksBySession: [UUID: Task]` — cancel-all on Fn+Esc.
- `isTranscribing` is now derived (`!liveTranscriptionSessions.isEmpty`) and
  only drives the UI.
- The delivery target is captured into a *local* at stop time and travels with
  that session's task, so dictation #2 cannot redirect dictation #1's text.
- `startRecording` no longer refuses while transcribing, and the shortcut
  controller is told `isTranscribing: false` when overlap is enabled, so the
  start press is not swallowed.

### Overlap hazards that were fixed

- **Recorder torn down under the next dictation.** `audioRecorder.cleanup()`
  ran from a transcription's completion, which now happens while a later
  recording may already be live. It is gated behind `cleanupAudioRecorderIfIdle()`.
- **Clipboard snapshot poisoning.** Each session snapshotted the clipboard
  before writing its transcript. With overlap, session B's snapshot captured
  session A's transcript and restored that as "the user's clipboard". A single
  `outstandingClipboardSnapshot` is now taken by the first session and held
  until the last outstanding restore releases it.
- **Terminals first, Accessibility second.** A terminal's `AXTextArea` can
  report `kAXSelectedText` as settable while the write only touches the
  rendered display and never reaches the tty. For known terminal bundle ids
  (`isTerminalLike`) tier 2 runs before tier 1.
- **Unconfirmed keystrokes keep the clipboard.** `postToPid` reports that
  events were posted, not that the app consumed them. After the `pid-keystroke`
  tier the transcript deliberately stays on the clipboard and the status reads
  "Sent to X — still on clipboard", so Cmd-V always recovers it.

### Known, not fixed

- `transcribingAudioFileName` is still a single var; session B overwrites it
  before session A's completion clears it. Only affects which audio file the
  cancel path points at.
- `endCriticalDictationActivity()` from session A fires while B records. It is
  idempotent-guarded, so the only effect is power-management, not audio.

### Settings (Settings → Clipboard)

- **Deliver back to where you were dictating** — default on.
- **Keep dictating while earlier transcripts finish** — default on.
- **Send keystrokes to background apps** — default on. Needed for terminals.
- **Last resort: bring the app forward and paste** — default off. This is the
  old behaviour; turning it on reintroduces the focus steal.

## Primary target: Paseo

`@getpaseo/cli` 0.7.0, "control your AI coding agents from the command line",
installed at `~/.npm-global/bin/paseo`, running as a Paseo Supervisor plus a
Paseo Daemon that listens on 127.0.0.1:6767 and 127.0.0.1:51021. The daemon
answers `/` with 404 and no content type, so it is an API/WebSocket endpoint,
not a web UI. Paseo's interface is therefore the CLI itself, which means the
delivery target is **Apple Terminal** (`com.apple.Terminal`), already in
`isTerminalLike`, so it resolves to tier 2 (`pid-keystroke`) and skips the AX
tier by design. If Apple Terminal turns out to drop background key events,
Paseo has no no-focus-steal path and the honest fallback is clipboard + Cmd-V.

## Build and install

```
cd /Users/personal/Documents/code/other/freeflow-fork-wt-async
make ARCH=arm64
```

Install **alongside** the existing dev app, as its own bundle:

```
make ARCH=arm64 APP_NAME="FreeFlow Dev Async" BUNDLE_ID="com.zachlatta.freeflow.dev.async" install
```

That is what is installed now, at `~/Applications/FreeFlow Dev Async.app`. It
carries the release icon rather than the hammer dev icon, so the two are
distinguishable in the menu bar. `FreeFlow Dev.app` is untouched.

Because the bundle id is new, macOS treats it as a different app: it needs its
own Accessibility and Microphone grants, and it starts from its own settings
domain. `hasCompletedSetup` and `updateAutoCheckEnabled` were carried over with
`defaults export | defaults import`; anything held in the Keychain was not, so
the API key may need entering once.

⚠️ The bundle is ad-hoc signed, so a rebuild changes its cdhash and macOS may
ask to re-grant Accessibility. Grant it before testing, otherwise every tier
silently degrades to clipboard.

## Test procedure (needs a person at the machine)

Not yet run. Order of operations: launch `FreeFlow Dev Async`, grant
Accessibility and Microphone when asked, set a shortcut that does not collide
with `FreeFlow Dev` (or keep `FreeFlow Dev` quit while testing), then work
through the cases below and note which tier each app resolves to.

1. **Same-app, no switch.** Dictate into TextEdit, release, stay put. Text
   should appear at the caret. Settings should show `ax-insert`.
2. **Switch app.** Dictate into TextEdit, release, immediately click into
   another app. Text must appear in TextEdit, and the front app must not change.
3. **Switch Desktop.** Dictate into TextEdit, release, switch Space. Same
   result, and no Space switch.
4. **Terminal / Paseo.** Dictate into a Paseo or Claude Code prompt in Terminal, release, switch
   away. Expect `pid-keystroke`. If the diagnostics line says
   `pid-keystroke posted` but nothing appeared, tier 2 does not work for Apple
   Terminal and the honest answer for terminals is clipboard + Cmd-V.
5. **Overlap.** Dictate a long sentence, release, immediately start a second
   dictation in a different app, release. Both transcripts must land in their
   own field, neither cancelled.
6. **Stale target.** Dictate into a TextEdit window, release, close the window.
   Expect status "On clipboard — press Cmd-V", nothing typed anywhere.

Record which tier each app resolves to; that table is the real deliverable.

## Merge hazard

This branch is based on `a8d2334` and therefore does **not** contain main's
uncommitted work in `AppState.swift`, `AppDelegate.swift`, `MenuBarView.swift`,
`PrefetchTranscriber.swift`, `TranscriptionProgressPanel.swift` and the
untracked `TranscribeFileView.swift`. Main's version carries a second
single-flight mechanism, `transcriptionAttemptID`, guarded as
`guard self.isTranscribing, self.transcriptionAttemptID == attemptID` — that
symbol does not exist in this worktree. It needs the same per-session treatment
before or during the merge. Cleanest order: commit main's WIP, rebase this
branch onto it, then re-apply the session refactor over the merged function.

## Open questions for the merge

- If tier 2 fails for Apple Terminal, is clipboard + Cmd-V acceptable for TUI
  targets, or should the fork special-case iTerm2 (its AppleScript can write
  into a specific session without focus) and suggest switching terminals?
- Should a failed delivery raise something more visible than a status line —
  the recording overlay, or a real notification?
