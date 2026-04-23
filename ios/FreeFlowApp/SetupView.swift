import SwiftUI
import AVFoundation

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @State private var isValidating = false
    @State private var microphoneGranted: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("FreeFlow lets you dictate into any iOS app through a custom keyboard. Complete the three steps below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("1. Groq API Key") {
                    Link("Create a free Groq API key", destination: URL(string: "https://console.groq.com/keys")!)
                    SecureField("gsk_...", text: $store.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: store.apiKey) { _, _ in
                            store.persistApiKey()
                            store.apiKeyValid = nil
                        }
                    HStack {
                        Button(isValidating ? "Validating…" : "Validate key") {
                            Task {
                                isValidating = true
                                await store.validateApiKey()
                                isValidating = false
                            }
                        }
                        .disabled(store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                        Spacer()
                        if let valid = store.apiKeyValid {
                            if valid {
                                Label("Valid", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Invalid", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("2. Microphone access") {
                    HStack {
                        Text(microphoneGranted ? "Microphone granted" : "Microphone not yet granted")
                        Spacer()
                        if microphoneGranted {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Request") { requestMicrophone() }
                        }
                    }
                    Text("FreeFlow records your voice and sends the audio to Groq for transcription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("3. Enable the FreeFlow keyboard") {
                    Text("""
Open iOS **Settings → General → Keyboard → Keyboards → Add New Keyboard…** and pick **FreeFlow**. Then tap the FreeFlow row and turn on **Allow Full Access**.

Full Access is required so the keyboard can reach Groq over the network and use the microphone.
""")
                    .font(.footnote)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("How to use") {
                    Text("""
1. Open any app with a text field (Notes, Messages, Safari).
2. Tap the keyboard globe button until the FreeFlow keyboard appears.
3. Tap the mic button to start recording, tap again to stop.
4. The cleaned transcript is inserted at the cursor.
""")
                    .font(.footnote)
                }
            }
            .navigationTitle("FreeFlow Setup")
            .onAppear { refreshMicrophoneStatus() }
        }
    }

    private func refreshMicrophoneStatus() {
        if #available(iOS 17.0, *) {
            microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        } else {
            microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        }
    }

    private func requestMicrophone() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { microphoneGranted = granted }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { microphoneGranted = granted }
            }
        }
    }
}
