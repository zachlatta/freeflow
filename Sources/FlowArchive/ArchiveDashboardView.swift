import AVFoundation
import AppKit
import SwiftUI

struct ArchiveDashboardView: View {
    @ObservedObject var archive: ArchiveService

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            NavigationSplitView {
                sidebar
                    .frame(minWidth: 180)
            } content: {
                noteList
                    .frame(minWidth: 240)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 980, minHeight: 560)
        .onAppear {
            archive.refreshDestination()
            archive.refreshLibrary()
            if let audio = archive.selectedNote?.audioURL {
                archive.materialize(audio)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $archive.searchQuery)
                .textFieldStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(archive.destinationMissing ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(archive.destinationMissing
                     ? "\(archive.destinationLabel) unavailable — saving locally"
                     : archive.destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sidebar: some View {
        List(selection: $archive.selectedSidebar) {
            Section("Folders") {
                Label {
                    HStack {
                        Text("Inbox")
                        Spacer()
                        if archive.inboxCount > 0 {
                            Text("\(archive.inboxCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "tray")
                }
                .tag(ArchiveSidebarItem.inbox)

                Label("Today", systemImage: "calendar")
                    .tag(ArchiveSidebarItem.today)

                ForEach(archive.folderNames, id: \.self) { folder in
                    Label(folder, systemImage: "folder")
                        .tag(ArchiveSidebarItem.folder(folder))
                }
            }

            if !archive.tagNames.isEmpty {
                Section("Tags") {
                    ForEach(archive.tagNames, id: \.self) { tag in
                        Label("#\(tag)", systemImage: "tag")
                            .tag(ArchiveSidebarItem.tag(tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var noteList: some View {
        List(archive.filteredNotes, selection: $archive.selectedNoteID) { note in
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(Self.shortDate.string(from: note.date))  ·  \(note.durationLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !note.snippet.isEmpty {
                    Text(note.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .tag(note.id)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let note = archive.selectedNote {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.title2.bold())
                            Text("\(Self.longDate.string(from: note.date))  ·  \(note.durationLabel)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let audioURL = note.audioURL {
                            ArchiveAudioPlayer(url: audioURL, onAppear: {
                                archive.materialize(audioURL)
                            })
                        }
                    }

                    if !note.tags.isEmpty {
                        HStack {
                            Text("Tags:")
                                .foregroundStyle(.secondary)
                            ForEach(note.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Summary", systemImage: "sparkles")
                            .font(.headline)
                        ForEach(Array(note.summary.enumerated()), id: \.offset) { _, bullet in
                            Text("• \(bullet)")
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Transcript", systemImage: "text.alignleft")
                            .font(.headline)
                        Text(note.transcript.isEmpty ? "(no transcript)" : note.transcript)
                            .textSelection(.enabled)
                            .font(.body)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Label("File Location", systemImage: "folder")
                            .font(.headline)
                        Text(note.markdownURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Button("Reveal Markdown") {
                                archive.reveal(note.markdownURL)
                            }
                            if let audio = note.audioURL {
                                Button("Reveal Audio") {
                                    archive.reveal(audio)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No Note Selected")
                    .font(.headline)
                Text("Plug in a Sony recorder or drop audio into Inbox/_drop.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct ArchiveAudioPlayer: View {
    let url: URL
    var onAppear: () -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        Button {
            toggle()
        } label: {
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
        }
        .onAppear {
            onAppear()
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
        .onChange(of: url) { _ in
            player?.pause()
            player = AVPlayer(url: url)
            isPlaying = false
        }
    }

    private func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}
