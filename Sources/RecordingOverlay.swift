import SwiftUI
import AppKit

// MARK: - State

final class RecordingOverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .recording
    @Published var audioLevel: Float = 0.0
    @Published var recordingTriggerMode: RecordingTriggerMode = .hold
    @Published var isCommandMode = false
    @Published var showsTranscribingSpinner = false
}

enum OverlayPhase {
    case initializing
    case recording
    case transcribing
    case feedback
}

// MARK: - Panel Helpers

private func makeOverlayPanel(width: CGFloat, height: CGFloat) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .screenSaver
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces]
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    return panel
}

private func makeNotchContent<V: View>(
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat,
    rootView: V
) -> NSView {
    let shaped = rootView
        .frame(width: width, height: height)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius))

    let hosting = NSHostingView(rootView: shaped)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.autoresizingMask = [.width, .height]
    return hosting
}

// MARK: - Manager

final class RecordingOverlayManager {
    private var overlayWindow: NSPanel?
    private let overlayState = RecordingOverlayState()
    private var lockedOverlayWidth: CGFloat?

    var onStopButtonPressed: (() -> Void)?

    private var screenHasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main, screenHasNotch else { return 0 }
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return 0 }
        return screen.frame.width - leftArea.width - rightArea.width
    }

    private var notchOverlap: CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    private var overlayAcceptsMouseEvents: Bool {
        overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle
    }

    func showInitializing(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .initializing
            self.overlayState.showsTranscribingSpinner = false
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: false)
        }
    }

    func showRecording(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .recording
            self.overlayState.showsTranscribingSpinner = false
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func transitionToRecording(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .recording
            self.overlayState.showsTranscribingSpinner = false
            self.updateOverlayLayout(animated: true)
        }
    }

    func setRecordingTriggerMode(_ mode: RecordingTriggerMode, animated: Bool) {
        DispatchQueue.main.async {
            self.overlayState.recordingTriggerMode = mode
            self.updateOverlayLayout(animated: animated)
        }
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.overlayState.audioLevel = level
        }
    }

    func prepareForTranscribing() {
        DispatchQueue.main.async {
            self.setTranscribingPhase(showsTranscribingSpinner: false)
        }
    }

    func showTranscribing() {
        DispatchQueue.main.async {
            self.setTranscribingPhase(showsTranscribingSpinner: true)
        }
    }

    func showFailureIndicator() {
        DispatchQueue.main.async {
            self.showFeedbackPanel()
        }
    }

    func dismiss() {
        DispatchQueue.main.async {
            self.dismissAll()
        }
    }

    private func showOverlayPanel(animatedResize: Bool) {
        let frame = overlayFrame

        if let panel = overlayWindow {
            panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
            panel.contentView = makeOverlayContent(frame: frame)
            resize(panel: panel, to: frame, animated: animatedResize)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let panel = makeOverlayPanel(width: frame.width, height: frame.height)
        panel.hasShadow = false
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)

        guard let screen = NSScreen.main else { return }

        let hiddenFrame = NSRect(x: frame.origin.x, y: screen.frame.maxY, width: frame.width, height: frame.height)
        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            panel.animator().setFrame(frame, display: true)
        }

        overlayWindow = panel
    }

    private func updateOverlayLayout(animated: Bool) {
        guard let panel = overlayWindow else { return }
        let frame = overlayFrame
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)
        resize(panel: panel, to: frame, animated: animated)
    }

    private func setTranscribingPhase(showsTranscribingSpinner: Bool) {
        lockedOverlayWidth = overlayWindow?.frame.width ?? overlayWidth
        overlayState.phase = .transcribing
        overlayState.showsTranscribingSpinner = showsTranscribingSpinner
        showOverlayPanel(animatedResize: true)
    }

    private func makeOverlayContent(frame: NSRect) -> NSView {
        makeNotchContent(
            width: frame.width,
            height: frame.height,
            cornerRadius: screenHasNotch ? 18 : 12,
            rootView: RecordingOverlayView(
                state: overlayState,
                onStopButtonPressed: { [weak self] in
                    self?.onStopButtonPressed?()
                }
            )
            .padding(.top, screenHasNotch ? notchOverlap : 0)
        )
    }

    private func resize(panel: NSPanel, to frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private var overlayFrame: NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let width = overlayWidth
        let overlap = screenHasNotch ? notchOverlap : 0
        let height: CGFloat = 38 + overlap
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var overlayWidth: CGFloat {
        if let lockedOverlayWidth, overlayState.phase == .transcribing {
            return lockedOverlayWidth
        }

        if overlayState.phase == .feedback {
            let feedbackWidth: CGFloat = 92
            guard screenHasNotch else { return feedbackWidth }
            return max(notchWidth, feedbackWidth)
        }

        let commandModeWidth: CGFloat = 180
        let toggleWidth: CGFloat = 150
        let defaultWidth: CGFloat = 92
        let baseWidth: CGFloat

        if overlayState.isCommandMode {
            baseWidth = commandModeWidth
        } else if overlayState.phase == .recording && overlayState.recordingTriggerMode == .toggle {
            baseWidth = toggleWidth
        } else {
            baseWidth = defaultWidth
        }

        guard screenHasNotch else { return baseWidth }
        return max(notchWidth, baseWidth)
    }

    private func showFeedbackPanel() {
        lockedOverlayWidth = nil
        overlayState.phase = .feedback
        showOverlayPanel(animatedResize: true)
    }

    private func dismissAll() {
        lockedOverlayWidth = nil
        overlayState.isCommandMode = false
        overlayState.showsTranscribingSpinner = false
        if let panel = overlayWindow {
            panel.orderOut(nil)
            overlayWindow = nil
        }
    }
}

// MARK: - Waveform Views

struct WaveformBar: View {
    let amplitude: CGFloat

    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 20

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformView: View {
    let audioLevel: Float

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index))
                    .animation(
                        .spring(
                            response: barResponse(for: index),
                            dampingFraction: 0.88
                        )
                        .delay(barDelay(for: index)),
                        value: audioLevel
                    )
            }
        }
        .frame(height: 20)
    }

    private func barAmplitude(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        return min(level * Self.multipliers[index], 1.0)
    }

    private func barResponse(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        let normalizedDistance = distance / Self.centerIndex
        return 0.18 + Double(normalizedDistance) * 0.06
    }

    private func barDelay(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        return Double(distance) * 0.01
    }
}

struct ProcessingWaveformView: View {
    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.42, 0.58, 0.76, 0.9, 1.0, 0.9, 0.76, 0.58, 0.42]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 2.5) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    let wave = 0.5 + 0.5 * sin((time * 5.6) - Double(index) * 0.5)
                    let shimmer = 0.5 + 0.5 * sin((time * 2.8) + Double(index) * 0.75)
                    let amplitude = min(
                        0.16 + CGFloat(wave) * Self.multipliers[index] * 0.52 + CGFloat(shimmer) * 0.08,
                        1.0
                    )

                    WaveformBar(amplitude: amplitude)
                        .opacity(0.45 + CGFloat(wave) * 0.5)
                }
            }
            .frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InitializingDotsView: View {
    @State private var activeDot = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(activeDot == index ? 0.9 : 0.25))
                    .frame(width: 4.5, height: 4.5)
                    .animation(.easeInOut(duration: 0.4), value: activeDot)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState
    let onStopButtonPressed: () -> Void

    private let leadingAccessoryWidth: CGFloat = 24
    private let trailingAccessoryWidth: CGFloat = 32

    private var showsLiveRecordingContent: Bool {
        state.phase == .recording || (state.phase == .transcribing && !state.showsTranscribingSpinner)
    }

    private var showsStopButton: Bool {
        showsLiveRecordingContent && state.recordingTriggerMode == .toggle
    }

    var body: some View {
        Group {
            if state.phase == .feedback {
                FailureIndicatorView()
            } else {
                ZStack {
                    Group {
                        if state.phase == .initializing {
                            InitializingDotsView()
                                .transition(.opacity)
                        } else if showsLiveRecordingContent {
                            WaveformView(audioLevel: state.audioLevel)
                                .transition(.opacity)
                        } else {
                            ProcessingWaveformView()
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }

                    HStack {
                        Group {
                            if state.isCommandMode {
                                CommandModeIndicator()
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                        .frame(width: leadingAccessoryWidth, alignment: .center)
                        .frame(maxHeight: .infinity, alignment: .center)

                        Spacer(minLength: 0)

                        Group {
                            if showsStopButton {
                                Button(action: onStopButtonPressed) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Color.red.opacity(0.92)))
                                }
                                .buttonStyle(.plain)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(width: trailingAccessoryWidth, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.phase)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.recordingTriggerMode)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.isCommandMode)
    }
}

// MARK: - Transcribing Indicator

struct CommandModeIndicator: View {
    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 16, height: 16, alignment: .center)
    }
}

struct FailureIndicatorView: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.red.opacity(0.92)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
