import AppKit
import SwiftUI

struct BrowserSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var statuses: [BrowserIntegrationStatus] = []
    @State private var errorMessage: String?
    @State private var copiedPath = false
    @State private var isInstallingAll = false

    private let installer = BrowserIntegrationInstaller()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save from Chromium")
                        .font(.title2.weight(.semibold))
                    Text("A one-time, two-part setup connects the extension to this Mac app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    setupStep(number: 1, title: "Install the native bridge") {
                        Text("This lets the browser hand visual captures to mood. It writes a small manifest into each browser’s user profile.")
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(statuses, id: \.browser) { status in
                                browserRow(status)
                                if status.browser != statuses.last?.browser { Divider() }
                            }
                        }
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            installAll()
                        } label: {
                            if isInstallingAll {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Install for all browsers", systemImage: "puzzlepiece.extension")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isInstallingAll || statuses.isEmpty)
                    }

                    setupStep(number: 2, title: "Load the mood. extension") {
                        Text("In your browser, open its Extensions page, enable Developer mode, choose “Load unpacked,” then select this folder:")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text(extensionDirectory?.path ?? "Extension resources are missing from this build")
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                copyExtensionPath()
                            } label: {
                                Label(copiedPath ? "Copied" : "Copy", systemImage: copiedPath ? "checkmark" : "doc.on.doc")
                            }
                            .disabled(extensionDirectory == nil)

                            Button("Show in Finder") {
                                if let extensionDirectory {
                                    NSWorkspace.shared.activateFileViewerSelecting([extensionDirectory])
                                }
                            }
                            .disabled(extensionDirectory == nil)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        Label("Pin the extension for one-click saves. On X, mood. also appears beside each post and follows X’s Bookmark button.", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 650, height: 650)
        .onAppear { refresh() }
    }

    private func setupStep<Content: View>(
        number: Int,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func browserRow(_ status: BrowserIntegrationStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.isOperational ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status.isOperational ? .green : .secondary)
            Text(status.browser.displayName)
            Spacer()
            Text(statusLabel(status))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !status.isOperational {
                Button("Install") { install(status.browser) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private func statusLabel(_ status: BrowserIntegrationStatus) -> String {
        if status.isOperational { return "Ready" }
        switch status.helperState {
        case .missing: return "Helper missing"
        case .notExecutable: return "Helper not executable"
        case .available: break
        }
        switch status.manifestState {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed"
        case .updateRequired: return "Update available"
        case .conflict: return "Conflict"
        case .unreadable: return "Needs attention"
        }
    }

    private var extensionDirectory: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func refresh() {
        statuses = installer.statuses()
    }

    private func install(_ browser: ChromiumBrowser) {
        do {
            try installer.install(for: browser)
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func installAll() {
        isInstallingAll = true
        defer { isInstallingAll = false }
        do {
            for browser in ChromiumBrowser.allCases {
                try installer.install(for: browser)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func copyExtensionPath() {
        guard let extensionDirectory else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(extensionDirectory.path, forType: .string)
        copiedPath = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiedPath = false
        }
    }
}
