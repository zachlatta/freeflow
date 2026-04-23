import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Primed session duration")
                            Spacer()
                            Text("\(Int(store.primedDurationMinutes)) min")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $store.primedDurationMinutes, in: 1...15, step: 1)
                    }
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("After the first mic tap in the keyboard, FreeFlow primes an audio session and stays ready for this long. Longer = fewer app-switch hops; shorter = less background battery use.")
                }

                Section("Provider") {
                    TextField("Base URL", text: $store.apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Transcription model", text: $store.transcriptionModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Post-processing model", text: $store.postProcessingModel, prompt: Text("openai/gpt-oss-20b"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Fallback model", text: $store.postProcessingFallbackModel, prompt: Text("meta-llama/llama-4-scout-17b-16e-instruct"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    NavigationLink("Custom system prompt") { PromptEditorView() }
                    NavigationLink("Custom vocabulary") { VocabularyEditorView() }
                    NavigationLink("Voice macros") { VoiceMacrosView() }
                } header: {
                    Text("Cleanup")
                } footer: {
                    Text("Custom prompt overrides the default cleanup behavior. Leave empty to use the built-in prompt (updated \(Prompts.defaultSystemPromptDate)).")
                }

                Section("API key") {
                    SecureField("gsk_...", text: $store.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Validate key") {
                        Task { await store.validateApiKey() }
                    }
                }

                Section {
                    Button("Save all changes") { store.persistAll() }
                }
            }
            .navigationTitle("Settings")
            .onDisappear { store.persistAll() }
        }
    }
}

struct PromptEditorView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft: String = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $draft)
                    .frame(minHeight: 400)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("System prompt")
            } footer: {
                Text("Last modified: \(store.resolvedSystemPromptLastModified()). Leave empty to use the default.")
            }
            Section {
                Button("Reset to default") {
                    draft = Prompts.defaultSystemPrompt
                }
                Button("Clear (use default)") {
                    draft = ""
                }
                Button("Save") {
                    store.customSystemPrompt = draft
                    store.persistAll()
                }
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("System Prompt")
        .onAppear {
            draft = store.customSystemPrompt.isEmpty ? Prompts.defaultSystemPrompt : store.customSystemPrompt
        }
    }
}

struct VocabularyEditorView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Form {
            Section {
                TextEditor(text: $store.customVocabulary)
                    .frame(minHeight: 220)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Custom vocabulary")
            } footer: {
                Text("One term per line, or comma/semicolon separated. Used as a spelling reference during cleanup.")
            }
            Section {
                Button("Save") { store.persistAll() }
                    .fontWeight(.semibold)
            }
        }
        .navigationTitle("Vocabulary")
    }
}

struct VoiceMacrosView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: VoiceMacro?
    @State private var showEditor = false

    var body: some View {
        List {
            Section {
                if store.voiceMacros.isEmpty {
                    Text("No voice macros yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.voiceMacros) { macro in
                        Button {
                            editing = macro
                            showEditor = true
                        } label: {
                            VStack(alignment: .leading) {
                                Text(macro.command)
                                    .font(.headline)
                                Text(macro.payload)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        store.voiceMacros.remove(atOffsets: indexSet)
                        store.persistAll()
                    }
                }
            } footer: {
                Text("When the transcript exactly matches a macro command (case and punctuation ignored), the payload is inserted instead of the cleaned transcript.")
            }
        }
        .navigationTitle("Voice Macros")
        .toolbar {
            Button {
                editing = nil
                showEditor = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showEditor) {
            VoiceMacroEditorView(existing: editing) { macro in
                if let existing = editing, let index = store.voiceMacros.firstIndex(where: { $0.id == existing.id }) {
                    store.voiceMacros[index] = VoiceMacro(id: existing.id, command: macro.command, payload: macro.payload)
                } else {
                    store.voiceMacros.append(macro)
                }
                store.persistAll()
            }
        }
    }
}

struct VoiceMacroEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let existing: VoiceMacro?
    let onSave: (VoiceMacro) -> Void

    @State private var command: String = ""
    @State private var payload: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Command (spoken trigger)") {
                    TextField("e.g. email me", text: $command)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Payload (inserted text)") {
                    TextEditor(text: $payload)
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(existing == nil ? "New Macro" : "Edit Macro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedCmd.isEmpty, !trimmedPayload.isEmpty else { return }
                        onSave(VoiceMacro(id: existing?.id ?? UUID(), command: trimmedCmd, payload: trimmedPayload))
                        dismiss()
                    }
                }
            }
            .onAppear {
                command = existing?.command ?? ""
                payload = existing?.payload ?? ""
            }
        }
    }
}
