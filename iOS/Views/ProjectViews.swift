import PinaxCore
import SwiftUI

struct ProjectManagerView: View {
    @Bindable var store: LibraryStore
    let onMutation: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editor: ProjectEditorDestination?
    @State private var projectToDelete: Project?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No projects yet", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Projects keep inspiration for a product, brand, or idea together.")
                    } actions: {
                        Button("Create Project") { editor = .new }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.projects) { project in
                        projectRow(project)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    projectToDelete = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editor = .edit(project)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.accentColor)
                            }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .accessibilityLabel("New project")
                }
            }
            .sheet(item: $editor) { destination in
                ProjectEditorView(existingProject: destination.project) { name, colorHex in
                    switch destination {
                    case .new:
                        _ = try await store.createProject(name: name, colorHex: colorHex)
                    case .edit(let project):
                        _ = try await store.updateProject(
                            id: project.id,
                            name: name,
                            colorHex: colorHex
                        )
                    }
                    onMutation()
                }
            }
            .confirmationDialog(
                "Delete project?",
                isPresented: Binding(
                    get: { projectToDelete != nil },
                    set: { if !$0 { projectToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: projectToDelete
            ) { project in
                Button("Delete “\(project.name)”", role: .destructive) {
                    Task { await delete(project) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { project in
                Text("Its \(store.counts[project.id]) saved items will move to General.")
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            editor = .edit(project)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color(pinaxHex: project.colorHex))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .foregroundStyle(.primary)
                    Text("\(store.counts[project.id]) inspiration\(store.counts[project.id] == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edits this project")
    }

    @MainActor
    private func delete(_ project: Project) async {
        projectToDelete = nil
        do {
            _ = try await store.deleteProject(id: project.id)
            onMutation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum ProjectEditorDestination: Identifiable {
    case new
    case edit(Project)

    var id: String {
        switch self {
        case .new:
            "new"
        case .edit(let project):
            project.id.uuidString
        }
    }

    var project: Project? {
        switch self {
        case .new: nil
        case .edit(let project): project
        }
    }
}

struct ProjectEditorView: View {
    let existingProject: Project?
    let onSave: (String, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private let colors = [
        "#5E5CE6",
        "#007AFF",
        "#30B0C7",
        "#34C759",
        "#FF9F0A",
        "#FF375F",
        "#AF52DE",
    ]

    init(
        existingProject: Project? = nil,
        onSave: @escaping (String, String?) async throws -> Void
    ) {
        self.existingProject = existingProject
        self.onSave = onSave
        _name = State(initialValue: existingProject?.name ?? "")
        _selectedColor = State(initialValue: existingProject?.colorHex ?? "#5E5CE6")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Project name", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }

                Section("Color") {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                selectedColor = hex
                            } label: {
                                Circle()
                                    .fill(Color(pinaxHex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedColor == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Project color \(hex)")
                            .accessibilityAddTraits(selectedColor == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingProject == nil ? "New project" : "Edit project")
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
                    .disabled(trimmedName.isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { isNameFocused = true }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func save() async {
        guard !trimmedName.isEmpty, !isSaving else { return }
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
