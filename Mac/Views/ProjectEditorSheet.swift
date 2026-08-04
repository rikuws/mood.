import PinaxCore
import SwiftUI

struct ProjectEditorSheet: View {
    let existingProject: Project?
    let onSave: (String, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private let colors = ["#5E5CE6", "#007AFF", "#30B0C7", "#34C759", "#FF9F0A", "#FF375F", "#AF52DE"]

    init(existingProject: Project? = nil, onSave: @escaping (String, String?) async throws -> Void) {
        self.existingProject = existingProject
        self.onSave = onSave
        _name = State(initialValue: existingProject?.name ?? "")
        _selectedColor = State(initialValue: existingProject?.colorHex ?? "#5E5CE6")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(existingProject == nil ? "New project" : "Edit project")
                .font(.title2.weight(.semibold))

            TextField("Project name", text: $name)
                .focused($isNameFocused)
                .onSubmit { Task { await save() } }

            VStack(alignment: .leading, spacing: 9) {
                Text("Color").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            selectedColor = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if selectedColor == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Project color \(hex)")
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || isSaving)
            }
        }
        .padding(22)
        .frame(width: 390)
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func save() async {
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(trimmedName, selectedColor)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
