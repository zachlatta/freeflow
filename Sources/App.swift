import SwiftUI

@main
struct FreeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
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
