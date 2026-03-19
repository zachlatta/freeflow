import SwiftUI
import AppKit

struct DictationShortcutEditor: View {
    @EnvironmentObject var appState: AppState

    let showsIntroText: Bool
    let onCaptureStateChange: ((Bool) -> Void)?

    @State private var activeCaptureRole: ShortcutRole?
    @State private var holdValidationMessage: String?
    @State private var toggleValidationMessage: String?

    init(showsIntroText: Bool = true, onCaptureStateChange: ((Bool) -> Void)? = nil) {
        self.showsIntroText = showsIntroText
        self.onCaptureStateChange = onCaptureStateChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsIntroText {
                Text("Hold to record, tap to start and stop, and press the toggle shortcut while holding to latch into tap mode. You can disable either workflow if you only want one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ShortcutRoleSection(
                role: .hold,
                selection: appState.holdShortcut,
                validationMessage: holdValidationMessage,
                isCapturing: Binding(
                    get: { activeCaptureRole == .hold },
                    set: { activeCaptureRole = $0 ? .hold : nil }
                ),
                onSelect: { binding in
                    holdValidationMessage = appState.setShortcut(binding, for: .hold)
                }
            )

            ShortcutRoleSection(
                role: .toggle,
                selection: appState.toggleShortcut,
                validationMessage: toggleValidationMessage,
                isCapturing: Binding(
                    get: { activeCaptureRole == .toggle },
                    set: { activeCaptureRole = $0 ? .toggle : nil }
                ),
                onSelect: { binding in
                    toggleValidationMessage = appState.setShortcut(binding, for: .toggle)
                }
            )

            Text("Custom shortcuts can use a regular key combo or a modifier paired with another modifier. Bare modifier keys are available as presets.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.usesFnShortcut {
                Text("Tip: If Fn opens the Emoji picker, go to System Settings > Keyboard and change \"Press fn key to\" to \"Do Nothing\".")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: activeCaptureRole) { role in
            onCaptureStateChange?(role != nil)
        }
        .onDisappear {
            onCaptureStateChange?(false)
        }
    }
}

struct ShortcutRoleSection: View {
    @EnvironmentObject var appState: AppState
    let role: ShortcutRole
    let selection: ShortcutBinding
    let validationMessage: String?
    @Binding var isCapturing: Bool
    let onSelect: (ShortcutBinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role.title)
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 6) {
                ShortcutPresetRow(
                    title: "Disabled",
                    isSelected: selection.isDisabled,
                    action: { onSelect(.disabled) }
                )

                ForEach(ShortcutPreset.allCases) { preset in
                    ShortcutPresetRow(
                        title: preset.title,
                        isSelected: selection == preset.binding,
                        action: { onSelect(preset.binding) }
                    )
                }

                ShortcutCaptureRow(
                    savedBinding: appState.savedCustomShortcut(for: role),
                    isSelected: selection.isCustom,
                    isCapturing: $isCapturing,
                    onSelectSaved: onSelect,
                    onCapture: onSelect
                )
            }

            if let validationMessage, !validationMessage.isEmpty {
                Label(validationMessage, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ShortcutPresetRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutCaptureRow: View {
    let savedBinding: ShortcutBinding?
    let isSelected: Bool
    @Binding var isCapturing: Bool
    let onSelectSaved: (ShortcutBinding) -> Void
    let onCapture: (ShortcutBinding) -> Void

    @State private var localKeyMonitor: Any?
    @State private var localFlagsMonitor: Any?
    @State private var pressedModifierKeyCodes: Set<UInt16> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    if let savedBinding {
                        onSelectSaved(savedBinding)
                    } else if !isCapturing {
                        startCapture()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : (savedBinding == nil ? "plus.circle" : "circle"))
                            .foregroundStyle(isSelected ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(savedBinding?.displayName ?? "Custom Shortcut")
                                .font(savedBinding == nil ? .body : .system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(savedBinding == nil ? "Record any key combo." : "Saved custom shortcut")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCapturing)

                Button(isCapturing ? "Cancel" : (savedBinding == nil ? "Record…" : "Re-record")) {
                    if isCapturing {
                        stopCapture(clearCaptureState: true)
                    } else {
                        startCapture()
                    }
                }
                .buttonStyle(.bordered)
            }

            if isCapturing {
                Label("Press a shortcut now. Use Escape to cancel.", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .onDisappear {
            stopCapture(clearCaptureState: true)
        }
    }

    private func startCapture() {
        stopCapture(clearCaptureState: false)
        isCapturing = true
        pressedModifierKeyCodes.removeAll()

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if ShortcutBinding.modifierKeyCodes.contains(event.keyCode) {
                if pressedModifierKeyCodes.contains(event.keyCode) {
                    pressedModifierKeyCodes.remove(event.keyCode)
                } else {
                    pressedModifierKeyCodes.insert(event.keyCode)
                }
            }

            if let binding = ShortcutBinding.fromModifierKeyCode(
                event.keyCode,
                pressedModifierKeyCodes: pressedModifierKeyCodes
            ) {
                onCapture(binding)
                stopCapture(clearCaptureState: true)
                return nil
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopCapture(clearCaptureState: true)
                return nil
            }

            guard let binding = ShortcutBinding.from(event: event) else {
                return nil
            }

            onCapture(binding)
            stopCapture(clearCaptureState: true)
            return nil
        }
    }

    private func stopCapture(clearCaptureState: Bool) {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        pressedModifierKeyCodes.removeAll()
        if clearCaptureState {
            isCapturing = false
        }
    }
}
