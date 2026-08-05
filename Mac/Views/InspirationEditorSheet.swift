import PinaxCore
import SwiftUI

struct InspirationEditorSheet: View {
    let inspiration: Inspiration
    let projects: [Project]
    let onSave: (Inspiration) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Inspiration
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field { case title, note }

    init(inspiration: Inspiration, projects: [Project], onSave: @escaping (Inspiration) async throws -> Void) {
        self.inspiration = inspiration
        self.projects = projects
        self.onSave = onSave
        _draft = State(initialValue: inspiration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit moodboard item")
                .font(.title2.weight(.semibold))
                .padding(22)

            Divider()

            Form {
                TextField("Title", text: $draft.title)
                    .focused($focusedField, equals: .title)
                TextField("Note", text: $draft.text, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focusedField, equals: .note)
                Picker("Collection", selection: $draft.projectID) {
                    Text("General").tag(Project.ID?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Project.ID?.some(project.id))
                    }
                }
                LabeledContent("Original link") {
                    Text(draft.url.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(draft.url.absoluteString)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
            .padding(16)
        }
        .frame(width: 500, height: 420)
        .onAppear { focusedField = .title }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
