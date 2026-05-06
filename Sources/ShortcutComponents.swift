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

            Text("Custom shortcuts can use modifier-only or modifier combos, extra mouse buttons, two keys together, or a mouse button plus a key (e.g. middle-click + Space). Left click is not allowed.")
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
    @State private var localKeyUpMonitor: Any?
    @State private var localFlagsMonitor: Any?
    @State private var localMouseMonitor: Any?
    @State private var localMouseUpMonitor: Any?
    @State private var pressedModifierKeyCodes: Set<UInt16> = []
    @State private var pressedCaptureKeys: Set<UInt16> = []
    @State private var pressedCaptureMouse: Set<Int> = []
    @State private var currentBinding: ShortcutBinding?

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
                            Text(displayedBindingName)
                                .font(displayedBindingUsesMonospace ? .system(.body, design: .monospaced).weight(.semibold) : .body)
                                .foregroundStyle(.primary)
                            Text(displayedBindingSubtitle)
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

                Button(isCapturing ? "Done" : "Record…") {
                    if isCapturing {
                        finishCapture()
                    } else {
                        startCapture()
                    }
                }
                .buttonStyle(.bordered)

                if isCapturing {
                    Button("Cancel") {
                        cancelCapture()
                    }
                    .buttonStyle(.plain)
                }
            }

            if isCapturing {
                Label(
                    currentBinding == nil
                        ? "Hold the combo you want (e.g. middle-click + Space), then Enter or Done."
                        : "Press Esc or Enter to save.",
                    systemImage: "keyboard"
                )
                    .font(.subheadline.weight(.semibold))
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
        pressedCaptureKeys.removeAll()
        pressedCaptureMouse.removeAll()
        currentBinding = nil

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            if ShortcutBinding.modifierKeyCodes.contains(event.keyCode) {
                if pressedModifierKeyCodes.contains(event.keyCode) {
                    pressedModifierKeyCodes.remove(event.keyCode)
                } else {
                    pressedModifierKeyCodes.insert(event.keyCode)
                }
            }
            refreshCaptureBinding(modifierFlags: event.modifierFlags, flagsEventKeyCode: event.keyCode)
            return nil
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturnKey = event.keyCode == 36 || event.keyCode == 76
            let hasPendingCapture = currentBinding != nil

            if isReturnKey && hasPendingCapture {
                finishCapture()
                return nil
            }
            if event.keyCode == 53 && hasPendingCapture {
                finishCapture()
                return nil
            }

            guard !ShortcutBinding.modifierKeyCodes.contains(event.keyCode) else {
                return nil
            }

            pressedCaptureKeys.insert(event.keyCode)
            refreshCaptureBinding(modifierFlags: event.modifierFlags, flagsEventKeyCode: nil)
            return nil
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            pressedCaptureKeys.remove(event.keyCode)
            refreshCaptureBinding(modifierFlags: event.modifierFlags, flagsEventKeyCode: nil)
            return event
        }

        let mouseMask = NSEvent.EventTypeMask.leftMouseDown
            .union(.rightMouseDown)
            .union(.otherMouseDown)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { event in
            let button = event.buttonNumber
            guard button != 0 else { return event }
            pressedCaptureMouse.insert(button)
            refreshCaptureBinding(modifierFlags: event.modifierFlags, flagsEventKeyCode: nil)
            return nil
        }

        let mouseUpMask = NSEvent.EventTypeMask.leftMouseUp
            .union(.rightMouseUp)
            .union(.otherMouseUp)
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseUpMask) { event in
            pressedCaptureMouse.remove(event.buttonNumber)
            refreshCaptureBinding(modifierFlags: event.modifierFlags, flagsEventKeyCode: nil)
            return event
        }
    }

    private func refreshCaptureBinding(modifierFlags: NSEvent.ModifierFlags, flagsEventKeyCode: UInt16?) {
        if let chord = ShortcutBinding.fromCaptureState(
            pressedKeys: pressedCaptureKeys,
            pressedMouse: pressedCaptureMouse,
            modifierFlags: modifierFlags
        ) {
            currentBinding = chord
            return
        }

        let nonMod = pressedCaptureKeys.filter { !ShortcutBinding.modifierKeyCodes.contains($0) }
        if nonMod.isEmpty && pressedCaptureMouse.isEmpty {
            if let kc = flagsEventKeyCode,
               let binding = ShortcutBinding.fromModifierKeyCode(
                   kc,
                   pressedModifierKeyCodes: pressedModifierKeyCodes,
                   allowBareModifier: true
               ) {
                currentBinding = binding
            } else {
                currentBinding = nil
            }
            return
        }

        currentBinding = nil
    }

    private func finishCapture() {
        guard let currentBinding else {
            cancelCapture()
            return
        }
        onCapture(currentBinding)
        stopCapture(clearCaptureState: true)
    }

    private func cancelCapture() {
        stopCapture(clearCaptureState: true)
    }

    private func stopCapture(clearCaptureState: Bool) {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        if let monitor = localMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseUpMonitor = nil
        }
        pressedModifierKeyCodes.removeAll()
        pressedCaptureKeys.removeAll()
        pressedCaptureMouse.removeAll()
        currentBinding = nil
        if clearCaptureState {
            isCapturing = false
        }
    }

    private var displayedBindingName: String {
        if let currentBinding {
            currentBinding.displayName
        } else if let savedBinding {
            savedBinding.displayName
        } else {
            "Custom Shortcut"
        }
    }

    private var displayedBindingSubtitle: String {
        if isCapturing {
            return currentBinding == nil ? "Recording shortcut…" : "Recorded shortcut"
        }
        return savedBinding == nil ? "Record any key combo." : "Saved custom shortcut"
    }

    private var displayedBindingUsesMonospace: Bool {
        currentBinding != nil || savedBinding != nil
    }
}
