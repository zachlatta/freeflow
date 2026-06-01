import SwiftUI

/// A reusable dropdown for selecting a model from predefined options,
/// or providing a custom model string if "Custom..." is chosen.
struct ModelDropdownView: View {
    let title: String
    let subtitle: String?
    let predefinedModels: [String]
    let defaultModel: String
    
    @Binding var textDraft: String
    let onCommit: () -> Void
    let onReset: () -> Void
    
    @State private var isCustom: Bool = false
    @FocusState private var isEditingCustom: Bool
    
    private var effectiveSelection: Binding<String> {
        Binding(
            get: {
                if predefinedModels.contains(textDraft) && !isCustom {
                    return textDraft
                } else {
                    return "Custom..."
                }
            },
            set: { newValue in
                if newValue == "Custom..." {
                    isCustom = true
                    if predefinedModels.contains(textDraft) {
                        textDraft = ""
                    }
                } else {
                    isCustom = false
                    textDraft = newValue
                    onCommit()
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            
            HStack(spacing: 8) {
                Picker("", selection: effectiveSelection) {
                    ForEach(predefinedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    Divider()
                    Text("Custom...").tag("Custom...")
                }
                .labelsHidden()
                
                if effectiveSelection.wrappedValue == "Custom..." {
                    TextField(defaultModel, text: $textDraft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingCustom)
                        .onSubmit {
                            onCommit()
                        }
                        .onChange(of: isEditingCustom) { isEditing in
                            if !isEditing {
                                onCommit()
                            }
                        }
                }
                
                Button("Reset to Default") {
                    isCustom = false
                    onReset()
                }
                .font(.caption)
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if !predefinedModels.contains(textDraft) && !textDraft.isEmpty {
                isCustom = true
            }
        }
        .onChange(of: textDraft) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                isCustom = !predefinedModels.contains(trimmed)
            }
        }
    }
}
