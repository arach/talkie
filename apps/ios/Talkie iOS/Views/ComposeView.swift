import CoreData
import Observation
import SwiftUI
import TalkieMobileKit
import UIKit

private enum ComposeRevisionPath: String, CaseIterable, Identifiable {
    case direct
    case mac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct:
            return "API"
        case .mac:
            return "Mac"
        }
    }

    var systemImage: String {
        switch self {
        case .direct:
            return "network"
        case .mac:
            return "desktopcomputer"
        }
    }
}

enum ComposeMicPlacement {
    case bottomCenter
    case bottomTrailing

    var alignment: Alignment {
        switch self {
        case .bottomCenter:
            return .bottom
        case .bottomTrailing:
            return .bottomTrailing
        }
    }

    var contentBottomInset: CGFloat {
        switch self {
        case .bottomCenter:
            return 76
        case .bottomTrailing:
            return 64
        }
    }
}

@MainActor
@Observable
private final class ComposeVoiceCommandState {
    var dictationState: InlineDictationController.State = .idle
    var errorMessage: String?
    var latestTranscript: String?

    private let controller = InlineDictationController()
    private var didConfigure = false

    func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        controller.onStateChange = { [weak self] state in
            self?.dictationState = state
        }
        controller.onTranscript = { [weak self] transcript in
            self?.errorMessage = nil
            self?.latestTranscript = transcript
        }
        controller.onError = { [weak self] message in
            self?.errorMessage = message
            self?.dictationState = .idle
        }
    }

    func toggle(canStart: Bool) {
        errorMessage = nil

        switch controller.currentState {
        case .idle:
            guard canStart else { return }
            Task {
                await controller.start()
            }
        case .recording:
            controller.stop(insertTranscript: true)
        case .transcribing:
            break
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func consumeTranscript() {
        latestTranscript = nil
    }

    func cancel() {
        controller.cancel()
    }
}

struct ComposeView: View {
    enum PresentationStyle {
        case sheet
        case embedded
    }

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let presentationStyle: PresentationStyle
    private let onBack: (() -> Void)?

    @State private var bridgeManager = BridgeManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @StateObject private var themeManager = ThemeManager.shared

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var savedNotes: FetchedResults<ComposeNote>

    @State private var draftText = ""
    @State private var instructionText = ""
    @State private var pendingRevision: ComposePendingRevision?
    @State private var appliedRevisions: [ComposeAppliedRevision] = []
    @State private var isRevising = false
    @State private var errorMessage: String?
    @State private var dictationState: InlineDictationController.State = .idle
    @State private var dictationError: String?
    @State private var draftDictationTrigger = 0
    @State private var draftDictationResetTrigger = 0
    @State private var voiceCommandState = ComposeVoiceCommandState()
    @State private var directOptions: ComposeDirectOptionsResult?
    @State private var isLoadingDirectOptions = false
    @State private var directOptionsRequestID = 0
    @State private var directOptionsError: String?
    @State private var showingBridgeSettings = false
    @State private var actionBarHeight: CGFloat = 120
    @State private var commandPreview: ComposeVoiceCommandPreview?
    @State private var activeNote: ComposeNote?
    @State private var isShowingNoteEditor = false
    @FocusState private var isDraftFocused: Bool

    init(
        presentationStyle: PresentationStyle = .sheet,
        onBack: (() -> Void)? = nil
    ) {
        self.presentationStyle = presentationStyle
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if presentationStyle == .sheet {
                NavigationStack {
                    composeContent
                }
            } else {
                composeContent
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var composeContent: some View {
        ZStack(alignment: .bottom) {
            Color.surfacePrimary
                .allowsHitTesting(false)

            composeBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isShowingNoteEditor, let commandPreview {
                ComposeVoiceCommandPreviewBubble(text: commandPreview.text)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, actionBarHeight + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composeActionTray
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .allowsHitTesting(false)
                            .preference(key: ComposeActionBarHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
        }
        .modifier(ComposeNavigationChrome(
            presentationStyle: presentationStyle,
            isShowingNoteEditor: isShowingNoteEditor,
            hasDraft: hasDraft,
            canSaveNote: canSaveNote,
            hasPendingNoteChanges: hasPendingNoteChanges,
            draftText: draftText,
            isRevising: isRevising,
            hasActiveDictation: hasActiveDictation,
            saveNote: { saveNote() },
            createNewNote: { focus in
                createNewNote(focus: focus)
            },
            clearDraft: clearDraft
        ))
        .navigationDestination(isPresented: $showingBridgeSettings) {
            BridgeSettingsView()
        }
        .onPreferenceChange(ComposeActionBarHeightPreferenceKey.self) { newHeight in
            guard abs(actionBarHeight - newHeight) > 0.5 else { return }
            actionBarHeight = newHeight
        }
        .onAppear {
            voiceCommandState.configureIfNeeded()
            refreshDirectOptionsIfNeeded()
        }
        .onChange(of: voiceCommandState.latestTranscript) { _, transcript in
            guard let transcript else { return }
            presentCommandPreview(transcript)
            submitInstruction(transcript)
            voiceCommandState.consumeTranscript()
        }
        .onChange(of: bridgeManager.isPaired) { _, isPaired in
            if !isPaired {
                directOptions = nil
                directOptionsError = nil
            } else {
                refreshDirectOptionsIfNeeded(force: true)
            }
        }
        .onChange(of: bridgeManager.status) { _, newStatus in
            guard bridgeManager.isPaired else { return }
            if newStatus == .connected {
                refreshDirectOptionsIfNeeded(force: true)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshDirectOptionsIfNeeded(force: true)
        }
    }

    @ViewBuilder
    private var composeBody: some View {
        if isShowingNoteEditor {
            composeEditorBody
        } else {
            composeNotesListBody
        }
    }

    private func composeErrorBanner(message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.recording)
    }

    @ViewBuilder
    private var composeEditorBody: some View {
        if pendingRevision == nil && appliedRevisions.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let composeErrorMessage {
                    composeErrorBanner(message: composeErrorMessage)
                }

                ComposeEditorCard(
                    placeholder: "",
                    editorMinHeight: 200,
                    text: $draftText,
                    draftFocus: $isDraftFocused,
                    dictationState: $dictationState,
                    dictationError: $dictationError,
                    dictationTrigger: $draftDictationTrigger,
                    dictationResetTrigger: $draftDictationResetTrigger,
                    showsDictationButton: true,
                    prefersMinimalKeyboard: false
                ) {
                    composeRevisionControls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let composeErrorMessage {
                        composeErrorBanner(message: composeErrorMessage)
                    }

                    ComposeEditorCard(
                        placeholder: "",
                        editorMinHeight: 200,
                        text: $draftText,
                        draftFocus: $isDraftFocused,
                        dictationState: $dictationState,
                        dictationError: $dictationError,
                        dictationTrigger: $draftDictationTrigger,
                        dictationResetTrigger: $draftDictationResetTrigger,
                        showsDictationButton: true,
                        prefersMinimalKeyboard: false
                    ) {
                        composeRevisionControls
                    }

                    if let pendingRevision {
                        ComposePreviewCard(
                            revision: pendingRevision,
                            applyRevision: applyPendingRevision,
                            discardRevision: discardPendingRevision
                        )
                    }

                    if !appliedRevisions.isEmpty {
                        ComposeHistoryCard(revisions: appliedRevisions)
                    }
                }
                .padding(Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var composeNotesListBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let composeErrorMessage {
                composeErrorBanner(message: composeErrorMessage)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(themeManager.colors.textTertiary)

                    Spacer()

                    Text("LAST EDITED")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(themeManager.colors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(themeManager.colors.tableHeaderBackground)

                List {
                    if savedNotes.isEmpty {
                        ComposeNotesEmptyStateRow(createNote: {
                            createNewNote(focus: true)
                        })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(themeManager.colors.tableCellBackground)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(savedNotes) { note in
                            ComposeNoteRow(note: note)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(themeManager.colors.tableCellBackground)
                                .listRowSeparatorTint(themeManager.colors.tableDivider)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openNote(note)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        promoteNoteToMemo(note)
                                    } label: {
                                        Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                                    }
                                    .tint(.accentColor)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteNote(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(themeManager.colors.tableCellBackground)
            .clipShape(.rect(cornerRadius: CornerRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(themeManager.colors.tableBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ComposeNavigationChrome: ViewModifier {
    let presentationStyle: ComposeView.PresentationStyle
    let isShowingNoteEditor: Bool
    let hasDraft: Bool
    let canSaveNote: Bool
    let hasPendingNoteChanges: Bool
    let draftText: String
    let isRevising: Bool
    let hasActiveDictation: Bool
    let saveNote: () -> Void
    let createNewNote: (Bool) -> Void
    let clearDraft: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(presentationStyle == .sheet ? "Compose" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if presentationStyle == .sheet {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if isShowingNoteEditor {
                            Button("Save") {
                                saveNote()
                            }
                            .disabled(!canSaveNote || !hasPendingNoteChanges)

                            if hasDraft {
                                ShareLink(item: draftText) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .accessibilityLabel("Share Draft")
                            }

                            Button("Clear") {
                                clearDraft()
                            }
                            .disabled(isRevising || hasActiveDictation)
                        } else {
                            Button("New") {
                                createNewNote(true)
                            }
                        }
                    }
                }
            }
    }
}

extension ComposeView {
    private var hasDraft: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSaveNote: Bool {
        hasDraft && !isRevising && !hasActiveDictation
    }

    private var hasPendingNoteChanges: Bool {
        let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return false }

        guard let activeNote else {
            return true
        }

        let storedText = (activeNote.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDraft != storedText
    }

    private var availableDirectProviders: [ComposeDirectProviderOption] {
        directOptions?.providers ?? []
    }

    private var selectedRevisionPath: ComposeRevisionPath {
        ComposeRevisionPath(rawValue: appSettings.composeRevisionPath) ?? .direct
    }

    private var selectedDirectProvider: ComposeDirectProviderOption? {
        if let matchingProvider = availableDirectProviders.first(where: {
            $0.providerId == appSettings.composeDirectProviderId
        }) {
            return matchingProvider
        }

        return availableDirectProviders.first
    }

    private var selectedDirectModel: ComposeDirectModelOption? {
        guard let selectedDirectProvider else { return nil }

        if let matchingModel = selectedDirectProvider.models.first(where: {
            $0.id == appSettings.composeDirectModelId
        }) {
            return matchingModel
        }

        return selectedDirectProvider.models.first
    }

    private var hasActiveDictation: Bool {
        dictationState != .idle || voiceCommandState.dictationState != .idle
    }

    private var areQuickActionsEnabled: Bool {
        hasDraft && !isRevising && !hasActiveDictation
    }

    private var isVoiceCommandButtonEnabled: Bool {
        voiceCommandState.dictationState == .recording
            || (!isRevising && dictationState == .idle && voiceCommandState.dictationState == .idle)
    }

    private var quickPrompts: [String] {
        [
            "Make this shorter",
            "Clean this up",
            "Make this friendlier",
            "Turn this into notes",
        ]
    }

    private var composeErrorMessage: String? {
        voiceCommandState.errorMessage ?? errorMessage
    }

    @ViewBuilder
    private var composeRevisionControls: some View {
        ComposeRevisionControlsRow(
            selectedRevisionPath: selectedRevisionPath,
            isPaired: bridgeManager.isPaired,
            connectionStatus: bridgeManager.status,
            pairedMacName: bridgeManager.pairedMacName,
            pairedMacs: bridgeManager.pairedMacs,
            activePairedMacID: bridgeManager.activePairedMacID,
            availableDirectProviders: availableDirectProviders,
            selectedDirectProviderId: appSettings.composeDirectProviderId,
            selectedDirectModelId: appSettings.composeDirectModelId,
            isLoadingDirectOptions: isLoadingDirectOptions,
            directOptionsError: directOptionsError,
            selectRevisionPath: { path in
                selectRevisionPath(path)
            },
            selectPairedMac: { macID in
                Task { await bridgeManager.activatePairedMac(id: macID) }
            },
            selectDirectProvider: { providerId in
                selectDirectProvider(providerId)
            },
            selectDirectModel: { modelId in
                selectDirectModel(modelId)
            },
            reconnectToMac: reconnectToMac,
            openBridgeSettings: openBridgeSettings,
            showsStatusMessage: false
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var composeActionTray: some View {
        if isShowingNoteEditor {
            VStack(spacing: 8) {
                if hasDraft {
                    ComposeQuickActionsBar(
                        quickPrompts: quickPrompts,
                        areQuickActionsEnabled: areQuickActionsEnabled,
                        canSaveNote: canSaveNote && hasPendingNoteChanges,
                        saveNote: { saveNote() },
                        applyQuickPrompt: applyQuickPrompt
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ComposeQuickActionsSkeletonBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ComposeCommandDock(
                    backAccessibilityLabel: "Back to notes",
                    isVoiceCommandEnabled: isVoiceCommandButtonEnabled,
                    voiceCommandState: voiceCommandState.dictationState,
                    backAction: performBackAction,
                    voiceCommandAction: toggleVoiceCommand,
                    keyboardAction: focusDraftEditor
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            ComposeNotesListDock(
                backAccessibilityLabel: presentationStyle == .sheet ? "Close Compose" : "Return to memos",
                backAction: performBackAction,
                createNoteAction: {
                    createNewNote(focus: true)
                }
            )
        }
    }

    private func clearDraft() {
        voiceCommandState.cancel()
        voiceCommandState.clearError()
        cancelDraftDictation()
        draftText = ""
        instructionText = ""
        pendingRevision = nil
        errorMessage = nil
        appliedRevisions.removeAll()
        commandPreview = nil
    }

    private func applyQuickPrompt(_ prompt: String) {
        submitInstruction(prompt)
    }

    private func performBackAction() {
        voiceCommandState.cancel()
        cancelDraftDictation()
        isDraftFocused = false

        if isShowingNoteEditor {
            if hasPendingNoteChanges {
                saveNote(andReturnToList: true)
            } else {
                showNotesList()
            }
            return
        }

        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func focusDraftEditor() {
        isDraftFocused = true
    }

    private func toggleVoiceCommand() {
        errorMessage = nil
        voiceCommandState.clearError()
        voiceCommandState.toggle(
            canStart: !isRevising && dictationState == .idle
        )
    }

    private func createNewNote(focus: Bool = false) {
        clearDraft()
        activeNote = nil
        isShowingNoteEditor = true

        if focus {
            Task { @MainActor in
                isDraftFocused = true
            }
        }
    }

    private func openNote(_ note: ComposeNote, focus: Bool = false) {
        clearDraft()
        activeNote = note
        draftText = note.content ?? ""
        isShowingNoteEditor = true

        if focus {
            Task { @MainActor in
                isDraftFocused = true
            }
        }
    }

    private func showNotesList() {
        voiceCommandState.cancel()
        voiceCommandState.clearError()
        cancelDraftDictation()
        isDraftFocused = false
        commandPreview = nil
        errorMessage = nil
        activeNote = nil
        isShowingNoteEditor = false
    }

    private func cancelDraftDictation() {
        draftDictationResetTrigger += 1
        dictationState = .idle
        dictationError = nil
    }

    private func saveNote(_ focus: Bool = false) {
        saveNote(andReturnToList: false, focus: focus)
    }

    private func saveNote(andReturnToList: Bool, focus: Bool = false) {
        let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            if andReturnToList {
                showNotesList()
            }
            return
        }

        let note = activeNote ?? ComposeNote(context: viewContext)
        let now = Date()

        if note.id == nil {
            note.id = UUID()
        }
        if note.createdAt == nil {
            note.createdAt = now
        }

        note.lastModified = now
        note.content = draftText
        note.title = noteTitle(from: draftText)

        do {
            try viewContext.save()
            activeNote = note
            errorMessage = nil

            if andReturnToList {
                showNotesList()
            } else if focus {
                Task { @MainActor in
                    isDraftFocused = true
                }
            }
        } catch {
            viewContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote(_ note: ComposeNote) {
        if activeNote?.objectID == note.objectID {
            activeNote = nil
        }

        viewContext.delete(note)

        do {
            try viewContext.save()
            errorMessage = nil
        } catch {
            viewContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func promoteNoteToMemo(_ note: ComposeNote) {
        guard let content = note.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let memo = VoiceMemo(context: viewContext)
        memo.id = UUID()
        memo.title = note.title ?? noteTitle(from: content)
        memo.createdAt = note.createdAt ?? Date()
        memo.lastModified = Date()
        memo.duration = 0
        memo.isTranscribing = false
        memo.sortOrder = Int32((note.createdAt ?? Date()).timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false

        memo.addSystemTranscript(
            content: content,
            fromMacOS: false,
            engine: "compose_note"
        )

        do {
            try viewContext.save()
            PersistenceController.refreshWidgetData(context: viewContext)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            viewContext.rollback()
            AppLogger.app.error("Failed to promote note to memo: \(error)")
        }
    }

    private func noteTitle(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "Untitled Note" }

        let collapsed = trimmedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return "Untitled Note" }

        if collapsed.count <= 56 {
            return collapsed
        }

        let cutoffIndex = collapsed.index(collapsed.startIndex, offsetBy: 56)
        return "\(collapsed[..<cutoffIndex])..."
    }

    private func presentCommandPreview(_ transcript: String) {
        let preview = ComposeVoiceCommandPreview(text: transcript)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            commandPreview = preview
        }

        Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard commandPreview?.id == preview.id else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    commandPreview = nil
                }
            }
        }
    }

    private func submitInstruction(_ instruction: String) {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else { return }

        instructionText = trimmedInstruction
        errorMessage = nil

        guard hasDraft else {
            errorMessage = ComposeLocalRevisionError.missingText.localizedDescription
            return
        }

        requestRevision()
    }

    private func requestRevision() {
        switch selectedRevisionPath {
        case .direct:
            requestDirectRevision()
        case .mac:
            requestMacRevision()
        }
    }

    private func requestDirectRevision() {
        guard !isRevising else { return }

        let instruction = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !instruction.isEmpty, !draft.isEmpty else { return }
        guard let selectedDirectProvider else {
            errorMessage = directOptionsError ?? "Direct iPhone Compose is not ready yet."
            return
        }

        let selectedModelId = selectedDirectModel?.id ?? appSettings.composeDirectModelId

        isRevising = true
        errorMessage = nil

        Task {
            do {
                let provider = try await bridgeManager.composeBorrowedProvider(
                    providerId: selectedDirectProvider.providerId,
                    modelId: selectedModelId
                )
                let result = try await ComposeLocalRevisionService.shared.revise(
                    text: draftText,
                    instruction: instruction,
                    provider: provider
                )
                pendingRevision = ComposePendingRevision(
                    originalText: draftText,
                    revisedText: result.revisedText,
                    instruction: instruction,
                    providerName: result.providerName,
                    modelId: result.modelId,
                    fallbackReason: result.fallbackReason,
                    createdAt: .now
                )
            } catch {
                errorMessage = error.localizedDescription
            }

            isRevising = false
        }
    }

    private func requestMacRevision() {
        guard !isRevising else { return }

        let instruction = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !instruction.isEmpty, !draft.isEmpty else { return }

        isRevising = true
        errorMessage = nil

        Task {
            do {
                let result = try await bridgeManager.composeRevision(
                    text: draftText,
                    instruction: instruction
                )
                pendingRevision = ComposePendingRevision(
                    originalText: draftText,
                    revisedText: result.revisedText,
                    instruction: instruction,
                    providerName: result.providerName,
                    modelId: result.modelId,
                    fallbackReason: result.fallbackReason,
                    createdAt: .now
                )
            } catch {
                errorMessage = error.localizedDescription
            }

            isRevising = false
        }
    }

    private func applyPendingRevision() {
        guard let pendingRevision else { return }

        draftText = pendingRevision.revisedText
        appliedRevisions.insert(
            ComposeAppliedRevision(
                instruction: pendingRevision.instruction,
                text: pendingRevision.revisedText,
                providerName: pendingRevision.providerName,
                modelId: pendingRevision.modelId,
                createdAt: pendingRevision.createdAt
            ),
            at: 0
        )
        self.pendingRevision = nil
        errorMessage = nil
    }

    private func discardPendingRevision() {
        pendingRevision = nil
    }

    private func openBridgeSettings() {
        showingBridgeSettings = true
    }

    private func reconnectToMac() {
        guard bridgeManager.isPaired else { return }
        guard bridgeManager.status != .connecting else { return }

        Task {
            await bridgeManager.connect()
        }
    }

    private func selectRevisionPath(_ path: ComposeRevisionPath) {
        appSettings.composeRevisionPath = path.rawValue
    }

    private func refreshDirectOptionsIfNeeded(force: Bool = false) {
        guard bridgeManager.isPaired else { return }
        guard force || bridgeManager.status == .connected || bridgeManager.shouldConnect else { return }

        directOptionsRequestID += 1
        let requestID = directOptionsRequestID
        isLoadingDirectOptions = true

        Task {
            do {
                let options = try await bridgeManager.composeDirectOptions()
                guard requestID == directOptionsRequestID else { return }
                directOptions = options
                directOptionsError = nil
                reconcileDirectSelection(with: options)
            } catch {
                guard requestID == directOptionsRequestID else { return }
                directOptionsError = error.localizedDescription
            }

            if requestID == directOptionsRequestID {
                isLoadingDirectOptions = false
            }
        }
    }

    private func reconcileDirectSelection(with options: ComposeDirectOptionsResult) {
        guard !options.providers.isEmpty else {
            appSettings.composeDirectProviderId = options.selectedProviderId
            appSettings.composeDirectModelId = options.selectedModelId
            return
        }

        let selectedProvider = options.providers.first(where: {
            $0.providerId == appSettings.composeDirectProviderId
        }) ?? options.providers.first(where: {
            $0.providerId == options.selectedProviderId
        }) ?? options.providers[0]

        let selectedModel = selectedProvider.models.first(where: {
            $0.id == appSettings.composeDirectModelId
        }) ?? selectedProvider.models.first(where: {
            $0.id == options.selectedModelId
        }) ?? selectedProvider.models.first

        appSettings.composeDirectProviderId = selectedProvider.providerId
        appSettings.composeDirectModelId = selectedModel?.id ?? ""
    }

    private func selectDirectProvider(_ providerId: String) {
        guard let provider = availableDirectProviders.first(where: { $0.providerId == providerId }) else { return }
        appSettings.composeDirectProviderId = provider.providerId

        if !provider.models.contains(where: { $0.id == appSettings.composeDirectModelId }) {
            appSettings.composeDirectModelId = provider.models.first?.id ?? ""
        }
    }

    private func selectDirectModel(_ modelId: String) {
        guard let selectedDirectProvider else { return }
        guard selectedDirectProvider.models.contains(where: { $0.id == modelId }) else { return }
        appSettings.composeDirectModelId = modelId
    }
}

private struct ComposeActionBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ComposePendingRevision {
    let originalText: String
    let revisedText: String
    let instruction: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
    let createdAt: Date
}

private struct ComposeVoiceCommandPreview: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

private struct ComposeAppliedRevision: Identifiable {
    let id = UUID()
    let instruction: String
    let text: String
    let providerName: String
    let modelId: String
    let createdAt: Date
}

private struct ComposeRevisionControlsRow: View {
    let selectedRevisionPath: ComposeRevisionPath
    let isPaired: Bool
    let connectionStatus: BridgeManager.ConnectionStatus
    let pairedMacName: String?
    let pairedMacs: [BridgeManager.PairedMac]
    let activePairedMacID: String?
    let availableDirectProviders: [ComposeDirectProviderOption]
    let selectedDirectProviderId: String
    let selectedDirectModelId: String
    let isLoadingDirectOptions: Bool
    let directOptionsError: String?
    let selectRevisionPath: (ComposeRevisionPath) -> Void
    let selectPairedMac: (String) -> Void
    let selectDirectProvider: (String) -> Void
    let selectDirectModel: (String) -> Void
    let reconnectToMac: () -> Void
    let openBridgeSettings: () -> Void
    var showsStatusMessage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits {
                selectionChips
                    .frame(maxWidth: .infinity, alignment: .center)

                ScrollView(.horizontal, showsIndicators: false) {
                    selectionChips
                }
            }

            if showsStatusMessage, let statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)

                    Text(statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var selectionChips: some View {
        HStack(spacing: Spacing.xs) {
            Menu {
                Button {
                    selectRevisionPath(.direct)
                } label: {
                    Label(ComposeRevisionPath.direct.title, systemImage: ComposeRevisionPath.direct.systemImage)
                }

                if isPaired {
                    if connectionStatus == .connected {
                        Button {
                            selectRevisionPath(.mac)
                        } label: {
                            Label(ComposeRevisionPath.mac.title, systemImage: ComposeRevisionPath.mac.systemImage)
                        }
                    } else if connectionStatus == .connecting {
                        Button {
                        } label: {
                            Label("Connecting to Mac", systemImage: "wifi.exclamationmark")
                        }
                        .disabled(true)
                    } else {
                        Button {
                            reconnectToMac()
                        } label: {
                            Label("Reconnect Mac", systemImage: "arrow.clockwise")
                        }
                    }

                    Button {
                        openBridgeSettings()
                    } label: {
                        Label("Mac Settings", systemImage: "gearshape")
                    }
                } else {
                    Button {
                        openBridgeSettings()
                    } label: {
                        Label("Pair Mac", systemImage: "desktopcomputer.badge.plus")
                    }
                }
            } label: {
                ComposeSelectionChip(
                    title: selectedPathTitle,
                    systemImage: selectedPathIcon,
                    tint: selectedRevisionPath == .direct ? Color.brandAccent : statusColor,
                    showsMenuIndicator: true
                )
            }

            if pairedMacs.count > 1 {
                Menu {
                    ForEach(pairedMacs) { pairedMac in
                        Button {
                            selectPairedMac(pairedMac.id)
                        } label: {
                            Label(pairedMacTitle(for: pairedMac), systemImage: pairedMac.id == activePairedMacID ? "checkmark.circle.fill" : "desktopcomputer")
                        }
                    }
                } label: {
                    ComposeSelectionChip(
                        title: activeMacTitle,
                        systemImage: "desktopcomputer",
                        tint: statusColor,
                        showsMenuIndicator: true
                    )
                }
            }

            if selectedRevisionPath == .direct {
                if let selectedProvider {
                    Menu {
                        ForEach(availableDirectProviders) { provider in
                            Button {
                                selectDirectProvider(provider.providerId)
                            } label: {
                                Label(provider.providerName, systemImage: providerSymbol(for: provider.providerId))
                            }
                        }
                    } label: {
                        ComposeSelectionChip(
                            title: selectedProvider.providerName,
                            systemImage: providerSymbol(for: selectedProvider.providerId),
                            tint: providerTint(for: selectedProvider.providerId),
                            showsMenuIndicator: true
                        )
                    }
                    
                    if let selectedModel {
                        Menu {
                            ForEach(selectedProvider.models) { model in
                                Button(model.name) {
                                    selectDirectModel(model.id)
                                }
                            }
                        } label: {
                            ComposeSelectionChip(
                                title: selectedModel.name,
                                systemImage: "cpu",
                                tint: Color.textSecondary,
                                showsMenuIndicator: true
                            )
                        }
                    } else if showsDirectSelectionPlaceholders {
                        ComposeSelectionChip(
                            title: directModelPlaceholderTitle,
                            systemImage: directModelPlaceholderIcon,
                            tint: directPlaceholderTint,
                            isEnabled: false,
                            showsLoadingIndicator: isLoadingDirectOptions
                        )
                    }
                } else if showsDirectSelectionPlaceholders {
                    ComposeSelectionChip(
                        title: directProviderPlaceholderTitle,
                        systemImage: directProviderPlaceholderIcon,
                        tint: directPlaceholderTint,
                        isEnabled: false,
                        showsLoadingIndicator: isLoadingDirectOptions
                    )

                    ComposeSelectionChip(
                        title: directModelPlaceholderTitle,
                        systemImage: directModelPlaceholderIcon,
                        tint: directPlaceholderTint,
                        isEnabled: false,
                        showsLoadingIndicator: isLoadingDirectOptions
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var selectedProvider: ComposeDirectProviderOption? {
        availableDirectProviders.first(where: { $0.providerId == selectedDirectProviderId })
            ?? availableDirectProviders.first
    }

    private var activeMacTitle: String {
        if let activeMac = pairedMacs.first(where: { $0.id == activePairedMacID }) {
            return pairedMacTitle(for: activeMac)
        }

        return pairedMacName ?? "Active Mac"
    }

    private func pairedMacTitle(for pairedMac: BridgeManager.PairedMac) -> String {
        pairedMac.pairedMacName.isEmpty ? pairedMac.hostname : pairedMac.pairedMacName
    }

    private var selectedModel: ComposeDirectModelOption? {
        guard let selectedProvider else { return nil }

        return selectedProvider.models.first(where: { $0.id == selectedDirectModelId })
            ?? selectedProvider.models.first
    }

    private var statusMessage: String? {
        switch selectedRevisionPath {
        case .direct:
            if !isPaired {
                return "Pair your Mac once, then use its saved API providers here."
            }

            switch connectionStatus {
            case .connected:
                if isLoadingDirectOptions && availableDirectProviders.isEmpty {
                    return "Loading API providers from your Mac."
                }
                return availableDirectProviders.isEmpty
                    ? (directOptionsError ?? "Add OpenAI or Groq on your Mac to use API revision.")
                    : nil
            case .connecting, .disconnected:
                return isLoadingDirectOptions
                    ? "Connecting to your Mac and loading API providers."
                    : "Reconnect to your Mac to load API providers."
            case .error:
                return directOptionsError ?? "Couldn’t load API providers from your Mac."
            }
        case .mac:
            if !isPaired {
                return "Pair Mac to revise through your Mac."
            }

            switch connectionStatus {
            case .connected:
                return pairedMacName.map { "Running on \($0)." }
            case .connecting, .disconnected:
                return "Reconnect to your Mac to revise there."
            case .error:
                return "Couldn’t reach your Mac for Compose."
            }
        }
    }

    private var statusIcon: String {
        switch selectedRevisionPath {
        case .direct:
            if !isPaired {
                return "desktopcomputer.badge.plus"
            }
        case .mac:
            if !isPaired {
                return "desktopcomputer.badge.plus"
            }
        }

        switch connectionStatus {
        case .connecting:
            return "wifi.exclamationmark"
        case .disconnected:
            return "wifi.slash"
        case .error:
            return "exclamationmark.triangle.fill"
        case .connected:
            return selectedRevisionPath == .mac ? "desktopcomputer" : "checkmark.circle.fill"
        }
    }

    private var selectedPathTitle: String {
        switch selectedRevisionPath {
        case .direct:
            return ComposeRevisionPath.direct.title
        case .mac:
            guard isPaired else { return "Pair Mac" }

            switch connectionStatus {
            case .connected:
                return ComposeRevisionPath.mac.title
            case .connecting:
                return "Connecting…"
            case .disconnected, .error:
                return "Reconnect Mac"
            }
        }
    }

    private var selectedPathIcon: String {
        switch selectedRevisionPath {
        case .direct:
            return ComposeRevisionPath.direct.systemImage
        case .mac:
            guard isPaired else { return "desktopcomputer.badge.plus" }

            switch connectionStatus {
            case .connected:
                return ComposeRevisionPath.mac.systemImage
            case .connecting:
                return "wifi.exclamationmark"
            case .disconnected, .error:
                return "arrow.clockwise"
            }
        }
    }

    private var statusColor: Color {
        if !isPaired {
            return Color.warning
        }

        switch connectionStatus {
        case .connecting, .disconnected:
            return Color.warning
        case .error:
            return Color.recording
        case .connected:
            return Color.success
        }
    }

    private var showsDirectSelectionPlaceholders: Bool {
        isPaired || isLoadingDirectOptions || directOptionsError != nil
    }

    private var directProviderPlaceholderTitle: String {
        if !isPaired {
            return "Saved APIs"
        }

        if isLoadingDirectOptions {
            return "Loading APIs"
        }

        if directOptionsError != nil {
            return "API Unavailable"
        }

        return "No APIs"
    }

    private var directProviderPlaceholderIcon: String {
        if directOptionsError != nil {
            return "exclamationmark.triangle.fill"
        }

        if connectionStatus == .connecting || connectionStatus == .disconnected {
            return "wifi.exclamationmark"
        }

        return "network"
    }

    private var directModelPlaceholderTitle: String {
        if isLoadingDirectOptions {
            return "Loading Model"
        }

        if directOptionsError != nil {
            return "Model Unavailable"
        }

        return "Choose Model"
    }

    private var directModelPlaceholderIcon: String {
        directOptionsError == nil ? "cpu" : "exclamationmark.triangle.fill"
    }

    private var directPlaceholderTint: Color {
        if directOptionsError != nil {
            return Color.recording
        }

        if isLoadingDirectOptions || connectionStatus == .connecting || connectionStatus == .disconnected {
            return Color.warning
        }

        return Color.textTertiary
    }

    private func providerSymbol(for providerId: String) -> String {
        switch providerId {
        case "openai":
            return "sparkles"
        case "groq":
            return "bolt.fill"
        default:
            return "network"
        }
    }

    private func providerTint(for providerId: String) -> Color {
        switch providerId {
        case "openai":
            return Color(red: 0.30, green: 0.68, blue: 0.50)
        case "groq":
            return Color(red: 0.88, green: 0.43, blue: 0.27)
        default:
            return Color.brandAccent
        }
    }
}

private struct ComposeSelectionChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    var showsMenuIndicator = false
    var isEnabled = true
    var showsLoadingIndicator = false

    var body: some View {
        HStack(spacing: 6) {
            if showsLoadingIndicator {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.surfacePrimary)
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .opacity(isEnabled ? 1 : 0.74)
    }
}

struct ComposeKeyboardTextSurface: View {
    @Binding var text: String
    let placeholder: String
    let focus: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    @Binding var dictationTrigger: Int
    @Binding var dictationResetTrigger: Int
    let minHeight: CGFloat
    let micPlacement: ComposeMicPlacement
    var showsDictationButton = true
    var prefersMinimalKeyboard = false

    var body: some View {
        ComposeKeyboardTextView(
            text: $text,
            placeholder: placeholder,
            isFocused: focus,
            dictationState: $dictationState,
            dictationError: $dictationError,
            contentBottomInset: showsDictationButton ? micPlacement.contentBottomInset : 16,
            prefersMinimalKeyboard: prefersMinimalKeyboard,
            dictationTrigger: dictationTrigger,
            dictationResetTrigger: dictationResetTrigger
        )
        .frame(minHeight: minHeight)
        .background(Color.surfacePrimary)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Color.borderPrimary.opacity(0.4), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .overlay(alignment: micPlacement.alignment) {
            if showsDictationButton {
                dictationButton
                    .padding(micPadding)
                    .zIndex(1)
            }
        }
    }

    private var dictationButton: some View {
        Button {
            focus.wrappedValue = true
            dictationTrigger += 1
        } label: {
            Image(systemName: dictationIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(dictationForegroundStyle)
                .frame(width: 52, height: 52)
                .background(dictationBackground)
                .clipShape(.circle)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .disabled(dictationState == .transcribing)
        .accessibilityLabel(dictationLabel)
    }

    private var dictationIcon: String {
        switch dictationState {
        case .idle:
            return "mic.fill"
        case .recording:
            return "stop.fill"
        case .transcribing:
            return "waveform"
        }
    }

    private var dictationLabel: String {
        switch dictationState {
        case .idle:
            return "Start dictation"
        case .recording:
            return "Stop dictation"
        case .transcribing:
            return "Transcribing dictation"
        }
    }

    private var dictationForegroundStyle: Color {
        switch dictationState {
        case .idle:
            return Color.textPrimary
        case .recording:
            return Color.white
        case .transcribing:
            return Color.brandAccent
        }
    }

    @ViewBuilder
    private var dictationBackground: some View {
        switch dictationState {
        case .idle:
            Color.surfaceSecondary
        case .recording:
            Color.recording
        case .transcribing:
            Color.brandAccent.opacity(0.14)
        }
    }

    private var micPadding: EdgeInsets {
        switch micPlacement {
        case .bottomCenter:
            return EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 0)
        case .bottomTrailing:
            return EdgeInsets(top: 0, leading: 0, bottom: 14, trailing: 14)
        }
    }
}

struct ComposeKeyboardTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    let contentBottomInset: CGFloat
    let prefersMinimalKeyboard: Bool
    let dictationTrigger: Int
    let dictationResetTrigger: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            dictationState: $dictationState,
            dictationError: $dictationError
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        configure(textView, coordinator: context.coordinator)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.dictationState = $dictationState
        context.coordinator.dictationError = $dictationError
        context.coordinator.setFocused = { focused in
            isFocused.wrappedValue = focused
        }
        context.coordinator.textView = textView
        context.coordinator.keyboard = textView.inputView as? HostedTalkieKeyboardView
        context.coordinator.keyboard?.preferredInitialLayout = prefersMinimalKeyboard ? .minimal : .compact
        context.coordinator.keyboard?.preferredInitialModeId = KeyboardMode.abc.id

        if textView.text != text {
            textView.text = text
            context.coordinator.updatePlaceholderVisibility()
        }

        context.coordinator.handleDictationTrigger(
            dictationTrigger,
            for: textView
        )
        context.coordinator.handleDictationResetTrigger(dictationResetTrigger)

        if isFocused.wrappedValue {
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }
    }

    private func configure(_ textView: UITextView, coordinator: Coordinator) {
        let keyboard = HostedTalkieKeyboardView()
        keyboard.preferredInitialLayout = prefersMinimalKeyboard ? .minimal : .compact
        keyboard.preferredInitialModeId = KeyboardMode.abc.id
        keyboard.inputHost = coordinator
        keyboard.onDictationToggle = { [weak coordinator] in
            coordinator?.toggleDictation()
        }
        keyboard.onLayoutHeightChange = { [weak textView] in
            textView?.reloadInputViews()
        }
        keyboard.onRequestCollapse = { [weak textView] in
            textView?.resignFirstResponder()
        }

        textView.inputView = keyboard
        textView.delegate = coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(Color.textPrimary)
        textView.tintColor = UIColor(Color.brandAccent)
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: contentBottomInset, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []

        coordinator.textView = textView
        coordinator.keyboard = keyboard
        coordinator.updatePlaceholder(in: textView, placeholder: placeholder)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, KeyboardInputHost {
        private enum Constants {
            static let placeholderTag = 7_001
        }

        var text: Binding<String>
        var dictationState: Binding<InlineDictationController.State>
        var dictationError: Binding<String?>
        var setFocused: ((Bool) -> Void)?
        weak var textView: UITextView?
        weak var keyboard: HostedTalkieKeyboardView?

        private let dictationController = InlineDictationController()
        private var lastDictationTrigger = 0
        private var lastDictationResetTrigger = 0
        private var hasSynchronizedDictationTrigger = false

        init(
            text: Binding<String>,
            dictationState: Binding<InlineDictationController.State>,
            dictationError: Binding<String?>
        ) {
            self.text = text
            self.dictationState = dictationState
            self.dictationError = dictationError
            super.init()

            dictationController.onStateChange = { [weak self] state in
                self?.dictationState.wrappedValue = state
                self?.applyDictationState(state)
            }
            dictationController.onTranscript = { [weak self] transcript in
                guard let self else { return }
                self.dictationError.wrappedValue = nil
                self.replaceSelection(with: transcript)
                self.keyboard?.showDictationSuccessFeedback()
            }
            dictationController.onError = { [weak self] message in
                self?.dictationError.wrappedValue = message
                self?.dictationState.wrappedValue = .idle
                self?.keyboard?.setDictationState(.idle)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            keyboard?.resetToPreferredInitialLayout()
            setFocused?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            setFocused?(false)
            if dictationController.currentState != .idle {
                dictationController.cancel()
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            updatePlaceholderVisibility(in: textView)
        }

        func performKeyboardAction(_ action: KeyboardAction) {
            guard let textView else { return }

            switch action {
            case .insert(let insertedText):
                replaceSelection(with: insertedText)
            case .deleteBackward:
                textView.deleteBackward()
                text.wrappedValue = textView.text
                updatePlaceholderVisibility(in: textView)
            case .copy:
                copySelection(from: textView)
            case .paste:
                guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else { return }
                replaceSelection(with: clipboardText)
            case .toggleShift, .toggleControl, .interrupt:
                break
            case .tab:
                replaceSelection(with: "\t")
            case .escape, .dismissKeyboard:
                textView.resignFirstResponder()
            case .enter:
                replaceSelection(with: "\n")
            case .moveCursor(let movement):
                moveCursor(movement, in: textView)
            }
        }

        func toggleDictation() {
            dictationError.wrappedValue = nil

            switch dictationController.currentState {
            case .idle:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.dictationController.start()
                }
            case .recording:
                dictationController.stop(insertTranscript: true)
            case .transcribing:
                break
            }
        }

        func updatePlaceholderVisibility() {
            guard let textView else { return }
            updatePlaceholderVisibility(in: textView)
        }

        func handleDictationTrigger(_ trigger: Int, for textView: UITextView) {
            if !hasSynchronizedDictationTrigger {
                lastDictationTrigger = trigger
                hasSynchronizedDictationTrigger = true
                return
            }

            guard trigger != lastDictationTrigger else { return }
            lastDictationTrigger = trigger

            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }

            toggleDictation()
        }

        func handleDictationResetTrigger(_ trigger: Int) {
            guard trigger != lastDictationResetTrigger else { return }
            lastDictationResetTrigger = trigger
            cancelDictation()
        }

        func updatePlaceholder(in textView: UITextView, placeholder: String) {
            if placeholder.isEmpty {
                textView.viewWithTag(Constants.placeholderTag)?.removeFromSuperview()
                return
            }

            let label: UILabel
            if let existing = textView.viewWithTag(Constants.placeholderTag) as? UILabel {
                label = existing
            } else {
                let newLabel = UILabel()
                newLabel.tag = Constants.placeholderTag
                newLabel.translatesAutoresizingMaskIntoConstraints = false
                newLabel.numberOfLines = 0
                textView.addSubview(newLabel)
                NSLayoutConstraint.activate([
                    newLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 14),
                    newLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 16),
                    newLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -14),
                ])
                label = newLabel
            }

            label.text = placeholder
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = UIColor(Color.textTertiary)
            label.isHidden = !textView.text.isEmpty
        }

        private func updatePlaceholderVisibility(in textView: UITextView) {
            (textView.viewWithTag(Constants.placeholderTag) as? UILabel)?.isHidden = !textView.text.isEmpty
        }

        private func applyDictationState(_ state: InlineDictationController.State) {
            let keyboardState: HostedTalkieKeyboardView.DictationState
            switch state {
            case .idle:
                keyboardState = .idle
            case .recording:
                keyboardState = .recording
            case .transcribing:
                keyboardState = .processing
            }
            keyboard?.setDictationState(keyboardState)
        }

        private func cancelDictation() {
            dictationError.wrappedValue = nil
            dictationController.cancel()
            keyboard?.setDictationState(.idle)
        }

        private func replaceSelection(with insertedText: String) {
            guard let textView else { return }

            if let selectedRange = textView.selectedTextRange {
                textView.replace(selectedRange, withText: insertedText)
            } else {
                textView.text += insertedText
            }

            text.wrappedValue = textView.text
            updatePlaceholderVisibility(in: textView)
        }

        private func copySelection(from textView: UITextView) {
            let selectedRange = textView.selectedRange
            if selectedRange.length > 0 {
                let textNSString = textView.text as NSString
                UIPasteboard.general.string = textNSString.substring(with: selectedRange)
            } else {
                UIPasteboard.general.string = textView.text
            }
        }

        private func moveCursor(_ movement: KeyboardCursorMovement, in textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else { return }
            let anchor = selectedRange.start

            let nextPosition: UITextPosition?
            switch movement {
            case .left:
                nextPosition = textView.position(from: anchor, offset: -1)
            case .right:
                nextPosition = textView.position(from: anchor, offset: 1)
            case .up:
                nextPosition = textView.position(from: anchor, in: .up, offset: 1)
            case .down:
                nextPosition = textView.position(from: anchor, in: .down, offset: 1)
            case .wordLeft:
                nextPosition = textView.position(from: anchor, offset: -5)
            case .wordRight:
                nextPosition = textView.position(from: anchor, offset: 5)
            }

            guard let nextPosition,
                  let collapsedRange = textView.textRange(from: nextPosition, to: nextPosition) else {
                return
            }

            textView.selectedTextRange = collapsedRange
        }
    }
}

struct ComposeEditorCard<HeaderContent: View>: View {
    let placeholder: String
    let editorMinHeight: CGFloat
    @Binding var text: String
    let draftFocus: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    @Binding var dictationTrigger: Int
    @Binding var dictationResetTrigger: Int
    let headerContent: HeaderContent
    var showsDictationButton = true
    var prefersMinimalKeyboard = false
    @State private var showingCopiedFeedback = false

    init(
        placeholder: String,
        editorMinHeight: CGFloat = 360,
        text: Binding<String>,
        draftFocus: FocusState<Bool>.Binding,
        dictationState: Binding<InlineDictationController.State>,
        dictationError: Binding<String?>,
        dictationTrigger: Binding<Int>,
        dictationResetTrigger: Binding<Int>,
        showsDictationButton: Bool = true,
        prefersMinimalKeyboard: Bool = false,
        @ViewBuilder headerContent: () -> HeaderContent
    ) {
        self.placeholder = placeholder
        self.editorMinHeight = editorMinHeight
        self._text = text
        self.draftFocus = draftFocus
        self._dictationState = dictationState
        self._dictationError = dictationError
        self._dictationTrigger = dictationTrigger
        self._dictationResetTrigger = dictationResetTrigger
        self.showsDictationButton = showsDictationButton
        self.prefersMinimalKeyboard = prefersMinimalKeyboard
        self.headerContent = headerContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            headerContent

            ComposeKeyboardTextSurface(
                text: $text,
                placeholder: placeholder,
                focus: draftFocus,
                dictationState: $dictationState,
                dictationError: $dictationError,
                dictationTrigger: $dictationTrigger,
                dictationResetTrigger: $dictationResetTrigger,
                minHeight: editorMinHeight,
                micPlacement: .bottomCenter,
                showsDictationButton: showsDictationButton,
                prefersMinimalKeyboard: prefersMinimalKeyboard
            )

            HStack {
                Spacer()

                Button(action: copyDraft) {
                    HStack(spacing: 4) {
                        Image(systemName: showingCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))

                        Text(showingCopiedFeedback ? "Copied" : "Quick Copy")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(showingCopiedFeedback ? Color.success : Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.surfacePrimary)
                    .clipShape(.capsule)
                    .overlay {
                        Capsule()
                            .stroke(Color.borderPrimary.opacity(0.7), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                }
                .buttonStyle(.plain)
                .disabled(trimmedText.isEmpty)
                .opacity(trimmedText.isEmpty ? 0.45 : 1)
            }

            if dictationState != .idle || dictationError != nil {
                HStack(spacing: 8) {
                    Image(systemName: dictationState == .recording ? "waveform.circle.fill" : "waveform.badge.magnifyingglass")
                        .foregroundStyle(dictationState == .recording ? Color.recording : Color.brandAccent)

                    Text(dictationMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyDraft() {
        guard !trimmedText.isEmpty else { return }
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            showingCopiedFeedback = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingCopiedFeedback = false
                }
            }
        }
    }

    private var dictationMessage: String {
        if let dictationError {
            return dictationError
        }

        switch dictationState {
        case .idle:
            return ""
        case .recording:
            return "Recording from your iPhone microphone. Stop dictation to insert it into the note."
        case .transcribing:
            return "Transcribing on iPhone and inserting into your note."
        }
    }
}

private struct ComposePreviewCard: View {
    let revision: ComposePendingRevision
    let applyRevision: () -> Void
    let discardRevision: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Revision Preview")
                        .font(.headlineSmall)
                        .foregroundStyle(Color.textPrimary)

                    Text(revision.instruction)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)

                    Text(summaryLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Text(revision.providerName)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.brandAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.brandAccent.opacity(0.12))
                    .clipShape(.capsule)
            }

            if let fallbackReason = revision.fallbackReason {
                Text(fallbackReason)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested Draft")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)

                Text(revision.revisedText)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.surfacePrimary)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
            }

            HStack(spacing: Spacing.sm) {
                Button("Discard", systemImage: "xmark") {
                    discardRevision()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Replace Draft", systemImage: "arrow.down.doc") {
                    applyRevision()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var summaryLabel: String {
        let originalCount = revision.originalText.split(whereSeparator: \.isWhitespace).count
        let revisedCount = revision.revisedText.split(whereSeparator: \.isWhitespace).count
        return "\(originalCount) → \(revisedCount) words"
    }
}

private struct ComposeHistoryCard: View {
    let revisions: [ComposeAppliedRevision]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Applied Revisions")
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)

            ForEach(revisions.prefix(5)) { revision in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(revision.instruction)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Text("\(revision.providerName) • \(revision.modelId)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(revision.createdAt, style: .time)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)

                        Text("\(revision.text.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.borderPrimary, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct ComposeCommandDock: View {
    let backAccessibilityLabel: String
    let isVoiceCommandEnabled: Bool
    let voiceCommandState: InlineDictationController.State
    let backAction: () -> Void
    let voiceCommandAction: () -> Void
    let keyboardAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ComposeTrayCircleButton(
                icon: "chevron.left",
                accessibilityLabel: backAccessibilityLabel,
                action: backAction
            )
            .frame(width: DockLayout.sideButtonSize, height: DockLayout.sideButtonSize)

            Spacer()

            ComposeVoiceCommandButton(
                state: voiceCommandState,
                isEnabled: isVoiceCommandEnabled,
                action: voiceCommandAction
            )

            Spacer()

            ComposeTrayCircleButton(
                icon: "keyboard",
                accessibilityLabel: "Open the keyboard",
                action: keyboardAction
            )
            .frame(width: DockLayout.sideButtonSize, height: DockLayout.sideButtonSize)
        }
        .padding(.horizontal, DockLayout.horizontalPadding)
        .padding(.top, DockLayout.topPadding)
        .padding(.bottom, DockLayout.bottomPadding)
        .frame(maxWidth: .infinity)
        .background {
            BottomTrayBackground()
                .allowsHitTesting(false)
        }
    }
}

private struct ComposeQuickActionsBar: View {
    let quickPrompts: [String]
    let areQuickActionsEnabled: Bool
    let canSaveNote: Bool
    let saveNote: () -> Void
    let applyQuickPrompt: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ComposeDockQuickActionPill(
                    title: "Save Note",
                    isEnabled: canSaveNote
                ) {
                    saveNote()
                }

                ForEach(quickPrompts, id: \.self) { prompt in
                    ComposeDockQuickActionPill(
                        title: prompt,
                        isEnabled: areQuickActionsEnabled
                    ) {
                        applyQuickPrompt(prompt)
                    }
                }
            }
            .padding(.horizontal, DockLayout.horizontalPadding)
        }
        .frame(height: 32)
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ComposeNotesListDock: View {
    let backAccessibilityLabel: String
    let backAction: () -> Void
    let createNoteAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ComposeTrayCircleButton(
                icon: "chevron.left",
                accessibilityLabel: backAccessibilityLabel,
                action: backAction
            )
            .frame(width: DockLayout.sideButtonSize, height: DockLayout.sideButtonSize)

            Spacer()

            ComposeCreateNoteButton(action: createNoteAction)

            Spacer()

            Color.clear
                .frame(width: DockLayout.sideButtonSize, height: DockLayout.sideButtonSize)
        }
        .padding(.horizontal, DockLayout.horizontalPadding)
        .padding(.top, DockLayout.topPadding)
        .padding(.bottom, DockLayout.bottomPadding)
        .frame(maxWidth: .infinity)
        .background {
            BottomTrayBackground()
                .allowsHitTesting(false)
        }
    }
}

private struct ComposeQuickActionsSkeletonBar: View {
    private let widths: [CGFloat] = [88, 108, 96, 118]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(widths, id: \.self) { width in
                    Capsule()
                        .fill(Color.surfacePrimary.opacity(0.75))
                        .frame(width: width, height: 32)
                        .overlay {
                            Capsule()
                                .stroke(Color.borderPrimary.opacity(0.55), lineWidth: 0.5)
                        }
                        .overlay {
                            Capsule()
                                .fill(Color.textPrimary.opacity(0.05))
                                .padding(6)
                        }
                }
            }
            .padding(.horizontal, DockLayout.horizontalPadding)
        }
        .frame(height: 32)
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ComposeVoiceCommandPreviewBubble: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.brandAccent)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceSecondary.opacity(0.96))
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(Color.borderPrimary.opacity(0.8), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}

private struct ComposeDockQuickActionPill: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background(buttonBackground)
        .overlay {
            Capsule()
                .strokeBorder(Color.borderPrimary.opacity(0.7), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .clipShape(.capsule)
        .opacity(isEnabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Capsule()
                .fill(Color.surfacePrimary.opacity(0.55))
        }
    }
}

private struct ComposeCreateNoteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.surfacePrimary)
                    .frame(width: DockLayout.recordButtonSize, height: DockLayout.recordButtonSize)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.brandAccent.opacity(0.45), lineWidth: 1)
                            .allowsHitTesting(false)
                    }

                Image(systemName: "square.and.pencil")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.brandAccent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a new note")
    }
}

private struct ComposeNotesEmptyStateRow: View {
    let createNote: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.textTertiary)

            Text("NO NOTES")
                .font(.techLabel)
                .tracking(2)
                .foregroundStyle(Color.textSecondary)

            Text("Create a note to start revising text here.")
                .font(.bodySmall)
                .foregroundStyle(Color.textTertiary)

            Button("New Note", systemImage: "plus") {
                createNote()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
}

private struct ComposeNoteRow: View {
    let note: ComposeNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(noteTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(notePreview)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Text(lastEditedText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Text(wordCountLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var noteTitle: String {
        let storedTitle = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedTitle.isEmpty {
            return storedTitle
        }

        let trimmedContent = (note.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedContent.isEmpty ? "Untitled Note" : trimmedContent
    }

    private var notePreview: String {
        let trimmedContent = (note.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedContent.isEmpty ? "No content saved yet." : trimmedContent
    }

    private var lastEditedText: String {
        let date = note.lastModified ?? note.createdAt ?? .now
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private var wordCountLabel: String {
        let words = (note.content ?? "").split(whereSeparator: \.isWhitespace).count
        return "\(words) word\(words == 1 ? "" : "s")"
    }
}

private struct ComposeTrayCircleButton: View {
    let icon: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        BottomCircleButton(
            icon: icon,
            isActive: false,
            action: action
        )
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ComposeVoiceCommandButton: View {
    let state: InlineDictationController.State
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .recording {
                    Circle()
                        .fill(Color.recording)
                        .frame(width: 72, height: 72)
                        .blur(radius: 18)
                        .opacity(0.4)
                }

                Circle()
                    .fill(buttonFill)
                    .frame(width: DockLayout.recordButtonSize, height: DockLayout.recordButtonSize)
                    .overlay {
                        Circle()
                            .strokeBorder(buttonBorder, lineWidth: 1)
                            .allowsHitTesting(false)
                    }

                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .scaleEffect(state == .recording ? 1.08 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: state)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "sparkles"
        case .recording:
            return "stop.fill"
        case .transcribing:
            return "waveform"
        }
    }

    private var iconColor: Color {
        switch state {
        case .idle:
            return Color.brandAccent
        case .recording:
            return .white
        case .transcribing:
            return Color.brandAccent
        }
    }

    private var buttonFill: Color {
        switch state {
        case .idle:
            return Color.surfacePrimary
        case .recording:
            return Color.recording
        case .transcribing:
            return Color.surfacePrimary
        }
    }

    private var buttonBorder: Color {
        switch state {
        case .idle:
            return Color.brandAccent.opacity(0.45)
        case .recording:
            return Color.recordingGlow.opacity(0.4)
        case .transcribing:
            return Color.brandAccent.opacity(0.3)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            return "Start voice command"
        case .recording:
            return "Stop voice command"
        case .transcribing:
            return "Transcribing voice command"
        }
    }
}
