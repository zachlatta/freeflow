import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updateManager = UpdateManager.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("FreeFlow v\(appVersion)")
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
                Text(appState.useToggleMode
                    ? "Press \(appState.selectedHotkey.displayName) to toggle dictation"
                    : "Hold \(appState.selectedHotkey.displayName) to dictate")
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

            if let error = appState.errorMessage {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .lineLimit(3)
            }

            if !appState.lastTranscript.isEmpty && !appState.isRecording && !appState.isTranscribing {
                Divider()
                Text(appState.lastTranscript)
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

            Divider()

            // Hotkey picker
            Menu("Push-to-Talk Key") {
                ForEach(HotkeyOption.allCases) { option in
                    Button {
                        appState.selectedHotkey = option
                    } label: {
                        if appState.selectedHotkey == option {
                            Text("✓ \(option.displayName)")
                        } else {
                            Text("  \(option.displayName)")
                        }
                    }
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

            Divider()

            Button(appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Debug Overlay") {
                appState.toggleDebugOverlay()
            }

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
                        Label("Update Available", systemImage: "arrow.down.circle.fill")
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

            Button("Quit FreeFlow") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }
}

extension Notification.Name {
    static let showSetup = Notification.Name("showSetup")
    static let showSettings = Notification.Name("showSettings")
}
