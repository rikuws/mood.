import PinaxCore
import SwiftUI

struct CaptureSheet: View {
    let projects: [Project]
    let initialProjectID: Project.ID?
    let onCapture: (CapturePayload) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var title = ""
    @State private var note = ""
    @State private var projectID: Project.ID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case url, title, note
    }

    init(
        projects: [Project],
        initialProjectID: Project.ID?,
        onCapture: @escaping (CapturePayload) async throws -> Void
    ) {
        self.projects = projects
        self.initialProjectID = initialProjectID
        self.onCapture = onCapture
        _projectID = State(initialValue: initialProjectID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tint)
                Text(ProductIdentity.saveActionTitle)
                    .accessibilityLabel(Text(ProductIdentity.saveActionSpokenLabel))
                    .font(.title2.weight(.semibold))
                Text("Paste any page or X post. mood. keeps the original link and avoids duplicates.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(22)

            Divider()

            Form {
                TextField("URL", text: $urlText, prompt: Text("https://…"))
                    .textContentType(.URL)
                    .focused($focusedField, equals: .url)
                    .onSubmit { focusedField = .title }

                TextField("Title", text: $title, prompt: Text("Optional"))
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .note }

                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .note)

                Picker("Collection", selection: $projectID) {
                    Text("General").tag(Project.ID?.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Project.ID?.some(project.id))
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Divider()

            HStack {
                Text("⌘↩ to save")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || validatedURL == nil)
            }
            .padding(16)
        }
        .frame(width: 470)
        .onAppear { focusedField = .url }
    }

    private var validatedURL: URL? {
        guard let components = URLComponents(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        return components.url
    }

    @MainActor
    private func save() async {
        guard let url = validatedURL else {
            errorMessage = "Enter a complete HTTP or HTTPS link."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let source: CaptureSource = {
            let host = url.host()?.lowercased() ?? ""
            return host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com")
                ? .x
                : .web
        }()

        do {
            try await onCapture(
                CapturePayload(
                    source: source,
                    url: url,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    text: note.trimmingCharacters(in: .whitespacesAndNewlines),
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
