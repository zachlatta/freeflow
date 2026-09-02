# Issues filed on zachlatta/freeflow

Filed 2026-09-02 23:21. Branch pushed to
`https://github.com/JaPossert/freeflow/tree/feat/async-target-paste` first so
every issue can cite real code.

| # | Issue |
|---|---|
| [308](https://github.com/zachlatta/freeflow/issues/308) | Caret-exact insertion is impossible inside terminals (unresolved, with findings) |
| [309](https://github.com/zachlatta/freeflow/issues/309) | Deliver the transcript back to the element it was dictated into, without stealing focus |
| [310](https://github.com/zachlatta/freeflow/issues/310) | Overlapping dictations: isTranscribing is single-flight |
| [311](https://github.com/zachlatta/freeflow/issues/311) | Electron and Chromium: Accessibility writes report success and silently swallow the text |
| [312](https://github.com/zachlatta/freeflow/issues/312) | Recording overlay disappears while other transcriptions are still running |
| [313](https://github.com/zachlatta/freeflow/issues/313) | Recording overlay does not show input loudness |
| [314](https://github.com/zachlatta/freeflow/issues/314) | First toggle-stop press is swallowed after a menu-bar start |

Prior contributions upstream, for context: PR #250 merged (notification banner
instead of a URLSession timeout), PR #252 open (background HTTP
pre-transcription while recording). Related existing issue: #237, Edit Mode
falling back to dictation in Electron and Chromium, which #311 explains the
mechanism for.

The drafts below are what was filed.

---

## 1. Deliver the transcript back to the element it was dictated into

**Problem.** Transcription is asynchronous but delivery is not. `pasteAtCursor`
stores the frontmost `NSRunningApplication` at stop time, then calls
`activate(options: .activateIgnoringOtherApps)` and posts Cmd-V. Three
consequences: it yanks focus back mid-task, it drags you across Spaces if you
switched Desktop, and because it only remembers the *app* it will paste into a
different window or tab of that app if you moved.

**What I did instead.** A four-rung ladder, in `Sources/TextDelivery.swift`:

1. `ax-insert`: pin the `AXUIElement` that had keyboard focus at stop time
   along with its `kAXSelectedTextRange`, then restore the range and write
   `kAXSelectedTextAttribute`. No activation, survives Space switches, lands on
   the exact caret rather than the window.
2. `pid-keystroke`: `CGEvent.postToPid` with `keyboardSetUnicodeString`,
   chunked to 16 UTF-16 units, for anything that refuses AX text writes.
3. `activate-paste`: the current behaviour, kept but off by default.
4. `clipboard`: leave it there and say so.

Every rung records why it failed, surfaced in Settings so a misdelivery is
diagnosable instead of mysterious.

**Worth discussing.** Whether rung 3 should stay opt-in or remain the default
for existing users.

---

## 2. Overlapping dictations: `isTranscribing` is single-flight

**Problem.** `startRecording` refuses while `isTranscribing`, `transcriptionTask`
is one task, and the stop path cancels it before starting the next. So a second
dictation cannot begin until the first has fully landed. On a local model that
is a 10 to 25 second wait per 30 seconds of speech.

**What I did instead.** Sessions keyed by UUID:
`liveTranscriptionSessions: Set<UUID>`, `transcriptionTasksBySession`, and
`isTranscribing` derived from the set. Each session carries its own delivery
target in a local, so dictation #2 cannot redirect dictation #1's text.

Three hazards that surfaced and needed fixing, all invisible until overlap
exists:
- `audioRecorder.cleanup()` ran from a transcription's completion, tearing the
  shared recorder down under a recording already in progress.
- The clipboard snapshot was taken per session, so session B captured session
  A's transcript and would restore *that* as "the user's clipboard".
- `endCriticalDictationActivity()` from A fires while B records; idempotent, so
  harmless, but worth knowing.

---

## 3. An AX write can report success and silently swallow the text

**Problem.** `AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute, text)`
returns `.success` in Chromium and Electron apps while the text never reaches
the editable surface. The transcript vanishes with no error anywhere.

**What I did instead.** Read `kAXNumberOfCharacters`, falling back to
`kAXValue`, before and after the write. If the element did not grow, treat the
write as failed and fall through to the next rung. Elements that expose neither
are accepted unverified, which is the honest default.

Also: set `AXManualAccessibility` on the target application before reading its
focused element, otherwise Chromium keeps its accessibility tree switched off.

---

## 4. The recording overlay disappears while transcriptions are still running

**Problem.** Each completion calls `overlayManager.dismiss()`. With more than
one transcription in flight, the first to finish takes the overlay away and the
rest run invisibly.

**What I did instead.** `dismissOverlayIfIdle()` takes the overlay down only
when no sessions remain, and `RecordingOverlayState.pendingTranscriptionCount`
drives a small count badge to the left of the processing bars, so a queue of
several is legible at a glance.

---

## 5. The recording overlay does not show loudness

**Problem.** The waveform animates but does not track input level, so there is
no way to tell mid-sentence whether the microphone is actually hearing you.
Wispr Flow and ordinary recorders all show this.

**Status.** Not implemented yet. `LiveAudioLevelNormalizer` already carries the
signal; the work is presentational.

---

## 6. First toggle-stop press is swallowed after a menu-bar start

**Problem.** `beginManual(mode:)` sets `toggleStopArmed = false`, but the stop
handler requires it true, so a recording started from the menu bar ignores the
first shortcut press.

**Fix.** `toggleStopArmed = (mode == .toggle)`. One line, no design question.
Probably the easiest of these to take.
