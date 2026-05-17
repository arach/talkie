import CoreData
import Observation
import SwiftUI
import TalkieMobileKit
import UIKit

// Notification pipe so the Keyboard pill in the bottom tray can pop the custom
// Talkie keyboard on the editor's UITextView. SwiftUI's @FocusState binding
// doesn't always propagate to a UIViewRepresentable's updateUIView, so this
// gives us a deterministic side channel.
extension Notification.Name {
    static let composeRequestEditorFocus = Notification.Name("composeRequestEditorFocus")
    static let composeRequestEditorBlur = Notification.Name("composeRequestEditorBlur")
}

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

struct ComposeInitialContext: Equatable, Identifiable {
    let id: UUID
    let title: String?
    let text: String
    let sourceDescription: String?
    let sourceURL: String?

    init(
        id: UUID = UUID(),
        title: String? = nil,
        text: String,
        sourceDescription: String? = nil,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.sourceDescription = sourceDescription
        self.sourceURL = sourceURL
    }

    init(capture: Capture) {
        self.id = capture.id
        self.title = capture.title
        self.text = capture.text
        self.sourceDescription = capture.bookmark?.sourceApplicationName
            ?? capture.bookmark?.siteName
            ?? capture.sourceType.capitalized
        self.sourceURL = capture.sourceURL
    }
}

private enum ComposeSegmentKind {
    case capturedContext
    case pastedContext
    case dictation
    case revision
    case savedNote

    var title: String {
        switch self {
        case .capturedContext:
            return "Capture"
        case .pastedContext:
            return "Paste"
        case .dictation:
            return "Dictation"
        case .revision:
            return "Revision"
        case .savedNote:
            return "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .capturedContext:
            return "tray.and.arrow.down.fill"
        case .pastedContext:
            return "doc.on.clipboard"
        case .dictation:
            return "waveform"
        case .revision:
            return "sparkles"
        case .savedNote:
            return "note.text"
        }
    }

    var tint: Color {
        switch self {
        case .capturedContext:
            return Color.orange
        case .pastedContext:
            return Color.blue
        case .dictation:
            return Color.recording
        case .revision:
            return Color.brandAccent
        case .savedNote:
            return Color.textSecondary
        }
    }
}

private struct ComposeSegment: Identifiable, Equatable {
    let id = UUID()
    let kind: ComposeSegmentKind
    let title: String
    let detail: String?
    let text: String
    let createdAt: Date
}

private struct ComposeWorkflowAction: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let prompt: String
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

        // Drive off the observed state (what the pill icon is showing) rather
        // than controller.currentState — that internal value can briefly lag
        // the @Observable property and cause a "tap to stop" to mis-fire a
        // brand-new start instead.
        switch dictationState {
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
    private let initialContext: ComposeInitialContext?
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
    @State private var commandPreview: ComposeVoiceCommandPreview?
    @State private var activeNote: ComposeNote?
    @State private var isShowingNoteEditor = false
    @State private var didPrepareInitialEditor = false
    @State private var composeSegments: [ComposeSegment] = []
    @State private var recentCaptures: [Capture] = []
    @State private var selectedRange: NSRange?
    @State private var showingRevisionHistory = false
    @FocusState private var isDraftFocused: Bool

    init(
        presentationStyle: PresentationStyle = .embedded,
        initialContext: ComposeInitialContext? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.presentationStyle = presentationStyle
        self.initialContext = initialContext
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
            }
        }
    }

    private var composeContent: some View {
        ZStack(alignment: .bottom) {
            Color.surfacePrimary
                .allowsHitTesting(false)

            composeBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Voice command preview floats in from the bottom when active.
            if isShowingNoteEditor, let commandPreview {
                ComposeVoiceCommandPreviewBubble(text: commandPreview.text)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            headerModelControls: AnyView(composeHeaderModelControls),
            saveNote: { saveNote() },
            createNewNote: { focus in
                createNewNote(focus: focus)
            },
            clearDraft: clearDraft
        ))
        .navigationDestination(isPresented: $showingBridgeSettings) {
            BridgeSettingsView()
        }
        .sheet(isPresented: $showingRevisionHistory) {
            ComposeHistorySheet(
                revisions: appliedRevisions,
                onDismiss: { showingRevisionHistory = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            voiceCommandState.configureIfNeeded()
            refreshRecentCaptures()
            prepareInitialEditorIfNeeded()
            refreshDirectOptionsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in
            refreshRecentCaptures()
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
        ComposeEditorWorkspace(
            errorMessage: composeErrorMessage,
            appliedRevisions: appliedRevisions,
            draftText: $draftText,
            draftFocus: $isDraftFocused,
            dictationState: $dictationState,
            dictationError: $dictationError,
            dictationTrigger: $draftDictationTrigger,
            dictationResetTrigger: $draftDictationResetTrigger,
            selectedRange: $selectedRange,
            segments: composeSegments,
            latestCaptureTitle: latestCaptureTitle,
            canPaste: UIPasteboard.general.hasStrings,
            canAddLatestCapture: !recentCaptures.isEmpty,
            voiceCommandState: voiceCommandState.dictationState,
            isVoiceCommandEnabled: isVoiceCommandButtonEnabled,
            canStartDraftDictation: canStartDraftDictation,
            primaryActions: primaryWorkflowActions,
            secondaryActions: loopWorkflowActions,
            areQuickActionsEnabled: areQuickActionsEnabled,
            canSave: canSaveNote && hasPendingNoteChanges,
            pendingRevision: $pendingRevision,
            onSelectRevision: applyAppliedRevision,
            onAppendClipboard: appendClipboardContext,
            onAppendLatestCapture: appendLatestCaptureContext,
            onDictationTranscript: recordDictationSegment,
            onSave: { saveNote() },
            onApplyPending: applyPendingRevision,
            onDiscardPending: discardPendingRevision,
            onToggleVoiceCommand: toggleVoiceCommand,
            onPerformAction: performWorkflowAction
        )
    }

    private var composeNotesListBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let composeErrorMessage {
                composeErrorBanner(message: composeErrorMessage)
            }

            VStack(spacing: 0) {
                HStack {
                    TalkieEyebrow(text: "Notes")
                    Spacer()
                    TalkieEyebrow(text: "Last Edited", tint: .ink, showLeader: false)
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
    let headerModelControls: AnyView?
    let saveNote: () -> Void
    let createNewNote: (Bool) -> Void
    let clearDraft: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private var canCommitSave: Bool {
        canSaveNote && hasPendingNoteChanges
    }

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isShowingNoteEditor, let headerModelControls {
                        // "Compose with ✨ Model ▾" — tappable Menu inline as
                        // the nav title. Stays in the principal slot so it
                        // centers naturally with the leading back chevron.
                        headerModelControls
                    } else {
                        Text(isShowingNoteEditor ? "Compose" : "Notes")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                }

                if isShowingNoteEditor {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { saveNote() }
                            .fontWeight(.medium)
                            .disabled(!canCommitSave)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New") { createNewNote(true) }
                            .fontWeight(.medium)
                    }
                }
            }
    }
}

private struct ComposeEditorWorkspace: View {
    let errorMessage: String?
    let appliedRevisions: [ComposeAppliedRevision]
    @Binding var draftText: String
    let draftFocus: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    @Binding var dictationTrigger: Int
    @Binding var dictationResetTrigger: Int
    var selectedRange: Binding<NSRange?>?
    let segments: [ComposeSegment]
    let latestCaptureTitle: String?
    let canPaste: Bool
    let canAddLatestCapture: Bool
    let voiceCommandState: InlineDictationController.State
    let isVoiceCommandEnabled: Bool
    let canStartDraftDictation: Bool
    let primaryActions: [ComposeWorkflowAction]
    let secondaryActions: [ComposeWorkflowAction]
    let areQuickActionsEnabled: Bool
    let canSave: Bool
    @Binding var pendingRevision: ComposePendingRevision?
    let onSelectRevision: (ComposeAppliedRevision) -> Void
    let onAppendClipboard: () -> Void
    let onAppendLatestCapture: () -> Void
    let onDictationTranscript: (String) -> Void
    let onSave: () -> Void
    let onApplyPending: () -> Void
    let onDiscardPending: () -> Void
    let onToggleVoiceCommand: () -> Void
    let onPerformAction: (ComposeWorkflowAction) -> Void

    init(
        errorMessage: String?,
        appliedRevisions: [ComposeAppliedRevision],
        draftText: Binding<String>,
        draftFocus: FocusState<Bool>.Binding,
        dictationState: Binding<InlineDictationController.State>,
        dictationError: Binding<String?>,
        dictationTrigger: Binding<Int>,
        dictationResetTrigger: Binding<Int>,
        selectedRange: Binding<NSRange?>?,
        segments: [ComposeSegment],
        latestCaptureTitle: String?,
        canPaste: Bool,
        canAddLatestCapture: Bool,
        voiceCommandState: InlineDictationController.State,
        isVoiceCommandEnabled: Bool,
        canStartDraftDictation: Bool,
        primaryActions: [ComposeWorkflowAction],
        secondaryActions: [ComposeWorkflowAction],
        areQuickActionsEnabled: Bool,
        canSave: Bool,
        pendingRevision: Binding<ComposePendingRevision?>,
        onSelectRevision: @escaping (ComposeAppliedRevision) -> Void,
        onAppendClipboard: @escaping () -> Void,
        onAppendLatestCapture: @escaping () -> Void,
        onDictationTranscript: @escaping (String) -> Void,
        onSave: @escaping () -> Void,
        onApplyPending: @escaping () -> Void,
        onDiscardPending: @escaping () -> Void,
        onToggleVoiceCommand: @escaping () -> Void,
        onPerformAction: @escaping (ComposeWorkflowAction) -> Void
    ) {
        self.errorMessage = errorMessage
        self.appliedRevisions = appliedRevisions
        self._draftText = draftText
        self.draftFocus = draftFocus
        self._dictationState = dictationState
        self._dictationError = dictationError
        self._dictationTrigger = dictationTrigger
        self._dictationResetTrigger = dictationResetTrigger
        self.selectedRange = selectedRange
        self.segments = segments
        self.latestCaptureTitle = latestCaptureTitle
        self.canPaste = canPaste
        self.canAddLatestCapture = canAddLatestCapture
        self.voiceCommandState = voiceCommandState
        self.isVoiceCommandEnabled = isVoiceCommandEnabled
        self.canStartDraftDictation = canStartDraftDictation
        self.primaryActions = primaryActions
        self.secondaryActions = secondaryActions
        self.areQuickActionsEnabled = areQuickActionsEnabled
        self.canSave = canSave
        self._pendingRevision = pendingRevision
        self.onSelectRevision = onSelectRevision
        self.onAppendClipboard = onAppendClipboard
        self.onAppendLatestCapture = onAppendLatestCapture
        self.onDictationTranscript = onDictationTranscript
        self.onSave = onSave
        self.onApplyPending = onApplyPending
        self.onDiscardPending = onDiscardPending
        self.onToggleVoiceCommand = onToggleVoiceCommand
        self.onPerformAction = onPerformAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let errorMessage {
                    ComposeErrorBanner(message: errorMessage)
                }

                if !segments.isEmpty {
                    ComposeSegmentsBar(segments: segments)
                }

                if !appliedRevisions.isEmpty {
                    ComposeVersionsCellStrip(
                        revisions: appliedRevisions,
                        onSelect: onSelectRevision
                    )
                }

                ComposeEditorCard(
                    placeholder: "Type, paste, or dictate...",
                    editorMinHeight: 360,
                    text: $draftText,
                    draftFocus: draftFocus,
                    dictationState: $dictationState,
                    dictationError: $dictationError,
                    dictationTrigger: $dictationTrigger,
                    dictationResetTrigger: $dictationResetTrigger,
                    selectedRange: selectedRange,
                    showsDictationButton: true,
                    prefersMinimalKeyboard: false,
                    usesSystemKeyboard: true,
                    canStartDictation: canStartDraftDictation,
                    onDictationTranscript: onDictationTranscript,
                    providerLabel: nil,
                    showsFooterStrip: false,
                    onSave: onSave,
                    canSave: canSave,
                    pendingRevision: $pendingRevision,
                    onApplyPending: onApplyPending,
                    onDiscardPending: onDiscardPending
                ) {
                    EmptyView()
                } footerContent: {
                    EmptyView()
                }
                .frame(maxHeight: .infinity, alignment: .top)

                commandAndTransformControls
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ComposeTray(
                voiceCommandState: voiceCommandState,
                isVoiceCommandEnabled: isVoiceCommandEnabled,
                onToggleVoiceCommand: onToggleVoiceCommand,
                isDraftFocused: draftFocus.wrappedValue,
                onToggleKeyboard: toggleKeyboardFocus
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .simultaneousGesture(keyboardDismissDrag)
    }

    private func toggleKeyboardFocus() {
        let willFocus = !draftFocus.wrappedValue
        draftFocus.wrappedValue = willFocus
        NotificationCenter.default.post(
            name: willFocus ? .composeRequestEditorFocus : .composeRequestEditorBlur,
            object: nil
        )
    }

    private var commandAndTransformControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if areQuickActionsEnabled && !primaryActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    TalkieEyebrow(text: "Transforms", tint: .ink, showLeader: true)
                        .padding(.leading, 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(primaryActions) { action in
                                ComposeBayQuickChip(
                                    title: action.title,
                                    systemImage: action.systemImage,
                                    isEnabled: true
                                ) {
                                    onPerformAction(action)
                                }
                            }

                            if !secondaryActions.isEmpty {
                                ComposeBayMenuChip(
                                    title: "Loop",
                                    systemImage: "point.3.connected.trianglepath.dotted",
                                    isEnabled: areQuickActionsEnabled,
                                    actions: secondaryActions,
                                    onPerformAction: onPerformAction
                                )
                            }
                        }
                    }
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            dismissDraftKeyboard()
        })
    }

    private var keyboardDismissDrag: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard shouldDismissKeyboard(for: value) else { return }
                dismissDraftKeyboard()
            }
    }

    private func shouldDismissKeyboard(for value: DragGesture.Value) -> Bool {
        let verticalDistance = value.translation.height
        let horizontalDistance = abs(value.translation.width)
        return verticalDistance > 46 && verticalDistance > horizontalDistance * 1.4
    }

    private func dismissDraftKeyboard() {
        guard draftFocus.wrappedValue else { return }
        draftFocus.wrappedValue = false
    }
}

private struct ComposeErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.recording)
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

        return resolvedDirectModel(for: selectedDirectProvider)
    }

    /// Compact "Provider · Model" label rendered inline at the bottom of the
    /// editor card. `nil` when nothing useful is configured.
    private var composeProviderLabel: String? {
        guard let provider = selectedDirectProvider else { return nil }
        let providerName = provider.providerName
        if let model = selectedDirectModel {
            return "\(providerName) \(theme.chrome.eyebrowLeader) \(model.name)"
        }
        return providerName
    }

    /// Re-exposed so the inline provider label can pick the active theme's
    /// eyebrow leader. (`themeManager` is observed; this just renames it.)
    private var theme: ThemeManager { themeManager }

    private var phoneAIProvider: ComposeBorrowedProvider? {
        TalkieAIProviderResolver.shared.configuredProvider()
    }

    private var latestCaptureTitle: String? {
        guard let capture = recentCaptures.first else { return nil }
        if let title = capture.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return capture.sourceType.capitalized
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

    private var canStartDraftDictation: Bool {
        !isRevising && voiceCommandState.dictationState == .idle
    }

    private var primaryWorkflowActions: [ComposeWorkflowAction] {
        [
            ComposeWorkflowAction(
                id: "clean-up",
                title: "Clean Up",
                systemImage: "wand.and.sparkles",
                prompt: "Clean this up while preserving my meaning and voice."
            ),
            ComposeWorkflowAction(
                id: "shorter",
                title: "Shorten",
                systemImage: "text.badge.minus",
                prompt: "Make this shorter without losing the important details."
            ),
            ComposeWorkflowAction(
                id: "tasks",
                title: "Tasks",
                systemImage: "checklist",
                prompt: "Extract clear tasks, owners, and next steps from this."
            ),
            ComposeWorkflowAction(
                id: "notes",
                title: "Notes",
                systemImage: "note.text",
                prompt: "Turn this into clean structured notes with useful headings."
            ),
            ComposeWorkflowAction(
                id: "friendlier",
                title: "Friendlier",
                systemImage: "face.smiling",
                prompt: "Make this friendlier and warmer while keeping it direct."
            ),
            ComposeWorkflowAction(
                id: "title",
                title: "Title",
                systemImage: "textformat.size",
                prompt: "Suggest a strong concise title, then keep the note below it."
            ),
        ]
    }

    private var loopWorkflowActions: [ComposeWorkflowAction] {
        [
            ComposeWorkflowAction(
                id: "continue",
                title: "Continue",
                systemImage: "arrow.clockwise",
                prompt: "Continue this into the next useful paragraph or section."
            ),
            ComposeWorkflowAction(
                id: "critique",
                title: "Critique",
                systemImage: "magnifyingglass",
                prompt: "Critique this briefly, then provide a stronger revised version."
            ),
            ComposeWorkflowAction(
                id: "questions",
                title: "Questions",
                systemImage: "questionmark.bubble",
                prompt: "List the most important follow-up questions, then revise the note to make gaps obvious."
            ),
            ComposeWorkflowAction(
                id: "decision",
                title: "Decision",
                systemImage: "arrow.branch",
                prompt: "Turn this into a decision memo with context, options, recommendation, and next steps."
            ),
            ComposeWorkflowAction(
                id: "message",
                title: "Message",
                systemImage: "bubble.left.and.text.bubble.right",
                prompt: "Rewrite this as a clear message I can send to another person."
            ),
            ComposeWorkflowAction(
                id: "workflow",
                title: "Workflow",
                systemImage: "point.3.connected.trianglepath.dotted",
                prompt: "Convert this into a practical AI workflow loop: inputs, actions, review points, and outputs."
            ),
        ]
    }

    private var composeErrorMessage: String? {
        voiceCommandState.errorMessage ?? errorMessage
    }

    @ViewBuilder
    private var composeHeaderModelControls: some View {
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
            selectDirectProviderModel: { providerId, modelId in
                selectDirectProviderModel(providerId: providerId, modelId: modelId)
            },
            reconnectToMac: reconnectToMac,
            openBridgeSettings: openBridgeSettings,
            showsStatusMessage: false,
            useEditorialLabel: true
        )
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
        composeSegments.removeAll()
        selectedRange = nil
    }

    private func prepareInitialEditorIfNeeded() {
        guard !didPrepareInitialEditor else { return }
        didPrepareInitialEditor = true

        if let initialContext {
            clearDraft()
            activeNote = nil
            draftText = initialContext.text
            isShowingNoteEditor = true
            addSegment(
                kind: .capturedContext,
                title: initialContext.title ?? "Captured context",
                detail: initialContext.sourceDescription ?? initialContext.sourceURL,
                text: initialContext.text
            )
            return
        }

        if !isShowingNoteEditor {
            activeNote = nil
            isShowingNoteEditor = true
        }
    }

    private func refreshRecentCaptures() {
        CaptureStore.shared.reload()
        recentCaptures = CaptureStore.shared.all()
    }

    private func appendClipboardContext() {
        guard let clipboardText = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            return
        }

        appendTextAsSegment(
            clipboardText,
            kind: .pastedContext,
            title: "Pasted text",
            detail: "Clipboard"
        )
    }

    private func appendLatestCaptureContext() {
        refreshRecentCaptures()
        guard let capture = recentCaptures.first else { return }
        let title = capture.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title?.isEmpty == false ? title ?? "Latest capture" : "Latest capture"
        appendTextAsSegment(
            capture.text,
            kind: .capturedContext,
            title: displayTitle,
            detail: capture.bookmark?.siteName ?? capture.sourceType.capitalized
        )
    }

    private func appendTextAsSegment(
        _ text: String,
        kind: ComposeSegmentKind,
        title: String,
        detail: String?
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !draftText.hasSuffix("\n") {
                draftText += "\n"
            }
            draftText += "\n"
        }
        draftText += trimmedText
        addSegment(kind: kind, title: title, detail: detail, text: trimmedText)
        isShowingNoteEditor = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func recordDictationSegment(_ transcript: String) {
        addSegment(
            kind: .dictation,
            title: "Voice segment",
            detail: "\(transcript.split(whereSeparator: \.isWhitespace).count) words",
            text: transcript
        )
    }

    private func addSegment(
        kind: ComposeSegmentKind,
        title: String,
        detail: String?,
        text: String
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        composeSegments.insert(
            ComposeSegment(
                kind: kind,
                title: title,
                detail: detail,
                text: trimmedText,
                createdAt: .now
            ),
            at: 0
        )
    }

    private func performWorkflowAction(_ action: ComposeWorkflowAction) {
        submitInstruction(action.prompt)
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
        if hasDraft {
            addSegment(
                kind: .savedNote,
                title: note.title ?? "Saved note",
                detail: note.lastModified.map { $0.formatted(.dateTime.month().day().hour().minute()) },
                text: draftText
            )
        }
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
        selectedRange = nil
        composeSegments.removeAll()
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

    private func currentRevisionTarget() -> ComposeRevisionTarget? {
        let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return nil }

        if let selectedRange,
           selectedRange.length > 0 {
            let nsText = draftText as NSString
            let rangeEnd = selectedRange.location + selectedRange.length
            if selectedRange.location >= 0, rangeEnd <= nsText.length {
                let selectedText = nsText.substring(with: selectedRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !selectedText.isEmpty {
                    return ComposeRevisionTarget(
                        text: selectedText,
                        fullDocument: draftText,
                        selectedRange: selectedRange
                    )
                }
            }
        }

        return ComposeRevisionTarget(
            text: draftText,
            fullDocument: draftText,
            selectedRange: nil
        )
    }

    private func macInstruction(
        _ instruction: String,
        for target: ComposeRevisionTarget
    ) -> String {
        guard target.selectedRange != nil else { return instruction }

        return [
            instruction,
            "",
            "Editing scope: Selected excerpt of a larger note.",
            "",
            "Current full document:",
            target.fullDocument,
            "",
            "Return only the revised selected excerpt.",
        ].joined(separator: "\n")
    }

    private func revisionHistoryPromptContext() -> String {
        guard !appliedRevisions.isEmpty else { return "No prior revisions." }

        return appliedRevisions.reversed().enumerated().map { index, revision in
            [
                "Revision \(index + 1)",
                "- Timestamp: \(ISO8601DateFormatter().string(from: revision.createdAt))",
                "- Scope: \(revision.scope)",
                "- Instruction: \(revision.instruction)",
                "- Text After:",
                revision.text,
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func requestDirectRevision() {
        guard !isRevising else { return }

        let instruction = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = currentRevisionTarget() else { return }

        guard !instruction.isEmpty else { return }

        let directProviderOption = selectedDirectProvider
        let selectedModelId = selectedDirectModel?.id ?? appSettings.composeDirectModelId

        isRevising = true
        errorMessage = nil

        Task {
            do {
                let provider: ComposeBorrowedProvider
                if let phoneAIProvider {
                    provider = phoneAIProvider
                } else {
                    guard let directProviderOption else {
                        throw BridgeError.messageFailed(
                            directOptionsError ?? "Set up AI credentials in Settings -> AI, or pair a Mac provider."
                        )
                    }

                    provider = try await bridgeManager.composeBorrowedProvider(
                        providerId: directProviderOption.providerId,
                        modelId: selectedModelId
                    )
                }

                let result = try await ComposeLocalRevisionService.shared.revise(
                    text: target.text,
                    instruction: instruction,
                    provider: provider,
                    fullDocument: target.fullDocument,
                    editingScope: target.editingScope,
                    revisionHistory: revisionHistoryPromptContext()
                )
                pendingRevision = ComposePendingRevision(
                    originalText: target.text,
                    originalDocumentText: target.fullDocument,
                    targetRange: target.selectedRange,
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
        guard let target = currentRevisionTarget() else { return }

        guard !instruction.isEmpty else { return }

        isRevising = true
        errorMessage = nil

        Task {
            do {
                let result = try await bridgeManager.composeRevision(
                    text: target.text,
                    instruction: macInstruction(instruction, for: target)
                )
                pendingRevision = ComposePendingRevision(
                    originalText: target.text,
                    originalDocumentText: target.fullDocument,
                    targetRange: target.selectedRange,
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

        if let targetRange = pendingRevision.targetRange {
            guard replacePendingSelection(pendingRevision, targetRange: targetRange) else {
                errorMessage = "The selected text changed. Run the voice command again."
                return
            }
        } else {
            draftText = pendingRevision.revisedText
        }

        appliedRevisions.insert(
            ComposeAppliedRevision(
                instruction: pendingRevision.instruction,
                scope: pendingRevision.isSelectionRevision ? "Selection" : "Document",
                text: pendingRevision.revisedText,
                providerName: pendingRevision.providerName,
                modelId: pendingRevision.modelId,
                createdAt: pendingRevision.createdAt
            ),
            at: 0
        )
        addSegment(
            kind: .revision,
            title: pendingRevision.isSelectionRevision ? "Selection revised" : "Draft revised",
            detail: pendingRevision.instruction,
            text: pendingRevision.revisedText
        )
        // Speak the revised draft excerpt — no separate AI explanation field exists.
        let spokenText = String(pendingRevision.revisedText.prefix(280))
        self.pendingRevision = nil
        errorMessage = nil
        Task { @MainActor in
            _ = await AIResponseSpeechRouter.shared.speak(spokenText)
        }
    }

    private func discardPendingRevision() {
        pendingRevision = nil
    }

    fileprivate func applyAppliedRevision(_ revision: ComposeAppliedRevision) {
        draftText = revision.text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func replacePendingSelection(
        _ pendingRevision: ComposePendingRevision,
        targetRange: NSRange
    ) -> Bool {
        let nsText = draftText as NSString
        let rangeEnd = targetRange.location + targetRange.length
        guard targetRange.location >= 0, rangeEnd <= nsText.length else {
            return false
        }

        let currentTarget = nsText.substring(with: targetRange)
        guard currentTarget == pendingRevision.originalText else {
            return false
        }

        if let swiftRange = Range(targetRange, in: draftText) {
            draftText.replaceSubrange(swiftRange, with: pendingRevision.revisedText)
            selectedRange = NSRange(
                location: targetRange.location,
                length: (pendingRevision.revisedText as NSString).length
            )
            return true
        }

        return false
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

        let selectedModel = resolvedDirectModel(
            for: selectedProvider,
            savedModelId: appSettings.composeDirectModelId,
            serverSelectedModelId: options.selectedModelId
        )

        appSettings.composeDirectProviderId = selectedProvider.providerId
        appSettings.composeDirectModelId = selectedModel?.id ?? ""
    }

    private func selectDirectProvider(_ providerId: String) {
        guard let provider = availableDirectProviders.first(where: { $0.providerId == providerId }) else { return }
        appSettings.composeDirectProviderId = provider.providerId

        let savedModelId = appSettings.composeDirectModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldKeepSavedModel = shouldKeepSavedDirectModel(savedModelId, providerId: provider.providerId)
            && provider.models.contains(where: { $0.id == savedModelId })

        if !shouldKeepSavedModel {
            appSettings.composeDirectModelId = resolvedDirectModel(
                for: provider,
                savedModelId: savedModelId
            )?.id ?? ""
        }
    }

    private func selectDirectModel(_ modelId: String) {
        guard let selectedDirectProvider else { return }
        guard selectedDirectProvider.models.contains(where: { $0.id == modelId }) else { return }
        appSettings.composeDirectModelId = modelId
    }

    private func selectDirectProviderModel(providerId: String, modelId: String) {
        guard let provider = availableDirectProviders.first(where: { $0.providerId == providerId }) else { return }

        appSettings.composeDirectProviderId = provider.providerId
        if provider.models.contains(where: { $0.id == modelId }) {
            appSettings.composeDirectModelId = modelId
        } else {
            appSettings.composeDirectModelId = resolvedDirectModel(for: provider)?.id ?? ""
        }
    }

    private func resolvedDirectModel(
        for provider: ComposeDirectProviderOption,
        savedModelId: String? = nil,
        serverSelectedModelId: String? = nil
    ) -> ComposeDirectModelOption? {
        let savedModelId = (savedModelId ?? appSettings.composeDirectModelId)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldKeepSavedDirectModel(savedModelId, providerId: provider.providerId),
           let matchingModel = provider.models.first(where: { $0.id == savedModelId }) {
            return matchingModel
        }

        if let preferredModel = preferredDirectModel(in: provider) {
            return preferredModel
        }

        if let serverSelectedModelId,
           let serverModel = provider.models.first(where: { $0.id == serverSelectedModelId }) {
            return serverModel
        }

        if let legacyModel = provider.models.first(where: { $0.id == savedModelId }) {
            return legacyModel
        }

        return provider.models.first
    }

    private func preferredDirectModel(in provider: ComposeDirectProviderOption) -> ComposeDirectModelOption? {
        let preferredModelId = TalkieAIProviderCredentialPayload.defaultModel(for: provider.providerId)
        return provider.models.first { $0.id == preferredModelId }
    }

    private func shouldKeepSavedDirectModel(_ modelId: String, providerId: String) -> Bool {
        guard !modelId.isEmpty else { return false }
        return !TalkieAIProviderCredentialPayload.isLegacyDefaultModel(modelId, for: providerId)
    }
}

struct ComposePendingRevision: Identifiable {
    let id = UUID()
    let originalText: String
    let originalDocumentText: String
    let targetRange: NSRange?
    var revisedText: String
    let instruction: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
    let createdAt: Date

    var isSelectionRevision: Bool {
        targetRange != nil
    }
}

private struct ComposeVoiceCommandPreview: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

private struct ComposeAppliedRevision: Identifiable {
    let id = UUID()
    let instruction: String
    let scope: String
    let text: String
    let providerName: String
    let modelId: String
    let createdAt: Date
}

private struct ComposeRevisionTarget {
    let text: String
    let fullDocument: String
    let selectedRange: NSRange?

    var editingScope: String {
        selectedRange == nil ? "Entire document." : "Selected excerpt of a larger note."
    }

    var historyScopeLabel: String {
        selectedRange == nil ? "Document" : "Selection"
    }
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
    let selectDirectProviderModel: (String, String) -> Void
    let reconnectToMac: () -> Void
    let openBridgeSettings: () -> Void
    var showsStatusMessage = true
    var useEditorialLabel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits {
                selectionChips
                    .frame(maxWidth: .infinity, alignment: .leading)

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
        Menu {
            Section("Method") {
                Button {
                    selectRevisionPath(.direct)
                } label: {
                    Label("API", systemImage: selectedRevisionPath == .direct ? "checkmark.circle.fill" : ComposeRevisionPath.direct.systemImage)
                }

                if isPaired {
                    Button {
                        selectRevisionPath(.mac)
                        if connectionStatus != .connected {
                            reconnectToMac()
                        }
                    } label: {
                        Label(macMethodMenuTitle, systemImage: selectedRevisionPath == .mac ? "checkmark.circle.fill" : macMethodMenuIcon)
                    }
                } else {
                    Button {
                        openBridgeSettings()
                    } label: {
                        Label("Pair Mac", systemImage: "desktopcomputer.badge.plus")
                    }
                }
            }

            Section("API Model") {
                if availableDirectProviders.isEmpty {
                    apiPlaceholderMenuItem
                } else {
                    ForEach(availableDirectProviders) { provider in
                        if provider.models.isEmpty {
                            Button {
                                selectRevisionPath(.direct)
                                selectDirectProvider(provider.providerId)
                            } label: {
                                Label(provider.providerName, systemImage: selectedProvider?.providerId == provider.providerId ? "checkmark.circle.fill" : providerSymbol(for: provider.providerId))
                            }
                        } else {
                            Menu {
                                ForEach(provider.models) { model in
                                    Button {
                                        selectRevisionPath(.direct)
                                        selectDirectProviderModel(provider.providerId, model.id)
                                    } label: {
                                        Label(model.name, systemImage: isSelected(provider: provider, model: model) ? "checkmark.circle.fill" : "cpu")
                                    }
                                }
                            } label: {
                                Label(provider.providerName, systemImage: selectedProvider?.providerId == provider.providerId ? "checkmark.circle.fill" : providerSymbol(for: provider.providerId))
                            }
                        }
                    }
                }
            }

            Section("Mac") {
                if pairedMacs.isEmpty {
                    Button {
                        if isPaired {
                            reconnectToMac()
                        } else {
                            openBridgeSettings()
                        }
                    } label: {
                        Label(isPaired ? activeMacTitle : "Pair Mac", systemImage: isPaired ? "arrow.clockwise" : "desktopcomputer.badge.plus")
                    }
                } else {
                    ForEach(pairedMacs) { pairedMac in
                        Button {
                            selectPairedMac(pairedMac.id)
                            selectRevisionPath(.mac)
                            if connectionStatus != .connected {
                                reconnectToMac()
                            }
                        } label: {
                            Label(pairedMacTitle(for: pairedMac), systemImage: pairedMac.id == activePairedMacID && selectedRevisionPath == .mac ? "checkmark.circle.fill" : "desktopcomputer")
                        }
                    }

                    if connectionStatus != .connected {
                        Button {
                            reconnectToMac()
                        } label: {
                            Label("Reconnect Mac", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Button {
                    openBridgeSettings()
                } label: {
                    Label(isPaired ? "Mac Settings" : "Pair Mac", systemImage: isPaired ? "gearshape" : "desktopcomputer.badge.plus")
                }
            }
        } label: {
            if useEditorialLabel {
                ComposeEditorialModelLabel(
                    title: selectedRouteTitle,
                    tint: selectedRouteTint,
                    isLoading: selectedRouteIsLoading
                )
            } else {
                ComposeSelectionChip(
                    title: selectedRouteTitle,
                    systemImage: selectedRouteIcon,
                    tint: selectedRouteTint,
                    showsMenuIndicator: true,
                    showsLoadingIndicator: selectedRouteIsLoading
                )
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var apiPlaceholderMenuItem: some View {
        if isLoadingDirectOptions {
            Button {
            } label: {
                Label("Loading API Providers", systemImage: "hourglass")
            }
            .disabled(true)
        } else if !isPaired {
            Button {
                openBridgeSettings()
            } label: {
                Label("Pair Mac to Load APIs", systemImage: "desktopcomputer.badge.plus")
            }
        } else if directOptionsError != nil {
            Button {
                reconnectToMac()
            } label: {
                Label("Reload API Providers", systemImage: "arrow.clockwise")
            }
        } else {
            Button {
            } label: {
                Label("No API Providers", systemImage: "network.slash")
            }
            .disabled(true)
        }
    }

    private var selectedRouteTitle: String {
        switch selectedRevisionPath {
        case .direct:
            if let selectedProvider, let selectedModel {
                return "API · \(selectedProvider.providerName) · \(selectedModel.name)"
            }
            if let selectedProvider {
                return "API · \(selectedProvider.providerName)"
            }
            if isLoadingDirectOptions {
                return "API · Loading"
            }
            if directOptionsError != nil {
                return "API · Unavailable"
            }
            return "API"
        case .mac:
            return "Mac · \(activeMacTitle)"
        }
    }

    private var selectedRouteIcon: String {
        switch selectedRevisionPath {
        case .direct:
            guard let selectedProvider else { return directProviderPlaceholderIcon }
            return providerSymbol(for: selectedProvider.providerId)
        case .mac:
            return selectedPathIcon
        }
    }

    private var selectedRouteTint: Color {
        switch selectedRevisionPath {
        case .direct:
            guard let selectedProvider else { return directPlaceholderTint }
            return providerTint(for: selectedProvider.providerId)
        case .mac:
            return statusColor
        }
    }

    private var selectedRouteIsLoading: Bool {
        selectedRevisionPath == .direct && isLoadingDirectOptions && availableDirectProviders.isEmpty
    }

    private var macMethodMenuTitle: String {
        guard isPaired else { return "Pair Mac" }

        switch connectionStatus {
        case .connected:
            return "Mac"
        case .connecting:
            return "Connecting to Mac"
        case .disconnected, .error:
            return "Reconnect Mac"
        }
    }

    private var macMethodMenuIcon: String {
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

    private func isSelected(provider: ComposeDirectProviderOption, model: ComposeDirectModelOption) -> Bool {
        selectedRevisionPath == .direct
            && selectedProvider?.providerId == provider.providerId
            && selectedModel?.id == model.id
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
    var isLive = true   // lit signal-dot when the chip represents an active path

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let corner = max(chrome.chromeCorner, 6)
        HStack(spacing: 6) {
            // Signal dot — lit when this lever is on an active path, faint when
            // the chip is a placeholder/loading state. Reads as "channel armed".
            TalkieStatusDot(
                diameter: 5,
                pulses: showsLoadingIndicator,
                color: isLive && isEnabled ? tint : theme.colors.textTertiary.opacity(0.5)
            )

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
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)

            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(theme.colors.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(
                    isLive && isEnabled ? chrome.edge : chrome.edgeFaint,
                    lineWidth: chrome.hairlineWidth
                )
                .allowsHitTesting(false)
        }
        .opacity(isEnabled ? 1 : 0.7)
    }
}

// Consolidated editorial header: "Draft with ✨ provider · model ▾". Replaces
// the separate DRAFT eyebrow + model byline pair with one line that reads as a
// single tappable phrase. Sparkles glyph carries the AI cue; the route title
// trails as the noun. Tap anywhere opens the picker Menu.
private struct ComposeEditorialModelLabel: View {
    let title: String
    let tint: Color
    var isLoading: Bool = false

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Text("Compose with")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(theme.colors.textTertiary)

            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint.opacity(0.85))
                .scopePhosphorGlow(radius: 2)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            }

            Text(modelDisplay)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .accessibilityLabel("Model: \(modelDisplay)")
        .accessibilityHint("Tap to change route or model")
    }

    // Display the model as a clean short noun. Drops the route prefix AND the
    // provider name (users recognize the model — "GPT-5" — without needing
    // "OpenAI" attached). Trailing component after the last " · " wins.
    //   "API · OpenAI · GPT-5"  → "GPT-5"
    //   "API · OpenAI"           → "OpenAI"  (no model picked yet for this provider)
    //   "API · Loading"          → "Loading…"
    //   "API · Unavailable"      → "Unavailable"
    //   "API"                    → "Choose model"  (nothing picked at all)
    //   "Mac · iMac"             → "iMac"
    //   "Mac"                    → "Mac"
    private var modelDisplay: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        for prefix in ["API · ", "MAC · ", "Mac · "] {
            if trimmed.hasPrefix(prefix) {
                let remainder = String(trimmed.dropFirst(prefix.count))
                if remainder == "Loading" { return "Loading…" }
                if let lastSegment = remainder.components(separatedBy: " · ").last,
                   !lastSegment.isEmpty {
                    return lastSegment
                }
                return remainder
            }
        }
        if trimmed == "API" { return "Choose model" }
        return trimmed
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
    var selectedRange: Binding<NSRange?>? = nil
    var showsDictationButton = true
    var prefersMinimalKeyboard = false
    var usesSystemKeyboard = false
    var canStartDictation = true
    var onDictationTranscript: ((String) -> Void)?

    var body: some View {
        editorContent
        .frame(minHeight: minHeight, maxHeight: .infinity, alignment: .top)
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

    @ViewBuilder
    private var editorContent: some View {
        if usesSystemKeyboard {
            ComposeNativeDraftTextEditor(
                text: $text,
                placeholder: placeholder,
                focus: focus,
                dictationState: $dictationState,
                dictationError: $dictationError,
                dictationTrigger: dictationTrigger,
                dictationResetTrigger: dictationResetTrigger,
                selectedRange: selectedRange,
                contentBottomInset: showsDictationButton ? micPlacement.contentBottomInset : 16,
                canStartDictation: canStartDictation,
                onDictationTranscript: onDictationTranscript
            )
        } else {
            ComposeKeyboardTextView(
                text: $text,
                placeholder: placeholder,
                isFocused: focus,
                dictationState: $dictationState,
                dictationError: $dictationError,
                selectedRange: selectedRange,
                contentBottomInset: showsDictationButton ? micPlacement.contentBottomInset : 16,
                prefersMinimalKeyboard: prefersMinimalKeyboard,
                canStartDictation: canStartDictation,
                dictationTrigger: dictationTrigger,
                dictationResetTrigger: dictationResetTrigger,
                onDictationTranscript: onDictationTranscript
            )
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
        .disabled(isDictationButtonDisabled)
        .accessibilityLabel(dictationLabel)
    }

    private var isDictationButtonDisabled: Bool {
        dictationState == .transcribing || (dictationState == .idle && !canStartDictation)
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

private struct ComposeNativeDictationTranscript: Equatable {
    let id = UUID()
    let text: String
}

private enum ComposeRevisionReviewMode: String, CaseIterable, Identifiable {
    case before
    case after
    case diff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .before:
            return "Before"
        case .after:
            return "After"
        case .diff:
            return "Diff"
        }
    }
}

@MainActor
@Observable
private final class ComposeNativeEditorDictationState {
    var state: InlineDictationController.State = .idle
    var errorMessage: String?
    var latestTranscript: ComposeNativeDictationTranscript?

    private let controller = InlineDictationController()

    init() {
        controller.onStateChange = { [weak self] state in
            self?.state = state
        }
        controller.onTranscript = { [weak self] transcript in
            self?.errorMessage = nil
            self?.latestTranscript = ComposeNativeDictationTranscript(text: transcript)
        }
        controller.onError = { [weak self] message in
            self?.errorMessage = message
            self?.state = .idle
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

    func cancel() {
        controller.cancel()
    }

    func consumeTranscript() {
        latestTranscript = nil
    }
}

private struct ComposeNativeDraftTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let focus: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    let dictationTrigger: Int
    let dictationResetTrigger: Int
    var selectedRange: Binding<NSRange?>?
    let contentBottomInset: CGFloat
    let canStartDictation: Bool
    var onDictationTranscript: ((String) -> Void)?

    @State private var dictation = ComposeNativeEditorDictationState()
    @State private var textSelection: TextSelection?
    @State private var lastDictationTrigger = 0
    @State private var lastDictationResetTrigger = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text, selection: $textSelection)
                .focused(focus)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandAccent)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .contentMargins(.top, 16, for: .scrollContent)
                .contentMargins(.bottom, contentBottomInset, for: .scrollContent)
                .background(Color.clear)

            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            lastDictationTrigger = dictationTrigger
            lastDictationResetTrigger = dictationResetTrigger
            dictationState = dictation.state
            dictationError = dictation.errorMessage
            selectedRange?.wrappedValue = nil
        }
        .onDisappear {
            cancelDictation(clearError: true)
            selectedRange?.wrappedValue = nil
        }
        .onChange(of: text) { _, _ in
            selectedRange?.wrappedValue = nil
        }
        .onChange(of: textSelection) { _, selection in
            publishSelection(selection)
        }
        .onChange(of: dictationTrigger) { _, trigger in
            handleDictationTrigger(trigger)
        }
        .onChange(of: dictationResetTrigger) { _, trigger in
            handleDictationResetTrigger(trigger)
        }
        .onChange(of: dictation.state) { _, state in
            dictationState = state
        }
        .onChange(of: dictation.errorMessage) { _, message in
            dictationError = message
        }
        .onChange(of: dictation.latestTranscript) { _, result in
            guard let result else { return }
            if let insertedTranscript = appendTranscript(result.text) {
                onDictationTranscript?(insertedTranscript)
            }
            dictation.consumeTranscript()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    focus.wrappedValue = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }

    private func handleDictationTrigger(_ trigger: Int) {
        guard trigger != lastDictationTrigger else { return }
        lastDictationTrigger = trigger
        focus.wrappedValue = true
        dictation.toggle(canStart: canStartDictation)
    }

    private func handleDictationResetTrigger(_ trigger: Int) {
        guard trigger != lastDictationResetTrigger else { return }
        lastDictationResetTrigger = trigger
        cancelDictation(clearError: true)
    }

    private func appendTranscript(_ transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separator = text.isEmpty || text.last?.isWhitespace == true ? "" : " "
        text += separator + trimmed
        selectedRange?.wrappedValue = nil
        return trimmed
    }

    private func publishSelection(_ selection: TextSelection?) {
        selectedRange?.wrappedValue = selectedNSRange(from: selection)
    }

    private func selectedNSRange(from selection: TextSelection?) -> NSRange? {
        guard let selection, !selection.isInsertion else { return nil }

        switch selection.indices {
        case .selection(let range):
            return nsRange(for: range)
        case .multiSelection(let ranges):
            guard let range = ranges.ranges.first(where: { !$0.isEmpty }) else {
                return nil
            }
            return nsRange(for: range)
        @unknown default:
            return nil
        }
    }

    private func nsRange(for range: Range<String.Index>) -> NSRange? {
        guard !range.isEmpty else { return nil }
        return NSRange(range, in: text)
    }

    private func cancelDictation(clearError: Bool) {
        dictation.cancel()
        dictationState = .idle
        if clearError {
            dictationError = nil
        }
    }
}

private struct ComposeRevisionEditableTextSurface: View {
    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($isFocused)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .tint(Color.brandAccent)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .contentMargins(.top, 16, for: .scrollContent)
                .contentMargins(.bottom, 16, for: .scrollContent)
                .background(Color.clear)

            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button {
                    isFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }
}

struct ComposeKeyboardTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    var selectedRange: Binding<NSRange?>?
    let contentBottomInset: CGFloat
    let prefersMinimalKeyboard: Bool
    let canStartDictation: Bool
    let dictationTrigger: Int
    let dictationResetTrigger: Int
    var onDictationTranscript: ((String) -> Void)?

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
        context.coordinator.canStartDictation = canStartDictation
        context.coordinator.setFocused = { focused in
            isFocused.wrappedValue = focused
        }
        context.coordinator.selectedRange = selectedRange
        context.coordinator.onDictationTranscript = onDictationTranscript
        context.coordinator.textView = textView
        context.coordinator.keyboard = textView.inputView as? HostedTalkieKeyboardView
        context.coordinator.keyboard?.preferredInitialLayout = prefersMinimalKeyboard ? .minimal : .compact
        context.coordinator.keyboard?.preferredInitialModeId = KeyboardMode.abc.id
        textView.isUserInteractionEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: contentBottomInset, right: 14)

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
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        coordinator.teardown()
        uiView.delegate = nil
        uiView.inputView = nil
        if uiView.isFirstResponder {
            uiView.resignFirstResponder()
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
        coordinator.keyboard = keyboard

        textView.delegate = coordinator
        textView.accessibilityIdentifier = "keyboard.compose"
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
        var canStartDictation = true
        var setFocused: ((Bool) -> Void)?
        var selectedRange: Binding<NSRange?>?
        var onDictationTranscript: ((String) -> Void)?
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
                self.onDictationTranscript?(transcript)
                self.keyboard?.showDictationSuccessFeedback()
            }
            dictationController.onError = { [weak self] message in
                self?.dictationError.wrappedValue = message
                self?.dictationState.wrappedValue = .idle
                self?.keyboard?.setDictationState(.idle)
            }

            // Side-channel focus pipe — the bottom-tray Keyboard button posts
            // these notifications because FocusState.Binding writes don't
            // reliably trigger this representable's updateUIView.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusRequest),
                name: .composeRequestEditorFocus,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBlurRequest),
                name: .composeRequestEditorBlur,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleFocusRequest() {
            guard let textView, !textView.isFirstResponder else { return }
            textView.becomeFirstResponder()
        }

        @objc private func handleBlurRequest() {
            guard let textView, textView.isFirstResponder else { return }
            textView.resignFirstResponder()
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange?.wrappedValue = textView.selectedRange.length > 0 ? textView.selectedRange : nil
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

            // Drive off the binding the UI is reading (what the mic icon
            // currently shows) so a "tap to stop" never gets reinterpreted as
            // a fresh start during the start()-→-recording transition window.
            switch dictationState.wrappedValue {
            case .idle:
                guard canStartDictation else { return }
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
                newLabel.isUserInteractionEnabled = false
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

        func teardown() {
            dictationController.cancel()
            keyboard?.inputHost = nil
            keyboard?.onDictationToggle = nil
            keyboard?.onLayoutHeightChange = nil
            keyboard?.onRequestCollapse = nil
            keyboard = nil
            textView = nil
            selectedRange?.wrappedValue = nil
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

struct ComposeEditorCard<HeaderContent: View, FooterContent: View>: View {
    let placeholder: String
    let editorMinHeight: CGFloat
    @Binding var text: String
    let draftFocus: FocusState<Bool>.Binding
    @Binding var dictationState: InlineDictationController.State
    @Binding var dictationError: String?
    @Binding var dictationTrigger: Int
    @Binding var dictationResetTrigger: Int
    var selectedRange: Binding<NSRange?>?
    let headerContent: HeaderContent
    let footerContent: FooterContent
    var showsDictationButton = true
    var prefersMinimalKeyboard = false
    var usesSystemKeyboard = false
    var canStartDictation = true
    var onDictationTranscript: ((String) -> Void)?
    var providerLabel: String? = nil   // e.g. "OpenAI · GPT-5" — shown inline with Quick Copy
    var showsConsoleHeader = true
    var consoleHeaderLabel: String = "Draft"
    var headerModelControls: AnyView? = nil
    var showsFooterStrip: Bool = true
    var onSave: (() -> Void)? = nil
    var canSave: Bool = false
    var onShowHistory: (() -> Void)? = nil
    var historyCount: Int = 0
    @Binding var pendingRevision: ComposePendingRevision?
    var onApplyPending: (() -> Void)? = nil
    var onDiscardPending: (() -> Void)? = nil
    @State private var showingCopiedFeedback = false
    @State private var revisionReviewMode: ComposeRevisionReviewMode = .after
    @ObservedObject private var theme = ThemeManager.shared

    init(
        placeholder: String,
        editorMinHeight: CGFloat = 360,
        text: Binding<String>,
        draftFocus: FocusState<Bool>.Binding,
        dictationState: Binding<InlineDictationController.State>,
        dictationError: Binding<String?>,
        dictationTrigger: Binding<Int>,
        dictationResetTrigger: Binding<Int>,
        selectedRange: Binding<NSRange?>? = nil,
        showsDictationButton: Bool = true,
        prefersMinimalKeyboard: Bool = false,
        usesSystemKeyboard: Bool = false,
        canStartDictation: Bool = true,
        onDictationTranscript: ((String) -> Void)? = nil,
        providerLabel: String? = nil,
        showsConsoleHeader: Bool = true,
        consoleHeaderLabel: String = "Draft",
        headerModelControls: AnyView? = nil,
        showsFooterStrip: Bool = true,
        onSave: (() -> Void)? = nil,
        canSave: Bool = false,
        onShowHistory: (() -> Void)? = nil,
        historyCount: Int = 0,
        pendingRevision: Binding<ComposePendingRevision?> = .constant(nil),
        onApplyPending: (() -> Void)? = nil,
        onDiscardPending: (() -> Void)? = nil,
        @ViewBuilder headerContent: () -> HeaderContent,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.placeholder = placeholder
        self.editorMinHeight = editorMinHeight
        self._text = text
        self.draftFocus = draftFocus
        self._dictationState = dictationState
        self._dictationError = dictationError
        self._dictationTrigger = dictationTrigger
        self._dictationResetTrigger = dictationResetTrigger
        self.selectedRange = selectedRange
        self.showsDictationButton = showsDictationButton
        self.prefersMinimalKeyboard = prefersMinimalKeyboard
        self.usesSystemKeyboard = usesSystemKeyboard
        self.canStartDictation = canStartDictation
        self.onDictationTranscript = onDictationTranscript
        self.providerLabel = providerLabel
        self.showsConsoleHeader = showsConsoleHeader
        self.consoleHeaderLabel = consoleHeaderLabel
        self.headerModelControls = headerModelControls
        self.showsFooterStrip = showsFooterStrip
        self.onSave = onSave
        self.canSave = canSave
        self.onShowHistory = onShowHistory
        self.historyCount = historyCount
        self._pendingRevision = pendingRevision
        self.onApplyPending = onApplyPending
        self.onDiscardPending = onDiscardPending
        self.headerContent = headerContent()
        self.footerContent = footerContent()
    }

    var body: some View {
        let chrome = theme.chrome
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if showsConsoleHeader && pendingRevision != nil {
                consoleHeader(chrome: chrome)
            }

            headerContent

            if let pendingRevision {
                revisionReviewSurface(
                    revision: pendingRevision,
                    chrome: chrome
                )
            } else {
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
                    selectedRange: selectedRange,
                    showsDictationButton: showsDictationButton,
                    prefersMinimalKeyboard: prefersMinimalKeyboard,
                    usesSystemKeyboard: usesSystemKeyboard,
                    canStartDictation: canStartDictation,
                    onDictationTranscript: onDictationTranscript
                )
                .frame(maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .stroke(chrome.edgeFaint, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !trimmedText.isEmpty {
                        editorCopyButton(chrome: chrome)
                            .padding(.bottom, 12)
                            .padding(.trailing, 12)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: trimmedText.isEmpty)
                .animation(.easeOut(duration: 0.18), value: showingCopiedFeedback)
            }

            if showsFooterStrip {
                footerStrip
            }

            if let dictationError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.recording)
                    Text(dictationError)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: pendingRevision?.id) { _, revisionID in
            if revisionID != nil {
                revisionReviewMode = .after
            }
        }
    }

    // Footer strip — command + route chooser on the left, persistence affordances
    // on the right. It stacks only when the phone width is too narrow.
    private var footerStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                footerContent

                Spacer(minLength: 8)

                footerActions
            }

            VStack(alignment: .leading, spacing: 8) {
                footerContent
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    footerActions
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var footerActions: some View {
        HStack(spacing: 14) {
            if let onShowHistory, historyCount > 0 {
                Button(action: onShowHistory) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10, weight: .light))
                        Text("History · \(historyCount)")
                            .font(.system(size: 10, weight: .regular))
                    }
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show revision history, \(historyCount) entries")
            }

            Button(action: copyDraft) {
                HStack(spacing: 4) {
                    Image(systemName: showingCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .light))

                    Text(showingCopiedFeedback ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .regular))
                }
                .foregroundStyle(showingCopiedFeedback ? Color.success : theme.colors.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(trimmedText.isEmpty ? 0.45 : 1)
        }
    }

    @ViewBuilder
    private func revisionReviewSurface(
        revision: ComposePendingRevision,
        chrome: ChromeTokens
    ) -> some View {
        Group {
            switch revisionReviewMode {
            case .before:
                revisionTextScrollSurface(text: revision.originalText)
            case .after:
                ComposeRevisionEditableTextSurface(
                    text: revisedTextBinding,
                    placeholder: "Edit the revised draft..."
                )
            case .diff:
                ScrollView {
                    ComposeRevisionDiffView(
                        originalText: revision.originalText,
                        revisedText: revision.revisedText
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                }
            }
        }
        .frame(height: editorMinHeight)
        .background(Color.surfacePrimary)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(chrome.action.opacity(0.35), lineWidth: chrome.hairlineWidth)
                .allowsHitTesting(false)
        }
    }

    private func revisionTextScrollSurface(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundStyle(theme.colors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
        }
    }

    // Tiny instrument-display strip: theme eyebrow + thin trace + live word
    // count. Gives the editor a "working surface" framing without consuming
    // meaningful vertical space.
    @ViewBuilder
    private func consoleHeader(chrome: ChromeTokens) -> some View {
        // The header only surfaces when a pending revision needs the
        // before/after/diff picker — everything else (model name, counts,
        // save) lives in the navigation bar now.
        if pendingRevision != nil {
            HStack(spacing: 10) {
                revisionHeaderControls(chrome: chrome)
            }
            .padding(.horizontal, 2)
        }
    }

    private func revisionHeaderControls(chrome: ChromeTokens) -> some View {
        HStack(spacing: 5) {
            Picker("Revision view", selection: $revisionReviewMode) {
                ForEach(ComposeRevisionReviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 168)

            Button {
                onDiscardPending?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.recording)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.recording.opacity(0.10))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.recording.opacity(0.45), lineWidth: chrome.hairlineWidth)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard revision")

            Button {
                onApplyPending?()
            } label: {
                Image(systemName: pendingRevision?.isSelectionRevision == true ? "arrow.down.doc" : "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.surfacePrimary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(chrome.accent)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pendingRevision?.isSelectionRevision == true ? "Apply selection" : "Replace draft")
        }
        .frame(maxWidth: .infinity)
    }

    private var revisedTextBinding: Binding<String> {
        Binding(
            get: { pendingRevision?.revisedText ?? "" },
            set: { newValue in
                var nextRevision = pendingRevision
                nextRevision?.revisedText = newValue
                pendingRevision = nextRevision
            }
        )
    }

    private var composeCounts: (words: Int, characters: Int) {
        let trimmed = trimmedText
        guard !trimmed.isEmpty else { return (0, 0) }
        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        return (words, trimmed.count)
    }

    private func consoleCountLabel(_ counts: (words: Int, characters: Int)) -> String {
        guard counts.words > 0 else { return "0W" }
        if counts.characters >= 1000 {
            let kilo = Double(counts.characters) / 1000
            return String(format: "%dW · %.1fKC", counts.words, kilo)
        }
        return "\(counts.words)W · \(counts.characters)C"
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Floating Copy affordance pinned to the top-right of the editor surface
    // (inside the text area). Quiet circular chip, slightly elevated. Toggles
    // to a checkmark with success tint on confirm.
    private func editorCopyButton(chrome: ChromeTokens) -> some View {
        Button(action: copyDraft) {
            Image(systemName: showingCopiedFeedback ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(showingCopiedFeedback ? Color.success : theme.colors.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(theme.colors.cardBackground.opacity(0.92))
                )
                .overlay {
                    Circle()
                        .stroke(
                            showingCopiedFeedback ? Color.success.opacity(0.5) : chrome.edgeFaint,
                            lineWidth: chrome.hairlineWidth
                        )
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingCopiedFeedback ? "Draft copied" : "Copy draft to clipboard")
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
            // Eyebrow alone — the headline used to duplicate this label.
            HStack {
                TalkieEyebrow(text: "Revision Preview")
                Spacer()
                TalkieChannelLabel(code: revision.providerName, isActive: true)
            }

            // Instruction is the real signal — make it the primary content.
            Text(revision.instruction)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)

            // Signal indicator: word count transformation reads as input → output.
            HStack(spacing: 6) {
                TalkieStatusDot(diameter: 4)
                Text(summaryLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)
            }

            if let fallbackReason = revision.fallbackReason {
                Text(fallbackReason)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TalkieEyebrow(
                        text: revision.isSelectionRevision ? "Suggested Selection" : "Diff",
                        tint: .ink,
                        showLeader: false
                    )
                    Spacer(minLength: 4)
                    diffLegend
                }

                ComposeRevisionDiffView(
                    originalText: revision.originalText,
                    revisedText: revision.revisedText
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.surfacePrimary)
                .clipShape(.rect(cornerRadius: CornerRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(ThemeManager.shared.chrome.edgeFaint, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: Spacing.sm) {
                Button("Discard", systemImage: "xmark") {
                    discardRevision()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(revision.isSelectionRevision ? "Apply Selection" : "Replace Draft", systemImage: "arrow.down.doc") {
                    applyRevision()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.active)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(ThemeManager.shared.chrome.edge, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var summaryLabel: String {
        let originalCount = revision.originalText.split(whereSeparator: \.isWhitespace).count
        let revisedCount = revision.revisedText.split(whereSeparator: \.isWhitespace).count
        return "\(originalCount) → \(revisedCount) words"
    }

    @ViewBuilder
    private var diffLegend: some View {
        let chrome = ThemeManager.shared.chrome
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Rectangle()
                    .fill(chrome.accent)
                    .frame(width: 6, height: 1.5)
                Text("ADDED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(chrome.accent)
            }
            HStack(spacing: 3) {
                Rectangle()
                    .fill(Color.textTertiary)
                    .frame(width: 6, height: 1.5)
                Text("REMOVED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

private struct ComposeHistoryCard: View {
    let revisions: [ComposeAppliedRevision]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Applied Revisions")

            Text("Applied Revisions")
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)

            TalkieDivider()
                .padding(.vertical, 2)

            ForEach(Array(revisions.prefix(5).enumerated()), id: \.element.id) { index, revision in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    TalkieChannelLabel(code: String(format: "R%02d", index + 1))
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(revision.instruction)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Text("\(revision.scope) • \(revision.providerName) • \(revision.modelId)")
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
                .stroke(ThemeManager.shared.chrome.edge, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct ComposeSegmentsBar: View {
    let segments: [ComposeSegment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(segments.prefix(12).enumerated()), id: \.element.id) { index, segment in
                    ComposeSegmentChip(segment: segment, index: index)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Compose segments")
    }
}

private struct ComposeSegmentChip: View {
    let segment: ComposeSegment
    let index: Int

    @ObservedObject private var theme = ThemeManager.shared

    private var channelCode: String { String(format: "S%02d", index + 1) }

    var body: some View {
        let chrome = theme.chrome
        HStack(spacing: 7) {
            // Channel pill — situates each segment as a numbered signal
            TalkieChannelLabel(code: channelCode, isActive: false)

            Image(systemName: segment.kind.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(segment.kind.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(segment.title.isEmpty ? segment.kind.title : segment.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(segment.detail ?? segmentPreview)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.colors.cardBackground)
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(chrome.edgeFaint, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var segmentPreview: String {
        let words = segment.text.split(whereSeparator: \.isWhitespace).prefix(6)
        return words.joined(separator: " ")
    }
}

private struct ComposeVoiceCommandPreviewBubble: View {
    let text: String

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        HStack(spacing: 8) {
            // Signal indicator — pulsing phosphor dot + chrome trace = "AI inbound"
            HStack(spacing: 4) {
                TalkieStatusDot(diameter: 5, pulses: true)
                Rectangle()
                    .fill(chrome.accent.opacity(0.45))
                    .frame(width: 12, height: 1)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(chrome.accent)
                    .talkieAccentGlow()
            }

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.cardBackground.opacity(0.96))
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(chrome.accent.opacity(0.35), lineWidth: 0.5)
        }
        .shadow(color: chrome.accentGlow, radius: chrome.glowRadius * 2)
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}

private struct ComposeNotesEmptyStateRow: View {
    let createNote: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: 6) {
                TalkieStatusDot(diameter: 5, pulses: true)
                TalkieEyebrow(text: "Awaiting Input", showLeader: false)
            }

            Image(systemName: "square.and.pencil")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.textTertiary)

            TalkieEyebrow(text: "No Notes", tint: .ink, showLeader: false)

            Text("Create a note to start revising text here.")
                .font(.bodySmall)
                .foregroundStyle(Color.textTertiary)

            Button("New Note", systemImage: "plus") {
                createNote()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.active)
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

// MARK: - Word-level Diff
//
// LCS-based word diff used to render an inline preview of an AI revision —
// common words appear plain, additions are accent-tinted with an underline,
// deletions get a strikethrough. Good enough for short paragraphs; for very
// long bodies we still fall back to the full revised text.

private enum ComposeDiffToken: Hashable {
    case unchanged(String)
    case added(String)
    case removed(String)
}

private enum ComposeWordDiff {
    static func tokens(from original: String, to revised: String) -> [ComposeDiffToken] {
        let originalWords = tokenize(original)
        let revisedWords = tokenize(revised)
        let n = originalWords.count
        let m = revisedWords.count

        guard n > 0 || m > 0 else { return [] }

        // LCS dynamic-programming table.
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if originalWords[i] == revisedWords[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        // Backtrack to produce tokens in document order.
        var tokens: [ComposeDiffToken] = []
        var i = n
        var j = m
        while i > 0 && j > 0 {
            if originalWords[i - 1] == revisedWords[j - 1] {
                tokens.append(.unchanged(originalWords[i - 1]))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                tokens.append(.removed(originalWords[i - 1]))
                i -= 1
            } else {
                tokens.append(.added(revisedWords[j - 1]))
                j -= 1
            }
        }
        while i > 0 {
            tokens.append(.removed(originalWords[i - 1]))
            i -= 1
        }
        while j > 0 {
            tokens.append(.added(revisedWords[j - 1]))
            j -= 1
        }
        return tokens.reversed()
    }

    private static func tokenize(_ string: String) -> [String] {
        string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
}

private struct ComposeRevisionDiffView: View {
    let originalText: String
    let revisedText: String

    @ObservedObject private var theme = ThemeManager.shared

    private static let maxDiffCharacters = 4000

    var body: some View {
        if shouldFallbackToFullText {
            Text(revisedText)
                .font(.body)
                .foregroundStyle(theme.colors.textPrimary)
                .textSelection(.enabled)
        } else {
            Text(attributedDiff)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private var shouldFallbackToFullText: Bool {
        originalText.count + revisedText.count > Self.maxDiffCharacters
    }

    private var attributedDiff: AttributedString {
        let tokens = ComposeWordDiff.tokens(from: originalText, to: revisedText)
        var result = AttributedString()
        for (index, token) in tokens.enumerated() {
            var fragment: AttributedString
            switch token {
            case .unchanged(let word):
                fragment = AttributedString(word)
                fragment.foregroundColor = theme.colors.textPrimary
            case .added(let word):
                fragment = AttributedString(word)
                fragment.foregroundColor = theme.chrome.accent
                fragment.underlineStyle = .single
            case .removed(let word):
                fragment = AttributedString(word)
                fragment.foregroundColor = theme.colors.textTertiary
                fragment.strikethroughStyle = .single
            }
            result.append(fragment)
            if index < tokens.count - 1 {
                result.append(AttributedString(" "))
            }
        }
        return result
    }
}

// MARK: - Versions Cell Strip
//
// Horizontal R-cell strip mounted above the editor when applied revisions
// exist. Each cell shows R-code · short instruction · time. Tap to swap that
// revision into the draft (replaces the draft text).

private struct ComposeVersionsCellStrip: View {
    let revisions: [ComposeAppliedRevision]
    let onSelect: (ComposeAppliedRevision) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    var body: some View {
        let chrome = theme.chrome
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TalkieEyebrow(text: "Versions", tint: .accent, showLeader: true)
                Spacer(minLength: 4)
                Text("\(revisions.count) SAVED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 2)

            HStack(spacing: 0) {
                ForEach(Array(revisions.prefix(4).enumerated()), id: \.element.id) { index, revision in
                    Button {
                        onSelect(revision)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "R%02d", index + 1))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(chrome.accent)
                            Text(revision.instruction)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.colors.textPrimary)
                                .lineLimit(1)
                            Text(Self.timeFormatter.string(from: revision.createdAt))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(index == 0 ? theme.colors.tableCellBackground : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .trailing) {
                        if index < min(revisions.count, 4) - 1 {
                            Rectangle()
                                .fill(chrome.edgeFaint)
                                .frame(width: chrome.hairlineWidth)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.colors.background)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Versions, \(revisions.count) saved")
    }
}

// MARK: - Revision Overlay
//
// Full-screen sheet presented when an AI revision is ready to review. The
// diff fills the screen so the user can really read it; scroll if long.

private struct ComposeRevisionOverlay: View {
    let revision: ComposePendingRevision
    let apply: () -> Void
    let discard: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    headerStrip(chrome: chrome)

                    Text(revision.instruction)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let fallbackReason = revision.fallbackReason {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.warning)
                            Text(fallbackReason)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }

                    diffLegend(chrome: chrome)

                    ComposeRevisionDiffView(
                        originalText: revision.originalText,
                        revisedText: revision.revisedText
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(theme.colors.background)
                    .clipShape(.rect(cornerRadius: CornerRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                            .allowsHitTesting(false)
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(theme.colors.cardBackground)
            .navigationTitle(revision.isSelectionRevision ? "Selection Revision" : "Draft Revision")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar(chrome: chrome)
            }
        }
    }

    private func headerStrip(chrome: ChromeTokens) -> some View {
        HStack(spacing: 6) {
            TalkieEyebrow(text: "Diff", tint: .accent, showLeader: true)
            Spacer(minLength: 4)
            TalkieChannelLabel(code: revision.providerName, isActive: true)
            TalkieChannelLabel(code: revision.modelId)
        }
    }

    private func diffLegend(chrome: ChromeTokens) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(chrome.accent)
                    .frame(width: 10, height: 2)
                Text("ADDED")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(chrome.accent)
            }
            HStack(spacing: 4) {
                Rectangle()
                    .fill(theme.colors.textTertiary)
                    .frame(width: 10, height: 2)
                Text("REMOVED")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            Spacer(minLength: 0)
            Text(wordDeltaLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var wordDeltaLabel: String {
        let originalCount = revision.originalText.split(whereSeparator: \.isWhitespace).count
        let revisedCount = revision.revisedText.split(whereSeparator: \.isWhitespace).count
        let delta = revisedCount - originalCount
        let sign = delta > 0 ? "+" : ""
        return "\(originalCount) → \(revisedCount)W (\(sign)\(delta))"
    }

    private func actionBar(chrome: ChromeTokens) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(chrome.edgeFaint)
                .frame(height: chrome.hairlineWidth)

            HStack(spacing: Spacing.sm) {
                Button(role: .destructive) { discard() } label: {
                    Label("Discard", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { apply() } label: {
                    Label(revision.isSelectionRevision ? "Apply Selection" : "Replace Draft", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(chrome.accent)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(theme.colors.cardBackground)
        }
    }
}

// MARK: - History Sheet
//
// Sheet-presented table of applied revisions. Tap rows to inspect a row's
// metadata; this replaces the inline ComposeHistoryCard / top-of-bay strip.

private struct ComposeHistorySheet: View {
    let revisions: [ComposeAppliedRevision]
    let onDismiss: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if revisions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(revisions.enumerated()), id: \.element.id) { index, revision in
                            HistoryRow(index: index, revision: revision)
                                .listRowBackground(theme.colors.tableCellBackground)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(theme.colors.background)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.medium)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No revisions yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.textSecondary)
            Text("Applied AI revisions will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }
}

private struct HistoryRow: View {
    let index: Int
    let revision: ComposeAppliedRevision

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TalkieChannelLabel(code: String(format: "R%02d", index + 1))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(revision.instruction)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(revision.scope)
                    Text(theme.chrome.eyebrowLeader)
                    Text(revision.providerName)
                    Text(theme.chrome.eyebrowLeader)
                    Text(revision.modelId)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(revision.createdAt, style: .time)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textSecondary)

                Text("\(wordCount(revision.text))W")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func wordCount(_ string: String) -> Int {
        string.split(whereSeparator: \.isWhitespace).count
    }
}

// MARK: - Compose Bay Action Row
//
// The thin bottom action row inside the bay. Mirrors the macOS layout: a
// filled COMMAND voice pill on the left, then a scrollable strip of quick
// action chips. The home tab bar's mic stays separate (memos, different path).

private struct ComposeBayActionRow: View {
    let voiceCommandState: InlineDictationController.State
    let isVoiceCommandEnabled: Bool
    let quickActions: [ComposeWorkflowAction]
    let quickActionsEnabled: Bool
    let toggleVoiceCommand: () -> Void
    let applyAction: (ComposeWorkflowAction) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Lane 1 — the voice command pill on its own line.
            HStack {
                ComposeBayCommandPill(
                    state: voiceCommandState,
                    isEnabled: isVoiceCommandEnabled,
                    action: toggleVoiceCommand
                )
                Spacer(minLength: 0)
            }

            // Lane 2 — quick action chips, only shown when something can act
            // on the draft. No empty/disabled row hanging out.
            if quickActionsEnabled && !quickActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickActions) { action in
                            ComposeBayQuickChip(
                                title: action.title,
                                systemImage: action.systemImage,
                                isEnabled: true
                            ) {
                                applyAction(action)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct ComposeBayCommandPill: View {
    let state: InlineDictationController.State
    let isEnabled: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let corner = max(chrome.chromeCorner, 8)
        Button(action: action) {
            HStack(spacing: 8) {
                iconView
                Text("Command")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(strokeColor, lineWidth: state == .idle ? chrome.hairlineWidth : 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .frame(minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
    }

    // Idle: mic + small sparkles glyph in the top-trailing corner — composes
    // "AI-powered voice command" without inventing a new symbol. Recording:
    // single stop glyph (no AI flourish — the action is just "stop"). Tran-
    // scribing: waveform.
    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .idle:
            ZStack(alignment: .topTrailing) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))

                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.chrome.accent)
                    .offset(x: 4, y: -3)
                    .scopePhosphorGlow(radius: 2)
            }
            .frame(width: 18, height: 18)
        case .recording:
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .semibold))
        case .transcribing:
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private var foreground: Color {
        switch state {
        case .recording:    return .white
        case .transcribing: return theme.chrome.accent
        case .idle:         return theme.colors.textPrimary
        }
    }

    private var fill: Color {
        switch state {
        case .recording:    return Color.recording
        case .transcribing: return theme.chrome.accentTint
        case .idle:         return theme.colors.tableCellBackground
        }
    }

    private var strokeColor: Color {
        switch state {
        case .recording:    return Color.recording.opacity(0.6)
        case .transcribing: return theme.chrome.accent.opacity(0.4)
        case .idle:         return theme.chrome.edge.opacity(0.85)
        }
    }

    private var shadowColor: Color {
        switch state {
        case .recording:    return Color.recording.opacity(0.30)
        case .transcribing: return theme.chrome.accent.opacity(0.18)
        case .idle:         return Color.black.opacity(0.08)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:         return "Start voice command"
        case .recording:    return "Stop voice command"
        case .transcribing: return "Transcribing voice command"
        }
    }
}

// Joystick complication — sits in the middle of the compose tray as a visual
// fifth wheel and a cursor-nav affordance. Rendered as a stylized 4-arrow dpad
// inside a 44pt square. Toggles `isActive` on tap (lit state); the actual
// cursor-pad expansion is future work — the seat is here in the meantime.
private struct ComposeJoystickButton: View {
    let isActive: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let corner = max(chrome.chromeCorner, 8)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(isActive ? chrome.accentTint : theme.colors.tableCellBackground)

                VStack(spacing: 3) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .bold))

                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 7, weight: .bold))

                        Circle()
                            .fill(isActive ? chrome.accent : theme.colors.textTertiary.opacity(0.55))
                            .frame(width: 4, height: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(isActive ? chrome.accent : theme.colors.textSecondary)
            }
            .frame(width: 44, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        isActive ? chrome.accent.opacity(0.45) : chrome.edge.opacity(0.7),
                        lineWidth: chrome.hairlineWidth
                    )
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cursor joystick")
        .accessibilityHint("Toggles the cursor navigator. Coming soon: drag to move the caret.")
    }
}

// Keyboard pill in the right cluster of the bottom tray. Pill shape with icon
// + uppercase label so it visually balances the Command pill on the left. Lit
// when the editor is focused (so the user knows tapping again will dismiss).
private struct ComposeBayKeyboardButton: View {
    let isFocused: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let corner = max(chrome.chromeCorner, 8)
        Button(action: action) {
            HStack(spacing: 7) {
                Text("Keyboard")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .textCase(.uppercase)
                Image(systemName: isFocused ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isFocused ? chrome.accent : theme.colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(isFocused ? chrome.accentTint : theme.colors.tableCellBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        isFocused ? chrome.accent.opacity(0.45) : chrome.edge.opacity(0.85),
                        lineWidth: chrome.hairlineWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(isFocused ? "Dismiss keyboard" : "Show keyboard")
    }
}

private struct ComposeBayQuickChip: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let corner = max(chrome.chromeCorner, 6)
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(theme.colors.cardBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct ComposeBayMenuChip: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let actions: [ComposeWorkflowAction]
    let onPerformAction: (ComposeWorkflowAction) -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        let corner = max(chrome.chromeCorner, 6)
        Menu {
            ForEach(actions) { action in
                Button {
                    onPerformAction(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(theme.colors.cardBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || actions.isEmpty)
        .opacity(isEnabled && !actions.isEmpty ? 1 : 0.5)
    }
}

// MARK: - Compose Tray
//
// Flat strip pinned to the bottom of the compose surface. Visual continuity
// with ActionDock — canvas background, top hairline, dock-style padding. Slot
// layout: prominent Command pill on the left, a joystick complication centered
// as the visual fifth wheel, then Copy + Keyboard complications on the right.

private struct ComposeTray: View {
    let voiceCommandState: InlineDictationController.State
    let isVoiceCommandEnabled: Bool
    let onToggleVoiceCommand: () -> Void
    let isDraftFocused: Bool
    let onToggleKeyboard: () -> Void

    @State private var isJoystickActive = false
    @ObservedObject private var theme = ThemeManager.shared

    init(
        voiceCommandState: InlineDictationController.State,
        isVoiceCommandEnabled: Bool,
        onToggleVoiceCommand: @escaping () -> Void,
        isDraftFocused: Bool,
        onToggleKeyboard: @escaping () -> Void
    ) {
        self.voiceCommandState = voiceCommandState
        self.isVoiceCommandEnabled = isVoiceCommandEnabled
        self.onToggleVoiceCommand = onToggleVoiceCommand
        self.isDraftFocused = isDraftFocused
        self.onToggleKeyboard = onToggleKeyboard
    }

    var body: some View {
        let chrome = theme.chrome
        VStack(spacing: 0) {
            Rectangle()
                .fill(chrome.edgeFaint)
                .frame(height: chrome.hairlineWidth)

            ZStack {
                // Center: joystick — absolutely centered so it sits directly
                // below the editor's dictation mic.
                ComposeJoystickButton(
                    isActive: isJoystickActive,
                    action: { isJoystickActive.toggle() }
                )

                // Edges: Command pill anchors leading, Keyboard pill anchors
                // trailing. The two pills balance across the joystick.
                HStack(spacing: 0) {
                    ComposeBayCommandPill(
                        state: voiceCommandState,
                        isEnabled: isVoiceCommandEnabled,
                        action: onToggleVoiceCommand
                    )

                    Spacer(minLength: 0)

                    ComposeBayKeyboardButton(
                        isFocused: isDraftFocused,
                        action: onToggleKeyboard
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background {
            if theme.currentTheme.isScope {
                ScopeMobile.canvas.opacity(0.96)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                theme.colors.cardBackground.opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

}

// Compact horizontal strip of applied revisions — a "scroll back through
// versions" affordance at the top of the bay. The full ComposeHistoryCard is
// kept available for places that want the vertical layout.
private struct ComposeRevisionsStrip: View {
    let revisions: [ComposeAppliedRevision]

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let chrome = theme.chrome
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TalkieEyebrow(text: "Versions", tint: .accent, showLeader: true)
                Spacer(minLength: 4)
                Text("\(revisions.count) APPLIED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(revisions.prefix(8).enumerated()), id: \.element.id) { index, revision in
                        ComposeRevisionPill(
                            index: index,
                            revision: revision,
                            chrome: chrome,
                            theme: theme
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}

private struct ComposeRevisionPill: View {
    let index: Int
    let revision: ComposeAppliedRevision
    let chrome: ChromeTokens
    let theme: ThemeManager

    var body: some View {
        let code = String(format: "R%02d", index + 1)
        HStack(spacing: 6) {
            TalkieChannelLabel(code: code, isActive: index == 0)
            Text(revision.instruction)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: max(chrome.chromeCorner, 4), style: .continuous)
                .fill(theme.colors.tableCellBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: max(chrome.chromeCorner, 4), style: .continuous)
                .stroke(index == 0 ? chrome.edge : chrome.edgeFaint, lineWidth: chrome.hairlineWidth)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Revision \(index + 1). \(revision.instruction).")
    }
}
