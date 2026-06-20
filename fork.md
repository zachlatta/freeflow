# FreeFlow Fork Patch Memory

## Header

- **Upstream repo:** https://github.com/zachlatta/freeflow
- **Fork location:** /Users/personal/Documents/code/freeflow-fork
- **Built app:** /Users/personal/Applications/FreeFlow Dev.app
- **Bundle ID:** com.zachlatta.freeflow.dev
- **Build command:** `cd /Users/personal/Documents/code/freeflow-fork && make`
- **Install command:** `cp -r "build/FreeFlow Dev.app" "/Users/personal/Applications/FreeFlow Dev.app" && xattr -dr com.apple.quarantine "/Users/personal/Applications/FreeFlow Dev.app"`

---

## Patches

Each patch has a unique ID, the relative file path, a description of what it does and why, and verbatim Search/Replace blocks. The consumer does literal string matching: indentation and spacing must match exactly.

---

### P1

- **File:** `Sources/ShortcutCore/DictationShortcutSessionController.swift`
- **Description:** Fix silent swallow of first toggle-stop press when recording started via menu bar button. `beginManual()` set `toggleStopArmed = false` but the stop handler requires it to be true. Fix: set it to `(mode == .toggle)` so the first shortcut press stops immediately rather than being silently ignored.

**Search:**
```
    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleStopArmed = false
    }
```

**Replace:**
```
    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        // When started without a physical key press/release cycle (e.g. via menu
        // bar button), arm stop immediately so the first shortcut press stops the
        // recording rather than being silently swallowed.
        toggleStopArmed = (mode == .toggle)
    }
```

---

### P2

- **File:** `Sources/AppState.swift`
- **Description:** Preserve saved audio file when transcription is cancelled mid-flight (cancelTranscription path). Upstream deletes the file silently; fork keeps it for retry.

**Search:**
```
        audioRecorder.cleanup()
        if let transcribingAudioFileName {
            Self.deleteAudioFile(transcribingAudioFileName)
            self.transcribingAudioFileName = nil
        }
        endCriticalDictationActivity()
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
```

**Replace:**
```
        audioRecorder.cleanup()
        // Keep the saved audio file — it's available in the run log for retry.
        self.transcribingAudioFileName = nil
        endCriticalDictationActivity()
        refreshAvailableMicrophonesIfNeeded()
        if !isRecording && !isTranscribing && statusText == "Cancelled" {
            scheduleReadyStatusReset(after: 2, matching: ["Cancelled"])
```

---

### P3

- **File:** `Sources/AppState.swift`
- **Description:** Preserve saved audio file in recording-start-error teardown path. Upstream deletes it on recording-start failure; fork keeps it for retry.

**Search:**
```
        if let transcribingAudioFileName {
            Self.deleteAudioFile(transcribingAudioFileName)
            self.transcribingAudioFileName = nil
        }
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        shortcutSessionController.reset()
        endCriticalDictationActivity()
        errorMessage = formattedRecordingStartError(error)
```

**Replace:**
```
        // Keep the saved audio file — it's available in the run log for retry.
        self.transcribingAudioFileName = nil
        activeRecordingTriggerMode = nil
        currentSessionIntent = .dictation
        shortcutSessionController.reset()
        endCriticalDictationActivity()
        errorMessage = formattedRecordingStartError(error)
```

---

### P4

- **File:** `Sources/AppState.swift`
- **Description:** Preserve saved audio when isTranscribing resets mid-flight in stopAndTranscribe completion. Upstream deletes the just-saved file silently; fork keeps it for retry.

**Search:**
```
            guard self.isTranscribing else {
                if let savedAudioFile {
                    Self.deleteAudioFile(savedAudioFile.fileName)
                }
                self.transcribingAudioFileName = nil
                activeRealtime?.cancel()
                self.audioRecorder.cleanup()
                self.endCriticalDictationActivity()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }
```

**Replace:**
```
            guard self.isTranscribing else {
                // Transcription was cancelled mid-flight. Keep the saved audio
                // file so it remains available in the run log for retry.
                self.transcribingAudioFileName = nil
                activeRealtime?.cancel()
                self.audioRecorder.cleanup()
                self.endCriticalDictationActivity()
                self.refreshAvailableMicrophonesIfNeeded()
                return
            }
```

---

### P5

- **File:** `Sources/TranscriptionService.swift`
- **Description:** Change default timeout from 20s to 300s (5 min); support -1 for no timeout. Local ASR (Qwen3-ASR-1.7B) takes 15–20s for 35s of audio; the 20s default caused silent failures on long recordings.

**Search:**
```
    private var transcriptionTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        return override > 0 ? override : 20
    }
```

**Replace:**
```
    private var transcriptionTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        if override < 0 { return .infinity }   // -1 = no timeout
        return override > 0 ? override : 300   // default: 5 min
    }
```

---

### P6

- **File:** `Sources/TranscriptionService.swift`
- **Description:** Skip the timeout task entirely when timeout is infinite (no-timeout mode). Without this guard, `UInt64(.infinity * 1e9)` overflows and the timeout fires immediately.

**Search:**
```
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                        raceState.finish(.failure(TranscriptionError.transcriptionTimedOut(timeoutSeconds)))
                    } catch is CancellationError {
                    } catch {
                        raceState.finish(.failure(error))
                    }
                }

                raceState.setTasks([transcriptionTask, timeoutTask])
```

**Replace:**
```
                if timeoutSeconds.isFinite {
                    let timeoutTask = Task {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                            raceState.finish(.failure(TranscriptionError.transcriptionTimedOut(timeoutSeconds)))
                        } catch is CancellationError {
                        } catch {
                            raceState.finish(.failure(error))
                        }
                    }
                    raceState.setTasks([transcriptionTask, timeoutTask])
                } else {
                    raceState.setTasks([transcriptionTask])
                }
```

---

### P7

- **File:** `Sources/AppState.swift`
- **Description:** Add elapsed-time warning in status text while transcribing. After 20s shows "Transcribing... (Xs)"; after 60s shows "Still processing... (Xs)". Uses didSet on isTranscribing to auto-stop the timer when transcription ends.

This patch has three sub-parts applied in order: P7a (add stored properties with didSet), P7b (add timer methods before scheduleReadyStatusReset), P7c (start the timer when transcription begins).

**P7a — Add didSet + timer properties after `@Published var isTranscribing = false`**

Search:
```
    @Published var isTranscribing = false
```

Replace:
```
    @Published var isTranscribing = false {
        didSet {
            if !isTranscribing && oldValue {
                stopTranscriptionElapsedTimer()
            }
        }
    }
    private var transcriptionStartTime: Date?
    private var transcriptionElapsedTimer: Timer?
```

**P7b — Add timer methods before `scheduleReadyStatusReset`**

Search:
```
    private func scheduleReadyStatusReset(after delay: TimeInterval, matching statuses: Set<String>? = nil) {
```

Replace:
```
    private func startTranscriptionElapsedTimer() {
        transcriptionStartTime = Date()
        transcriptionElapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isTranscribing, let start = self.transcriptionStartTime else { return }
            let elapsed = Int(-start.timeIntervalSinceNow)
            guard elapsed >= 20 else { return }
            let prefix = elapsed >= 60 ? "Still processing" : "Transcribing"
            self.statusText = "\(prefix)... (\(elapsed)s)"
        }
    }

    private func stopTranscriptionElapsedTimer() {
        transcriptionElapsedTimer?.invalidate()
        transcriptionElapsedTimer = nil
        transcriptionStartTime = nil
    }

    private func scheduleReadyStatusReset(after delay: TimeInterval, matching statuses: Set<String>? = nil) {
```

**P7c — Start the timer when transcription status is set**

Search:
```
            self.statusText = "Transcribing..."
            self.debugStatusMessage = "Transcribing audio"
```

Replace:
```
            self.statusText = "Transcribing..."
            self.debugStatusMessage = "Transcribing audio"
            self.startTranscriptionElapsedTimer()
```

---

### P8

- **File:** `Sources/App.swift`
- **Description:** Shade the dev-build menu bar icon to 40% opacity at idle so the user can distinguish the fork from the production build at a glance.

**Search:**
```
        if AppBuild.isDevBundle && !appState.isRecording && !appState.isTranscribing {
            Image(nsImage: StampedMenuBarIcon.templateImage)
                .renderingMode(.template)
        } else {
```

**Replace:**
```
        if AppBuild.isDevBundle && !appState.isRecording && !appState.isTranscribing {
            Image(nsImage: StampedMenuBarIcon.templateImage)
                .renderingMode(.template)
                .opacity(0.4)
        } else {
```

---

### P9

- **File:** `Sources/SettingsView.swift`
- **Description:** Add Transcription Timeout settings card — toggle for no-timeout and a seconds input field. Lets the user configure or disable the timeout via the Settings UI rather than `defaults write`. Three additive sub-patches: P9a adds the `@AppStorage` property, P9b inserts the `SettingsCard` into the card list, P9c adds the `transcriptionTimeoutSection` computed property.

**P9a — Add `@AppStorage` property for timeout after `use_compact_overlay` line**

Search:
```
    @AppStorage("use_compact_overlay") private var useCompactOverlay = true
    @State private var screensVersion = 0
```

Replace:
```
    @AppStorage("use_compact_overlay") private var useCompactOverlay = true
    @AppStorage("transcription_timeout_seconds") private var transcriptionTimeoutRaw: Double = 300
    @State private var screensVersion = 0
```

**P9b — Insert SettingsCard for Transcription Timeout after Sound Volume card**

Search:
```
                SettingsCard("Sound Volume", icon: "speaker.wave.2.fill") {
                    soundVolumeSection
                }
                SettingsCard("Custom Vocabulary", icon: "text.book.closed.fill") {
                    vocabularySection
                }
```

Replace:
```
                SettingsCard("Sound Volume", icon: "speaker.wave.2.fill") {
                    soundVolumeSection
                }
                SettingsCard("Transcription Timeout", icon: "clock.fill") {
                    transcriptionTimeoutSection
                }
                SettingsCard("Custom Vocabulary", icon: "text.book.closed.fill") {
                    vocabularySection
                }
```

**P9c — Add `transcriptionTimeoutSection` computed property before `// MARK: Custom Vocabulary`**

Search:
```
    // MARK: Custom Vocabulary

    private var vocabularySection: some View {
```

Replace:
```
    // MARK: Transcription Timeout

    private var noTimeoutBinding: Binding<Bool> {
        Binding(
            get: { transcriptionTimeoutRaw < 0 },
            set: { transcriptionTimeoutRaw = $0 ? -1 : 300 }
        )
    }

    private var transcriptionTimeoutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("No timeout — wait as long as needed", isOn: noTimeoutBinding)

            if !noTimeoutBinding.wrappedValue {
                HStack {
                    Text("Timeout after")
                    Spacer()
                    TextField("", value: $transcriptionTimeoutRaw, format: .number)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
                Text("Status shows elapsed time after 20 s so you know it's still working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Custom Vocabulary

    private var vocabularySection: some View {
```

---

### P10

- **File:** `Makefile`
- **Description:** Use ad-hoc signing (`-`) instead of requiring a named "FreeFlow Dev" certificate. Allows local builds without a matching code-signing identity in the keychain.

**Search:**
```
	@codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" --entitlements FreeFlow.entitlements "$(APP_BUNDLE)"
```

**Replace:**
```
	@codesign --force --sign - --entitlements FreeFlow.entitlements "$(APP_BUNDLE)"
```
