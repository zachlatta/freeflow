# PLUGINS

Four self-contained pieces built on a fork of FreeFlow, put at the repository
root so they can be read without cloning or diffing anything. Each one is the
file as it actually ships in the fork, not a sketch.

They are here as a demonstration and a reference. The real integration lives on
the `feat/async-target-paste` branch, where these files sit in `Sources/`
alongside the changes in `AppState.swift` and `RecordingOverlay.swift` that
call into them.

Written with AI assistance and then used daily against a local Qwen3 ASR
server. Everything described below was observed on a real machine, not
theorised.

## `TextDelivery.swift` — get the transcript back where it came from

Transcription is asynchronous; delivery was not. Upstream stores the frontmost
application at stop time, activates it and posts Cmd-V, which takes focus back,
crosses Spaces, and only knows the app rather than the field.

This pins the focused `AXUIElement` **and** its `kAXSelectedTextRange` at stop
time, then walks an ordered ladder:

| Rung | Mechanism | Steals focus |
|---|---|---|
| `ax-insert` | restore the range, write `kAXSelectedTextAttribute` | no |
| `pid-paste` | Cmd-V via `CGEvent.postToPid` | no |
| `pid-keystroke` | `keyboardSetUnicodeString` via `postToPid` | no |
| `activate-paste` | today's behaviour, opt-in | yes |
| `clipboard` | left on the clipboard, with a panel saying so | no |

Two findings worth more than the code:

- An Accessibility write into a Chromium or Electron host returns `.success`
  while the text never lands. The insert therefore measures the element
  (`kAXNumberOfCharacters`, falling back to `kAXValue`) before and after and
  treats no growth as failure. See issue #311.
- Chromium reads a synthesised key event by its virtual key code and ignores
  the attached unicode, so injected text arrives as a stray keypress. In one
  app it opened an AI panel instead of typing. Hence a paste rung, tried before
  injection for such hosts.

## `LoudnessMeter.swift` — see whether the microphone is hearing you

The existing waveform takes `audioLevel` but mixes it with a traveling sine and
a shimmer, so the bars move in silence and barely change when you get louder.
It looks alive without telling you anything.

This draws a scrolling meter: one bar per moment, height from the level then,
newest on the right, quiet bars dimmed. What an ordinary voice recorder shows.
See issue #313.

## `ClipboardWaitingPanel.swift` — say so when delivery could not happen

When the ladder falls through to the clipboard, a menu-bar status line is easy
to miss, since the whole point is that you have moved on to another app. This
raises a floating, non-activating `NSPanel` that appears on whichever Space you
are on, names the app the text could not reach, shows what is waiting and why.

## Related issues

#308 through #314, plus #250 (merged) and #252 (open).
