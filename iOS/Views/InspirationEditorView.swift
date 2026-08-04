import PinaxCore
import SwiftUI

struct InspirationEditorView: View {
    let inspiration: Inspiration
    let projects: [Project]
    let onSave: (Inspiration) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String
    @State private var rawURL: String
    @State private var projectID: Project.ID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case note
        case url
    }

    init(
        inspiration: Inspiration,
        projects: [Project],
        onSave: @escaping (Inspiration) async throws -> Void
    ) {
        self.inspiration = inspiration
        self.projects = projects
        self.onSave = onSave
        _title = State(initialValue: inspiration.title)
        _note = State(initialValue: inspiration.text)
        _rawURL = State(initialValue: inspiration.url.absoluteString)
        _projectID = State(initialValue: inspiration.projectID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Moodboard item") {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focusedField, equals: .note)
                }

                Section("Original link") {
                    TextField("https://…", text: $rawURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                }

                Section("Collection") {
                    ProjectPicker(projectID: $projectID, projects: projects)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || validatedURL == nil)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { focusedField = .title }
        }
    }

    private var validatedURL: URL? {
        CaptureURL.validatedWebURL(rawURL)
    }

    @MainActor
    private func save() async {
        guard let url = validatedURL else {
            errorMessage = "Enter a complete HTTP or HTTPS link."
            focusedField = .url
            return
        }

        var updated = inspiration
        updated.url = url
        updated.source = CaptureURL.source(for: url)
        updated.title = title
        updated.text = note
        updated.projectID = projectID

        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProjectPicker: View {
    @Binding var projectID: Project.ID?
    let projects: [Project]

    var body: some View {
        Picker("Collection", selection: $projectID) {
            Label("General", systemImage: "tray.full")
                .tag(Project.ID?.none)
            ForEach(projects) { project in
                Label(project.name, systemImage: "folder.fill")
                    .tag(Project.ID?.some(project.id))
            }
        }
    }
}
