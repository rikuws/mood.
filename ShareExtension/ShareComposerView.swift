import PinaxCore
import SwiftUI

struct ShareComposerView: View {
    @Bindable var model: ShareComposerModel
    let onCancel: @MainActor () -> Void
    let onComplete: @MainActor () -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case note
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    loadingView
                case .ready:
                    editor
                case .extractionFailed(let message):
                    failureView(message)
                }
            }
            .navigationTitle(Text(ProductIdentity.saveActionTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(ProductIdentity.saveActionTitle)
                        .font(.headline)
                        .accessibilityLabel(Text(ProductIdentity.saveActionSpokenLabel))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Saving")
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
        .interactiveDismissDisabled(model.isSaving)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Preparing your visual…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var editor: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    preview

                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            model.sourceLabel,
                            systemImage: model.source == .x ? "bubble.left.fill" : "globe"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text(model.url?.host() ?? "Shared link")
                            .font(.headline)
                            .lineLimit(2)

                        Text(model.url?.absoluteString ?? "")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Title") {
                TextField("Visual title", text: $model.title, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .note }
            }

            Section("Note") {
                TextField("What do you want to remember?", text: $model.note, axis: .vertical)
                    .lineLimit(3...7)
                    .focused($focusedField, equals: .note)
            }

            Section("Collection") {
                Picker("Save to", selection: $model.projectID) {
                    Label("General", systemImage: "tray.full")
                        .tag(Project.ID?.none)
                    ForEach(model.projects) { project in
                        Label(project.name, systemImage: "folder.fill")
                            .tag(Project.ID?.some(project.id))
                    }
                }
            }

            if let storageErrorMessage = model.storageErrorMessage {
                Section {
                    Label {
                        Text(storageErrorMessage)
                    } icon: {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Storage error. \(storageErrorMessage)")
                }
            }

            if let saveErrorMessage = model.saveErrorMessage {
                Section {
                    Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var preview: some View {
        if let image = model.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Shared image preview")
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .frame(width: 84, height: 84)
                .overlay {
                    Image(systemName: model.source == .x ? "quote.bubble.fill" : "safari.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Link preview")
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't read this share", systemImage: "link.badge.plus")
        } description: {
            Text(message)
            Text("Try sharing the post's link from X using Share via… and choose Save to mood.")
        } actions: {
            Button("Close", action: onCancel)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    @MainActor
    private func save() async {
        if await model.save() {
            onComplete()
        }
    }
}
