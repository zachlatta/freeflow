import SwiftUI

struct HistoryView: View {
    @State private var items: [PipelineHistoryItem] = []

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No dictations yet. Use the FreeFlow keyboard in another app and your history will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            HistoryDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.finalTranscript.isEmpty ? "(empty)" : item.finalTranscript)
                                    .lineLimit(2)
                                HStack {
                                    Text(item.createdAt, style: .time)
                                    Text("·")
                                    Text(item.modelUsed)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            PipelineHistoryStore.shared.remove(id: items[idx].id)
                        }
                        reload()
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                Button("Clear") {
                    PipelineHistoryStore.shared.clear()
                    reload()
                }
                .disabled(items.isEmpty)
            }
            .onAppear { reload() }
            .refreshable { reload() }
        }
    }

    private func reload() {
        items = PipelineHistoryStore.shared.all()
    }
}

struct HistoryDetailView: View {
    let item: PipelineHistoryItem

    var body: some View {
        Form {
            Section("Final output") {
                Text(item.finalTranscript.isEmpty ? "(empty)" : item.finalTranscript)
                    .textSelection(.enabled)
            }
            Section("Raw transcript") {
                Text(item.rawTranscript.isEmpty ? "(empty)" : item.rawTranscript)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Details") {
                LabeledContent("When", value: item.createdAt.formatted())
                LabeledContent("Transcription model", value: item.transcriptionModel)
                LabeledContent("Post-processing model", value: item.modelUsed)
                if !item.note.isEmpty {
                    LabeledContent("Note", value: item.note)
                }
            }
        }
        .navigationTitle("Dictation")
    }
}
