import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updateManager = UpdateManager.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var recentHistoryItems: [PipelineHistoryItem] {
        Array(appState.pipelineHistory.filter { !transcriptText(for: $0).isEmpty }.prefix(10))
    }

    private func transcriptText(for item: PipelineHistoryItem) -> String {
        let cleaned = item.postProcessedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return cleaned
        }
        return item.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcriptFull(for item: PipelineHistoryItem) -> String {
        if !item.postProcessedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return item.postProcessedTranscript
        }
        return item.rawTranscript
    }

    private func transcriptSnippet(for item: PipelineHistoryItem) -> String {
        let text = transcriptText(for: item)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "(no transcript)" }
        return text.count > 48 ? String(text.prefix(48)) + "..." : text
    }

    private func copyTranscriptToPasteboard(_ transcript: String) {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func openRunLog() {
        appState.selectedSettingsTab = .runLog
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(AppName.displayName) v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            Divider()

            if !appState.hasScreenRecordingPermission {
                Button {
                    appState.requestScreenCapturePermission()
                } label: {
                    Label("Screen Recording Permission Needed", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange)

                Divider()
            }

            // Accessibility warning
            if !appState.hasAccessibility {
                Button {
                    appState.showAccessibilityAlert()
                } label: {
                    Label("Accessibility Required", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.red)

                Divider()
            }

            // Status
            if appState.isRecording {
                Label("Recording...", systemImage: "record.circle")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else if appState.isTranscribing {
                Label(appState.debugStatusMessage, systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else {
                Text(appState.shortcutStatusText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            Divider()

            // Manual toggle
            Button(appState.isRecording ? "Stop Recording" : "Start Dictating") {
                appState.toggleRecording()
            }
            .disabled(appState.isTranscribing)

            if let hotkeyError = appState.hotkeyMonitoringErrorMessage {
                Divider()
                Text(hotkeyError)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            if let error = appState.errorMessage {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            Divider()

            if !appState.lastTranscript.isEmpty && !appState.isRecording && !appState.isTranscribing {
                Text(appState.lastTranscript.count > 35
                    ? String(appState.lastTranscript.prefix(35)) + "…"
                    : appState.lastTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .lineLimit(4)
                    .frame(maxWidth: 280, alignment: .leading)

                Button("Copy Again") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.lastTranscript, forType: .string)
                }
            }

            Menu("History") {
                if recentHistoryItems.isEmpty {
                    Text("No transcripts yet")
                } else {
                    ForEach(recentHistoryItems) { item in
                        let transcript = transcriptText(for: item)
                        Button {
                            copyTranscriptToPasteboard(transcriptFull(for: item))
                        } label: {
                            Text(transcriptSnippet(for: item))
                        }
                        .disabled(transcript.isEmpty)
                    }

                    Divider()
                }

                Button("Open Run Log") {
                    openRunLog()
                }
            }

            Divider()

            Menu("Hold Shortcut") {
                Button {
                    _ = appState.setShortcut(.disabled, for: .hold)
                } label: {
                    if appState.holdShortcut.isDisabled {
                        Text("✓ Disabled")
                    } else {
                        Text("  Disabled")
                    }
                }

                ForEach(ShortcutPreset.allCases) { preset in
                    Button {
                        _ = appState.setShortcut(preset.binding, for: .hold)
                    } label: {
                        if appState.holdShortcut == preset.binding {
                            Text("✓ \(preset.title)")
                        } else {
                            Text("  \(preset.title)")
                        }
                    }
                    .disabled(preset.binding == appState.toggleShortcut)
                }

                if let savedCustomShortcut = appState.savedCustomShortcut(for: .hold) {
                    Divider()
                    Button {
                        _ = appState.setShortcut(savedCustomShortcut, for: .hold)
                    } label: {
                        if appState.holdShortcut == savedCustomShortcut {
                            Text("✓ Custom: \(savedCustomShortcut.displayName)")
                        } else {
                            Text("  Custom: \(savedCustomShortcut.displayName)")
                        }
                    }
                }

                Divider()
                Button("Customize…") {
                    appState.selectedSettingsTab = .general
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }

            Menu("Toggle Shortcut") {
                Button {
                    _ = appState.setShortcut(.disabled, for: .toggle)
                } label: {
                    if appState.toggleShortcut.isDisabled {
                        Text("✓ Disabled")
                    } else {
                        Text("  Disabled")
                    }
                }

                ForEach(ShortcutPreset.allCases) { preset in
                    Button {
                        _ = appState.setShortcut(preset.binding, for: .toggle)
                    } label: {
                        if appState.toggleShortcut == preset.binding {
                            Text("✓ \(preset.title)")
                        } else {
                            Text("  \(preset.title)")
                        }
                    }
                    .disabled(preset.binding == appState.holdShortcut)
                }

                if let savedCustomShortcut = appState.savedCustomShortcut(for: .toggle) {
                    Divider()
                    Button {
                        _ = appState.setShortcut(savedCustomShortcut, for: .toggle)
                    } label: {
                        if appState.toggleShortcut == savedCustomShortcut {
                            Text("✓ Custom: \(savedCustomShortcut.displayName)")
                        } else {
                            Text("  Custom: \(savedCustomShortcut.displayName)")
                        }
                    }
                }

                Divider()
                Button("Customize…") {
                    appState.selectedSettingsTab = .general
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
            }

            Menu("Microphone") {
                Button {
                    appState.selectedMicrophoneID = "default"
                } label: {
                    if appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty {
                        Text("✓ System Default")
                    } else {
                        Text("  System Default")
                    }
                }
                ForEach(appState.availableMicrophones) { device in
                    Button {
                        appState.selectedMicrophoneID = device.uid
                    } label: {
                        if appState.selectedMicrophoneID == device.uid {
                            Text("✓ \(device.name)")
                        } else {
                            Text("  \(device.name)")
                        }
                    }
                }
            }

            Button("Re-run Setup...") {
                NotificationCenter.default.post(name: .showSetup, object: nil)
            }

            Button("Settings") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }

            Button {
                Task {
                    await updateManager.checkForUpdates(userInitiated: true)
                }
            } label: {
                HStack(spacing: 6) {
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(updateManager.isChecking ? "Checking for Updates..." : "Check for Updates")
                }
            }
            .disabled(updateManager.isChecking)

            if updateManager.updateAvailable {
                Divider()

                switch updateManager.updateStatus {
                case .downloading:
                    VStack(spacing: 4) {
                        Text("Downloading update... \(Int((updateManager.downloadProgress ?? 0) * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        ProgressView(value: updateManager.downloadProgress ?? 0)
                            .progressViewStyle(.linear)
                            .tint(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)

                case .installing, .readyToRelaunch:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing update...")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)

                default:
                    Button {
                        updateManager.showUpdateAlert()
                    } label: {
                        Label("Update available", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                }
            }

            Divider()

            Button("Quit \(AppName.displayName)") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }
}
