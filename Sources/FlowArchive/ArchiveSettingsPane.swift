import AppKit
import SwiftUI

struct ArchiveSettingsPane: View {
    @ObservedObject var archive: ArchiveService
    @ObservedObject var settings: ArchiveSettings

    init(archive: ArchiveService) {
        self.archive = archive
        self._settings = ObservedObject(wrappedValue: archive.settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Archive")
                    .font(.largeTitle.bold())

                archiveCard("Ingest", icon: "externaldrive") {
                    Toggle("Archive recordings from a Sony recorder", isOn: enabledBinding)
                    Toggle("Watch Inbox/_drop for files dropped manually", isOn: dropBinding)
                    Text("When a matching USB volume mounts, new audio is copied, transcribed, and filed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                archiveCard("Backup destination", icon: "icloud") {
                    Picker("Save archive to", selection: providerBinding) {
                        ForEach(CloudProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .onChange(of: settings.provider) { provider in
                        if provider == .custom || (provider == .idrive && archive.destinationMissing) {
                            archive.chooseDestinationFolder(provider: provider)
                        } else {
                            archive.refreshDestination()
                            archive.refreshLibrary()
                        }
                    }

                    HStack {
                        Text("Current: \(archive.destinationLabel)")
                            .font(.caption)
                            .foregroundStyle(archive.destinationMissing ? .orange : .secondary)
                        Spacer()
                        Button("Choose Folder…") {
                            archive.chooseDestinationFolder(provider: settings.provider)
                        }
                    }

                    if let root = archive.resolveLibraryRoot() {
                        Text(root.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                archiveCard("Recorder", icon: "waveform") {
                    TextField("Extra volume names (comma-separated)", text: extraNamesBinding)
                    Text("Matches IC RECORDER, RECORDER, RECORDS, plus any names listed here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Audio extensions", text: extensionsBinding)
                }

                archiveCard("Folder rules", icon: "folder.badge.gearshape") {
                    Text("If a tag or spoken keyword matches, the note is filed in that folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(settings.folderRules.enumerated()), id: \.element.id) { index, _ in
                        HStack {
                            TextField("Keyword or tag", text: ruleKeywordBinding(index))
                            TextField("Folder (e.g. Projects/Project X)", text: ruleFolderBinding(index))
                            Button(role: .destructive) {
                                var rules = settings.folderRules
                                rules.remove(at: index)
                                settings.folderRules = rules
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("Add Rule") {
                        settings.folderRules.append(FolderRule(keyword: "", folder: "Projects"))
                    }
                }

                archiveCard("Organizer prompt", icon: "text.bubble") {
                    TextEditor(text: promptBinding)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                    Button("Reset to Default") {
                        settings.organizerPrompt = ArchiveSettings.defaultOrganizerPrompt
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.enabled },
            set: { settings.enabled = $0 }
        )
    }

    private var dropBinding: Binding<Bool> {
        Binding(
            get: { settings.dropFolderEnabled },
            set: {
                settings.dropFolderEnabled = $0
                archive.refreshDestination()
            }
        )
    }

    private var providerBinding: Binding<CloudProvider> {
        Binding(
            get: { settings.provider },
            set: { settings.provider = $0 }
        )
    }

    private var extraNamesBinding: Binding<String> {
        Binding(
            get: { settings.extraVolumeNames },
            set: { settings.extraVolumeNames = $0 }
        )
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { settings.audioExtensions },
            set: { settings.audioExtensions = $0 }
        )
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { settings.organizerPrompt },
            set: { settings.organizerPrompt = $0 }
        )
    }

    private func ruleKeywordBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { settings.folderRules[index].keyword },
            set: {
                var rules = settings.folderRules
                guard rules.indices.contains(index) else { return }
                rules[index].keyword = $0
                settings.folderRules = rules
            }
        )
    }

    private func ruleFolderBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { settings.folderRules[index].folder },
            set: {
                var rules = settings.folderRules
                guard rules.indices.contains(index) else { return }
                rules[index].folder = $0
                settings.folderRules = rules
            }
        )
    }

    private func archiveCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
