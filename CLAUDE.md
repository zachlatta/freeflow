# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is FreeFlow

FreeFlow is a free, open-source macOS menu bar dictation app (pure Swift, no Xcode project). It records speech, transcribes via Groq's Whisper API, then post-processes with an LLM for context-aware text cleanup before pasting into the active app.

## Build Commands

```bash
make run                          # Build and launch (dev build, bundle ID: com.zachlatta.freeflow.dev)
make run CODESIGN_IDENTITY="-"    # Build with ad-hoc signing (no certificate needed)
make clean && make CODESIGN_IDENTITY="-"  # Clean rebuild
make ARCH=universal               # Universal binary (arm64 + x86_64)
make dmg                          # Create distributable DMG
```

The build uses `swiftc` directly (no Xcode project or SPM). All 24 Swift files in `Sources/` are compiled together. Output goes to `build/FreeFlow Dev.app/`.

There are no automated tests. Manual testing is done by running the app and using the debug overlay (available in the menu bar).

## Architecture

### Pipeline Flow

```
HotkeyManager (keyboard event tap)
  → DictationShortcutSessionController (hold/toggle state machine)
    → AppState.beginRecording()
      → AudioRecorder (AVAudioEngine + tap)
      → AppContextService (screenshot + metadata → LLM context summary)  [parallel]
    → TranscriptionService (Groq Whisper API)
    → PostProcessingService (LLM cleanup with context)
    → Paste result into active app
```

### Key Files

- **`AppState.swift`** (61KB) — Central hub. Manages all state, settings persistence (UserDefaults + Keychain), recording lifecycle, and coordinates the entire pipeline. This is where most orchestration logic lives.
- **`AudioRecorder.swift`** — AVAudioEngine recording with Bluetooth recovery (config change observer + buffer watchdog). Thread-safe buffer counting via `OSAllocatedUnfairLock`.
- **`HotkeyManager.swift`** — Global keyboard monitoring via `CGEventTap` (falls back to `NSEvent` local monitors). Tracks pressed keys/modifiers and evaluates shortcut bindings.
- **`AppContextService.swift`** — Captures frontmost app screenshot + metadata, sends to vision LLM for a 2-sentence activity summary used in post-processing.
- **`TranscriptionService.swift`** — Uploads audio to Groq's `/audio/transcriptions` endpoint. Supports URLSession and curl (HTTP/2) transports. 20-second timeout with race pattern.

### Hotkey System

Two-layer event model: `HotkeyManager` detects raw keyboard events → emits `ShortcutEvent` → `DictationShortcutSessionController` manages hold/toggle state transitions → `AppState` acts on `.start`/`.stop`/`.switchedToToggle` actions.

Key codes: 63=Fn, 54/55=Cmd, 56/60=Shift, 58/61=Option, 59/62=Control.

### API Integration

Default endpoint: `https://api.groq.com/openai/v1` (supports custom LLM endpoints like Ollama).
- Transcription model: `whisper-large-v3`
- Context/post-processing model: `meta-llama/llama-4-scout-17b-16e-instruct`
- API key stored in Keychain (`groq_api_key`)

## macOS Permissions Required

- **Accessibility** — for pasting results and reading window context
- **Microphone** — audio recording
- **Screen Recording** — screenshot capture for context (optional, gracefully degrades)

## Debugging

```bash
log stream --predicate 'subsystem == "com.zachlatta.freeflow"' --level info
```

Categories: `Recording` (audio/engine lifecycle), `Transcription` (API calls). The app also has a Debug Overlay (toggle from menu bar) and Pipeline History showing recent transcription attempts.
