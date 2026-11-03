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
    @State private var isSearching = false
    @State private var canvasWidth: CGFloat = 0
    @State private var canvasGesturePresentation = MacCanvasGesturePresentation.inactive
    @State private var canvasInteractionPhase = MacCanvasInteractionPhase.idle
    @State private var searchActivation = UUID()
    @AppStorage("libraryCanvasZoom") private var canvasZoom = 0.5
    @AppStorage("macProjectSidebarCollapsed") private var isProjectSidebarCollapsed = false
    @AppStorage("macStudyShowsBoard") private var prefersStudyBoard = true
    @State private var studyFilter = StudyBoardFilter.all
    @State private var selectedStudyEntryID: StudyBoardEntry.ID?
    @State private var hoveredStudyPatternID: StudyReflection.ID?
    @State private var studyArrivals = StudyBoardArrivals()
    @State private var studyRunner = StudyAgentRunner.shared

    private static let defaultCanvasZoom = 0.5
    private let canvasHorizontalPadding: CGFloat = 20
    private let canvasSpacing: CGFloat = 16
    private let minimumCanvasCardWidth: CGFloat = 148
    private let maximumCanvasColumns = 8
    private let expandedProjectSidebarWidth: CGFloat = 224
    private let collapsedProjectSidebarWidth: CGFloat = 80

    var body: some View {
        libraryCanvas
            .frame(minWidth: 720, minHeight: 520)
    }

    private var libraryCanvas: some View {
        commandObservingCanvas
    }

    private var presentationCanvas: AnyView {
        AnyView(
            styledCanvas
            .sheet(item: $sheet, content: sheetContent)
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
        )
    }

    private var lifecycleCanvas: AnyView {
        AnyView(
            presentationCanvas
            .task { await syncAndReload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await syncAndReload() } }
            }
            // The library window is AppKit-owned, so `scenePhase` does not
            // change when the user switches back from another app. Reload then,
            // so suggestions and patterns an agent added with mood-agent appear.
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                Task { await syncAndReload() }
            }
            .onChange(of: store.inspirations) { _, inspirations in
                if let selectedInspirationID,
                   !inspirations.contains(where: { $0.id == selectedInspirationID }) {
                    setSelectedInspiration(nil)
                }
            }
            .onChange(of: studyBoardObservation, initial: true) { old, new in
                noteStudyArrivals(from: old, to: new)
            }
        )
    }

    private var captureObservingCanvas: AnyView {
        AnyView(
            lifecycleCanvas
            .onReceive(NotificationCenter.default.publisher(for: .pinaxCaptureSucceeded)) { notification in
                guard let result = notification.object as? CaptureResult else { return }
                setSelectedInspiration(result.inspiration.id)
                reveal(result.inspiration)
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
        )
    }

    private var commandObservingCanvas: AnyView {
        AnyView(
            captureObservingCanvas
            .onReceive(NotificationCenter.default.publisher(for: .pinaxCanvasZoomIn)) { _ in
                zoomCanvas(byColumnDelta: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinaxCanvasZoomOut)) { _ in
                zoomCanvas(byColumnDelta: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinaxCanvasZoomReset)) { _ in
                resetCanvasZoom()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinaxFind)) { _ in
                beginSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinaxSwitchProject)) { _ in
                showProjectSidebar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinaxToggleProjectSidebar)) { _ in
                toggleProjectSidebar()
            }
            .onKeyPress("/") {
                guard !isSearching else { return .ignored }
                beginSearch()
                return .handled
            }
            .onExitCommand(perform: handleExitCommand)
            .accessibilityAction(named: "Search") { beginSearch() }
            .accessibilityAction(named: "Show Projects Sidebar") { showProjectSidebar() }
        )
    }

    private var styledCanvas: some View {
        framedMoodboard
            .ignoresSafeArea()
            .background(MacCanvasWindowConfigurator())
            .accentColor(PinaxCatalogPalette.accent(for: colorScheme))
            .tint(PinaxCatalogPalette.accent(for: colorScheme))
            .overlay(alignment: .bottom) { toastOverlay }
    }

    private var framedMoodboard: some View {
        HStack(spacing: 0) {
            MacProjectSidebar(
                items: sidebarItems,
                currentScope: store.scope,
                isCollapsed: isProjectSidebarCollapsed,
                onSelect: selectSpace,
                onToggleCollapse: toggleProjectSidebar,
                onCreate: { sheet = .newProject },
                onCreateStudy: { sheet = .newStudy },
                onEdit: { sheet = .editProject($0) },
                onStudy: { project in
                    if project.isStudy {
                        openStudyBoard(project.id)
                    } else {
                        sheet = .startStudy(project)
                    }
                },
                onDelete: { pendingProjectDeletion = $0 },
                onCapture: { sheet = .capture },
                onBrowserSetup: { sheet = .browserSetup }
            )
            .frame(
                width: isProjectSidebarCollapsed
                    ? collapsedProjectSidebarWidth
                    : expandedProjectSidebarWidth
            )

            // Every board is a page of the sketchbook, inside its cover.
            ZStack {
                SketchPaper()
                canvasStack
            }
            .clipShape(moodboardStageShape)
            .padding(.vertical, 4)
            .padding(.trailing, 4)
        }
        .background(Sketchbook.cover)
    }

    private var moodboardStageShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var canvasStack: some View {
        ZStack(alignment: .trailing) {
            libraryContent
                .overlay(alignment: .topTrailing) {
                    canvasChrome
                }

            if isShowingCloseLook {
                closeLookScrim
            }

            if !showsStudyBoard, let selectedInspiration {
                closeLookCard {
                    inspirationCloseLook(selectedInspiration)
                }
            }

            if showsStudyBoard,
               let studyProject = currentStudyProject,
               let study = studyProject.study,
               let entry = selectedStudyEntryID.flatMap({ StudyBoard(study: study).entry(id: $0) }) {
                closeLookCard {
                    studyCloseLook(entry, project: studyProject, study: study)
                }
            }
        }
    }

    /// A moodboard item up close, in the same frame as a study find, so ⌘[
    /// and ⌘] step through the visible board here too.
    private func inspirationCloseLook(_ inspiration: Inspiration) -> some View {
        let visible = store.visibleInspirations
        let index = visible.firstIndex(where: { $0.id == inspiration.id })

        // No "3 of 214" here: browsing a moodboard isn't a queue to work through.
        return CloseLookFrame(
            position: nil,
            count: visible.count,
            onPrevious: inspirationSelector(at: index.map { $0 - 1 }, in: visible),
            onNext: inspirationSelector(at: index.map { $0 + 1 }, in: visible),
            onClose: closeDetailInspector
        ) {
            // Stacked, so stepping crossfades the old item into the new one
            // in place while the frame stays still.
            ZStack {
                InspirationDetailView(
                    inspiration: inspiration,
                    localImageURL: store.localImageURL(for: inspiration),
                    project: inspiration.projectID.flatMap(project(with:)),
                    projects: projects,
                    onMove: { projectID in move(inspiration, to: projectID) },
                    onEdit: { sheet = .editInspiration(inspiration) },
                    onDelete: { pendingInspirationDeletion = inspiration },
                    onClose: closeDetailInspector,
                    showsCloseButton: false
                )
                .id(inspiration.id)
                .transition(.opacity)
            }
        }
    }

    private func inspirationSelector(at index: Int?, in inspirations: [Inspiration]) -> (() -> Void)? {
        guard let index, inspirations.indices.contains(index) else { return nil }
        let id = inspirations[index].id
        return { setSelectedInspiration(id) }
    }

    private var isShowingCloseLook: Bool {
        showsStudyBoard ? selectedStudyEntryID != nil : selectedInspirationID != nil
    }

    /// Dims the canvas behind a close look; clicking it closes the look.
    private var closeLookScrim: some View {
        Color.black
            .opacity(colorScheme == .dark ? 0.55 : 0.28)
            .contentShape(Rectangle())
            .onTapGesture {
                if showsStudyBoard {
                    closeStudyCloseLook()
                } else {
                    closeDetailInspector()
                }
            }
            .accessibilityHidden(true)
            .transition(.opacity)
            .zIndex(1)
    }

    /// A close look as large as the canvas allows: the image gets most of
    /// the room and the details a column beside it.
    private func closeLookCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: 1240, maxHeight: 900)
            .clipShape(detailPanelShape)
            .overlay {
                detailPanelShape.strokeBorder(detailPanelStroke, lineWidth: 1)
            }
            .background {
                detailPanelShape
                    .fill(PinaxCatalogPalette.folio(for: colorScheme))
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1),
                        radius: 3,
                        y: 1
                    )
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16),
                        radius: 30,
                        y: 16
                    )
            }
            .contentShape(detailPanelShape)
            // Fades as one layer, so the shadow and content don't show
            // through each other mid-transition.
            .compositingGroup()
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    )
            )
            .zIndex(2)
    }

    private var canvasChrome: some View {
        HStack(spacing: 8) {
            if showsStudyBoard, let project = currentStudyProject, let study = project.study {
                studyAgentControl(project: project, study: study)
            }

            if currentStudyProjectID != nil {
                MacCanvasModeSwitch(showsStudyBoard: studyCanvasSelection)
                    .fixedSize()
                    .help("Switch between the study's moodboard and the board of everything it found")
            }

            MacCanvasSearchControl(
                text: $store.searchText,
                isExpanded: isSearching || !store.searchText.isEmpty,
                activation: searchActivation,
                onOpen: beginSearch,
                onDismiss: dismissSearch
            )
        }
        // On the canvas's own edge, so the chrome and the board's right
        // edge share one line.
        .padding(.trailing, canvasHorizontalPadding)
        .padding(.top, 15)
        .accessibilitySortPriority(1)
    }

    private var libraryContent: some View {
        Group {
            if showsStudyBoard, let project = currentStudyProject, let study = project.study {
                studyBoard(project: project, study: study)
            } else {
                moodboard
            }
        }
        // Each space is its own page: switching crossfades to it, opened
        // at the top.
        .id(store.scope)
        .transition(.opacity)
        .task(id: canvasInteractionPhase) {
            await finishCanvasInteractionAfterSettling()
        }
    }

    @ViewBuilder
    private var moodboard: some View {
        let visibleInspirations = store.visibleInspirations

        if store.isLoading && store.inspirations.isEmpty {
            ProgressView("Opening your moodboard…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            zoomableCanvas(spacing: canvasSpacing) {
                VStack(alignment: .leading, spacing: canvasSpacing) {
                    moodboardHeader
                    if visibleInspirations.isEmpty {
                        moodboardEmptyNote
                    }
                }
                .padding(.bottom, pageHeaderGap)
            } cards: { activeColumnCount in
                ForEach(visibleInspirations) { inspiration in
                    InspirationCard(
                        inspiration: inspiration,
                        localImageURL: store.localImageURL(for: inspiration),
                        canvasColumnCount: activeColumnCount,
                        isSelected: selectedInspirationID == inspiration.id,
                        onSelect: {
                            guard canvasInteractionPhase == .idle else { return }
                            setSelectedInspiration(inspiration.id)
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
        }
    }

    /// The pinch-zoomable masonry both the moodboard and the study board sit
    /// on. `header` scrolls with the cards. The study board spaces its cards
    /// wider, so the ink loops around kept ones don't run into each other.
    private func zoomableCanvas<Header: View, Cards: View>(
        spacing: CGFloat,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder cards: @escaping (_ activeColumnCount: Int) -> Cards
    ) -> some View {
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
                VStack(alignment: .leading, spacing: 0) {
                    header()

                    InterleavedCanvasLayout(
                        columnPosition: canvasLayoutColumnPosition(for: availableWidth),
                        minimumColumnCount: 1,
                        maximumColumnCount: maximumColumnCount,
                        horizontalSpacing: spacing,
                        verticalSpacing: spacing
                    ) {
                        cards(activeColumnCount)
                    }
                    .overlayPreferenceValue(StudyCardAnchorKey.self) { anchors in
                        studyEvidenceOverlay(anchors)
                    }
                    .scaleEffect(
                        reduceMotion ? 1 : canvasGesturePresentation.boundaryScale,
                        anchor: canvasGesturePresentation.anchor
                    )
                }
                .padding(.horizontal, canvasHorizontalPadding)
                // Room for the canvas chrome above the page's header.
                .padding(.top, pageTopInset)
                .padding(.bottom, 28)
            }
            // Cards soften as they pass under the canvas chrome rather than
            // being cut by the window's edge.
            .modifier(SoftTopScrollEdge())
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

    // MARK: Study board

    /// Every find and pattern of the open study on the same zoomable canvas as
    /// the moodboard. A running agent's finds develop into place at the end,
    /// after grain tiles that hold the slots it's still filling.
    private func studyBoard(project: Project, study: ProjectStudy) -> some View {
        let board = StudyBoard(study: study)
        let entries = board.entries(for: studyFilter, matching: store.searchText)
        let isLooking = studyRunner.isRunning(project.id)
        let isSearchingText = !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return zoomableCanvas(spacing: studyBoardSpacing) {
            VStack(alignment: .leading, spacing: canvasSpacing) {
                StudyBoardHeader(
                    study: study,
                    board: board,
                    filter: $studyFilter,
                    onEdit: { sheet = .startStudy(project) }
                )

                if entries.isEmpty, !isLooking {
                    StudyBoardEmptyState(
                        stage: study.stage(itemCount: store.studyItems(for: project.id).count),
                        filter: studyFilter,
                        boardIsEmpty: board.isEmpty,
                        isSearchingText: isSearchingText && !board.isEmpty
                    )
                }
            }
            .padding(.bottom, pageHeaderGap)
        } cards: { activeColumnCount in
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                studyBoardCard(entry, project: project, columnCount: activeColumnCount)
                    .transition(
                        StudyBoardMotion.cardTransition(
                            index: index,
                            arrivedJustNow: studyArrivals.fresh.contains(entry.id),
                            reduceMotion: reduceMotion
                        )
                    )
            }
            if isLooking {
                StudyLatentCard(columns: activeColumnCount, aspectRatio: 0.86)
                    .transition(.opacity)
                StudyLatentCard(columns: activeColumnCount, aspectRatio: 1.18, phase: .pi)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : StudyBoardMotion.settle, value: entries.map(\.id))
        .animation(reduceMotion ? nil : StudyBoardMotion.settle, value: isLooking)
    }

    /// The study's agent, in the canvas chrome beside the board switch.
    private func studyAgentControl(project: Project, study: ProjectStudy) -> some View {
        StudyAgentControl(
            store: store,
            project: project,
            study: study,
            onProgress: { [store] in
                await store.reload()
            },
            onChange: { [store, syncCoordinator] in
                await store.reload()
                guard let syncCoordinator else { return }
                _ = await syncCoordinator.sync()
                await store.reload()
            },
            onRefresh: {
                // The rejected finds step aside so the new ones arrive
                // on a clear board.
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    studyFilter = .toJudge
                }
            }
        )
        // A study's nudge and open card stay with it.
        .id(project.id)
        .transition(.opacity)
    }

    @ViewBuilder
    private func studyBoardCard(_ entry: StudyBoardEntry, project: Project, columnCount: Int) -> some View {
        let isSelected = selectedStudyEntryID == entry.id
        switch entry {
        case .finding(let suggestion) where suggestion.isMove:
            VStack(alignment: .leading, spacing: StudyMarginNote.spacing) {
                Button {
                    guard canvasInteractionPhase == .idle else { return }
                    selectStudyEntry(entry.id)
                } label: {
                    StudyMoveCard(
                        suggestion: suggestion,
                        localImageURL: savedInspiration(for: suggestion).flatMap { store.localImageURL(for: $0) },
                        columns: columnCount,
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
                .studyBoardVerdict(entry.verdict, seed: entry.id)
                .modifier(
                    MacStudyQuickVerdict(isAvailable: suggestion.status == .pending) { verdict in
                        decide(suggestion, verdict: verdict, reason: nil, advancing: false)
                    }
                )
                .studyCardAnchor(entry.id)

                StudyMarginNote(suggestion: suggestion, columns: columnCount)
            }
            .contextMenu { studyFindingMenu(suggestion) }
            .accessibilityHint("Opens the move up close")
        case .finding(let suggestion):
            let item = savedInspiration(for: suggestion)
                ?? suggestion.previewInspiration(projectID: project.id)
            VStack(alignment: .leading, spacing: StudyMarginNote.spacing) {
                InspirationCard(
                    inspiration: item,
                    localImageURL: store.localImageURL(for: item),
                    canvasColumnCount: columnCount,
                    isSelected: isSelected,
                    onSelect: {
                        guard canvasInteractionPhase == .idle else { return }
                        selectStudyEntry(entry.id)
                    }
                )
                .environment(\.previewImageReveal, studyArrivals.reveal(for: entry.id))
                .studyBoardVerdict(entry.verdict, seed: entry.id)
                .modifier(
                    MacStudyQuickVerdict(isAvailable: suggestion.status == .pending) { verdict in
                        decide(suggestion, verdict: verdict, reason: nil, advancing: false)
                    }
                )
                .studyCardAnchor(entry.id)

                StudyMarginNote(suggestion: suggestion, columns: columnCount)
            }
            .contextMenu { studyFindingMenu(suggestion) }
        case .pattern(let reflection):
            Button {
                guard canvasInteractionPhase == .idle else { return }
                selectStudyEntry(entry.id)
            } label: {
                StudyPatternCard(
                    reflection: reflection,
                    columns: columnCount,
                    isSelected: isSelected,
                    developsOnArrival: studyArrivals.fresh.contains(entry.id)
                )
            }
            .buttonStyle(.plain)
            .studyBoardVerdict(entry.verdict, seed: entry.id, circlesKept: false)
            .studyCardAnchor(entry.id)
            .onHover { isHovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    if isHovering {
                        hoveredStudyPatternID = reflection.id
                    } else if hoveredStudyPatternID == reflection.id {
                        hoveredStudyPatternID = nil
                    }
                }
            }
            .contextMenu { studyPatternMenu(reflection) }
            .accessibilityHint("Opens the pattern up close")
        }
    }

    /// While the pointer rests on a pattern, pencil lines run to the kept
    /// finds it was drawn from, and dashed ones to the rejects it stands
    /// against.
    @ViewBuilder
    private func studyEvidenceOverlay(_ anchors: [UUID: Anchor<CGRect>]) -> some View {
        if showsStudyBoard,
           selectedStudyEntryID == nil,
           let patternID = hoveredStudyPatternID,
           let study = currentStudyProject?.study,
           let reflection = study.reflections.first(where: { $0.id == patternID }) {
            StudyEvidenceLines(
                pattern: patternID,
                evidence: reflection.evidence(in: study),
                contrasts: reflection.rejectedSuggestionIDs,
                anchors: anchors
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func studyFindingMenu(_ suggestion: StudySuggestion) -> some View {
        Button("Look Closer") { selectStudyEntry(suggestion.id) }
        switch suggestion.status {
        case .pending:
            Button("Keep") { decide(suggestion, verdict: .keep, reason: nil, advancing: false) }
            Button("Reject") { decide(suggestion, verdict: .reject, reason: nil, advancing: false) }
        case .kept:
            if let savedID = suggestion.savedInspirationID {
                Button("Show on Moodboard") { showOnMoodboard(savedID) }
            }
        case .rejected:
            Button("Keep Instead") {
                decide(suggestion, verdict: .keep, reason: suggestion.reason, advancing: false)
            }
        }
        Divider()
        Button("Open Source Page") { NSWorkspace.shared.open(suggestion.url) }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(suggestion.url.absoluteString, forType: .string)
            showToast("Link copied", symbol: "doc.on.doc")
        }
    }

    @ViewBuilder
    private func studyPatternMenu(_ reflection: StudyReflection) -> some View {
        Button("Look Closer") { selectStudyEntry(reflection.id) }
        Button("That's Right") { respond(reflection, with: .confirm, advancing: false) }
            .disabled(reflection.status == .confirmed)
        Button("Not Me") { respond(reflection, with: .dismiss, advancing: false) }
            .disabled(reflection.status == .dismissed)
    }

    @ViewBuilder
    private func studyCloseLook(_ entry: StudyBoardEntry, project: Project, study: ProjectStudy) -> some View {
        let entries = StudyBoard(study: study).entries(for: studyFilter, matching: store.searchText)
        let index = entries.firstIndex(where: { $0.id == entry.id })

        CloseLookFrame(
            position: index.map { $0 + 1 },
            count: entries.count,
            onPrevious: studyEntrySelector(at: index.map { $0 - 1 }, in: entries),
            onNext: studyEntrySelector(at: index.map { $0 + 1 }, in: entries),
            onClose: closeStudyCloseLook
        ) {
            // Stacked, so stepping crossfades one entry into the next in
            // place while the frame and its counter stay still.
            ZStack {
                Group {
                    switch entry {
                    case .finding(let suggestion):
                        StudyFindingCloseLook(
                            suggestion: suggestion,
                            savedImageURL: savedInspiration(for: suggestion).flatMap { store.localImageURL(for: $0) },
                            relatedItems: studyCloseLookItems(suggestion.basedOnInspirationIDs),
                            targetItems: studyCloseLookItems(suggestion.forInspirationID.map { [$0] } ?? []),
                            onDecide: { verdict, reason in
                                decide(suggestion, verdict: verdict, reason: reason, advancing: true)
                            }
                        )
                    case .pattern(let reflection):
                        StudyPatternCloseLook(
                            reflection: reflection,
                            citedItems: studyCloseLookItems(reflection.inspirationIDs),
                            contrasts: reflection.rejectedSuggestionIDs.compactMap { id in
                                study.suggestions.first(where: { $0.id == id })
                            },
                            onRespond: { response in
                                respond(reflection, with: response, advancing: true)
                            }
                        )
                    }
                }
                .id(entry.id)
                .transition(.opacity)
            }
        }
    }

    private var showsStudyBoard: Bool {
        prefersStudyBoard && currentStudyProjectID != nil
    }

    private var currentStudyProject: Project? {
        currentStudyProjectID.flatMap(project(with:))
    }

    private var studyCanvasSelection: Binding<Bool> {
        Binding(
            get: { prefersStudyBoard },
            set: { setStudyBoardShown($0) }
        )
    }

    private var studyBoardObservation: MacStudyBoardObservation {
        guard showsStudyBoard, let study = currentStudyProject?.study else {
            return MacStudyBoardObservation(projectID: nil, entryIDs: [])
        }
        return MacStudyBoardObservation(
            projectID: currentStudyProjectID,
            entryIDs: StudyBoard(study: study).entries.map(\.id)
        )
    }

    /// Finds that arrive while the board is open develop into place; what was
    /// there when it opened stays still.
    private func noteStudyArrivals(from old: MacStudyBoardObservation, to new: MacStudyBoardObservation) {
        if old.projectID != new.projectID || new.projectID == nil || old == new {
            studyArrivals.reset()
        }
        let arrived = studyArrivals.note(new.entryIDs)
        if let selectedStudyEntryID, !new.entryIDs.contains(selectedStudyEntryID) {
            selectStudyEntry(nil)
        }
        guard !arrived.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            studyArrivals.settle(arrived)
        }
    }

    private func setStudyBoardShown(_ shown: Bool) {
        withAnimation(reduceMotion ? nil : MacChromeMotion.fade) {
            prefersStudyBoard = shown
            selectedStudyEntryID = nil
            if shown { selectedInspirationID = nil }
        }
    }

    private func openStudyBoard(_ projectID: Project.ID) {
        selectSpace(.project(projectID))
        setStudyBoardShown(true)
    }

    private func showOnMoodboard(_ inspirationID: Inspiration.ID) {
        setStudyBoardShown(false)
        setSelectedInspiration(inspirationID)
    }

    private func selectStudyEntry(_ id: StudyBoardEntry.ID?) {
        let changesPanelPresentation = (selectedStudyEntryID == nil) != (id == nil)
        if changesPanelPresentation {
            withAnimation(detailInspectorAnimation) {
                selectedStudyEntryID = id
            }
        } else {
            withAnimation(reduceMotion ? nil : StudyBoardMotion.step) {
                selectedStudyEntryID = id
            }
        }
    }

    private func closeStudyCloseLook() {
        guard selectedStudyEntryID != nil else { return }
        selectStudyEntry(nil)
    }

    private func studyEntrySelector(at index: Int?, in entries: [StudyBoardEntry]) -> (() -> Void)? {
        guard let index, entries.indices.contains(index) else { return nil }
        let id = entries[index].id
        return { selectStudyEntry(id) }
    }

    /// The next entry still waiting for a verdict, so judging up close moves
    /// straight on to it.
    private func nextStudyEntryToJudge(after id: StudyBoardEntry.ID) -> StudyBoardEntry.ID? {
        guard let study = currentStudyProject?.study else { return nil }
        let entries = StudyBoard(study: study).entries(for: studyFilter, matching: store.searchText)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let later = entries[(index + 1)...].first(where: { $0.verdict == .pending })
        let earlier = entries[..<index].first(where: { $0.verdict == .pending })
        return (later ?? earlier)?.id
    }

    private func savedInspiration(for suggestion: StudySuggestion) -> Inspiration? {
        guard let savedID = suggestion.savedInspirationID else { return nil }
        return store.snapshot.inspirations.first { $0.id == savedID }
    }

    private func studyCloseLookItems(_ ids: [Inspiration.ID]) -> [StudyCloseLookItem] {
        ids.compactMap { id in store.snapshot.inspirations.first { $0.id == id } }
            .map { StudyCloseLookItem(inspiration: $0, localImageURL: store.localImageURL(for: $0)) }
    }

    private func decide(
        _ suggestion: StudySuggestion,
        verdict: StudyVerdict,
        reason: String?,
        advancing: Bool
    ) {
        guard let projectID = currentStudyProjectID else { return }
        let upcoming = advancing && suggestion.status == .pending
            ? nextStudyEntryToJudge(after: suggestion.id)
            : nil
        Task { @MainActor in
            do {
                try await store.decideStudySuggestion(
                    projectID: projectID,
                    suggestionID: suggestion.id,
                    verdict: verdict,
                    reason: reason
                )
                if let upcoming, selectedStudyEntryID == suggestion.id {
                    selectStudyEntry(upcoming)
                }
                requestSync()
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func respond(
        _ reflection: StudyReflection,
        with response: StudyReflectionResponse,
        advancing: Bool
    ) {
        guard let projectID = currentStudyProjectID else { return }
        let upcoming = advancing && reflection.status == .pending
            ? nextStudyEntryToJudge(after: reflection.id)
            : nil
        Task { @MainActor in
            do {
                try await store.respondToStudyReflection(
                    projectID: projectID,
                    reflectionID: reflection.id,
                    response: response
                )
                if let upcoming, selectedStudyEntryID == reflection.id {
                    selectStudyEntry(upcoming)
                }
                requestSync()
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The page's name, written like the study board's subject, so the two
    /// boards of a study share one header line.
    private var moodboardHeader: some View {
        let project = currentProjectID.flatMap(project(with:))
        let edit = project.map { project in
            BoardPageEdit(
                title: project.isStudy ? "Edit Study…" : "Edit Project…",
                help: project.isStudy ? "Edit the subject and brief" : "Rename the project",
                hint: project.isStudy ? "Edits the subject and brief" : "Renames the project",
                action: { sheet = project.isStudy ? .startStudy(project) : .editProject(project) }
            )
        }
        return BoardPageHeader(
            title: project?.name ?? (store.scope == .general ? "General" : "All inspiration"),
            detail: project?.study?.brief ?? "",
            onEdit: edit
        )
    }

    /// Written on the page where the cards would be.
    @ViewBuilder
    private var moodboardEmptyNote: some View {
        if !store.searchText.isEmpty {
            BoardPageNote(
                title: "No matches",
                message: "Try a different title, author, note, or link."
            ) {
                Button("Clear Search") { store.searchText = "" }
            }
        } else if store.inspirations.isEmpty {
            BoardPageNote(
                title: "Start your moodboard",
                message: "Save what catches your eye from X or any page: interfaces and type, interiors, objects, and art."
            ) {
                HStack(spacing: 8) {
                    Button("Save a Link") { sheet = .capture }
                        .buttonStyle(.borderedProminent)
                    Button("Set Up Browser") { sheet = .browserSetup }
                }
            }
        } else {
            BoardPageNote(
                title: "Nothing here yet",
                message: store.scope == .general
                    ? "What you save without a project lands here."
                    : "Move things here from the moodboard, or save a link straight into this project."
            ) {
                Button("Save a Link") { sheet = .capture }
            }
        }
    }

    /// Clears the canvas chrome above a page's header.
    private let pageTopInset: CGFloat = 64

    /// Between a page's header and its first cards, the same on both
    /// boards, so switching between them leaves the cards' tops in place.
    private let pageHeaderGap: CGFloat = 24

    /// Room between study cards for the ink loops around kept ones.
    private let studyBoardSpacing: CGFloat = 24

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
        if let study = inspiration.projectID.flatMap(project(with:))?.study {
            Divider()
            Button("Find Ways to Make This Better") { startImproving(inspiration, lenses: .rams) }
            Button("Check Against Your Direction") { startImproving(inspiration, lenses: .direction) }
                .disabled(!study.reflections.contains { $0.status == .confirmed || $0.status == .corrected })
        }
        Divider()
        Button("Delete", role: .destructive) { pendingInspirationDeletion = inspiration }
    }

    /// Starts the study's agent on ways to make one of the person's own items
    /// better, then shows the board where the moves arrive.
    private func startImproving(_ inspiration: Inspiration, lenses: StudyAgentTarget.Lenses) {
        guard let projectID = inspiration.projectID,
              let project = project(with: projectID),
              project.isStudy else { return }
        guard !studyRunner.isBusy(projectID) else {
            showToast("The study's agent is already working", symbol: "hourglass")
            return
        }
        let target = StudyAgentTarget(
            inspirationID: inspiration.id,
            title: inspiration.meaningfulTitle ?? inspiration.title,
            lenses: lenses
        )
        Task {
            let configuration = StudyAgentSettings.load()
            let agent = await Task.detached { ResolvedStudyAgent.resolve(configuration) }.value
            guard let agent else {
                showToast("Set up a study agent first", symbol: "exclamationmark.triangle")
                return
            }
            do {
                try await studyRunner.start(
                    task: .improve,
                    project: project,
                    agent: agent,
                    configuration: configuration,
                    repository: store.repository,
                    target: target,
                    onProgress: { [store] in
                        await store.reload()
                    },
                    onChange: { [store, syncCoordinator] in
                        await store.reload()
                        guard let syncCoordinator else { return }
                        _ = await syncCoordinator.sync()
                        await store.reload()
                    }
                )
                closeDetailInspector()
                openStudyBoard(projectID)
                studyFilter = .toJudge
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ destination: SheetDestination) -> some View {
        switch destination {
        case .capture:
            CaptureSheet(projects: projects, initialProjectID: currentProjectID) { payload in
                let result = try await store.capture(payload)
                _ = await store.fillMissingPreview(for: result.inspiration.id)
                setSelectedInspiration(result.inspiration.id)
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
                setSelectedInspiration(updated.id)
                showToast("Item updated")
                requestSync()
            }
        case .browserSetup:
            BrowserSetupView()
        case .newStudy:
            StudyStartForm { subject, brief in
                let project = try await store.createStudy(subject: subject, brief: brief)
                openStudyBoard(project.id)
                showToast("Study started", symbol: "eye")
                requestSync()
            }
        case .startStudy(let project):
            StudyStartForm(existingProject: project) { subject, brief in
                try await store.startStudy(projectID: project.id, subject: subject, brief: brief)
                if project.isStudy {
                    store.scope = .project(project.id)
                } else {
                    openStudyBoard(project.id)
                }
                showToast(project.isStudy ? "Study updated" : "Study started", symbol: "eye")
                requestSync()
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            // A capsule on one line, keeping its rounded ends when a longer
            // message, like a sync error, wraps.
            let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
            Label(toast.message, systemImage: toast.symbol)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThickMaterial, in: shape)
                .overlay { shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var projects: [Project] {
        store.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var sidebarItems: [MacProjectSidebarItem] {
        let counts = store.counts
        let covers = store.snapshot.projectCovers()
        var items = [
            MacProjectSidebarItem(
                scope: .all,
                title: "All inspiration",
                count: counts.total,
                colorHex: nil,
                cover: nil,
                project: nil
            ),
            MacProjectSidebarItem(
                scope: .general,
                title: "General",
                count: counts.general,
                colorHex: nil,
                cover: nil,
                project: nil
            ),
        ]
        items.append(
            contentsOf: projects.map { project in
                MacProjectSidebarItem(
                    scope: .project(project.id),
                    title: project.name,
                    count: counts[project.id],
                    colorHex: project.colorHex,
                    cover: covers[project.id].map { cover in
                        MacProjectSidebarCover(
                            localURL: store.localImageURL(for: cover),
                            remoteURL: cover.imageURL
                        )
                    },
                    project: project
                )
            }
        )
        return items
    }

    private var selectedInspiration: Inspiration? {
        guard let selectedInspirationID else { return nil }
        return store.inspirations.first { $0.id == selectedInspirationID }
    }

    private var detailPanelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    private var detailPanelStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.16)
    }

    private var detailInspectorAnimation: Animation? {
        reduceMotion ? nil : MacChromeMotion.panel
    }

    private func closeDetailInspector() {
        guard selectedInspirationID != nil else { return }
        setSelectedInspiration(nil)
    }

    private func setSelectedInspiration(_ id: Inspiration.ID?) {
        let changesPanelPresentation = (selectedInspirationID == nil) != (id == nil)
        if changesPanelPresentation {
            withAnimation(detailInspectorAnimation) {
                selectedInspirationID = id
            }
        } else {
            withAnimation(reduceMotion ? nil : StudyBoardMotion.step) {
                selectedInspirationID = id
            }
        }
    }

    private var currentStudyProjectID: Project.ID? {
        guard let id = currentProjectID, project(with: id)?.isStudy == true else { return nil }
        return id
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
                    _ = await store.fillMissingPreview(for: result.inspiration.id)
                    newest = result.inspiration
                }
                setSelectedInspiration(newest?.id)
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
                if selectedInspirationID == inspiration.id { setSelectedInspiration(nil) }
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

    private func toggleProjectSidebar() {
        withAnimation(reduceMotion ? nil : MacChromeMotion.chrome) {
            isProjectSidebarCollapsed.toggle()
        }
    }

    private func showProjectSidebar() {
        guard isProjectSidebarCollapsed else { return }
        withAnimation(reduceMotion ? nil : MacChromeMotion.chrome) {
            isProjectSidebarCollapsed = false
        }
    }

    private func beginSearch() {
        withAnimation(reduceMotion ? nil : MacChromeMotion.quick) {
            isSearching = true
            searchActivation = UUID()
        }
    }

    private func dismissSearch() {
        withAnimation(reduceMotion ? nil : MacChromeMotion.quick) {
            store.searchText = ""
            isSearching = false
        }
    }

    private func selectSpace(_ scope: LibraryScope) {
        if scope != store.scope {
            selectStudyEntry(nil)
            studyFilter = .all
        }
        withAnimation(reduceMotion ? nil : MacChromeMotion.fade) {
            store.scope = scope
        }
        if let selectedInspiration, !scope.contains(selectedInspiration) {
            setSelectedInspiration(nil)
        }
    }

    private func handleExitCommand() {
        if selectedStudyEntryID != nil {
            closeStudyCloseLook()
        } else if selectedInspirationID != nil {
            closeDetailInspector()
        } else if isSearching {
            if store.searchText.isEmpty {
                dismissSearch()
            } else {
                store.searchText = ""
            }
        }
    }

    private func reveal(_ inspiration: Inspiration) {
        if !store.scope.contains(inspiration) {
            store.scope = .space(containing: inspiration)
        }
    }

    private func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        let next = ToastMessage(message: message, symbol: symbol)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { toast = next }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard toast?.id == next.id else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.16)) { toast = nil }
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

/// The soft scroll edge under the floating canvas chrome, where the system
/// has one.
private struct SoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
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
        // Every column starts on the same line; the cards' own heights make
        // the rhythm.
        var columnHeights = Array(repeating: CGFloat.zero, count: count)
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

/// What the study board shows, watched so finds that arrive while it's open
/// can develop into place.
private struct MacStudyBoardObservation: Equatable {
    var projectID: Project.ID?
    var entryIDs: [StudyBoardEntry.ID]
}

/// Keep and reject on a find's card, shown on hover, for judging at a glance.
/// The close look is where the person says why.
private struct MacStudyQuickVerdict: ViewModifier {
    let isAvailable: Bool
    let onDecide: (StudyVerdict) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            // The buttons sit over the card and take the pointer from it,
            // so the card stays lifted while they're the ones hovered.
            .environment(\.holdsCardHover, isAvailable && isHovering)
            .overlay(alignment: .topTrailing) {
                if isAvailable, isHovering {
                    HStack(spacing: 5) {
                        verdictButton("Keep", symbol: "checkmark", verdict: .keep)
                        verdictButton("Reject", symbol: "xmark", verdict: .reject)
                    }
                    .padding(9)
                    // Grows out of the corner it sits in, rather than just fading.
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity)
                    )
                }
            }
            // Tracked over the card and its buttons together: watching the
            // card alone ends the hover as the pointer reaches a button,
            // which hid the buttons before they could be clicked.
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82),
                value: isHovering
            )
            .accessibilityActions {
                if isAvailable {
                    Button("Keep") { onDecide(.keep) }
                    Button("Reject") { onDecide(.reject) }
                }
            }
    }

    private func verdictButton(_ title: String, symbol: String, verdict: StudyVerdict) -> some View {
        Button {
            onDecide(verdict)
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Color.white, in: Circle())
                .overlay { Circle().strokeBorder(.black.opacity(0.1), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(MacQuickVerdictButtonStyle())
        .help(title)
    }
}

/// Presses in under the pointer and springs back, like the cards around it.
private struct MacQuickVerdictButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

private enum SheetDestination: Identifiable {
    case capture
    case newProject
    case editProject(Project)
    case editInspiration(Inspiration)
    case browserSetup
    case newStudy
    case startStudy(Project)

    var id: String {
        switch self {
        case .capture: "capture"
        case .newProject: "new-project"
        case .editProject(let project): "edit-project-\(project.id)"
        case .editInspiration(let inspiration): "edit-inspiration-\(inspiration.id)"
        case .browserSetup: "browser-setup"
        case .newStudy: "new-study"
        case .startStudy(let project): "start-study-\(project.id)"
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
    static let pinaxFind = Notification.Name("Pinax.find")
    static let pinaxSwitchProject = Notification.Name("Pinax.switchProject")
    static let pinaxToggleProjectSidebar = Notification.Name("Pinax.toggleProjectSidebar")
}
