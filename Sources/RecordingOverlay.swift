import SwiftUI
import AppKit

// MARK: - State

class RecordingOverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .recording
    @Published var audioLevel: Float = 0.0
}

enum OverlayPhase {
    case recording
    case transcribing
    case done
}

// MARK: - Panel Helper

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

// MARK: - Manager

class RecordingOverlayManager {
    private var overlayWindow: NSPanel?
    private var transcribingPanel: NSPanel?
    private var overlayState = RecordingOverlayState()

    func showRecording() {
        DispatchQueue.main.async { self._showRecording() }
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async { self.overlayState.audioLevel = level }
    }

    func showTranscribing() {
        DispatchQueue.main.async { self._showTranscribing() }
    }

    func slideUpToNotch(completion: @escaping () -> Void) {
        DispatchQueue.main.async { self._slideUpToNotch(completion: completion) }
    }

    func showDone() {
        DispatchQueue.main.async { self._showDone() }
    }

    func dismiss() {
        DispatchQueue.main.async { self._dismiss() }
    }

    private func _showRecording() {
        overlayState.phase = .recording
        overlayState.audioLevel = 0.0

        let panelWidth: CGFloat = 200
        let panelHeight: CGFloat = 40

        if let panel = overlayWindow {
            guard let screen = NSScreen.main else { return }
            let x = panelX(screen, width: panelWidth)
            let y = screen.visibleFrame.maxY - panelHeight
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let panel = makeOverlayPanel(width: panelWidth, height: panelHeight)

        let view = RecordingOverlayView(state: overlayState)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let x = panelX(screen, width: panelWidth)
            let y = screen.visibleFrame.maxY - panelHeight

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
        }

        self.overlayWindow = panel
    }

    private func _slideUpToNotch(completion: @escaping () -> Void) {
        guard let panel = overlayWindow else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            self.overlayWindow = nil
            completion()
        })
    }

    private func _showTranscribing() {
        overlayState.phase = .transcribing

        if let panel = overlayWindow {
            panel.orderOut(nil)
            overlayWindow = nil
        }

        if transcribingPanel != nil { return }

        let panelWidth: CGFloat = 44
        let panelHeight: CGFloat = 22

        let panel = makeOverlayPanel(width: panelWidth, height: panelHeight)

        let view = TranscribingIndicatorView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let x = panelX(screen, width: panelWidth)
            let y = screen.visibleFrame.maxY - panelHeight
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }

        self.transcribingPanel = panel
    }

    private func _showDone() {
        overlayState.phase = .done

        if let panel = transcribingPanel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                self.transcribingPanel = nil
            })
        }
    }

    private func _dismiss() {
        if let panel = overlayWindow {
            panel.orderOut(nil)
            overlayWindow = nil
        }
        if let panel = transcribingPanel {
            panel.orderOut(nil)
            transcribingPanel = nil
        }
    }

    private func panelX(_ screen: NSScreen, width: CGFloat) -> CGFloat {
        screen.frame.midX - width / 2
    }
}

// MARK: - Glass Background

/// A Liquid Glass–style background: dark translucent fill with a subtle bright edge.
struct GlassBackground<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.black.opacity(0.55))
            .overlay(
                shape
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}

// MARK: - Waveform Views

struct WaveformBar: View {
    let amplitude: CGFloat

    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 16

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.9))
            .frame(width: 2.5, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformView: View {
    let audioLevel: Float

    private let multipliers: [CGFloat] = [0.5, 0.8, 1.0, 0.7, 0.45]
    private let delays: [Double] = [0.04, 0.02, 0.0, 0.03, 0.05]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index))
                    .animation(
                        .interpolatingSpring(stiffness: 300, damping: 15)
                            .delay(delays[index]),
                        value: audioLevel
                    )
            }
        }
        .frame(height: 16)
    }

    private func barAmplitude(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        return min(level * multipliers[index], 1.0)
    }
}

// MARK: - Recording Overlay View

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
                .shadow(color: .red.opacity(0.6), radius: 4)

            WaveformView(audioLevel: state.audioLevel)
                .frame(width: 70, height: 16)

            Spacer(minLength: 0)

            Text("Recording")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .frame(width: 200, height: 40)
        .background(GlassBackground(shape: Capsule()))
    }
}

// MARK: - Transcribing Indicator

struct TranscribingIndicatorView: View {
    @State private var animatingDot = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(animatingDot == index ? 0.9 : 0.25))
                    .frame(width: 4.5, height: 4.5)
                    .animation(.easeInOut(duration: 0.4), value: animatingDot)
            }
        }
        .frame(width: 44, height: 22)
        .background(
            GlassBackground(shape: UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11))
        )
        .onAppear { startDotAnimation() }
    }

    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }
}
