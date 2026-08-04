import Combine
import PinaxCloudSync
import PinaxCore
import SwiftUI

struct MacLibraryView: View {
    @Bindable var store: LibraryStore
    let syncCoordinator: PinaxSyncCoordinator?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedInspirationID: Inspiration.ID?
    @State private var sheet: SheetDestination?
    @State private var pendingInspirationDeletion: Inspiration?
    @State private var pendingProjectDeletion: Project?
    @State private var toast: ToastMessage?
    @State private var isDropTargeted = false
    @State private var isSidebarVisible = true
    @State private var canvasWidth: CGFloat = 0
    @State private var canvasGesturePresentation = MacCanvasGesturePresentation.inactive
    @State private var canvasInteractionPhase = MacCanvasInteractionPhase.idle
    @AppStorage("libraryCanvasZoom") private var canvasZoom = 0.5

    private static let defaultCanvasZoom = 0.5
    private let canvasHorizontalPadding: CGFloat = 20
    private let canvasSpacing: CGFloat = 16
    private let minimumCanvasCardWidth: CGFloat = 148
    private let maximumCanvasColumns = 8

    var body: some View {
        HSplitView {
            if isSidebarVisible {
                sidebar
                    .frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
                    .background(.bar)
            }

            HStack(spacing: 0) {
                libraryContent

                if let selectedInspiration {
                    Divider()
                    InspirationDetailView(
                        inspiration: selectedInspiration,
                        localImageURL: store.localImageURL(for: selectedInspiration),
                        project: selectedInspiration.projectID.flatMap(project(with:)),
                        projects: projects,
                        onMove: { projectID in move(selectedInspiration, to: projectID) },
                        onEdit: { sheet = .editInspiration(selectedInspiration) },
                        onDelete: { pendingInspirationDeletion = selectedInspiration },
                        onClose: {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                selectedInspirationID = nil
                            }
                        }
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity)
                    )
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.22),
                value: selectedInspirationID
            )
        }
        .navigationTitle(scopeTitle)
        .accentColor(PinaxCatalogPalette.accent(for: colorScheme))
        .tint(PinaxCatalogPalette.accent(for: colorScheme))
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search your moodboard")
        .toolbar { toolbar }
        .overlay(alignment: .bottom) { toastOverlay }
        .sheet(item: $sheet) { destination in
            sheetContent(destination)
        }
        .alert("Delete this item?", isPresented: inspirationDeleteAlert) {
            Button("Delete", role: .destructive) { confirmInspirationDeletion() }
            Button("Cancel", role: .cancel) { pendingInspirationDeletion = nil }
        } message: {
            Text("This removes the item from your moodboard. The original page is not affected.")
        }
        .alert("Delete project?", isPresented: projectDeleteAlert) {
            Button("Delete", role: .destructive) { confirmProjectDeletion() }
            Button("Cancel", role: .cancel) { pendingProjectDeletion = nil }
        } message: {
            Text("Its items will move back to General.")
        }
        .task { await syncAndReload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncAndReload() } }
        }
        .onChange(of: store.inspirations) { _, inspirations in
            if let selectedInspirationID,
               !inspirations.contains(where: { $0.id == selectedInspirationID }) {
                self.selectedInspirationID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxCaptureSucceeded)) { notification in
            guard let result = notification.object as? CaptureResult else { return }
            selectedInspirationID = result.inspiration.id
            store.scope = .all
            showToast(result.inserted ? "Saved from browser" : "Already in mood. — refreshed")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxCaptureFailed)) { notification in
            guard let message = notification.object as? String else { return }
            showToast(message, symbol: "exclamationmark.triangle.fill")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxQuickCapture)) { _ in
            sheet = .capture
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxNewProject)) { _ in
            sheet = .newProject
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxBrowserSetup)) { _ in
            sheet = .browserSetup
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxCanvasZoomIn)) { _ in
            zoomCanvas(byColumnDelta: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxCanvasZoomOut)) { _ in
            zoomCanvas(byColumnDelta: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinaxCanvasZoomReset)) { _ in
            resetCanvasZoom()
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var sidebar: some View {
        List(selection: $store.scope) {
            Section("Library") {
                sidebarRow("All Visuals", icon: "square.grid.2x2", count: store.counts.total)
                    .tag(LibraryScope.all)
                sidebarRow("General", icon: "tray", count: store.counts.general)
                    .tag(LibraryScope.general)
            }

            Section {
                ForEach(projects) { project in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: project.colorHex ?? "#5E5CE6"))
                            .frame(width: 9, height: 9)
                        Text(project.name).lineLimit(1)
                        Spacer()
                        Text("\(store.counts[project.id])")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .tag(LibraryScope.project(project.id))
                    .contextMenu {
                        Button("Edit…") { sheet = .editProject(project) }
                        Divider()
                        Button("Delete", role: .destructive) { pendingProjectDeletion = project }
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        sheet = .newProject
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New project")
                }
            }

            Spacer(minLength: 12)

            Section {
                Button {
                    sheet = .browserSetup
                } label: {
                    Label("Browser Setup", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .safeAreaInset(edge: .bottom) {
            Button {
                sheet = .capture
            } label: {
                Label("Save a link", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(12)
        }
    }

    private func sidebarRow(_ title: String, icon: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        let visibleInspirations = store.visibleInspirations

        Group {
            if store.isLoading && store.inspirations.isEmpty {
                ProgressView("Opening your moodboard…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleInspirations.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    let availableWidth = max(
                        1,
                        geometry.size.width - (canvasHorizontalPadding * 2)
                    )
                    let activeColumnCount = canvasColumnCount(
                        for: availableWidth,
                        zoom: CGFloat(canvasZoom)
                    )
                    let maximumColumnCount = maximumCanvasColumnCount(for: availableWidth)

                    ScrollView {
                        InterleavedCanvasLayout(
                            columnPosition: canvasLayoutColumnPosition(for: availableWidth),
                            minimumColumnCount: 1,
                            maximumColumnCount: maximumColumnCount,
                            horizontalSpacing: canvasSpacing,
                            verticalSpacing: canvasSpacing
                        ) {
                            ForEach(visibleInspirations) { inspiration in
                                InspirationCard(
                                    inspiration: inspiration,
                                    localImageURL: store.localImageURL(for: inspiration),
                                    canvasColumnCount: activeColumnCount,
                                    isSelected: selectedInspirationID == inspiration.id,
                                    onSelect: {
                                        guard canvasInteractionPhase == .idle else { return }
                                        selectedInspirationID = inspiration.id
                                    }
                                )
                                .contextMenu { cardContextMenu(for: inspiration) }
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.98).combined(with: .opacity)
                                )
                            }
                        }
                        .scaleEffect(
                            reduceMotion ? 1 : canvasGesturePresentation.boundaryScale,
                            anchor: canvasGesturePresentation.anchor
                        )
                        .padding(.horizontal, canvasHorizontalPadding)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(canvasMagnificationGesture)
                    .accessibilityAction(named: "Zoom In") {
                        zoomCanvas(byColumnDelta: -1)
                    }
                    .accessibilityAction(named: "Zoom Out") {
                        zoomCanvas(byColumnDelta: 1)
                    }
                    .accessibilityAction(named: "Reset Zoom") {
                        resetCanvasZoom()
                    }
                    .onAppear { canvasWidth = availableWidth }
                    .onChange(of: availableWidth) { _, newWidth in
                        canvasWidth = newWidth
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        let webURLs = urls.filter(isWebURL)
                        guard !webURLs.isEmpty else { return false }
                        captureDropped(webURLs)
                        return true
                    } isTargeted: { isDropTargeted = $0 }
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    PinaxCatalogPalette.accentInk(for: colorScheme),
                                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                                )
                                .background(
                                    PinaxCatalogPalette.accentInk(for: colorScheme).opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .background(PinaxCatalogPalette.canvas(for: colorScheme))
        .task(id: canvasInteractionPhase) {
            await finishCanvasInteractionAfterSettling()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                store.searchText.isEmpty ? "Start your moodboard" : "No visuals found",
                systemImage: store.searchText.isEmpty ? "sparkles.rectangle.stack" : "magnifyingglass"
            )
        } description: {
            Text(emptyDescription)
        } actions: {
            if store.searchText.isEmpty {
                HStack {
                    Button("Save a link") { sheet = .capture }
                        .buttonStyle(.borderedProminent)
                    Button("Set up browser") { sheet = .browserSetup }
                }
            } else {
                Button("Clear search") { store.searchText = "" }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            let webURLs = urls.filter(isWebURL)
            guard !webURLs.isEmpty else { return false }
            captureDropped(webURLs)
            return true
        }
    }

    private var emptyDescription: String {
        if !store.searchText.isEmpty { return "Try a different title, author, note, or URL." }
        switch store.scope {
        case .all:
            return "Collect visual ideas from X or any webpage, then shape them into projects."
        case .general:
            return "Unsorted visuals land here by default."
        case .project:
            return "Move visuals here, or save a new link directly into this project."
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                sheet = .capture
            } label: {
                Label("Save Link", systemImage: "plus")
            }
            .help("Save a link (⇧⌘S)")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                sheet = .browserSetup
            } label: {
                Image(systemName: "puzzlepiece.extension")
            }
            .help("Browser setup")
        }
    }

    @ViewBuilder
    private func cardContextMenu(for inspiration: Inspiration) -> some View {
        Button("Open Original") { NSWorkspace.shared.open(inspiration.url) }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(inspiration.url.absoluteString, forType: .string)
            showToast("Link copied", symbol: "doc.on.doc")
        }
        Divider()
        Menu("Move to") {
            Button("General") { move(inspiration, to: nil) }
            ForEach(projects) { project in
                Button(project.name) { move(inspiration, to: project.id) }
            }
        }
        Button("Edit…") { sheet = .editInspiration(inspiration) }
        Divider()
        Button("Delete", role: .destructive) { pendingInspirationDeletion = inspiration }
    }

    @ViewBuilder
    private func sheetContent(_ destination: SheetDestination) -> some View {
        switch destination {
        case .capture:
            CaptureSheet(projects: projects, initialProjectID: currentProjectID) { payload in
                let result = try await store.capture(payload)
                selectedInspirationID = result.inspiration.id
                showToast(result.inserted ? "Saved to mood." : "Already saved — details refreshed")
                requestSync()
            }
        case .newProject:
            ProjectEditorSheet { name, color in
                let project = try await store.createProject(name: name, colorHex: color)
                store.scope = .project(project.id)
                showToast("Project created", symbol: "folder.badge.plus")
                requestSync()
            }
        case .editProject(let project):
            ProjectEditorSheet(existingProject: project) { name, color in
                try await store.updateProject(id: project.id, name: name, colorHex: color)
                showToast("Project updated")
                requestSync()
            }
        case .editInspiration(let inspiration):
            InspirationEditorSheet(inspiration: inspiration, projects: projects) { draft in
                let updated = try await store.updateInspiration(draft)
                selectedInspirationID = updated.id
                showToast("Item updated")
                requestSync()
            }
        case .browserSetup:
            BrowserSetupView()
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            Label(toast.message, systemImage: toast.symbol)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThickMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var projects: [Project] {
        store.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedInspiration: Inspiration? {
        guard let selectedInspirationID else { return nil }
        return store.inspirations.first { $0.id == selectedInspirationID }
    }

    private var scopeTitle: String {
        switch store.scope {
        case .all: "All Visuals"
        case .general: "General"
        case .project(let id): project(with: id)?.name ?? "Project"
        }
    }

    private var currentProjectID: Project.ID? {
        if case .project(let id) = store.scope { return id }
        return nil
    }

    private func project(with id: Project.ID) -> Project? {
        store.projects.first { $0.id == id }
    }

    private var inspirationDeleteAlert: Binding<Bool> {
        Binding(
            get: { pendingInspirationDeletion != nil },
            set: { if !$0 { pendingInspirationDeletion = nil } }
        )
    }

    private var projectDeleteAlert: Binding<Bool> {
        Binding(
            get: { pendingProjectDeletion != nil },
            set: { if !$0 { pendingProjectDeletion = nil } }
        )
    }

    private func captureDropped(_ urls: [URL]) {
        let projectID = currentProjectID
        Task { @MainActor in
            do {
                var newest: Inspiration?
                for url in urls {
                    let source: CaptureSource = {
                        let host = url.host()?.lowercased() ?? ""
                        return host == "x.com" || host.hasSuffix(".x.com") || host == "twitter.com" || host.hasSuffix(".twitter.com")
                            ? .x
                            : .web
                    }()
                    let result = try await store.capture(
                        CapturePayload(
                            source: source,
                            url: url,
                            projectID: projectID,
                            assignProjectOnDuplicate: true
                        )
                    )
                    newest = result.inspiration
                }
                selectedInspirationID = newest?.id
                showToast(urls.count == 1 ? "Link saved" : "\(urls.count) links saved")
                requestSync()
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func move(_ inspiration: Inspiration, to projectID: Project.ID?) {
        Task { @MainActor in
            do {
                try await store.moveInspiration(id: inspiration.id, to: projectID)
                let destinationName = projectID.flatMap { project(with: $0)?.name }
                showToast(destinationName.map { "Moved to \($0)" } ?? "Moved to General")
                requestSync()
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func confirmInspirationDeletion() {
        guard let inspiration = pendingInspirationDeletion else { return }
        pendingInspirationDeletion = nil
        Task { @MainActor in
            do {
                try await store.deleteInspiration(id: inspiration.id)
                if selectedInspirationID == inspiration.id { selectedInspirationID = nil }
                showToast("Item deleted", symbol: "trash")
                requestSync()
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func confirmProjectDeletion() {
        guard let project = pendingProjectDeletion else { return }
        pendingProjectDeletion = nil
        Task { @MainActor in
            do {
                try await store.deleteProject(id: project.id)
                showToast("Project deleted", symbol: "trash")
                requestSync()
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        let next = ToastMessage(message: message, symbol: symbol)
        withAnimation(.easeOut(duration: 0.18)) { toast = next }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard toast?.id == next.id else { return }
            withAnimation(.easeIn(duration: 0.16)) { toast = nil }
        }
    }

    @MainActor
    private func syncAndReload() async {
        await store.reload()

        guard let syncCoordinator else { return }
        let result = await syncCoordinator.sync()
        await store.reload()

        if result == nil, let error = syncCoordinator.lastError {
            showToast(
                "Sync unavailable. Your changes are saved on this Mac. \(error)",
                symbol: "icloud.slash"
            )
        }
    }

    private func requestSync() {
        Task { @MainActor in
            await syncAndReload()
        }
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host() != nil
    }

    private var canvasMagnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.03)
            .onChanged { value in
                let width = resolvedCanvasWidth
                let behavior = canvasZoomBehavior(for: width)
                let baseColumnCount = canvasGesturePresentation.isActive
                    ? canvasGesturePresentation.baseColumnCount
                    : canvasColumnCount(for: width, zoom: CGFloat(canvasZoom))
                let preview = behavior.preview(
                    from: baseColumnCount,
                    magnification: value.magnification
                )
                let columnPosition = CGFloat(baseColumnCount)
                    + ((CGFloat(preview.targetColumnCount) - CGFloat(baseColumnCount)) * preview.progress)
                let boundaryScale = preview.targetColumnCount == baseColumnCount
                    ? behavior.elasticScale(
                        for: value.magnification,
                        currentColumnCount: baseColumnCount
                    )
                    : 1

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                transaction.isContinuous = true
                withTransaction(transaction) {
                    canvasInteractionPhase = .pinching
                    canvasGesturePresentation = MacCanvasGesturePresentation(
                        baseColumnCount: baseColumnCount,
                        columnPosition: columnPosition,
                        boundaryScale: boundaryScale,
                        anchor: value.startAnchor,
                        isActive: true
                    )
                }
            }
            .onEnded { value in
                let width = resolvedCanvasWidth
                let behavior = canvasZoomBehavior(for: width)
                let baseColumnCount = canvasGesturePresentation.isActive
                    ? canvasGesturePresentation.baseColumnCount
                    : canvasColumnCount(for: width, zoom: CGFloat(canvasZoom))
                let targetColumnCount = behavior.targetColumnCount(
                    from: baseColumnCount,
                    magnification: value.magnification
                )
                settleCanvas(
                    at: targetColumnCount,
                    width: width,
                    animation: canvasSettleAnimation
                )
            }
    }

    private var resolvedCanvasWidth: CGFloat {
        canvasWidth > 1 ? canvasWidth : 900
    }

    private var canvasSettleAnimation: Animation {
        .interactiveSpring(
            response: 0.26,
            dampingFraction: 0.88,
            blendDuration: 0.1
        )
    }

    private var canvasCommandAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    private func canvasZoomBehavior(for width: CGFloat) -> CanvasZoomBehavior {
        CanvasZoomBehavior(maximumColumnCount: maximumCanvasColumnCount(for: width))
    }

    private func canvasLayoutColumnPosition(for width: CGFloat) -> CGFloat {
        let settledColumnCount = canvasColumnCount(
            for: width,
            zoom: CGFloat(canvasZoom)
        )
        guard !reduceMotion,
              let liveColumnPosition = canvasGesturePresentation.columnPosition else {
            return CGFloat(settledColumnCount)
        }
        return liveColumnPosition
    }

    private func maximumCanvasColumnCount(for width: CGFloat) -> Int {
        guard width > 1 else { return 3 }
        let fittedCount = Int(
            ((width + canvasSpacing) / (minimumCanvasCardWidth + canvasSpacing))
                .rounded(.down)
        )
        return min(maximumCanvasColumns, max(1, fittedCount))
    }

    private func canvasColumnCount(for width: CGFloat, zoom: CGFloat) -> Int {
        let maximum = maximumCanvasColumnCount(for: width)
        guard maximum > 1 else { return 1 }

        let interpolated = CGFloat(maximum) - (clampedCanvasZoom(zoom) * CGFloat(maximum - 1))
        return min(maximum, max(1, Int(interpolated.rounded())))
    }

    private func zoomCanvas(byColumnDelta delta: Int) {
        let width = resolvedCanvasWidth
        let maximum = maximumCanvasColumnCount(for: width)
        let current = canvasColumnCount(for: width, zoom: CGFloat(canvasZoom))
        let target = min(maximum, max(1, current + delta))
        guard target != current else { return }

        settleCanvas(
            at: target,
            width: width,
            animation: canvasCommandAnimation
        )
    }

    private func resetCanvasZoom() {
        let width = resolvedCanvasWidth
        let target = canvasColumnCount(
            for: width,
            zoom: CGFloat(Self.defaultCanvasZoom)
        )
        let current = canvasColumnCount(for: width, zoom: CGFloat(canvasZoom))
        guard target != current else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                canvasZoom = Self.defaultCanvasZoom
            }
            return
        }

        settleCanvas(
            at: target,
            width: width,
            persistedZoom: CGFloat(Self.defaultCanvasZoom),
            animation: canvasCommandAnimation
        )
    }

    private func settleCanvas(
        at columnCount: Int,
        width: CGFloat,
        persistedZoom: CGFloat? = nil,
        animation: Animation
    ) {
        let behavior = canvasZoomBehavior(for: width)
        let target = behavior.clampedColumnCount(columnCount)
        let current = canvasColumnCount(for: width, zoom: CGFloat(canvasZoom))
        let startingPosition = canvasGesturePresentation.columnPosition
            ?? CGFloat(current)
        let storedZoom = clampedCanvasZoom(
            persistedZoom
                ?? canvasZoomValue(
                    for: target,
                    maximum: behavior.maximumColumnCount
                )
        )

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            canvasZoom = Double(storedZoom)
            canvasInteractionPhase = reduceMotion ? .idle : .settling
            canvasGesturePresentation = MacCanvasGesturePresentation(
                baseColumnCount: current,
                columnPosition: reduceMotion ? nil : startingPosition,
                boundaryScale: reduceMotion ? 1 : canvasGesturePresentation.boundaryScale,
                anchor: canvasGesturePresentation.anchor,
                isActive: false
            )
        }

        guard !reduceMotion else { return }
        withAnimation(animation) {
            canvasGesturePresentation.columnPosition = CGFloat(target)
            canvasGesturePresentation.boundaryScale = 1
        }
    }

    @MainActor
    private func finishCanvasInteractionAfterSettling() async {
        guard canvasInteractionPhase == .settling else { return }

        do {
            try await Task.sleep(for: .milliseconds(420))
        } catch {
            return
        }

        guard !Task.isCancelled,
              canvasInteractionPhase == .settling else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            canvasGesturePresentation = .inactive
            canvasInteractionPhase = .idle
        }
    }

    private func canvasZoomValue(for columnCount: Int, maximum: Int) -> CGFloat {
        guard maximum > 1 else { return 1 }
        return CGFloat(maximum - columnCount) / CGFloat(maximum - 1)
    }

    private func clampedCanvasZoom(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}

private struct MacCanvasGesturePresentation: Equatable {
    static let inactive = MacCanvasGesturePresentation(
        baseColumnCount: 1,
        columnPosition: nil,
        boundaryScale: 1,
        anchor: .center,
        isActive: false
    )

    let baseColumnCount: Int
    var columnPosition: CGFloat?
    var boundaryScale: CGFloat
    let anchor: UnitPoint
    let isActive: Bool
}

private enum MacCanvasInteractionPhase: Equatable {
    case idle
    case pinching
    case settling
}

private struct InterleavedCanvasLayout: Layout {
    var columnPosition: CGFloat
    let minimumColumnCount: Int
    let maximumColumnCount: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    var animatableData: CGFloat {
        get { columnPosition }
        set { columnPosition = newValue }
    }

    struct Cache {
        fileprivate var measurements: [MeasurementKey: Measurements] = [:]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.measurements.removeAll(keepingCapacity: true)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let pair = measurementPair(
            for: width,
            subviews: subviews,
            cache: &cache
        )
        return CGSize(
            width: width,
            height: interpolate(
                from: pair.start.height,
                to: pair.end.height,
                progress: columnInterpolation
            )
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let pair = measurementPair(
            for: bounds.width,
            subviews: subviews,
            cache: &cache
        )

        for (index, subview) in subviews.enumerated() {
            guard pair.start.frames.indices.contains(index),
                  pair.end.frames.indices.contains(index) else { continue }
            let frame = interpolate(
                from: pair.start.frames[index],
                to: pair.end.frames[index],
                progress: columnInterpolation
            )
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private var clampedColumnPosition: CGFloat {
        min(
            CGFloat(maximumColumnCount),
            max(CGFloat(minimumColumnCount), columnPosition)
        )
    }

    private var lowerColumnCount: Int {
        Int(floor(clampedColumnPosition))
    }

    private var upperColumnCount: Int {
        Int(ceil(clampedColumnPosition))
    }

    private var columnInterpolation: CGFloat {
        clampedColumnPosition - CGFloat(lowerColumnCount)
    }

    private func measurementPair(
        for width: CGFloat,
        subviews: Subviews,
        cache: inout Cache
    ) -> (start: Measurements, end: Measurements) {
        let start = measurements(
            for: width,
            columnCount: lowerColumnCount,
            subviews: subviews,
            cache: &cache
        )
        guard upperColumnCount != lowerColumnCount,
              columnInterpolation > 0 else {
            return (start, start)
        }
        let end = measurements(
            for: width,
            columnCount: upperColumnCount,
            subviews: subviews,
            cache: &cache
        )
        return (start, end)
    }

    private func measurements(
        for width: CGFloat,
        columnCount: Int,
        subviews: Subviews,
        cache: inout Cache
    ) -> Measurements {
        guard !subviews.isEmpty else { return Measurements(frames: [], height: 0) }

        let count = max(1, columnCount)
        let key = MeasurementKey(
            width: width,
            columnCount: count,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        if let cached = cache.measurements[key] {
            return cached
        }

        let totalSpacing = horizontalSpacing * CGFloat(count - 1)
        let columnWidth = max(1, (width - totalSpacing) / CGFloat(count))
        var columnHeights = (0..<count).map(initialOffset(for:))
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for (index, subview) in subviews.enumerated() {
            let column: Int
            if index < count {
                column = index
            } else {
                column = columnHeights.enumerated().min { lhs, rhs in
                    if lhs.element == rhs.element { return lhs.offset < rhs.offset }
                    return lhs.element < rhs.element
                }?.offset ?? 0
            }

            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )
            let origin = CGPoint(
                x: CGFloat(column) * (columnWidth + horizontalSpacing),
                y: columnHeights[column]
            )
            frames.append(
                CGRect(origin: origin, size: CGSize(width: columnWidth, height: size.height))
            )
            columnHeights[column] += size.height + verticalSpacing
        }

        let measurements = Measurements(
            frames: frames,
            height: max(0, (columnHeights.max() ?? 0) - verticalSpacing)
        )
        cache.measurements[key] = measurements
        return measurements
    }

    private func initialOffset(for column: Int) -> CGFloat {
        switch column % 4 {
        case 1: 10
        case 2: 4
        case 3: 14
        default: 0
        }
    }

    private func interpolate(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        start + ((end - start) * progress)
    }

    private func interpolate(
        from start: CGRect,
        to end: CGRect,
        progress: CGFloat
    ) -> CGRect {
        CGRect(
            x: interpolate(from: start.minX, to: end.minX, progress: progress),
            y: interpolate(from: start.minY, to: end.minY, progress: progress),
            width: interpolate(from: start.width, to: end.width, progress: progress),
            height: interpolate(from: start.height, to: end.height, progress: progress)
        )
    }

    fileprivate struct Measurements {
        let frames: [CGRect]
        let height: CGFloat
    }

    fileprivate struct MeasurementKey: Hashable {
        let width: CGFloat
        let columnCount: Int
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
    }
}

private enum SheetDestination: Identifiable {
    case capture
    case newProject
    case editProject(Project)
    case editInspiration(Inspiration)
    case browserSetup

    var id: String {
        switch self {
        case .capture: "capture"
        case .newProject: "new-project"
        case .editProject(let project): "edit-project-\(project.id)"
        case .editInspiration(let inspiration): "edit-inspiration-\(inspiration.id)"
        case .browserSetup: "browser-setup"
        }
    }
}

private struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let symbol: String
}

extension Notification.Name {
    static let pinaxCaptureSucceeded = Notification.Name("Pinax.captureSucceeded")
    static let pinaxCaptureFailed = Notification.Name("Pinax.captureFailed")
    static let pinaxQuickCapture = Notification.Name("Pinax.quickCapture")
    static let pinaxNewProject = Notification.Name("Pinax.newProject")
    static let pinaxBrowserSetup = Notification.Name("Pinax.browserSetup")
    static let pinaxCanvasZoomIn = Notification.Name("Pinax.canvasZoomIn")
    static let pinaxCanvasZoomOut = Notification.Name("Pinax.canvasZoomOut")
    static let pinaxCanvasZoomReset = Notification.Name("Pinax.canvasZoomReset")
}
