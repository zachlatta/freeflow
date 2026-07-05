import AppKit
import SwiftUI

@main
struct FreeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var notificationManager = VocabularyNotificationManager.shared

    /// Rolling window of recent input levels rendered as the live
    /// menu bar waveform while recording.
    @State private var levelHistory: [Float] = Array(repeating: 0, count: 5)

    var body: some View {
        HStack(spacing: 4) {
            if notificationManager.showCheckmark {
                Image(systemName: "checkmark")
            }
            if appState.isRecording {
                Image(nsImage: LiveWaveMenuBarIcon.image(levels: levelHistory))
                    .renderingMode(.template)
            } else if appState.isTranscribing {
                Image(systemName: "ellipsis.circle")
            } else if AppBuild.isDevBundle {
                Image(nsImage: StampedMenuBarIcon.templateImage)
                    .renderingMode(.template)
            } else {
                Image(systemName: "waveform")
            }
        }
        .onChange(of: appState.menuBarAudioLevel) { level in
            guard appState.isRecording else { return }
            levelHistory.removeFirst()
            levelHistory.append(level)
        }
        .onChange(of: appState.isRecording) { recording in
            if !recording {
                levelHistory = Array(repeating: 0, count: 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notificationManager.showCheckmark)
    }
}

/// Renders the recording-state menu bar icon: a bar per recent level
/// sample, so the icon itself moves with the user's voice. Template
/// image, so it stays legible in light and dark menu bars.
enum LiveWaveMenuBarIcon {
    static func image(levels: [Float]) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let barWidth: CGFloat = 2
        let spacing: CGFloat = 1.5
        let image = NSImage(size: size, flipped: false) { rect in
            let count = CGFloat(levels.count)
            let totalWidth = count * barWidth + (count - 1) * spacing
            var x = (rect.width - totalWidth) / 2
            NSColor.black.setFill()
            for level in levels {
                let clamped = CGFloat(min(max(level, 0), 1))
                let height = 3 + clamped * 10
                let y = (rect.height - height) / 2
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: y, width: barWidth, height: height),
                    xRadius: barWidth / 2, yRadius: barWidth / 2
                ).fill()
                x += barWidth + spacing
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum StampedMenuBarIcon {
    static let templateImage: NSImage = {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.append(NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3))
            let bars: [(x: CGFloat, y: CGFloat, h: CGFloat)] = [
                (3.0,  7.0,  2.0),
                (5.5,  5.0,  6.0),
                (8.0,  3.0, 10.0),
                (10.5, 4.0,  8.0),
                (13.0, 6.0,  4.0),
            ]
            for bar in bars {
                path.append(NSBezierPath(
                    roundedRect: NSRect(x: bar.x, y: bar.y, width: 1.5, height: bar.h),
                    xRadius: 0.75, yRadius: 0.75
                ))
            }
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
