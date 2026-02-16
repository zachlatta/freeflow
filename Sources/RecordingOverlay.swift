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

/// Creates a container with a vibrancy blur layer and a SwiftUI overlay for the liquid glass effect.
private func makeGlassContent<V: View>(
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat,
    maskedCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner],
    rootView: V
) -> NSView {
    let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0

    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    container.wantsLayer = true
    container.layer?.contentsScale = scaleFactor

    let blur = NSVisualEffectView(frame: container.bounds)
    blur.appearance = NSAppearance(named: .darkAqua)
    blur.material = .hudWindow
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.contentsScale = scaleFactor
    blur.layer?.cornerRadius = cornerRadius
    blur.layer?.maskedCorners = maskedCorners
    blur.layer?.masksToBounds = true
    blur.autoresizingMask = [.width, .height]
    container.addSubview(blur)

    let hosting = NSHostingView(rootView: rootView)
    hosting.frame = container.bounds
    hosting.autoresizingMask = [.width, .height]
    hosting.layer?.contentsScale = scaleFactor
    container.addSubview(hosting)

    return container
}

// MARK: - Manager

class RecordingOverlayManager {
    private var overlayWindow: NSPanel?
    private var transcribingPanel: NSPanel?
    private var overlayState = RecordingOverlayState()

    /// Whether the main screen has a camera housing (notch).
    private var screenHasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

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

        let panelWidth: CGFloat = 120
        let panelHeight: CGFloat = 32

        let hasNotch = screenHasNotch
        let notchInset: CGFloat = 4 // tuck flat top behind menu bar (notch screens only)

        if let panel = overlayWindow {
            guard let screen = NSScreen.main else { return }
            let x = panelX(screen, width: panelWidth)
            let y: CGFloat
            if hasNotch {
                y = screen.visibleFrame.maxY - panelHeight + notchInset
            } else {
                y = screen.frame.maxY - panelHeight
            }
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let panel = makeOverlayPanel(width: panelWidth, height: panelHeight)

        let view = RecordingOverlayView(state: overlayState)
        panel.contentView = makeGlassContent(
            width: panelWidth,
            height: panelHeight,
            cornerRadius: 12,
            maskedCorners: [.layerMinXMinYCorner, .layerMaxXMinYCorner],
            rootView: view
        )

        if let screen = NSScreen.main {
            let x = panelX(screen, width: panelWidth)
            let hiddenY: CGFloat
            let visibleY: CGFloat
            if hasNotch {
                // Start hidden behind menu bar, pop out from notch
                hiddenY = screen.visibleFrame.maxY
                visibleY = screen.visibleFrame.maxY - panelHeight + notchInset
            } else {
                // Start hidden above screen top, pop in from very top
                hiddenY = screen.frame.maxY
                visibleY = screen.frame.maxY - panelHeight
            }

            panel.setFrame(NSRect(x: x, y: hiddenY, width: panelWidth, height: panelHeight), display: true)
            panel.alphaValue = 1
            panel.orderFrontRegardless()

            // Spring-like drop: overshoots slightly then settles
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
                panel.animator().setFrame(NSRect(x: x, y: visibleY, width: panelWidth, height: panelHeight), display: true)
            }
        }

        self.overlayWindow = panel
    }

    private func _slideUpToNotch(completion: @escaping () -> Void) {
        guard let panel = overlayWindow, let screen = NSScreen.main else {
            completion()
            return
        }

        let hiddenY = screenHasNotch ? screen.visibleFrame.maxY : screen.frame.maxY
        let frame = panel.frame

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
            panel.animator().setFrame(NSRect(x: frame.origin.x, y: hiddenY, width: frame.width, height: frame.height), display: true)
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
        panel.contentView = makeGlassContent(
            width: panelWidth,
            height: panelHeight,
            cornerRadius: 11,
            maskedCorners: [.layerMinXMinYCorner, .layerMaxXMinYCorner],
            rootView: view
        )

        if let screen = NSScreen.main {
            let x = panelX(screen, width: panelWidth)
            let y: CGFloat
            if screenHasNotch {
                y = screen.visibleFrame.maxY - panelHeight
            } else {
                y = screen.frame.maxY - panelHeight
            }
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

// MARK: - Liquid Glass Overlay

/// Decorative layers on top of the NSVisualEffectView blur to create a liquid glass appearance:
/// a specular highlight gradient and a gradient border that's brighter where light hits.
private struct LiquidGlassOverlay<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        ZStack {
            // Dark tint over the blur for a deeper glass look
            shape
                .fill(.black.opacity(0.45))

            // Specular highlight — subtle light refraction at the top
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.12), location: 0),
                            .init(color: .white.opacity(0.03), location: 0.35),
                            .init(color: .clear, location: 0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Glass edge — gradient border, brighter at top
            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.35), location: 0),
                            .init(color: .white.opacity(0.1), location: 0.5),
                            .init(color: .white.opacity(0.04), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
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
            .fill(
                LinearGradient(
                    colors: [.white, .white.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformView: View {
    let audioLevel: Float

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index))
                    .animation(
                        .interpolatingSpring(stiffness: 600, damping: 28),
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
}

// MARK: - Recording Overlay View

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState

    var body: some View {
        WaveformView(audioLevel: state.audioLevel)
            .frame(width: 100, height: 20)
            .frame(width: 120, height: 32)
            .background(LiquidGlassOverlay(shape: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)))
    }
}

// MARK: - Transcribing Indicator

struct TranscribingIndicatorView: View {
    @State private var animatingDot = 0
    @State private var dotAnimationTimer: Timer?

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
            LiquidGlassOverlay(shape: UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11))
        )
        .onAppear { startDotAnimation() }
        .onDisappear { stopDotAnimation() }
    }

    private func startDotAnimation() {
        dotAnimationTimer?.invalidate()
        dotAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }

    private func stopDotAnimation() {
        dotAnimationTimer?.invalidate()
        dotAnimationTimer = nil
    }
}
