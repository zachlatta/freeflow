import SwiftUI

// MARK: - Panel Dismissal

/// Closes the window-style MenuBarExtra panel. SwiftUI provides no public
/// dismissal API on macOS 13, so this matches the private panel class by
/// name. Matching is intentionally narrow ("MenuBarExtra") so the status
/// item's own NSStatusBarWindow is never touched.
@MainActor
func dismissMenuBarPanel() {
    for window in NSApp.windows where window.className.contains("MenuBarExtra") {
        window.close()
    }
}

// MARK: - Menu Bar Panel

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updateManager = UpdateManager.shared

    @State private var copiedItemID: UUID?
    @State private var copiedLastTranscript = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var recentHistoryItems: [PipelineHistoryItem] {
        Array(appState.pipelineHistory.filter { !transcriptText(for: $0).isEmpty }.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            permissionBanners

            VStack(spacing: 10) {
                dictateButton

                if let hotkeyError = appState.hotkeyMonitoringErrorMessage {
                    inlineError(hotkeyError)
                }
                if let error = appState.errorMessage {
                    inlineError(error)
                }

                if !appState.lastTranscript.isEmpty && !appState.isRecording && !appState.isTranscribing {
                    lastTranscriptCard
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            if !recentHistoryItems.isEmpty {
                sectionDivider
                historySection
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            sectionDivider
            controlsSection
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            updateBanner

            sectionDivider
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
    }

    // MARK: Header

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .orange }
        return .green
    }

    private var statusText: String {
        if appState.isRecording { return "Recording…" }
        if appState.isTranscribing { return appState.debugStatusMessage }
        return appState.shortcutStatusText
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(AppName.displayName)
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("v\(appVersion)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.2), value: appState.isTranscribing)
    }

    // MARK: Permission Banners

    @ViewBuilder
    private var permissionBanners: some View {
        VStack(spacing: 6) {
            if !appState.hasScreenRecordingPermission {
                PanelBannerButton(
                    title: "Screen Recording permission needed",
                    systemImage: "camera.viewfinder",
                    tint: .orange
                ) {
                    appState.requestScreenCapturePermission()
                }
            }
            if !appState.hasAccessibility {
                PanelBannerButton(
                    title: "Accessibility access required",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red
                ) {
                    appState.showAccessibilityAlert()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, appState.hasAccessibility && appState.hasScreenRecordingPermission ? 0 : 10)
    }

    // MARK: Primary Action

    private var dictateHint: String? {
        guard !appState.isRecording else { return nil }
        if !appState.holdShortcut.isDisabled {
            return "Hold \(appState.holdShortcut.displayName)"
        }
        if !appState.toggleShortcut.isDisabled {
            return "Tap \(appState.toggleShortcut.displayName)"
        }
        return nil
    }

    private var dictateButton: some View {
        Button {
            let shouldStop = appState.isRecording
            dismissMenuBarPanel()
            if shouldStop {
                appState.toggleRecording()
            } else {
                // Hand focus back to the previous app before recording so the
                // transcript pastes where the user was typing, not into
                // FreeFlow's own panel.
                NSApp.hide(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    appState.toggleRecording()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(appState.isRecording ? "Stop Recording" : "Start Dictating")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let hint = dictateHint {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: appState.isRecording
                                ? [Color.red, Color.red.opacity(0.8)]
                                : [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.isTranscribing)
        .opacity(appState.isTranscribing ? 0.5 : 1)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    // MARK: Last Transcript

    private var lastTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LAST TRANSCRIPT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.5)
                Spacer()
                Button {
                    appState.copyLastTranscriptToPasteboard()
                    withAnimation(.easeInOut(duration: 0.15)) { copiedLastTranscript = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copiedLastTranscript = false }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedLastTranscript ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(pasteAgainLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(copiedLastTranscript ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Text(appState.lastTranscript)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var pasteAgainLabel: String {
        if copiedLastTranscript { return "Copied" }
        if appState.copyAgainShortcut.isDisabled { return "Paste Again" }
        return "Paste Again  \(appState.copyAgainShortcut.displayName)"
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.5)
                Spacer()
                Button("View All") {
                    openSettingsTab(.runLog)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 4)

            ForEach(recentHistoryItems) { item in
                HistoryRow(
                    snippet: transcriptSnippet(for: item),
                    detail: historyDetail(for: item),
                    isCopied: copiedItemID == item.id
                ) {
                    copyToPasteboard(transcriptFull(for: item))
                    withAnimation(.easeInOut(duration: 0.15)) { copiedItemID = item.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedItemID == item.id {
                            withAnimation { copiedItemID = nil }
                        }
                    }
                }
            }
        }
    }

    private func historyDetail(for item: PipelineHistoryItem) -> String {
        let time = Self.relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date())
        if let app = item.contextAppName, !app.isEmpty {
            return "\(time) · \(app)"
        }
        return time
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: Controls

    private var controlsSection: some View {
        VStack(spacing: 2) {
            microphoneRow
            shortcutRow(role: .hold, icon: "hand.tap", current: appState.holdShortcut)
            shortcutRow(role: .toggle, icon: "cursorarrow.click.2", current: appState.toggleShortcut)
            shortcutRow(role: .copyAgain, icon: "doc.on.clipboard", current: appState.copyAgainShortcut)
        }
    }

    private var selectedMicrophoneName: String {
        if appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty {
            return "System Default"
        }
        return appState.availableMicrophones.first { $0.uid == appState.selectedMicrophoneID }?.name
            ?? "System Default"
    }

    private var microphoneRow: some View {
        PanelControlRow(icon: "mic", title: "Microphone") {
            Menu {
                Button {
                    appState.selectedMicrophoneID = "default"
                } label: {
                    menuChoiceLabel(
                        "System Default",
                        isSelected: appState.selectedMicrophoneID == "default"
                            || appState.selectedMicrophoneID.isEmpty
                    )
                }
                ForEach(appState.availableMicrophones) { device in
                    Button {
                        appState.selectedMicrophoneID = device.uid
                    } label: {
                        menuChoiceLabel(device.name, isSelected: appState.selectedMicrophoneID == device.uid)
                    }
                }
            } label: {
                Text(selectedMicrophoneName)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func conflictingBinding(for role: ShortcutRole) -> [ShortcutBinding] {
        switch role {
        case .hold: return [appState.toggleShortcut]
        case .toggle: return [appState.holdShortcut]
        case .copyAgain: return [appState.holdShortcut, appState.toggleShortcut]
        }
    }

    private func currentBinding(for role: ShortcutRole) -> ShortcutBinding {
        switch role {
        case .hold: return appState.holdShortcut
        case .toggle: return appState.toggleShortcut
        case .copyAgain: return appState.copyAgainShortcut
        }
    }

    private func shortcutRow(role: ShortcutRole, icon: String, current: ShortcutBinding) -> some View {
        PanelControlRow(icon: icon, title: role.title) {
            Menu {
                Button {
                    _ = appState.setShortcut(.disabled, for: role)
                } label: {
                    menuChoiceLabel("Disabled", isSelected: current.isDisabled)
                }

                ForEach(ShortcutPreset.allCases) { preset in
                    Button {
                        _ = appState.setShortcut(preset.binding, for: role)
                    } label: {
                        menuChoiceLabel(preset.title, isSelected: current == preset.binding)
                    }
                    .disabled(conflictingBinding(for: role).contains(preset.binding))
                }

                if let custom = appState.savedCustomShortcut(for: role) {
                    Divider()
                    Button {
                        _ = appState.setShortcut(custom, for: role)
                    } label: {
                        menuChoiceLabel("Custom: \(custom.displayName)", isSelected: current == custom)
                    }
                }

                Divider()
                Button("Customize…") {
                    openSettingsTab(.general)
                }
            } label: {
                Text(current.isDisabled ? "Off" : current.displayName)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func menuChoiceLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: Update Banner

    @ViewBuilder
    private var updateBanner: some View {
        if updateManager.updateAvailable {
            sectionDivider
            Group {
                switch updateManager.updateStatus {
                case .downloading:
                    VStack(spacing: 4) {
                        Text("Downloading update… \(Int((updateManager.downloadProgress ?? 0) * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                        ProgressView(value: updateManager.downloadProgress ?? 0)
                            .progressViewStyle(.linear)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                case .installing, .readyToRelaunch:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing update…")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.vertical, 8)

                default:
                    PanelBannerButton(
                        title: "Update available — install now",
                        systemImage: "arrow.down.circle.fill",
                        tint: .blue
                    ) {
                        dismissMenuBarPanel()
                        updateManager.showUpdateAlert()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            PanelFooterButton(title: "Settings", systemImage: "gearshape") {
                dismissMenuBarPanel()
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }

            Menu {
                Button("Paste Custom Word to Vocabulary") {
                    if appState.pasteWordToVocabulary() != nil {
                        VocabularyNotificationManager.shared.flashCheckmark()
                    }
                }
                Button("Re-run Setup…") {
                    dismissMenuBarPanel()
                    NotificationCenter.default.post(name: .showSetup, object: nil)
                }
                Divider()
                Button(updateManager.isChecking ? "Checking for Updates…" : "Check for Updates") {
                    Task {
                        await updateManager.checkForUpdates(userInitiated: true)
                    }
                }
                .disabled(updateManager.isChecking)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()

            PanelFooterButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: Helpers

    private func openSettingsTab(_ tab: SettingsTab) {
        appState.selectedSettingsTab = tab
        dismissMenuBarPanel()
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    private var sectionDivider: some View {
        Divider().opacity(0.5)
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
        return text.count > 60 ? String(text.prefix(60)) + "…" : text
    }

    private func copyToPasteboard(_ transcript: String) {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

// MARK: - Components

/// Full-width tinted banner used for permission warnings and update prompts.
private struct PanelBannerButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.6)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(isHovered ? 0.18 : 0.12))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// History row: snippet plus relative time, copies on click with hover affordance.
private struct HistoryRow: View {
    let snippet: String
    let detail: String
    let isCopied: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.green)
                } else if isHovered {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to copy")
    }
}

/// Labeled control row with a trailing menu/value.
private struct PanelControlRow<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
            Spacer()
            trailing
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

/// Compact footer button with hover highlight.
private struct PanelFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
