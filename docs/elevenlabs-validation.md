# ElevenLabs provider validation

This report covers the review update for PR #257 against `main` at `2067470`.
All automated fixtures contain invented text, fake credentials, and generated
audio. HTTP and WebSocket transports are injected; tests never contact an AI
provider or read existing app credentials, history, or clipboard contents.

## Automated coverage

| Area | Coverage |
| --- | --- |
| Provider configuration | Default OpenAI-compatible selection, independent custom URL/key overrides, missing keys, provider switching, dedicated ElevenLabs credentials, fixed batch/realtime Scribe models. |
| Uploads | Exact endpoint, authentication header, multipart boundary/fields/audio bytes, language omission, provider-specific defaults, key validation requests. |
| Responses | JSON and verbose JSON, Whisper segment metadata filtering, genuine short speech, silence, malformed/non-HTTP responses, HTTP 400/401/422, timeout, cancellation and transport cleanup. |
| Realtime | PCM16 at 16 kHz, URL query/header shape, partial/committed events, serialized chunks before commit, cancellation before/during finalization, caller cancellation, stalled finalization, early close, send failure, sanitized server errors. |
| Pipeline fallback | Configuration feeds the real upload clients and response parser; a generated mono 16 kHz PCM16 WAV reaches the selected provider unchanged. Realtime failure cancels the socket before one upload; success/silence skip upload; cancellation never uploads; missing audio remains a file error. |

Validation on 2026-10-09 with Swift 5.10 and the macOS Command Line Tools SDK:

- `make check`: passed the full app typecheck with warnings as errors, existing
  tests and all five new suites, plist checks, shell checks, and YAML validation.
- `git diff --check`: passed.
- `make ARCH=arm64 CODESIGN_IDENTITY=-`: passed the compile-and-bundle check.

These checks do not exercise microphone capture, global shortcuts, or paste.

## Logging boundary

Realtime server event names and error messages are server-controlled and are
neither logged nor copied into errors. Realtime failures use fixed messages.
Upload logs contain only a fixed provider label, HTTP status or numeric error
code, and byte count; response bodies, filenames, and localized error messages
are omitted. AppState's realtime-start failure log is also fixed text.

## Manual end-to-end app check

**Status: not run; pending before merge.** A signed app with approved microphone
and Accessibility access, a disposable editor, and working test credentials is
needed to verify dictation through paste. No permission prompts were triggered,
permissions changed, or real provider credentials used during this update.
Keep the PR in draft until a tester records these results.

Use only this invented sentence: **"An invented comet crossed the blue sky."**
Do not attach credentials, recordings, screenshots, provider response bodies,
clipboard dumps, or exports from an existing user's app profile. Record only
the app revision, OS version, pass/fail, and a brief content-free explanation.

| Manual check | Steps and expected result | Result |
| --- | --- | --- |
| Provider switching and credential isolation | In an isolated app profile, enter distinct test credentials for cleanup, OpenAI-compatible transcription, and ElevenLabs. Switch OpenAI-compatible → ElevenLabs → OpenAI-compatible. Each selection retains its own credential/model settings. Inspect only the destination and authentication header name at a test transport boundary; record no key values. ElevenLabs uses only `xi-api-key`; OpenAI-compatible uses only `Authorization`. | Pending |
| Upload dictate/paste | Disable realtime, choose ElevenLabs, focus the disposable editor, dictate the invented sentence, and stop. Confirm one final result is pasted and the app returns to idle. Repeat with OpenAI-compatible. | Pending |
| Realtime dictate/paste | Enable realtime and repeat for each provider. Speak long enough to produce several chunks, stop, and confirm the last words are present and exactly one final result is pasted. | Pending |
| Invalid key | In the isolated profile, replace the selected provider key with an invented invalid value. Validation/dictation shows a useful failure; no stale transcript is pasted and no raw provider message or key appears in public logs. Restore the test credential afterwards. | Pending |
| Cancellation | Start dictation, cancel during recording, then repeat and cancel while finalization is pending. The app returns to idle, closes realtime work, starts no fallback upload, and pastes no result. | Pending |
| Stalled finalization | Use an injected/local test transport that accepts the commit but withholds the final event. For ElevenLabs, finalization fails after the bounded 10-second deadline, closes the socket, and falls back once to ElevenLabs upload. Confirm one final paste; then repeat with upload failure and confirm an error instead of a stuck spinner. | Pending |

The deterministic tests cover the transport failures above. Their passing
results must not be recorded as completed manual microphone-to-paste checks.
