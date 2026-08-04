import PinaxCore
import SwiftUI

struct ManualCaptureView: View {
    let projects: [Project]
    let onCapture: (CapturePayload) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rawURL = ""
    @State private var title = ""
    @State private var note = ""
    @State private var projectID: Project.ID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case url
        case title
        case note
    }

    init(
        projects: [Project],
        initialProjectID: Project.ID? = nil,
        onCapture: @escaping (CapturePayload) async throws -> Void
    ) {
        self.projects = projects
        self.onCapture = onCapture
        _projectID = State(initialValue: initialProjectID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://x.com/…", text: $rawURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .title }
                } header: {
                    Text("Link")
                } footer: {
                    Text("Paste any web link. X and Twitter links are recognized automatically.")
                }

                Section("Details (optional)") {
                    TextField("Title", text: $title)
                        .focused($focusedField, equals: .title)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...7)
                        .focused($focusedField, equals: .note)
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
            .navigationTitle("Save a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await capture() }
                    }
                    .disabled(isSaving || rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { focusedField = .url }
        }
    }

    private var validatedURL: URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = CaptureURL.validatedWebURL(trimmed) { return url }
        guard !trimmed.contains("://") else { return nil }
        return CaptureURL.validatedWebURL("https://\(trimmed)")
    }

    @MainActor
    private func capture() async {
        guard let url = validatedURL else {
            errorMessage = "Enter a complete web link."
            focusedField = .url
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await onCapture(
                CapturePayload(
                    source: CaptureURL.source(for: url),
                    url: url,
                    title: title,
                    text: note,
                    projectID: projectID,
                    assignProjectOnDuplicate: true,
                    overwriteMetadataOnDuplicate: true
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
