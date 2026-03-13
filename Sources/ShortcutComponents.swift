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

            Text("Custom shortcuts must include a non-modifier key. System shortcuts may still take precedence.")
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
                    currentBinding: selection.isCustom ? selection : nil,
                    isCapturing: $isCapturing,
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
    let currentBinding: ShortcutBinding?
    @Binding var isCapturing: Bool
    let onCapture: (ShortcutBinding) -> Void

    @State private var localKeyMonitor: Any?
    @State private var localFlagsMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: currentBinding == nil ? "plus.circle" : "checkmark.circle.fill")
                    .foregroundColor(currentBinding == nil ? .secondary : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentBinding?.displayName ?? "Custom Shortcut")
                        .font(currentBinding == nil ? .body : .system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(currentBinding == nil ? "Record any key combo." : "Current custom selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isCapturing ? "Cancel" : (currentBinding == nil ? "Record…" : "Re-record")) {
                    if isCapturing {
                        stopCapture(clearCaptureState: true)
                    } else {
                        startCapture()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(currentBinding == nil ? Color(nsColor: .controlBackgroundColor) : Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(currentBinding == nil ? Color.clear : Color.blue, lineWidth: 1.5)
            )

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

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { _ in
            nil
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
        if clearCaptureState {
            isCapturing = false
        }
    }
}
