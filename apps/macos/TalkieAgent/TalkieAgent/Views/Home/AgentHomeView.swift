//
//  AgentHomeView.swift
//  TalkieAgent
//
//  Conversation surface. Mirrors the studio canon at
//  design/studio/components/studies/MacAgentHome.tsx — sidebar of
//  auto-named conversations on the left, a linear You ↔ Talkie
//  transcript on the right, every Talkie reply tucks extra context
//  (summary, action log, timing) behind a quiet "Details" link.
//
//  Palette: Talkie's cool-gray Scope substrate and ink hierarchy, with
//  Agent's steel chrome and signal-blue active state. Amber is reserved for
//  the shared Talkie brand mark and semantic warnings. One display-serif
//  moment for the conversation title; everything else is the system sans on
//  the 4 / 8 / 12 / 16 / 24 / 32 spacing scale.
//

import SwiftUI
import HudsonUI
import TalkieKit
import UniformTypeIdentifiers

private let agentHomeViewLog = Log(.ui)

struct AgentHomeView: View {
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var store = AgentHomeActivityStore()
    @StateObject private var voiceCapture = AgentHomeVoiceCapture()
    @State private var selectedTopicId: String?
    @State private var agentPrompt = ""
    @State private var pendingAttachments: [AgentInvocationAttachment] = []
    @State private var continuation: AgentHomeContinuationContext?
    @State private var voicePromptTarget: AgentHomePromptTarget?
    @State private var voicePromptAttachments: [AgentInvocationAttachment] = []
    @State private var openWorkTurnIds: Set<String> = []
    @State private var isAttachmentImporterPresented = false
    @State private var agentHomeReplySpeech = HudAgentReplySpeechController()
    @State private var agentHomeSpeechTask: Task<Void, Never>?
    /// The agent the composer chip points at. nil → the runtime's preferred
    /// default. (Routing the invocation to a chosen agent is a follow-up;
    /// today the runtime selects the agent.)
    @State private var selectedAgentId: String?
    /// Agent voice (TTS) — read replies aloud. Toggled by the reader-header
    /// speaker. Persisted per app, and speaks only newly-arriving replies.
    @AppStorage("talkie.agentHome.speakReplies") private var speakReplies = false
    @FocusState private var agentPromptFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)

            Rectangle()
                .fill(ScopeEdge.subtle)
                .frame(width: 1)

            reader
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AgentHomeChatPalette.pearl)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AgentHomeChatPalette.edge, lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.11), radius: 16, y: 8)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .background(AgentTheme.background)
        .onAppear {
            configureAgentHomeReplySpeech()
            store.startRefreshing()
            agentHomeReplySpeech.prime(with: latestSpeakableReply)
        }
        .onDisappear {
            store.stopRefreshing()
            voiceCapture.cancel()
            agentHomeSpeechTask?.cancel()
            agentHomeSpeechTask = nil
            SelectionSpeechPlaybackController.shared.stop()
        }
        .onChange(of: selectedTopic.id) { _, _ in
            agentHomeSpeechTask?.cancel()
            agentHomeSpeechTask = nil
            SelectionSpeechPlaybackController.shared.stop()
            agentHomeReplySpeech.prime(with: latestSpeakableReply)
        }
        .onChange(of: speakReplies) { _, enabled in
            if enabled {
                agentHomeReplySpeech.prime(with: latestSpeakableReply)
            } else {
                agentHomeSpeechTask?.cancel()
                agentHomeSpeechTask = nil
                SelectionSpeechPlaybackController.shared.stop()
            }
        }
        .onChange(of: latestSpeakableReply) { _, reply in
            speakAgentHomeReplyIfNeeded(reply)
        }
        .fileImporter(
            isPresented: $isAttachmentImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleAttachmentImport
        )
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: "CONVERSATIONS" + a quiet "+" (no big button, no
            // runtime badge, no adapter roster). Starting a conversation drops
            // you into the main area; the agent is picked there, in the input.
            HStack(spacing: 8) {
                Text("· CONVERSATIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(ScopeInk.subtle)

                Spacer(minLength: 0)

                Button(action: startNewTopic) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ScopeInk.faint)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(ScopeEdge.subtle, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("New conversation (⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let topics = store.conversationTopics
                    ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                        let prevGroup = index == 0
                            ? nil
                            : AgentHomeActivityStore.groupLabel(for: topics[index - 1].lastActivityAt)
                        let group = AgentHomeActivityStore.groupLabel(for: topic.lastActivityAt)
                        if prevGroup != group {
                            AgentHomeGroupLabel(label: group, isFirst: index == 0)
                        }
                        AgentHomeConversationRow(
                            topic: topic,
                            selected: topic.id == selectedTopic.id
                        ) {
                            selectTopic(topic.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            sidebarFooter
        }
        .background(AgentHomeChatPalette.chrome)
    }

    /// Two distinct, deliberately-separated footer entries: the relocated
    /// adapter roster as a subtle "N agents configured" settings entry, and
    /// global Settings below it — a rule between so they don't read as one.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(ScopeEdge.subtle)

            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.faint)
                    Text("\(store.agents.count) agents configured")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.muted)
                    Spacer(minLength: 0)
                    Text("Manage ›")
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeInk.subtle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Manage agents & adapters")

            Divider().overlay(ScopeEdge.subtle)

            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ScopeInk.faint)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Reader

    private var reader: some View {
        VStack(spacing: 0) {
            readerHeader

            Rectangle()
                .fill(ScopeEdge.subtle)
                .frame(height: 1)

            if isIdle {
                // Idle mode: replace the transcript + pinned-composer with a
                // centered IdleHero that integrates the composer right under
                // the headline. One focal point, no chrome handoff.
                ScrollView(.vertical, showsIndicators: false) {
                    AgentHomeIdleHero(
                        text: $agentPrompt,
                        isSending: store.isInvokingAgent,
                        hasActiveTurn: selectedTopic.activeCount > 0,
                        placeholder: composerPlaceholder,
                        continuation: promptContinuation,
                        continuationMode: promptContinuationMode,
                        voiceCapture: voiceCapture,
                        attachments: pendingAttachments,
                        error: store.invokeError,
                        isFocused: $agentPromptFocused,
                        agents: store.agents,
                        selectedAgentId: $selectedAgentId,
                        onClearContinuation: clearPromptContinuation,
                        onAddAttachment: pickAttachments,
                        onRemoveAttachment: removeAttachment,
                        onSend: sendAgentPrompt,
                        onStop: stopActiveTurn,
                        onCancelTalkBack: cancelTalkBack,
                        onTalkBack: talkBack,
                        onStarter: useStarter
                    )
                    .padding(.leading, AgentHomeMetrics.gutter)
                    .padding(.trailing, AgentHomeMetrics.gutter)
                    .padding(.top, 56)
                    .padding(.bottom, 32)
                    .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
                           alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        AgentHomeTranscriptView(
                            turns: selectedTurns,
                            openTurnIds: openWorkTurnIds,
                            onToggleWork: toggleWork,
                            onCopy: store.copy,
                            onContinue: continueConversation
                        )
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AgentHomeChatPalette.card)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AgentHomeChatPalette.edge.opacity(0.72), lineWidth: 1)
                    }
                    .padding(.leading, AgentHomeMetrics.gutter)
                    .padding(.trailing, AgentHomeMetrics.gutter)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
                           alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                composer
            }
        }
        .background {
            ZStack {
                AgentHomeChatPalette.pearl

                RadialGradient(
                    colors: [
                        AgentHomeChatPalette.brandSignal.opacity(0.055),
                        .clear,
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 540
                )
            }
        }
    }

    private var isIdle: Bool { selectedTurns.isEmpty }

    private var readerHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(AgentHomeChatPalette.brandSignal)
                        .frame(width: 5, height: 5)

                    Text("AGENT CHAT")
                        .font(OpsType.mono(OpsSize.micro, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(AgentHomeChatPalette.brandSignal)

                    Text("· CONVERSATION")
                        .font(OpsType.mono(OpsSize.micro, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(ScopeInk.subtle)
                }

                Text(selectedTopic.title)
                    .font(ScopeType.display(size: 28, weight: .regular))
                    .foregroundStyle(ScopeInk.primary)
                    .tracking(-0.25)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Agent VOICE (TTS) — a speaker, not a mic. Reads replies aloud.
            if !isIdle {
                AgentHomeVoiceReplyToggle(isOn: $speakReplies)
            }

            // This conversation's settings.
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(ScopeInk.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .help("Conversation settings")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(ScopeInk.primary.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.leading, AgentHomeMetrics.gutter)
        .padding(.trailing, AgentHomeMetrics.gutter)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
               alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: AgentTheme.background.opacity(0), location: 0),
                    .init(color: AgentTheme.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 12)

            AgentHomeComposer(
                text: $agentPrompt,
                isSending: store.isInvokingAgent,
                hasActiveTurn: selectedTopic.activeCount > 0,
                placeholder: composerPlaceholder,
                continuation: promptContinuation,
                continuationMode: promptContinuationMode,
                voiceCapture: voiceCapture,
                attachments: pendingAttachments,
                error: store.invokeError,
                isFocused: $agentPromptFocused,
                agents: store.agents,
                selectedAgentId: $selectedAgentId,
                onClearContinuation: clearPromptContinuation,
                onAddAttachment: pickAttachments,
                onRemoveAttachment: removeAttachment,
                onSend: sendAgentPrompt,
                onStop: stopActiveTurn,
                onCancelTalkBack: cancelTalkBack,
                onTalkBack: talkBack
            )
            .padding(.leading, AgentHomeMetrics.gutter)
            .padding(.trailing, AgentHomeMetrics.gutter)
            .padding(.bottom, 18)
            .frame(maxWidth: AgentHomeMetrics.readerColumn + AgentHomeMetrics.gutter * 2,
                   alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(AgentHomeChatPalette.pearl)
    }

    // MARK: Derived

    private var selectedTopic: AgentHomeConversationTopic {
        if let selectedTopicId,
           let topic = store.conversationTopics.first(where: { $0.id == selectedTopicId }) {
            return topic
        }
        if let selectedTopicId {
            return AgentHomeConversationTopic(
                id: selectedTopicId,
                title: "New conversation",
                subtitle: "Draft",
                wireLabel: nil,
                icon: "plus.bubble",
                activeCount: 0,
                turnCount: 0,
                lastActivityAt: nil
            )
        }
        return store.conversationTopics.first ?? .general
    }

    private var selectedTurns: [AgentHomeExecutorTurn] {
        store.executorTurns(in: selectedTopic.id)
    }

    private var latestContinuableTurn: AgentHomeExecutorTurn? {
        selectedTurns.last { $0.status.isTerminal }
    }

    private var latestSpeakableReply: HudAgentReplySpeechReply? {
        guard let turn = selectedTurns.last(where: { $0.status == .done }),
              let text = turn.spokenBody?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        else {
            return nil
        }
        return HudAgentReplySpeechReply(
            id: turn.id,
            conversationID: selectedTopic.id,
            revision: "\(turn.updatedAt.timeIntervalSinceReferenceDate)",
            text: text,
            metadata: [
                "agent": turn.agentDisplayName,
                "source": turn.source ?? "agent-home",
            ]
        )
    }

    private var promptContinuation: AgentHomeContinuationContext? {
        continuation ?? latestContinuableTurn.map(AgentHomeContinuationContext.init)
    }

    private var promptContinuationMode: AgentHomeContinuationMode? {
        guard promptContinuation != nil else { return nil }
        return continuation == nil ? .automatic : .pinned
    }

    private var headerSubtitle: String {
        let count = selectedTopic.turnCount
        let turnLabel = count == 1 ? "1 message" : "\(count) messages"
        var parts: [String] = []
        if let last = selectedTopic.lastActivityAt {
            parts.append(AgentHomeActivityStore.groupLabel(for: last) + " " +
                         AgentHomeActivityStore.sidebarStamp(for: last))
        }
        if count > 0 { parts.append(turnLabel) }
        if selectedTopic.activeCount > 0 { parts.append("working now") }
        return parts.isEmpty ? "Say or type something — Talkie's listening" : parts.joined(separator: " · ")
    }

    private var composerPlaceholder: String {
        if selectedTopic.turnCount == 0 {
            return "Say something, or type here"
        }
        if selectedTopic.activeCount > 0 {
            return "Add another note to this chat"
        }
        return "Reply to \(selectedTopic.title) by voice or text"
    }

    // MARK: Actions

    private func startNewTopic() {
        selectedTopicId = "agent-home-\(UUID().uuidString.lowercased())"
        continuation = nil
        agentPromptFocused = true
    }

    private func selectTopic(_ topicId: String) {
        selectedTopicId = topicId
        continuation = nil
        if voiceCapture.phase == .idle {
            agentPromptFocused = true
        }
    }

    private func configureAgentHomeReplySpeech() {
        agentHomeReplySpeech.register(
            HudAgentReplySpeechSynthesizer { request in
                let audio = try await SelectionSpeechPlaybackController.shared.synthesizeSelectionAudio(request.text)
                return HudAgentReplySpeechAudio(
                    data: audio.data,
                    format: HudAgentReplySpeechAudioFormat(talkieFormat: audio.format),
                    mimeType: audio.mimeType,
                    provider: audio.provider,
                    voice: audio.voiceId,
                    model: audio.model
                )
            }
        )
    }

    private func speakAgentHomeReplyIfNeeded(_ reply: HudAgentReplySpeechReply?) {
        guard speakReplies, reply != nil else { return }

        agentHomeSpeechTask?.cancel()
        agentHomeSpeechTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            do {
                guard let output = try await agentHomeReplySpeech.audioIfNeeded(for: reply, enabled: speakReplies) else {
                    return
                }
                guard !Task.isCancelled else { return }
                try SelectionSpeechPlaybackController.shared.playSynthesizedAudio(
                    SelectionSpeechAudio(
                        data: output.audio.data,
                        format: output.audio.format.rawValue,
                        mimeType: output.audio.mimeType ?? "application/octet-stream",
                        voiceId: output.audio.voice ?? "unknown",
                        provider: output.audio.provider ?? "unknown",
                        model: output.audio.model
                    )
                )
            } catch {
                guard !Task.isCancelled else { return }
                agentHomeViewLog.error("Agent Home reply TTS failed", detail: error.localizedDescription)
            }
        }
    }

    private func clearPromptContinuation() {
        if continuation != nil {
            continuation = nil
        } else if selectedTopic.turnCount > 0 {
            startNewTopic()
        }
    }

    private func toggleWork(_ turnId: String) {
        if openWorkTurnIds.contains(turnId) {
            openWorkTurnIds.remove(turnId)
        } else {
            openWorkTurnIds.insert(turnId)
        }
    }

    /// Starter chip handler — drops the starter text into the composer
    /// and focuses it. Users can edit before sending; we don't auto-fire
    /// because starters are seeds, not commands.
    private func useStarter(_ text: String) {
        agentPrompt = text
        agentPromptFocused = true
    }

    private func sendAgentPrompt() {
        let prompt = agentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !store.isInvokingAgent else { return }

        let attachments = pendingAttachments
        agentPrompt = ""
        pendingAttachments = []
        let target = currentPromptTarget()
        continuation = nil
        submitAgentPrompt(prompt, target: target, attachments: attachments)
    }

    private func continueConversation(from turn: AgentHomeExecutorTurn) {
        guard turn.status.isTerminal else { return }
        continuation = AgentHomeContinuationContext(turn: turn)
        selectedTopicId = continuation?.conversationId
        agentPromptFocused = true
    }

    private func talkBack() {
        switch voiceCapture.phase {
        case .idle:
            voicePromptTarget = currentPromptTarget()
            voicePromptAttachments = pendingAttachments
            agentPromptFocused = false
            voiceCapture.start()
        case .recording:
            let target = voicePromptTarget ?? currentPromptTarget()
            let attachments = voicePromptAttachments
            voiceCapture.stopAndTranscribe(
                onTranscript: { transcript in
                    continuation = nil
                    pendingAttachments.removeAll()
                    submitAgentPrompt(transcript, target: target, attachments: attachments)
                },
                onFinish: {
                    voicePromptTarget = nil
                    voicePromptAttachments = []
                }
            )
        case .processing:
            break
        }
    }

    private func cancelTalkBack() {
        voicePromptTarget = nil
        voicePromptAttachments = []
        voiceCapture.cancel()
    }

    private func currentPromptTarget() -> AgentHomePromptTarget {
        let resolvedContinuation = promptContinuation
        return AgentHomePromptTarget(
            conversationId: resolvedContinuation?.conversationId ?? selectedTopic.id,
            parentSessionId: resolvedContinuation?.parentSessionId,
            continueLatestTurn: false
        )
    }

    private func submitAgentPrompt(
        _ prompt: String,
        target: AgentHomePromptTarget,
        attachments: [AgentInvocationAttachment] = []
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !store.isInvokingAgent else { return }

        Task {
            await store.invokeAgent(
                text: trimmed,
                attachments: attachments,
                conversationId: target.conversationId,
                parentSessionId: target.parentSessionId,
                continueLatestTurn: target.continueLatestTurn
            )
        }
    }

    private func stopActiveTurn() {
        Task {
            await store.cancelLatestActiveTurn(in: selectedTopic.id)
        }
    }

    private func pickAttachments() {
        isAttachmentImporterPresented = true
    }

    private func removeAttachment(_ attachmentId: UUID) {
        pendingAttachments.removeAll { $0.id == attachmentId }
    }

    private func handleAttachmentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let newAttachments = urls.map(makeAttachment)
            pendingAttachments.append(contentsOf: newAttachments)
        case .failure(let error):
            agentHomeViewLog.warning("Agent Home attachment import failed", detail: error.localizedDescription)
        }
    }

    private func makeAttachment(from url: URL) -> AgentInvocationAttachment {
        let type = UTType(filenameExtension: url.pathExtension)
        let mediaType = type?.preferredMIMEType ?? "application/octet-stream"
        return AgentInvocationAttachment(
            name: url.lastPathComponent.nonEmpty ?? "Attachment",
            mediaType: mediaType,
            path: url.path,
            url: url.isFileURL ? nil : url.absoluteString,
            systemImage: systemImage(for: type, mediaType: mediaType, filename: url.lastPathComponent)
        )
    }

    private func systemImage(for type: UTType?, mediaType: String, filename: String) -> String {
        if type?.conforms(to: .image) == true || mediaType.hasPrefix("image/") {
            return "photo"
        }
        if type?.conforms(to: .audio) == true || mediaType.hasPrefix("audio/") {
            return "waveform"
        }
        if type?.conforms(to: .movie) == true || mediaType.hasPrefix("video/") {
            return "film"
        }
        if type?.conforms(to: .pdf) == true || filename.localizedCaseInsensitiveContains(".pdf") {
            return "doc.richtext"
        }
        if type?.conforms(to: .text) == true || mediaType.hasPrefix("text/") {
            return "doc.text"
        }
        return "paperclip"
    }
}

// MARK: - Metrics

private enum AgentHomeMetrics {
    /// Reader column width. Matches the studio's READER_COLUMN.
    static let readerColumn: CGFloat = 860
    /// Left/right gutter inside the reader. Matches studio READER_GUTTER.
    static let gutter: CGFloat = 32
}

private enum AgentHomeChatPalette {
    static let pearl = AgentInstrumentStyle.surface
    static let chrome = AgentInstrumentStyle.conversationChrome
    static let brandSignal = AgentTheme.brandAccent
    static let brandSignalStrong = AgentTheme.brandAccentStrong
    static let brandSignalSoft = brandSignal.opacity(0.10)
    static let brandSignalBorder = brandSignal.opacity(0.28)
    static let brandSignalGlow = brandSignal.opacity(0.22)
    static let edge = AgentInstrumentStyle.brandEdge
    static let card = AgentInstrumentStyle.prominentCard
}

private enum AgentHomeHudTheme {
    static var theme: HudTheme {
        HudTheme(
            palette: HudThemePalette(
                bg: AgentTheme.background,
                surface: AgentTheme.surface,
                chrome: AgentTheme.chrome,
                ink: ScopeInk.primary,
                muted: ScopeInk.muted,
                dim: ScopeInk.subtle,
                border: ScopeEdge.faint,
                accent: AgentHomeChatPalette.brandSignal,
                accentSoft: AgentHomeChatPalette.brandSignalSoft,
                statusOk: SemanticColor.success,
                statusWarn: SemanticColor.warning,
                statusError: SemanticColor.error,
                statusInfo: AgentHomeChatPalette.brandSignal
            ),
            hairline: HudThemeHairline(
                subtle: ScopeEdge.subtle,
                standard: ScopeEdge.faint
            ),
            radius: .default,
            focus: .default
        )
    }
}

private struct AgentHomePromptTarget: Equatable {
    let conversationId: String
    let parentSessionId: String?
    let continueLatestTurn: Bool
}

private extension HudAgentReplySpeechAudioFormat {
    init(talkieFormat: String) {
        switch talkieFormat.lowercased() {
        case "mp3":
            self = .mp3
        case "wav":
            self = .wav
        case "caf":
            self = .caf
        case "m4a":
            self = .m4a
        case "aac":
            self = .aac
        default:
            self = .unknown
        }
    }
}

private enum AgentHomeContinuationMode: Equatable {
    case automatic
    case pinned

    var title: String {
        switch self {
        case .automatic: return "Continuing this chat"
        case .pinned: return "Continuing selected reply"
        }
    }

    var clearHelp: String {
        switch self {
        case .automatic: return "Start a new chat"
        case .pinned: return "Use the latest reply instead"
        }
    }
}

// MARK: - Continuation context

private struct AgentHomeContinuationContext: Equatable {
    let conversationId: String
    let parentSessionId: String
    let label: String

    init(turn: AgentHomeExecutorTurn) {
        conversationId = turn.conversationId ?? "agent-home-main"
        parentSessionId = turn.id

        if let summary = turn.spokenSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            label = summary
        } else if let transcript = turn.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty {
            label = transcript
        } else {
            label = turn.id
        }
    }
}

// MARK: - Sidebar atoms

private struct AgentHomeGroupLabel: View {
    let label: String
    let isFirst: Bool

    var body: some View {
        Text("· \(label.uppercased())")
            .font(ScopeType.chrome)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(ScopeInk.subtle)
            .padding(.horizontal, 12)
            .padding(.top, isFirst ? 8 : 16)
            .padding(.bottom, 6)
    }
}

private struct AgentHomeConversationRow: View {
    let topic: AgentHomeConversationTopic
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(topic.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(ScopeInk.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    trailing
                }

                Text(topic.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(rowFill)
                    .shadow(color: selected ? Color.black.opacity(0.03) : .clear,
                            radius: 0.5, x: 0, y: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(selected ? "Focus the reply field" : "Open this conversation")
        .accessibilityLabel("\(topic.title), \(selected ? "selected" : "conversation")")
    }

    private var rowFill: Color {
        if selected { return AgentTheme.surface }
        if hovered  { return ScopeInk.primary.opacity(0.025) }
        return .clear
    }

    @ViewBuilder
    private var trailing: some View {
        if topic.activeCount > 0 {
            HStack(spacing: 6) {
                Text("working")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AgentHomeChatPalette.brandSignalStrong)
                Circle()
                    .fill(AgentHomeChatPalette.brandSignal)
                    .frame(width: 6, height: 6)
                    .shadow(color: AgentHomeChatPalette.brandSignalGlow, radius: 0, x: 0, y: 0)
                    .overlay(
                        Circle().stroke(AgentHomeChatPalette.brandSignalSoft, lineWidth: 3)
                    )
            }
        } else if hovered || selected {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovered ? AgentHomeChatPalette.brandSignalStrong : ScopeInk.subtle)
                .frame(width: 20, alignment: .trailing)
        } else {
            Text(AgentHomeActivityStore.sidebarStamp(for: topic.lastActivityAt))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ScopeInk.subtle)
        }
    }
}

// MARK: - Talk-back button (header)

/// Active agent selector — lives inside the composer input. Shows the
/// current/preferred agent; the menu switches it. (Routing the invocation
/// to a chosen agent is a follow-up; today the runtime picks the agent.)
private struct AgentHomeAgentChip: View {
    let agents: [AgentRuntimeAgentSnapshot]
    @Binding var selectedAgentId: String?

    private var active: AgentRuntimeAgentSnapshot? {
        if let selectedAgentId, let match = agents.first(where: { $0.id == selectedAgentId }) {
            return match
        }
        return agents.first(where: { $0.isPreferred == true }) ?? agents.first
    }

    var body: some View {
        Menu {
            ForEach(agents) { agent in
                Button {
                    selectedAgentId = agent.id
                } label: {
                    if agent.id == active?.id {
                        Label(agent.name, systemImage: "checkmark")
                    } else {
                        Text(agent.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill((active?.isAvailable ?? false) ? Color.green : ScopeInk.subtle)
                    .frame(width: 6, height: 6)
                Text(active?.name ?? "Agent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AgentHomeChatPalette.brandSignalStrong)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(AgentHomeChatPalette.brandSignalStrong)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(AgentHomeChatPalette.brandSignalSoft))
            .overlay(Capsule().stroke(AgentHomeChatPalette.brandSignalBorder, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch agent")
    }
}

/// Agent voice (TTS) toggle — a speaker, not a mic. Reads replies aloud.
private struct AgentHomeVoiceReplyToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? AgentHomeChatPalette.brandSignalStrong : ScopeInk.faint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? AgentHomeChatPalette.brandSignalSoft : ScopeInk.primary.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Agent voice on — replies are read aloud" : "Agent voice off — tap to read replies aloud")
    }
}

// MARK: - Transcript

struct AgentHomeTranscriptView: View {
    let turns: [AgentHomeExecutorTurn]
    let openTurnIds: Set<String>
    let onToggleWork: (String) -> Void
    let onCopy: (String) -> Void
    let onContinue: (AgentHomeExecutorTurn) -> Void

    var body: some View {
        if turns.isEmpty {
            AgentHomeEmptyRoom()
        } else {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    let prev = index > 0 ? turns[index - 1] : nil
                    if let prev, AgentHomeTranscriptView.hoursBetween(prev.createdAt, turn.createdAt) >= 24 {
                        AgentHomeDateDivider(label: AgentHomeTranscriptView.dayLabel(for: turn.createdAt))
                    }
                    AgentHomeTurnBlock(
                        turn: turn,
                        showWork: openTurnIds.contains(turn.id),
                        onToggleWork: { onToggleWork(turn.id) },
                        onCopy: onCopy,
                        onContinue: { onContinue(turn) }
                    )
                }
            }
        }
    }

    private static func hoursBetween(_ a: Date, _ b: Date) -> Double {
        abs(b.timeIntervalSince(a)) / 3_600
    }

    private static func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

private struct AgentHomeDateDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
            Text(label.uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
            Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

private struct AgentHomeEmptyRoom: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Say something to start.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ScopeInk.muted)
            Text("click the mic or type below")
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 48)
    }
}

// MARK: - Turn block (You + Talkie pair)

private struct AgentHomeTurnBlock: View {
    let turn: AgentHomeExecutorTurn
    let showWork: Bool
    let onToggleWork: () -> Void
    let onCopy: (String) -> Void
    let onContinue: () -> Void

    @State private var hovered = false

    private var isLive: Bool {
        turn.isLive
    }

    private var talkieBody: String {
        if isLive {
            return turn.response?.nonEmpty ?? turn.ack ?? "Working on it…"
        }
        return turn.response?.nonEmpty ?? turn.spokenSummary?.nonEmpty ?? turn.ack ?? "—"
    }

    private var talkieMeta: String? {
        if isLive {
            return turn.status == .waiting ? "starting" : "working"
        }
        if turn.status == .failed {
            return "needs attention"
        }
        return nil
    }

    private var footerVisible: Bool {
        isLive || showWork || hovered
    }

    private var assistantFooter: AnyView {
        guard footerVisible else { return AnyView(EmptyView()) }
        return AnyView(showWorkFooter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AgentHomeSpeech(
                speaker: .you,
                bodyText: turn.askBody ?? "—",
                attachments: turn.attachments,
                time: timeLabel(turn.createdAt),
                onCopy: { onCopy(turn.askBody ?? "") }
            )

            AgentHomeSpeech(
                speaker: .talkie,
                meta: talkieMeta,
                live: isLive,
                bodyText: talkieBody,
                rendersMarkdown: true,
                time: timeLabel(turn.updatedAt),
                onCopy: { onCopy(talkieBody) },
                onContinue: isLive ? nil : onContinue,
                footer: assistantFooter
            )
        }
        .padding(.leading, isLive ? 14 : 16)
        .hudTheme(AgentHomeHudTheme.theme)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isLive ? AgentHomeChatPalette.brandSignal : Color.clear)
                .frame(width: 2)
        }
        .animation(.easeOut(duration: 0.18), value: isLive)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var showWorkFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLive {
                AgentHomeLiveTurnRow(turn: turn)
            }

            Button(action: onToggleWork) {
                Text(showWork ? "Hide details" : "Details")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ScopeInk.subtle)
            }
            .buttonStyle(.plain)
            .help(showWork ? "Hide reply details" : "Show reply details")

            if showWork {
                AgentHomeWorkBlock(turn: turn)
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened).lowercased()
    }
}

private struct AgentHomeLiveTurnRow: View {
    let turn: AgentHomeExecutorTurn

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)

            Text(turn.liveHeadline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AgentTheme.accentStrong)

            if let detail = detailText {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AgentTheme.accentSoft.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AgentTheme.accent.opacity(0.22), lineWidth: 0.5)
        )
    }

    private var detailText: String? {
        guard let detail = turn.liveDetail?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else {
            return nil
        }
        return detail == turn.liveHeadline ? nil : detail
    }
}

// MARK: - Wire trace

private struct AgentHomeWireTrace: View {
    let turn: AgentHomeExecutorTurn

    private var trace: AgentHomeWireTraceText { turn.wireTrace }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(trace.primary)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(primaryColor)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(trace.secondary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ScopeInk.subtle)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 1)
        .help("\(trace.primary)\n\(trace.secondary)")
    }

    private var primaryColor: Color {
        switch turn.status {
        case .waiting, .running:
            return AgentTheme.accentStrong
        case .done:
            return ScopeInk.subtle
        case .failed:
            return .red
        }
    }
}

// MARK: - Speech

private enum AgentHomeSpeaker {
    case you
    case talkie

    var label: String {
        switch self {
        case .you:    return "You"
        case .talkie: return "Talkie"
        }
    }

    var initial: String {
        switch self {
        case .you:    return "Y"
        case .talkie: return "T"
        }
    }
}

private struct AgentHomeSpeech: View {
    let speaker: AgentHomeSpeaker
    var meta: String? = nil
    var live: Bool = false
    let bodyText: String
    var italic: Bool = false
    var rendersMarkdown: Bool = false
    var attachments: [AgentInvocationAttachment] = []
    var time: String? = nil
    var onCopy: () -> Void = {}
    var onContinue: (() -> Void)? = nil
    var footer: AnyView = AnyView(EmptyView())

    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AgentHomeAvatar(speaker: speaker, live: live)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                speakerLine

                messageBody

                if !attachments.isEmpty {
                    AgentHomeAttachmentStrip(attachments: attachments)
                }

                footer
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var messageBody: some View {
        if rendersMarkdown {
            HudMarkdownView(text: bodyText, contentSize: 13, style: .agent)
                .italic(italic)
        } else {
            Text(bodyText)
                .font(.system(size: 13))
                .italic(italic)
                .foregroundStyle(italic ? ScopeInk.muted : ScopeInk.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var speakerLine: some View {
        HStack(spacing: 7) {
            Text(speaker.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ScopeInk.primary)

            if let meta {
                Text("· \(meta)")
                    .font(.system(size: 11, weight: live ? .semibold : .medium))
                    .foregroundStyle(live ? AgentHomeChatPalette.brandSignalStrong : ScopeInk.subtle)
            }

            if live {
                Circle()
                    .fill(AgentHomeChatPalette.brandSignal)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle().stroke(AgentHomeChatPalette.brandSignalSoft, lineWidth: 3)
                    )
            }

            Spacer(minLength: 0)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ScopeInk.subtle)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Copy message")
            .opacity(hovered ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: hovered)

            if let onContinue {
                Button(action: onContinue) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Continue")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(AgentTheme.accentStrong)
                }
                .buttonStyle(.plain)
                .help("Continue from this turn")
                .opacity(hovered ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovered)
                .transition(.opacity)
            }

            if let time {
                Text(time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)
                    .opacity(hovered ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: hovered)
                    .help("Sent at \(time)")
            }
        }
    }
}

private struct AgentHomeAttachmentStrip: View {
    let attachments: [AgentInvocationAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 5) {
                        Image(systemName: attachment.systemImage)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AgentTheme.accentStrong)

                        Text(attachment.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ScopeInk.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AgentTheme.accentSoft.opacity(0.62))
                            .overlay(
                                Capsule()
                                    .stroke(AgentTheme.accent.opacity(0.18), lineWidth: 0.5)
                            )
                    )
                }
            }
        }
    }
}

private struct AgentHomeAvatar: View {
    let speaker: AgentHomeSpeaker
    let live: Bool

    var body: some View {
        let isTalkie = speaker == .talkie
        let bg: Color = isTalkie ? AgentHomeChatPalette.brandSignalSoft : ScopeInk.primary.opacity(0.05)
        let fg: Color = isTalkie ? AgentHomeChatPalette.brandSignalStrong : ScopeInk.muted

        RoundedRectangle(cornerRadius: 6)
            .fill(bg)
            .frame(width: 22, height: 22)
            .overlay(
                Text(speaker.initial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(fg)
            )
    }
}

// MARK: - Details block

private struct AgentHomeWorkBlock: View {
    let turn: AgentHomeExecutorTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !turn.threads.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(turn.threads) { thread in
                        AgentHomeActionRow(thread: thread)
                    }
                }
            }

            AgentHomeWireTrace(turn: turn)

            HStack(spacing: 8) {
                Text(identityLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ScopeInk.subtle)

                Spacer(minLength: 8)
            }
        }
    }

    private var identityLine: String {
        switch turn.status {
        case .waiting:
            return "\(turn.agentDisplayName) · queued"
        case .running:
            return "\(turn.agentDisplayName) · working"
        case .failed:
            return "\(turn.agentDisplayName) · needs attention"
        case .done:
            return "\(turn.agentDisplayName) · \(turn.latencyLabel ?? "done")"
        }
    }
}

// String/Optional helpers used by this view. The store has its own
// `private extension String` with the same shape — duplicated here on
// purpose so we don't widen its visibility.
fileprivate extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct AgentHomeActionRow: View {
    let thread: AgentHomeExecutorThread

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: glyphName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(thread.status == .failed ? .red : ScopeInk.subtle)
                .frame(width: 12, alignment: .center)

            Text(thread.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(thread.status == .waiting ? ScopeInk.subtle : ScopeInk.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if let detail = thread.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            statusBadge
        }
        .opacity(thread.status == .waiting ? 0.75 : 1)
    }

    private var glyphName: String {
        switch thread.kind {
        case .normalize: return "text.alignleft"
        case .dispatch:  return "arrow.turn.down.right"
        case .executor:  return "sparkles"
        case .response:  return "text.bubble"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch thread.status {
        case .running:
            Circle().fill(AgentTheme.accent).frame(width: 6, height: 6)
        case .waiting:
            Text("queued")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ScopeInk.subtle)
        case .failed:
            Text("failed")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
        case .done:
            EmptyView()
        }
    }
}

// MARK: - Idle hero (fresh conversation surface)

/// First-class surface for a fresh conversation. Borrows the "press to
/// transmit" idea from agent voice but quieted into something editorial
/// rather than instrumental:
///   - Headline is a question, not a command.
///   - One amber focal point (the mic disc); everything else is ink.
///   - Composer is *inside* the hero so the next action is obvious.
///   - Starters are conversational, not feature labels.
///
/// Studio reference: design/studio/components/studies/MacAgentHome.tsx
/// (the IdleHero / Starters / IdleMic group).
private struct AgentHomeIdleHero: View {
    @Binding var text: String
    let isSending: Bool
    let hasActiveTurn: Bool
    let placeholder: String
    let continuation: AgentHomeContinuationContext?
    let continuationMode: AgentHomeContinuationMode?
    @ObservedObject var voiceCapture: AgentHomeVoiceCapture
    let attachments: [AgentInvocationAttachment]
    let error: String?
    var isFocused: FocusState<Bool>.Binding
    let agents: [AgentRuntimeAgentSnapshot]
    @Binding var selectedAgentId: String?
    let onClearContinuation: () -> Void
    let onAddAttachment: () -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    let onCancelTalkBack: () -> Void
    let onTalkBack: () -> Void
    let onStarter: (String) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            AgentHomeIdleMic(phase: voiceCapture.phase, action: onTalkBack)

            VStack(spacing: 8) {
                Text("· NEW CONVERSATION")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)

                Text("What are you working on?")
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(ScopeInk.primary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Text("click the mic, type here, or use")
                    AgentHomeKbd(label: "⌃⌥⌘T")
                    Text("anywhere")
                }
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.faint)
            }

            AgentHomeComposer(
                text: $text,
                isSending: isSending,
                hasActiveTurn: hasActiveTurn,
                placeholder: placeholder,
                continuation: continuation,
                continuationMode: continuationMode,
                voiceCapture: voiceCapture,
                attachments: attachments,
                error: error,
                isFocused: isFocused,
                agents: agents,
                selectedAgentId: $selectedAgentId,
                onClearContinuation: onClearContinuation,
                onAddAttachment: onAddAttachment,
                onRemoveAttachment: onRemoveAttachment,
                onSend: onSend,
                onStop: onStop,
                onCancelTalkBack: onCancelTalkBack,
                onTalkBack: onTalkBack
            )
            .padding(.top, 12)

            AgentHomeStarters(onStarter: onStarter)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AgentHomeIdleMic: View {
    let phase: AgentHomeVoiceCapture.Phase
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AgentHomeChatPalette.brandSignalGlow)
                    .frame(width: 84, height: 84)
                    .blur(radius: 14)
                    .opacity(0.6)

                Circle()
                    .fill(AgentHomeChatPalette.brandSignal)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: AgentHomeChatPalette.brandSignalGlow, radius: 8, x: 0, y: 4)
                    .scaleEffect(hovered || phase == .recording ? 1.04 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .processing)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.18), value: hovered || phase == .recording)
        .help(helpText)
    }

    private var iconName: String {
        switch phase {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        }
    }

    private var helpText: String {
        switch phase {
        case .idle: return "Record in Agent Home"
        case .recording: return "Stop and send"
        case .processing: return "Transcribing"
        }
    }
}

private struct AgentHomeKbd: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(ScopeInk.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(AgentTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(ScopeEdge.subtle, lineWidth: 0.5)
            )
    }
}

private struct AgentHomeStarter: Identifiable {
    let id = UUID()
    let label: String
    let hint: String
}

private let AGENT_HOME_STARTERS: [AgentHomeStarter] = [
    .init(label: "Where did I leave off?",  hint: "recent activity"),
    .init(label: "Search my memos for …",   hint: "library"),
    .init(label: "What's in my tray?",      hint: "captures"),
]

private struct AgentHomeStarters: View {
    let onStarter: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("· OR PICK UP SOMETHING")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)

            HStack(spacing: 6) {
                ForEach(AGENT_HOME_STARTERS) { starter in
                    AgentHomeStarterChip(starter: starter, onTap: { onStarter(starter.label) })
                }
            }
        }
    }
}

private struct AgentHomeStarterChip: View {
    let starter: AgentHomeStarter
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(starter.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ScopeInk.muted)

                Text(starter.hint.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(ScopeInk.subtle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(hovered ? ScopeInk.primary.opacity(0.04) : AgentTheme.surface)
            )
            .overlay(
                Capsule().stroke(ScopeEdge.subtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Composer

private struct AgentHomeComposer: View {
    @Binding var text: String
    let isSending: Bool
    let hasActiveTurn: Bool
    let placeholder: String
    let continuation: AgentHomeContinuationContext?
    let continuationMode: AgentHomeContinuationMode?
    @ObservedObject var voiceCapture: AgentHomeVoiceCapture
    let attachments: [AgentInvocationAttachment]
    let error: String?
    var isFocused: FocusState<Bool>.Binding
    let agents: [AgentRuntimeAgentSnapshot]
    @Binding var selectedAgentId: String?
    let onClearContinuation: () -> Void
    let onAddAttachment: () -> Void
    let onRemoveAttachment: (UUID) -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    let onCancelTalkBack: () -> Void
    let onTalkBack: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let continuation, let continuationMode {
                AgentHomeContinuationPill(
                    continuation: continuation,
                    mode: continuationMode,
                    onClear: onClearContinuation
                )
                .padding(.leading, 2)
            }

            HudComposer(
                text: $text,
                phase: isSending || hasActiveTurn ? .streaming : .idle,
                style: HudComposerStyle(
                    placeholder: placeholder,
                    fontSize: 13,
                    lineLimit: 1...5,
                    fieldHorizontalPadding: 12,
                    fieldVerticalPadding: 9,
                    fieldCornerRadius: 14,
                    controlSize: 30
                ),
                layout: .stacked,
                focus: isFocused,
                leadingAccessory: {
                    AgentHomeAgentChip(agents: agents, selectedAgentId: $selectedAgentId)
                },
                trailingAccessory: {
                    Button(action: onTalkBack) {
                        Image(systemName: voiceButtonIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AgentHomeChatPalette.brandSignalStrong)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(AgentHomeChatPalette.brandSignalSoft))
                    }
                    .buttonStyle(.plain)
                    .disabled(voiceCapture.phase == .processing || isSending)
                    .help(voiceButtonHelp)
                },
                onAction: handleComposerAction,
                attachments: attachments.map { attachment in
                    HudComposerAttachment(
                        id: attachment.id,
                        name: attachment.name,
                        systemImage: attachment.systemImage
                    )
                },
                model: HudComposerModelInfo(model: activeAgentName, effort: "medium"),
                onAddAttachment: onAddAttachment,
                onRemoveAttachment: { attachment in
                    onRemoveAttachment(attachment.id)
                }
            )
            .hudTheme(AgentHomeHudTheme.theme)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AgentTheme.surface)
                    .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 12)
            )

            if showsVoiceStatus {
                AgentHomeVoiceCaptureStatus(
                    phase: voiceCapture.phase,
                    level: voiceCapture.level,
                    elapsed: voiceCapture.formattedElapsed,
                    error: voiceCapture.errorMessage,
                    onPrimary: onTalkBack,
                    onCancel: onCancelTalkBack
                )
                .padding(.leading, 40)
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 40)
            }
        }
    }

    private var showsVoiceStatus: Bool {
        voiceCapture.phase != .idle || voiceCapture.errorMessage != nil
    }

    private var activeAgentName: String {
        if let selectedAgentId, let agent = agents.first(where: { $0.id == selectedAgentId }) {
            return agent.name
        }
        return agents.first(where: { $0.isPreferred == true })?.name
            ?? agents.first?.name
            ?? "Agent"
    }

    private func handleComposerAction(_ action: HudComposerAction) {
        switch action {
        case .submit, .queue, .steer:
            guard canSend else { return }
            onSend()
        case .stop:
            onStop()
        }
    }

    private var voiceButtonIcon: String {
        switch voiceCapture.phase {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .processing: return "hourglass"
        }
    }

    private var voiceButtonHelp: String {
        switch voiceCapture.phase {
        case .idle: return "Record a voice reply here"
        case .recording: return "Stop and send this voice reply"
        case .processing: return "Transcribing voice reply"
        }
    }
}

private struct AgentHomeContinuationPill: View {
    let continuation: AgentHomeContinuationContext
    let mode: AgentHomeContinuationMode
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))

            Text(mode.title)
                .font(.system(size: 10, weight: .semibold))

            Text("·")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AgentHomeChatPalette.brandSignalStrong.opacity(0.65))

            Text(continuation.label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(mode.clearHelp)
        }
        .foregroundStyle(AgentHomeChatPalette.brandSignalStrong)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(AgentHomeChatPalette.brandSignalSoft))
        .overlay(Capsule().stroke(AgentHomeChatPalette.brandSignalBorder, lineWidth: 0.5))
    }
}

private struct AgentHomeVoiceCaptureStatus: View {
    let phase: AgentHomeVoiceCapture.Phase
    let level: Float
    let elapsed: String
    let error: String?
    let onPrimary: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentHomeVoiceMiniMeter(level: level, active: phase == .recording)
                .frame(width: 52, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(titleColor)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeInk.subtle)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if showsPrimaryButton {
                Button(action: onPrimary) {
                    Label(primaryLabel, systemImage: primaryIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(AgentTheme.accent)
                        )
                }
                .buttonStyle(.plain)
                .help(primaryHelp)
            }

            if showsCancelButton {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ScopeInk.subtle)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(ScopeInk.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AgentTheme.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
    }

    private var title: String {
        switch phase {
        case .recording: return "Listening \(elapsed)"
        case .processing: return "Transcribing voice reply"
        case .idle: return error == nil ? "Voice ready" : "Voice reply failed"
        }
    }

    private var detail: String? {
        if let error, !error.isEmpty { return error }
        switch phase {
        case .recording: return "Stop when you're done. This stays in Agent Home."
        case .processing: return "Talkie will add it as the next turn."
        case .idle: return nil
        }
    }

    private var titleColor: Color {
        phase == .idle && error != nil ? .red : ScopeInk.muted
    }

    private var showsPrimaryButton: Bool {
        phase == .recording || (phase == .idle && error != nil)
    }

    private var primaryLabel: String {
        phase == .recording ? "Stop & send" : "Try again"
    }

    private var primaryIcon: String {
        phase == .recording ? "stop.fill" : "mic.fill"
    }

    private var primaryHelp: String {
        phase == .recording ? "Stop recording and send" : "Record another voice reply"
    }

    private var showsCancelButton: Bool {
        phase == .recording || error != nil
    }
}

private struct AgentHomeVoiceMiniMeter: View {
    let level: Float
    let active: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let barCount = 14
                let spacing: CGFloat = 2
                let barWidth = max(1, (size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount))
                let now = timeline.date.timeIntervalSinceReferenceDate
                let baseLevel = active ? max(0.08, CGFloat(level)) : 0.04

                for index in 0..<barCount {
                    let phase = Double(index) * 0.62 + now * 7.0
                    let pulse = active ? CGFloat((sin(phase) + 1.0) * 0.5) : 0
                    let height = max(3, size.height * (0.18 + baseLevel * (0.35 + pulse * 0.65)))
                    let x = CGFloat(index) * (barWidth + spacing)
                    let y = (size.height - height) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    context.fill(path, with: .color(active ? AgentTheme.accent : ScopeInk.subtle.opacity(0.45)))
                }
            }
        }
    }
}

#Preview {
    AgentHomeView(onDismiss: {}, onOpenSettings: {})
        .frame(width: 980, height: 700)
}
