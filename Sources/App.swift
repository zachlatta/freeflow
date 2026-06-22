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
    }
}

@MainActor
struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var notificationManager = VocabularyNotificationManager.shared

    private var iconName: String {
        if appState.isRecording { return "record.circle" }
        if appState.isTranscribing { return "ellipsis.circle" }
        return "waveform"
    }

    var body: some View {
        HStack(spacing: 4) {
            if notificationManager.showCheckmark {
                Image(systemName: "checkmark")
            }
            if AppBuild.isDevBundle && !appState.isRecording && !appState.isTranscribing {
                Image(nsImage: StampedMenuBarIcon.templateImage)
                    .renderingMode(.template)
            } else {
                Image(systemName: iconName)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notificationManager.showCheckmark)
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
