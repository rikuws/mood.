import PinaxCore
import SwiftUI

struct IOSInspirationDetailView: View {
    @Bindable var store: LibraryStore
    let inspirationID: Inspiration.ID
    let onMutation: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editor: Inspiration?
    @State private var isConfirmingDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let inspiration {
                detail(inspiration)
            } else {
                ContentUnavailableView(
                    "Item unavailable",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("It may have been removed from mood. on another device.")
                )
            }
        }
        .navigationTitle("Moodboard item")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.pinaxPlum)
        .toolbar {
            if let inspiration {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: inspiration.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share moodboard item")

                    Menu {
                        Button {
                            editor = inspiration
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        moveMenu(inspiration)

                        Divider()
                        Button(role: .destructive) {
                            isConfirmingDeletion = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More actions")
                }
            }
        }
        .sheet(item: $editor) { inspiration in
            InspirationEditorView(
                inspiration: inspiration,
                projects: store.projects
            ) { updated in
                _ = try await store.updateInspiration(updated)
                onMutation()
            }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteInspiration() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the item from your moodboard.")
        }
        .alert(
            "Couldn't update item",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    @ViewBuilder
    private func detail(_ inspiration: Inspiration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InspirationImageView(
                    inspiration: inspiration,
                    localImageURL: store.localImageURL(for: inspiration),
                    contentMode: .fit,
                    showsFallbackMetadata: inspiration.source != .x
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 250, idealHeight: 360, maxHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 10) {
                    Text(displayTitle(for: inspiration))
                        .font(.system(.title2, design: .serif, weight: .bold))
                        .textSelection(.enabled)

                    if let byline = byline(for: inspiration) {
                        Text(byline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if !inspiration.text.isEmpty, inspiration.text != inspiration.title {
                        Text(inspiration.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }

                metadata(for: inspiration)

                Button {
                    openURL(inspiration.url)
                } label: {
                    Label("Open original", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens \(inspiration.url.host() ?? "the original website")")
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pinaxCanvas)
    }

    private func metadata(for inspiration: Inspiration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(project(for: inspiration)?.name ?? "General")
            } icon: {
                Image(systemName: project(for: inspiration) == nil ? "tray.full" : "folder.fill")
                    .foregroundStyle(
                        project(for: inspiration).map { Color(pinaxHex: $0.colorHex) }
                            ?? .secondary
                    )
            }

            Label(
                inspiration.createdAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "calendar"
            )

            Label(inspiration.url.host() ?? inspiration.url.absoluteString, systemImage: "link")
                .lineLimit(1)

            if inspiration.captureCount > 1 {
                Label("Saved \(inspiration.captureCount) times", systemImage: "square.stack.3d.up")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pinaxCardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func moveMenu(_ inspiration: Inspiration) -> some View {
        Menu {
            Button {
                move(inspiration, to: nil)
            } label: {
                if inspiration.projectID == nil {
                    Label("General", systemImage: "checkmark")
                } else {
                    Text("General")
                }
            }

            ForEach(store.projects) { project in
                Button {
                    move(inspiration, to: project.id)
                } label: {
                    if inspiration.projectID == project.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }
    }

    private var inspiration: Inspiration? {
        store.snapshot.inspiration(id: inspirationID)
    }

    private func project(for inspiration: Inspiration) -> Project? {
        inspiration.projectID.flatMap(store.snapshot.project(id:))
    }

    private func displayTitle(for inspiration: Inspiration) -> String {
        if inspiration.source == .x {
            return inspiration.xUsernameLabel ?? "X"
        }
        if !inspiration.title.isEmpty { return inspiration.title }
        if !inspiration.text.isEmpty { return inspiration.text }
        return inspiration.url.host() ?? "Untitled item"
    }

    private func byline(for inspiration: Inspiration) -> String? {
        guard inspiration.source != .x else { return nil }
        if let name = inspiration.authorName, let handle = inspiration.authorHandle {
            return "\(name) · @\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        }
        if let name = inspiration.authorName { return name }
        if let handle = inspiration.authorHandle {
            return "@\(handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))"
        }
        return nil
    }

    private func move(_ inspiration: Inspiration, to projectID: Project.ID?) {
        guard inspiration.projectID != projectID else { return }
        Task { @MainActor in
            do {
                _ = try await store.moveInspiration(id: inspiration.id, to: projectID)
                onMutation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func deleteInspiration() async {
        do {
            _ = try await store.deleteInspiration(id: inspirationID)
            onMutation()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
