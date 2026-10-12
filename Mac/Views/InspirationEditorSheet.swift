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

    private enum Field { case title, description, note }

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
                TextField("Description", text: $draft.text, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focusedField, equals: .description)
                TextField(
                    "Your note",
                    text: noteBinding,
                    prompt: Text("Why did you save this?"),
                    axis: .vertical
                )
                .lineLimit(2...6)
                .focused($focusedField, equals: .note)
                Picker("Verdict", selection: $draft.verdict) {
                    Text("Undecided").tag(InspirationVerdict?.none)
                    Text("Keep").tag(InspirationVerdict?.some(.keep))
                    Text("Reject").tag(InspirationVerdict?.some(.reject))
                }
                .pickerStyle(.segmented)
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
        .frame(width: 500, height: 520)
        .onAppear { focusedField = .title }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { draft.note ?? "" },
            set: { draft.note = $0 }
        )
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
