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

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        let icon: String = if appState.isRecording {
            "record.circle"
        } else if appState.isTranscribing {
            "ellipsis.circle"
        } else {
            "waveform"
        }
        Image(systemName: icon)
    }
}
