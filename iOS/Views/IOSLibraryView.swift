import PinaxCloudSync
import PinaxCore
import SwiftUI

struct IOSLibraryView: View {
    @Bindable var store: LibraryStore
    @Bindable var syncCoordinator: PinaxSyncCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(
        resetTransaction: Transaction(
            animation: .interactiveSpring(
                response: 0.26,
                dampingFraction: 0.88,
                blendDuration: 0.1
            )
        )
    ) private var canvasPinch = CanvasPinchState.inactive
    @AppStorage("iosCanvasColumnCount") private var settledCanvasColumnCount = 2
    @State private var navigationPath: [Inspiration.ID] = []
    @State private var canvasInteractionPhase = CanvasInteractionPhase.idle
    @State private var sheet: LibrarySheet?
    @State private var inspirationToDelete: Inspiration?
    @State private var message: LibraryMessage?
    @State private var operationError: String?
    @AppStorage("iosStudyShowsBoard") private var prefersStudyBoard = true
    @State private var studyFilter = StudyBoardFilter.all
    @State private var studyArrivals = StudyBoardArrivals()
    @State private var studyCloseLookEntryID: StudyBoardEntry.ID?
    @State private var studyNudge = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                libraryContent

                if let message {
                    ToastView(message: message.text)
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .navigationTitle(Text(ProductIdentity.displayName))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $store.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search your moodboard"
            )
            .toolbar { toolbarContent }
            .tint(.pinaxPlum)
            .navigationDestination(for: Inspiration.ID.self) { inspirationID in
                IOSInspirationDetailView(
                    store: store,
                    inspirationID: inspirationID,
                    onMutation: requestSync
                )
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .manualCapture:
                ManualCaptureView(
                    projects: store.projects,
                    initialProjectID: selectedProjectID
                ) { payload in
                    let result = try await store.capture(payload)
                    _ = await store.fillMissingPreview(for: result.inspiration.id)
                    showMessage(result.inserted ? "Saved to mood." : "Updated in mood.")
                    requestSync()
                }
            case .projects:
                ProjectManagerView(store: store, onMutation: requestSync)
            case .editInspiration(let inspiration):
                InspirationEditorView(
                    inspiration: inspiration,
                    projects: store.projects
                ) { updated in
                    _ = try await store.updateInspiration(updated)
                    showMessage("Changes saved")
                    requestSync()
                }
            case .newStudy:
                StudyStartForm { subject, brief in
                    let project = try await store.createStudy(subject: subject, brief: brief)
                    store.scope = .project(project.id)
                    prefersStudyBoard = true
                    showMessage("Study started")
                    requestSync()
                }
                .presentationDetents([.medium, .large])
            case .startStudy(let project):
                StudyStartForm(existingProject: project) { subject, brief in
                    try await store.startStudy(projectID: project.id, subject: subject, brief: brief)
                    store.scope = .project(project.id)
                    if !project.isStudy {
                        prefersStudyBoard = true
                    }
                    showMessage(project.isStudy ? "Study updated" : "Study started")
                    requestSync()
                }
                .presentationDetents([.medium, .large])
            case .studyCloseLook(let projectID):
                studyCloseLookSheet(projectID: projectID)
            }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: Binding(
                get: { inspirationToDelete != nil },
                set: { if !$0 { inspirationToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: inspirationToDelete
        ) { inspiration in
            Button("Delete", role: .destructive) {
                Task { await delete(inspiration) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the item from your moodboard.")
        }
        .alert(
            "mood. couldn't complete that",
            isPresented: Binding(
                get: {
                    operationError != nil
                        || store.lastError != nil
                        || syncCoordinator.lastError != nil
                },
                set: { isPresented in
                    if !isPresented {
                        operationError = nil
                        store.clearError()
                        syncCoordinator.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                operationError = nil
                store.clearError()
                syncCoordinator.clearError()
            }
        } message: {
            Text(
                operationError
                    ?? store.lastError
                    ?? syncCoordinator.lastError
                    ?? "An unknown error occurred."
            )
        }
        .task {
            await syncAndReload()
        }
        .task(id: canvasInteractionPhase) {
            await unlockCanvasInteractionAfterSettling()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await syncAndReload() }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onChange(of: canvasPinch.isActive) { wasActive, isActive in
            guard wasActive,
                  !isActive,
                  canvasInteractionPhase == .pinching else { return }
            canvasInteractionPhase = .settling
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        VStack(spacing: 0) {
            ScopeBar(store: store) {
                sheet = .projects
            }

            if selectedProject?.isStudy == true {
                Picker("Show", selection: $prefersStudyBoard) {
                    Text("Moodboard").tag(false)
                    Text("Study board").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if showsStudyBoard, let project = selectedProject, let study = project.study {
                studyBoard(project: project, study: study)
            } else if store.isLoading, store.snapshot.inspirations.isEmpty {
                Spacer()
                ProgressView("Opening library…")
                Spacer()
            } else if store.visibleInspirations.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    InterleavedCardLayout(
                        columnPosition: reduceMotion
                            ? CGFloat(activeCanvasColumnCount)
                            : canvasLayoutColumnPosition,
                        minimumColumnCount: canvasZoomBehavior.minimumColumnCount,
                        maximumColumnCount: maximumCanvasColumnCount
                    ) {
                        ForEach(store.visibleInspirations) { inspiration in
                            card(
                                for: inspiration,
                                columnCount: activeCanvasColumnCount
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 34)
                    .transaction { transaction in
                        guard reduceMotion else { return }
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                    .scaleEffect(
                        reduceMotion ? 1 : canvasBoundaryScale,
                        anchor: canvasPinch.anchor
                    )
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("inspirationCanvas")
                .accessibilityValue("\(activeCanvasColumnCount) columns")
                .simultaneousGesture(canvasZoomGesture)
                .refreshable {
                    await syncAndReload()
                }
            }
        }
        .background(Color.pinaxCanvas)
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.snapshot.inspirations.isEmpty {
            ContentUnavailableView {
                Label("Start your moodboard", systemImage: "sparkles.rectangle.stack")
            } description: {
                VStack(spacing: 8) {
                    Text("Collect visual ideas from X and the web — from interfaces and type to interiors, fashion, objects, and art.")
                    Text("In the X app, tap Share on a post, choose Share via…, then choose Save to mood. If it isn't visible, tap More to enable it.")
                }
            } actions: {
                Button {
                    sheet = .manualCapture
                } label: {
                    Label("Save a link", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button("Manage projects") {
                    sheet = .projects
                }
            }
            .padding(24)
        } else if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: store.searchText)
        } else {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "rectangle.stack")
            } description: {
                Text("Move saved visuals here or add a new link to this project.")
            } actions: {
                Button {
                    sheet = .manualCapture
                } label: {
                    Label("Save a link", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(ProductIdentity.displayName)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(Text(ProductIdentity.spokenName))
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    sheet = .manualCapture
                } label: {
                    Label("Save a link", systemImage: "link.badge.plus")
                }
                Button {
                    sheet = .projects
                } label: {
                    Label("Manage projects", systemImage: "folder")
                }
                Button {
                    sheet = .newStudy
                } label: {
                    Label("New visual study", systemImage: "eye")
                }
                if let project = selectedProject, !project.isStudy {
                    Button {
                        sheet = .startStudy(project)
                    } label: {
                        Label("Start a study on \(project.name)", systemImage: "eye")
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add to mood")
        }
    }

    // MARK: Study board

    private var showsStudyBoard: Bool {
        prefersStudyBoard && selectedProject?.isStudy == true
    }

    /// Every find and pattern of the selected study, on the same pinch-zoom
    /// masonry as the moodboard. Finds that arrive while it's open develop
    /// into place.
    private func studyBoard(project: Project, study: ProjectStudy) -> some View {
        let board = StudyBoard(study: study)
        let entries = board.entries(for: studyFilter, matching: store.searchText)
        let isSearchingText = !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let observation = IOSStudyBoardObservation(projectID: project.id, entryIDs: board.entries.map(\.id))

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StudyBoardHeader(
                    study: study,
                    board: board,
                    filter: $studyFilter,
                    onEdit: { sheet = .startStudy(project) }
                ) {
                    studyAgentHandoff(for: project)
                }

                if entries.isEmpty {
                    StudyBoardEmptyState(
                        stage: study.stage(itemCount: store.studyItems(for: project.id).count),
                        filter: studyFilter,
                        boardIsEmpty: board.isEmpty,
                        isSearchingText: isSearchingText && !board.isEmpty
                    )
                } else {
                    InterleavedCardLayout(
                        columnPosition: reduceMotion
                            ? CGFloat(activeCanvasColumnCount)
                            : canvasLayoutColumnPosition,
                        minimumColumnCount: canvasZoomBehavior.minimumColumnCount,
                        maximumColumnCount: maximumCanvasColumnCount
                    ) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            studyCard(entry, project: project, columnCount: activeCanvasColumnCount)
                                .transition(
                                    StudyBoardMotion.cardTransition(
                                        index: index,
                                        arrivedJustNow: studyArrivals.fresh.contains(entry.id),
                                        reduceMotion: reduceMotion
                                    )
                                )
                        }
                    }
                    .scaleEffect(
                        reduceMotion ? 1 : canvasBoundaryScale,
                        anchor: canvasPinch.anchor
                    )
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 34)
            .animation(reduceMotion ? nil : StudyBoardMotion.settle, value: entries.map(\.id))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studyBoard")
        .simultaneousGesture(canvasZoomGesture)
        .refreshable {
            await syncAndReload()
        }
        .onChange(of: observation, initial: true) { old, new in
            noteStudyArrivals(from: old, to: new)
        }
    }

    /// iOS doesn't start agents itself: it hands over a prompt, with the
    /// person's nudge, for an agent on another machine.
    private func studyAgentHandoff(for project: Project) -> some View {
        HStack(spacing: 8) {
            TextField("Nudge", text: $studyNudge, prompt: Text("Nudge it: warmer light…"))
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityLabel("Nudge the search")

            Button {
                StudyAgentPromptText.copy(for: project, nudge: studyNudge)
                showMessage("Copied. Paste it into an agent with mood-study")
            } label: {
                Label("Copy prompt", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func studyCard(_ entry: StudyBoardEntry, project: Project, columnCount: Int) -> some View {
        switch entry {
        case .finding(let suggestion):
            let item = savedInspiration(for: suggestion)
                ?? suggestion.previewInspiration(projectID: project.id)
            Button {
                guard allowsCardInteraction else { return }
                openStudyCloseLook(entry.id, projectID: project.id)
            } label: {
                IOSInspirationCard(
                    inspiration: item,
                    localImageURL: store.localImageURL(for: item),
                    canvasColumnCount: columnCount
                )
                .environment(\.previewImageReveal, studyArrivals.reveal(for: entry.id))
                .studyBoardVerdict(entry.verdict)
            }
            .buttonStyle(CollectedCardButtonStyle())
            .contextMenu { studyFindingMenu(suggestion, projectID: project.id) }
            .disabled(!allowsCardInteraction)
            .allowsHitTesting(allowsCardInteraction)
        case .pattern(let reflection):
            Button {
                guard allowsCardInteraction else { return }
                openStudyCloseLook(entry.id, projectID: project.id)
            } label: {
                StudyPatternCard(
                    reflection: reflection,
                    columns: columnCount,
                    developsOnArrival: studyArrivals.fresh.contains(entry.id)
                )
                .studyBoardVerdict(entry.verdict)
            }
            .buttonStyle(CollectedCardButtonStyle())
            .contextMenu { studyPatternMenu(reflection, projectID: project.id) }
            .disabled(!allowsCardInteraction)
            .allowsHitTesting(allowsCardInteraction)
        }
    }

    @ViewBuilder
    private func studyFindingMenu(_ suggestion: StudySuggestion, projectID: Project.ID) -> some View {
        Button {
            openStudyCloseLook(suggestion.id, projectID: projectID)
        } label: {
            Label("Look closer", systemImage: "eye")
        }
        switch suggestion.status {
        case .pending:
            Button {
                decide(suggestion, projectID: projectID, verdict: .keep, reason: nil, advancing: false)
            } label: {
                Label("Keep", systemImage: "checkmark")
            }
            Button {
                decide(suggestion, projectID: projectID, verdict: .reject, reason: nil, advancing: false)
            } label: {
                Label("Reject", systemImage: "xmark")
            }
        case .kept:
            EmptyView()
        case .rejected:
            Button {
                decide(suggestion, projectID: projectID, verdict: .keep, reason: suggestion.reason, advancing: false)
            } label: {
                Label("Keep instead", systemImage: "arrow.uturn.backward")
            }
        }
        Link(destination: suggestion.url) {
            Label("Open source page", systemImage: "safari")
        }
        ShareLink(item: suggestion.url) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder
    private func studyPatternMenu(_ reflection: StudyReflection, projectID: Project.ID) -> some View {
        Button {
            openStudyCloseLook(reflection.id, projectID: projectID)
        } label: {
            Label("Look closer", systemImage: "eye")
        }
        Button {
            respond(reflection, projectID: projectID, with: .confirm, advancing: false)
        } label: {
            Label("That's right", systemImage: "checkmark")
        }
        .disabled(reflection.status == .confirmed)
        Button {
            respond(reflection, projectID: projectID, with: .dismiss, advancing: false)
        } label: {
            Label("Not me", systemImage: "xmark")
        }
        .disabled(reflection.status == .dismissed)
    }

    @ViewBuilder
    private func studyCloseLookSheet(projectID: Project.ID) -> some View {
        if let study = store.snapshot.project(id: projectID)?.study,
           let entryID = studyCloseLookEntryID,
           let entry = StudyBoard(study: study).entry(id: entryID) {
            let entries = StudyBoard(study: study).entries(for: studyFilter, matching: store.searchText)
            let index = entries.firstIndex(where: { $0.id == entry.id })

            CloseLookFrame(
                position: index.map { $0 + 1 },
                count: entries.count,
                onPrevious: studyEntrySelector(at: index.map { $0 - 1 }, in: entries),
                onNext: studyEntrySelector(at: index.map { $0 + 1 }, in: entries),
                onClose: { sheet = nil }
            ) {
                // Stacked, so stepping crossfades one entry into the next
                // while the frame and its counter stay still.
                ZStack {
                    Group {
                        switch entry {
                        case .finding(let suggestion):
                            StudyFindingCloseLook(
                                suggestion: suggestion,
                                savedImageURL: savedInspiration(for: suggestion).flatMap { store.localImageURL(for: $0) },
                                relatedItems: studyCloseLookItems(suggestion.basedOnInspirationIDs),
                                onDecide: { verdict, reason in
                                    decide(suggestion, projectID: projectID, verdict: verdict, reason: reason, advancing: true)
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
                                    respond(reflection, projectID: projectID, with: response, advancing: true)
                                }
                            )
                        }
                    }
                    .id(entry.id)
                    .transition(.opacity)
                }
            }
            .presentationDragIndicator(.visible)
            .modifier(PageSizedSheet())
        } else {
            ContentUnavailableView(
                "Nothing to show",
                systemImage: "eye.slash",
                description: Text("This is no longer part of the study.")
            )
        }
    }

    private func openStudyCloseLook(_ id: StudyBoardEntry.ID, projectID: Project.ID) {
        studyCloseLookEntryID = id
        sheet = .studyCloseLook(projectID)
    }

    private func studyEntrySelector(at index: Int?, in entries: [StudyBoardEntry]) -> (() -> Void)? {
        guard let index, entries.indices.contains(index) else { return nil }
        let id = entries[index].id
        return { showStudyCloseLookEntry(id) }
    }

    private func showStudyCloseLookEntry(_ id: StudyBoardEntry.ID) {
        withAnimation(reduceMotion ? nil : StudyBoardMotion.step) {
            studyCloseLookEntryID = id
        }
    }

    /// Finds that arrive while the board is open develop into place; what was
    /// there when it opened stays still.
    private func noteStudyArrivals(from old: IOSStudyBoardObservation, to new: IOSStudyBoardObservation) {
        if old.projectID != new.projectID || old == new {
            studyArrivals.reset()
        }
        let arrived = studyArrivals.note(new.entryIDs)
        guard !arrived.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            studyArrivals.settle(arrived)
        }
    }

    /// The next entry still waiting for a verdict, so judging up close moves
    /// straight on to it.
    private func nextStudyEntryToJudge(after id: StudyBoardEntry.ID, projectID: Project.ID) -> StudyBoardEntry.ID? {
        guard let study = store.snapshot.project(id: projectID)?.study else { return nil }
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
        projectID: Project.ID,
        verdict: StudyVerdict,
        reason: String?,
        advancing: Bool
    ) {
        let upcoming = advancing && suggestion.status == .pending
            ? nextStudyEntryToJudge(after: suggestion.id, projectID: projectID)
            : nil
        Task { @MainActor in
            do {
                try await store.decideStudySuggestion(
                    projectID: projectID,
                    suggestionID: suggestion.id,
                    verdict: verdict,
                    reason: reason
                )
                if let upcoming, studyCloseLookEntryID == suggestion.id {
                    showStudyCloseLookEntry(upcoming)
                }
                requestSync()
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func respond(
        _ reflection: StudyReflection,
        projectID: Project.ID,
        with response: StudyReflectionResponse,
        advancing: Bool
    ) {
        let upcoming = advancing && reflection.status == .pending
            ? nextStudyEntryToJudge(after: reflection.id, projectID: projectID)
            : nil
        Task { @MainActor in
            do {
                try await store.respondToStudyReflection(
                    projectID: projectID,
                    reflectionID: reflection.id,
                    response: response
                )
                if let upcoming, studyCloseLookEntryID == reflection.id {
                    showStudyCloseLookEntry(upcoming)
                }
                requestSync()
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private var maximumCanvasColumnCount: Int {
        horizontalSizeClass == .regular ? 6 : 4
    }

    private var activeCanvasColumnCount: Int {
        guard !dynamicTypeSize.isAccessibilitySize, !voiceOverEnabled else { return 1 }
        return canvasZoomBehavior.clampedColumnCount(settledCanvasColumnCount)
    }

    private var canvasZoomBehavior: CanvasZoomBehavior {
        CanvasZoomBehavior(maximumColumnCount: maximumCanvasColumnCount)
    }

    private var canvasZoomEnabled: Bool {
        !dynamicTypeSize.isAccessibilitySize && !voiceOverEnabled
    }

    private var canvasLayoutBaseColumnCount: Int {
        guard canvasPinch.isActive else { return activeCanvasColumnCount }
        return canvasZoomBehavior.clampedColumnCount(canvasPinch.baseColumnCount)
    }

    private var canvasLayoutPreview: CanvasZoomPreview {
        let base = canvasLayoutBaseColumnCount
        guard canvasZoomEnabled, canvasPinch.isActive else {
            return CanvasZoomPreview(
                targetColumnCount: base,
                progress: 0,
                shouldCommit: false
            )
        }
        return canvasZoomBehavior.preview(
            from: base,
            magnification: canvasPinch.magnification
        )
    }

    /// A fractional density is the layout's animatable value. While the
    /// fingers are down it follows the resisted preview directly; when the
    /// gesture state resets, SwiftUI can spring this scalar back to the base
    /// integer or onward to the committed adjacent integer.
    private var canvasLayoutColumnPosition: CGFloat {
        let base = CGFloat(canvasLayoutBaseColumnCount)
        let preview = canvasLayoutPreview
        return base
            + ((CGFloat(preview.targetColumnCount) - base) * preview.progress)
    }

    private var canvasBoundaryScale: CGFloat {
        guard canvasZoomEnabled,
              canvasPinch.isActive,
              canvasLayoutPreview.targetColumnCount == canvasLayoutBaseColumnCount
        else { return 1 }
        return canvasZoomBehavior.elasticScale(
            for: canvasPinch.magnification,
            currentColumnCount: canvasLayoutBaseColumnCount
        )
    }

    private var canvasSettleAnimation: Animation {
        .interactiveSpring(
            response: 0.26,
            dampingFraction: 0.88,
            blendDuration: 0.1
        )
    }

    private var allowsCardInteraction: Bool {
        canvasInteractionPhase == .idle
    }

    private var canvasZoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.03)
            .updating($canvasPinch) { value, state, transaction in
                transaction.animation = nil
                transaction.isContinuous = true
                state = CanvasPinchState(
                    baseColumnCount: state.isActive
                        ? state.baseColumnCount
                        : activeCanvasColumnCount,
                    magnification: value.magnification,
                    anchor: value.startAnchor,
                    isActive: true
                )
            }
            .onChanged { _ in
                guard canvasZoomEnabled,
                      canvasInteractionPhase != .pinching else { return }
                canvasInteractionPhase = .pinching
            }
            .onEnded { value in
                guard canvasZoomEnabled else {
                    canvasInteractionPhase = .idle
                    return
                }
                canvasInteractionPhase = .settling
                let target = canvasZoomBehavior.targetColumnCount(
                    from: canvasPinch.isActive
                        ? canvasPinch.baseColumnCount
                        : activeCanvasColumnCount,
                    magnification: value.magnification
                )
                setCanvasDensity(target)
            }
    }

    @MainActor
    private func unlockCanvasInteractionAfterSettling() async {
        guard canvasInteractionPhase == .settling else { return }

        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }

        guard !Task.isCancelled,
              canvasInteractionPhase == .settling else { return }
        canvasInteractionPhase = .idle
    }

    private func setCanvasDensity(_ columnCount: Int) {
        let target = canvasZoomBehavior.clampedColumnCount(columnCount)
        let persisted = canvasZoomBehavior.clampedColumnCount(
            settledCanvasColumnCount
        )
        guard target != persisted else { return }

        if reduceMotion {
            settledCanvasColumnCount = target
        } else {
            withAnimation(canvasSettleAnimation) {
                settledCanvasColumnCount = target
            }
        }
    }

    private func card(
        for inspiration: Inspiration,
        columnCount: Int
    ) -> some View {
        Button {
            guard allowsCardInteraction else { return }
            navigationPath.append(inspiration.id)
        } label: {
            IOSInspirationCard(
                inspiration: inspiration,
                localImageURL: store.localImageURL(for: inspiration),
                canvasColumnCount: columnCount
            )
        }
        .buttonStyle(CollectedCardButtonStyle())
        .contextMenu {
            cardMenu(for: inspiration)
        }
        .disabled(!allowsCardInteraction)
        .allowsHitTesting(allowsCardInteraction)
    }

    @ViewBuilder
    private func cardMenu(for inspiration: Inspiration) -> some View {
        Button {
            sheet = .editInspiration(inspiration)
        } label: {
            Label("Edit", systemImage: "pencil")
        }

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

        Button(role: .destructive) {
            inspirationToDelete = inspiration
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var selectedProject: Project? {
        selectedProjectID.flatMap { store.snapshot.project(id: $0) }
    }

    private var selectedProjectID: Project.ID? {
        guard case .project(let projectID) = store.scope else { return nil }
        return projectID
    }

    private func move(_ inspiration: Inspiration, to projectID: Project.ID?) {
        guard inspiration.projectID != projectID else { return }
        Task { @MainActor in
            do {
                _ = try await store.moveInspiration(id: inspiration.id, to: projectID)
                showMessage(projectID.flatMap(store.snapshot.project(id:))?.name ?? "Moved to General")
                requestSync()
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func delete(_ inspiration: Inspiration) async {
        inspirationToDelete = nil
        do {
            _ = try await store.deleteInspiration(id: inspiration.id)
            showMessage("Item deleted")
            requestSync()
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func handleDeepLink(_ url: URL) {
        Task { @MainActor in
            do {
                let payload = try IOSCaptureDeepLink.payload(from: url)
                let result = try await store.capture(payload)
                _ = await store.fillMissingPreview(for: result.inspiration.id)
                showMessage(result.inserted ? "Saved to mood." : "Updated in mood.")
                requestSync()
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func showMessage(_ text: String) {
        let message = LibraryMessage(text: text)
        withAnimation(.snappy) { self.message = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard self.message?.id == message.id else { return }
            withAnimation(.easeOut(duration: 0.18)) { self.message = nil }
        }
    }

    @MainActor
    private func syncAndReload() async {
        await store.reload()
        _ = await syncCoordinator.sync()
        await store.reload()
    }

    private func requestSync() {
        Task { @MainActor in
            await syncAndReload()
        }
    }
}

private struct InterleavedCardLayout: Layout {
    var columnPosition: CGFloat
    let minimumColumnCount: Int
    let maximumColumnCount: Int

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
        let pair = measurementPair(for: width, subviews: subviews, cache: &cache)
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
            horizontalSpacing: horizontalSpacing(for: lowerColumnCount),
            verticalSpacing: verticalSpacing(for: lowerColumnCount),
            subviews: subviews,
            cache: &cache
        )
        guard upperColumnCount != lowerColumnCount, columnInterpolation > 0 else {
            return (start, start)
        }
        let end = measurements(
            for: width,
            columnCount: upperColumnCount,
            horizontalSpacing: horizontalSpacing(for: upperColumnCount),
            verticalSpacing: verticalSpacing(for: upperColumnCount),
            subviews: subviews,
            cache: &cache
        )
        return (start, end)
    }

    private func horizontalSpacing(for columnCount: Int) -> CGFloat {
        columnCount >= 4 ? 8 : 12
    }

    private func verticalSpacing(for columnCount: Int) -> CGFloat {
        switch columnCount {
        case 1...2: 18
        case 3: 14
        default: 10
        }
    }

    private func measurements(
        for width: CGFloat,
        columnCount: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat,
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
        var columnHeights = Array(repeating: CGFloat.zero, count: count)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for (index, subview) in subviews.enumerated() {
            let column = index % count
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

private struct CanvasPinchState: Equatable {
    static let inactive = CanvasPinchState(
        baseColumnCount: 1,
        magnification: 1,
        anchor: .center,
        isActive: false
    )

    let baseColumnCount: Int
    let magnification: CGFloat
    let anchor: UnitPoint
    let isActive: Bool
}

private struct ScopeBar: View {
    @Bindable var store: LibraryStore
    let onManageProjects: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                scopeButton("All", count: store.counts.total, scope: .all)
                scopeButton("General", count: store.counts.general, scope: .general)

                ForEach(store.projects) { project in
                    scopeButton(
                        project.name,
                        count: store.counts[project.id],
                        scope: .project(project.id),
                        color: Color(pinaxHex: project.colorHex)
                    )
                }

                Button(action: onManageProjects) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage projects")
            }
            .padding(.horizontal, 16)
        }
        .background(.bar)
    }

    private func scopeButton(
        _ title: String,
        count: Int,
        scope: LibraryScope,
        color: Color? = nil
    ) -> some View {
        Button {
            withAnimation(.snappy) { store.scope = scope }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    if let color {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                    }
                    Text(title)
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Capsule()
                    .fill(store.scope == scope ? Color.pinaxPlum : .clear)
                    .frame(height: 2)
            }
            .font(.subheadline.weight(store.scope == scope ? .semibold : .regular))
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) visual\(count == 1 ? "" : "s")")
        .accessibilityAddTraits(store.scope == scope ? .isSelected : [])
    }
}

private struct CollectedCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.08)
                    : .spring(response: 0.22, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

/// A close look gets the whole page on iPad, so the image can sit beside
/// its details; iPhone sheets are full height already.
private struct PageSizedSheet: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

/// What the study board shows, watched so finds that arrive while it's open
/// can develop into place.
private struct IOSStudyBoardObservation: Equatable {
    var projectID: Project.ID
    var entryIDs: [StudyBoardEntry.ID]
}

private enum LibrarySheet: Identifiable {
    case manualCapture
    case projects
    case editInspiration(Inspiration)
    case newStudy
    case startStudy(Project)
    case studyCloseLook(Project.ID)

    var id: String {
        switch self {
        case .manualCapture:
            "manual-capture"
        case .projects:
            "projects"
        case .editInspiration(let inspiration):
            "edit-\(inspiration.id.uuidString)"
        case .newStudy:
            "new-study"
        case .startStudy(let project):
            "start-study-\(project.id.uuidString)"
        case .studyCloseLook(let projectID):
            "study-close-look-\(projectID.uuidString)"
        }
    }
}

private enum CanvasInteractionPhase: Equatable {
    case idle
    case pinching
    case settling
}

private struct LibraryMessage: Identifiable {
    let id = UUID()
    let text: String
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.black.opacity(0.82), in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
            .accessibilityAddTraits(.isStaticText)
    }
}
