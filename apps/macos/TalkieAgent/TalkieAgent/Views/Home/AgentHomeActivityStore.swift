//
//  AgentHomeActivityStore.swift
//  TalkieAgent
//

import Foundation
import AppKit
import SwiftUI
import TalkieKit

private let agentHomeLog = Log(.ui)

enum AgentHomeJobStatus: String {
    case waiting
    case running
    case done
    case failed

    var title: String {
        switch self {
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .waiting: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: return .orange
        case .running: return .blue
        case .done: return .green
        case .failed: return .red
        }
    }
}

struct AgentHomeConversationTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let activeCount: Int
    let turnCount: Int
    let lastActivityAt: Date?

    static let general = AgentHomeConversationTopic(
        id: "agent-home-main",
        title: "General",
        subtitle: "General Talkie conversation",
        icon: "bubble.left.and.bubble.right",
        activeCount: 0,
        turnCount: 0,
        lastActivityAt: nil
    )
}

struct AgentHomeExecutorJob: Identifiable, Decodable {
    let jobId: String
    let sessionId: String
    let state: String
    let ack: String
    let providerId: String?
    let modelId: String?
    let topLevelProviderId: String?
    let topLevelProviderName: String?
    let topLevelModelId: String?
    let runtimeId: String?
    let runtimeName: String?
    let conversationId: String?
    let parentSessionId: String?
    let continuedFromSessionId: String?
    let source: String?
    let channelCode: String?
    let instruction: String?
    let transcript: String?
    let output: String?
    let spokenSummary: String?
    let bridgeStatus: String?
    let agentSessionId: String?
    let agentSessionThreadId: String?
    let agentSessionStatus: String?
    let agentSessionName: String?
    let createdAt: String?
    let updatedAt: String?
    let error: String?

    var id: String { sessionId }

    var status: AgentHomeJobStatus {
        switch state.lowercased() {
        case "working", "running", "started":
            return .running
        case "completed", "complete", "done", "succeeded":
            return .done
        case "failed", "cancelled", "canceled":
            return .failed
        default:
            return .waiting
        }
    }

    var title: String {
        let candidate = instruction ?? transcript ?? ack
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Talkie request" }
        return trimmed
    }

    var subtitle: String {
        var parts: [String] = []
        if let source { parts.append(source == "agent-home" ? "home" : source) }
        if let channelCode { parts.append(channelCode) }
        if let modelId { parts.append(modelId) }
        return parts.isEmpty ? sessionId : parts.joined(separator: " · ")
    }

    var createdDate: Date {
        Self.parseDate(createdAt) ?? updatedDate
    }

    var updatedDate: Date {
        Self.parseDate(updatedAt) ?? Self.parseDate(createdAt) ?? .distantPast
    }

    init(snapshot: WalkieRuntimeActivitySnapshot) {
        self.jobId = snapshot.id
        self.sessionId = snapshot.sessionId
        self.state = snapshot.state
        self.ack = snapshot.ack
        self.providerId = snapshot.providerId
        self.modelId = snapshot.modelId
        self.topLevelProviderId = snapshot.topLevelProviderId
        self.topLevelProviderName = snapshot.topLevelProviderName
        self.topLevelModelId = snapshot.topLevelModelId
        self.runtimeId = snapshot.runtimeId
        self.runtimeName = snapshot.runtimeName
        self.conversationId = snapshot.conversationId
        self.parentSessionId = snapshot.parentSessionId
        self.continuedFromSessionId = snapshot.continuedFromSessionId
        self.source = snapshot.source
        self.channelCode = snapshot.channelCode
        self.instruction = snapshot.instruction
        self.transcript = snapshot.transcript
        self.output = snapshot.output
        self.spokenSummary = snapshot.spokenSummary
        self.bridgeStatus = snapshot.bridgeStatus
        self.agentSessionId = snapshot.agentSessionId
        self.agentSessionThreadId = snapshot.agentSessionThreadId
        self.agentSessionStatus = snapshot.agentSessionStatus
        self.agentSessionName = snapshot.agentSessionName
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
        self.error = snapshot.error
    }

    private enum CodingKeys: String, CodingKey {
        case jobId = "id"
        case sessionId
        case state
        case ack
        case providerId
        case modelId
        case topLevelProviderId
        case topLevelProviderName
        case topLevelModelId
        case runtimeId
        case runtimeName
        case conversationId
        case parentSessionId
        case continuedFromSessionId
        case source
        case channelCode
        case instruction
        case transcript
        case output
        case spokenSummary
        case bridgeStatus
        case agentSessionId
        case agentSessionThreadId
        case agentSessionStatus
        case agentSessionName
        case createdAt
        case updatedAt
        case error
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

struct AgentHomeExecutorThread: Identifiable {
    enum Kind: String {
        case normalize
        case dispatch
        case executor
        case response
    }

    let id: String
    let kind: Kind
    let label: String
    let status: AgentHomeJobStatus
    let runtimeName: String
    let runtimeId: String?
    let providerId: String?
    let modelId: String?
    let detail: String?
    let metadata: String
    let timestamp: Date?
}

struct AgentHomeExecutorTurn: Identifiable {
    let id: String
    let conversationId: String?
    let parentSessionId: String?
    let continuedFromSessionId: String?
    let source: String?
    let agentSessionId: String?
    let agentSessionThreadId: String?
    let channelCode: String?
    let startedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let transcript: String?
    let instruction: String?
    let ack: String?
    let response: String?
    let spokenSummary: String?
    let status: AgentHomeJobStatus
    let topLevelProvider: String?
    let topLevelModel: String?
    let executorProvider: String?
    let executorModel: String?
    let runtimeId: String?
    let bridgeStatus: String?
    let threads: [AgentHomeExecutorThread]
    let error: String?

    /// Compact duration for the speaker meta line — "32s", "1m 04s", "3m 48s".
    /// Returns nil for turns that haven't completed yet (running/waiting) so
    /// the view can substitute a live label instead.
    var latencyLabel: String? {
        guard status == .done || status == .failed else { return nil }
        let seconds = Int(updatedAt.timeIntervalSince(createdAt).rounded())
        guard seconds >= 0 else { return nil }
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes)m \(String(format: "%02d", remainder))s"
    }

    /// Body the Talkie speaker line should show. Prefers the spoken summary
    /// (what Talkie would say aloud), then the longer response, then the ack.
    var spokenBody: String? {
        spokenSummary?.nonEmpty ?? response?.nonEmpty ?? ack?.nonEmpty
    }

    /// Body the You speaker line should show — what the user actually said or
    /// typed for this turn.
    var askBody: String? {
        transcript?.nonEmpty ?? instruction?.nonEmpty
    }

    init(job: AgentHomeExecutorJob, runtimePing: WalkieRuntimePing?) {
        let turnTranscript = job.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? job.instruction?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? job.ack.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let turnInstruction = job.instruction?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? turnTranscript
        let topLevelProvider = job.topLevelProviderName ?? job.topLevelProviderId
        let runtimeId = job.runtimeId ?? runtimePing?.runtimeId

        id = job.sessionId
        conversationId = job.conversationId
        parentSessionId = job.parentSessionId
        continuedFromSessionId = job.continuedFromSessionId
        source = job.source
        agentSessionId = job.agentSessionId
        agentSessionThreadId = job.agentSessionThreadId
        channelCode = job.channelCode ?? "CH-01"
        startedAt = job.createdDate
        createdAt = job.createdDate
        updatedAt = job.updatedDate
        transcript = turnTranscript
        instruction = turnInstruction
        ack = job.ack.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        response = job.output?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        spokenSummary = job.spokenSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        status = job.status
        self.topLevelProvider = topLevelProvider
        topLevelModel = job.topLevelModelId
        executorProvider = job.providerId
        executorModel = job.modelId
        self.runtimeId = runtimeId
        bridgeStatus = job.bridgeStatus ?? runtimePing?.scoutBridge.rawValue
        error = job.error?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        threads = Self.makeThreads(
            job: job,
            runtimePing: runtimePing,
            transcript: turnTranscript ?? "Voice note",
            instruction: turnInstruction ?? "Talkie request"
        )
    }

    private static func makeThreads(
        job: AgentHomeExecutorJob,
        runtimePing: WalkieRuntimePing?,
        transcript: String,
        instruction: String
    ) -> [AgentHomeExecutorThread] {
        let topLevelProvider = job.topLevelProviderName ?? job.topLevelProviderId
        let topLevelModel = job.topLevelModelId
        let runtimeName = job.runtimeName ?? runtimePing?.runtimeName ?? "Runtime"
        let runtimeId = job.runtimeId ?? runtimePing?.runtimeId
        let turnMetadata = job.source == "agent-home" ? "typed here" : "spoken"
        let executorDetail: String

        switch job.status {
        case .waiting:
            executorDetail = "I'll start as soon as the current work clears."
        case .running:
            executorDetail = job.continuedFromSessionId == nil
                ? "I'm working through this now."
                : "I'm continuing from the earlier reply."
        case .done:
            executorDetail = "Done."
        case .failed:
            executorDetail = job.error?.nonEmpty ?? "I couldn't finish this turn."
        }

        let responseDetail: String
        if let output = job.output?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            responseDetail = output
        } else if job.status == .failed {
            responseDetail = "No reply was saved for this turn."
        } else {
            responseDetail = "I'll pin the reply here when it's ready."
        }

        let branchLabel: String
        switch job.status {
        case .waiting:
            branchLabel = "Queued"
        case .running:
            branchLabel = job.continuedFromSessionId == nil ? "Working" : "Continuing"
        case .done:
            branchLabel = "Replied"
        case .failed:
            branchLabel = "Needs attention"
        }

        let branchDetail = job.spokenSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? job.output?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? responseDetail.nonEmpty
            ?? executorDetail

        let branchMetadata = [
            job.continuedFromSessionId == nil ? nil : "follow-up",
            turnMetadata,
            job.bridgeStatus ?? runtimePing?.scoutBridge.rawValue,
        ].compactMap { $0?.nonEmpty }.joined(separator: " · ")

        return [
            AgentHomeExecutorThread(
                id: "\(job.sessionId)-agent-branch",
                kind: .executor,
                label: branchLabel,
                status: job.status,
                runtimeName: runtimeName,
                runtimeId: runtimeId,
                providerId: job.providerId ?? topLevelProvider,
                modelId: job.modelId ?? topLevelModel,
                detail: branchDetail,
                metadata: branchMetadata,
                timestamp: job.updatedDate
            ),
        ]
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
final class AgentHomeActivityStore: ObservableObject {
    @Published private(set) var executorJobs: [AgentHomeExecutorJob] = []
    @Published private(set) var recentDictations: [LiveRecording] = []
    @Published private(set) var runtimePing: WalkieRuntimePing?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var isInvokingAgent = false
    @Published private(set) var invokeError: String?

    private var refreshTimer: Timer?
    private let defaultConversationId = "agent-home-main"

    var activeJobs: [AgentHomeExecutorJob] {
        executorJobs.filter { $0.status == .waiting || $0.status == .running }
    }

    var completedJobs: [AgentHomeExecutorJob] {
        executorJobs.filter { $0.status == .done || $0.status == .failed }
    }

    var conversationTopics: [AgentHomeConversationTopic] {
        let grouped = Dictionary(grouping: executorJobs) { job in
            job.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? defaultConversationId
        }

        let projected = grouped.map { conversationId, jobs in
            let activeCount = jobs.filter { $0.status == .waiting || $0.status == .running }.count
            let sortedJobs = jobs.sorted { $0.updatedDate > $1.updatedDate }
            let lastActivityAt = sortedJobs.first?.updatedDate
            return AgentHomeConversationTopic(
                id: conversationId,
                title: topicTitle(for: conversationId, jobs: sortedJobs),
                subtitle: topicSubtitle(for: conversationId, jobs: sortedJobs, activeCount: activeCount),
                icon: topicIcon(for: conversationId, jobs: sortedJobs),
                activeCount: activeCount,
                turnCount: jobs.count,
                lastActivityAt: lastActivityAt
            )
        }
        .sorted { left, right in
            (left.lastActivityAt ?? .distantPast) > (right.lastActivityAt ?? .distantPast)
        }

        if projected.contains(where: { $0.id == defaultConversationId }) {
            return projected
        }

        return [.general] + projected
    }

    var executorTurns: [AgentHomeExecutorTurn] {
        executorTurns(in: currentConversationId)
    }

    func executorTurns(in conversationId: String) -> [AgentHomeExecutorTurn] {
        executorJobs
            .filter { ($0.conversationId?.nonEmpty ?? defaultConversationId) == conversationId }
            .sorted { $0.createdDate < $1.createdDate }
            .map { AgentHomeExecutorTurn(job: $0, runtimePing: runtimePing) }
    }

    var currentConversationId: String {
        conversationTopics.first?.id ?? defaultConversationId
    }

    var latestActivityDate: Date? {
        let jobDate = executorJobs.first?.updatedDate
        let dictationDate = recentDictations.first?.createdAt
        return [jobDate, dictationDate].compactMap { $0 }.max()
    }

    /// Sidebar grouping: "Today" / "Yesterday" / "Earlier" based on the
    /// conversation's most recent activity. Returns nil for conversations
    /// with no activity yet — those float to the bottom under "Earlier".
    static func groupLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Earlier" }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return "Earlier"
    }

    /// Sidebar last-activity stamp — "now", "12m", "2h", "yesterday", or a
    /// short relative date. Matches the studio's compact right-rail label.
    static func sidebarStamp(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60      { return "now" }
        if elapsed < 3_600   { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400  { return "\(Int(elapsed / 3_600))h" }
        let cal = Calendar.current
        if cal.isDateInYesterday(date) { return "yesterday" }
        let days = Int(elapsed / 86_400)
        return "\(days)d"
    }

    func startRefreshing() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        recentDictations = UnifiedDatabase.recentDictations(limit: 12)
        lastRefreshed = Date()

        Task { @MainActor [weak self] in
            await self?.refreshRuntimeStatus()
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        SoundManager.shared.playPasted()
    }

    func invokeAgent(
        text: String,
        conversationId explicitConversationId: String? = nil,
        parentSessionId explicitParentSessionId: String? = nil
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isInvokingAgent else { return }

        let conversationId = explicitConversationId ?? currentConversationId
        let parentSessionId = explicitParentSessionId ?? latestSessionId(in: conversationId)
        isInvokingAgent = true
        invokeError = nil

        do {
            let invocation = WalkieAgentInvocation(
                id: UUID(),
                channel: .defaultChannel,
                transcript: trimmed,
                instruction: trimmed,
                topLevelModel: WalkieModelUse(
                    providerId: "talkie-agent",
                    providerName: "Talkie Agent",
                    modelId: "agent-home"
                ),
                requestedAt: Date(),
                conversationId: conversationId,
                parentSessionId: parentSessionId,
                source: "agent-home"
            )
            _ = try await WalkieNodeRuntimeClient.shared.invoke(invocation)
            await refreshRuntimeStatus()
        } catch {
            invokeError = error.localizedDescription
            agentHomeLog.warning(
                "Agent Home could not invoke agent session",
                detail: error.localizedDescription
            )
        }

        isInvokingAgent = false
    }

    private func refreshRuntimeStatus() async {
        do {
            let status = try await WalkieNodeRuntimeClient.shared.status()
            runtimePing = status.ping
            executorJobs = status.activities
                .map(AgentHomeExecutorJob.init(snapshot:))
                .sorted { $0.updatedDate > $1.updatedDate }
        } catch {
            runtimePing = nil
            executorJobs = []
            agentHomeLog.warning(
                "Agent Home could not refresh runtime status",
                detail: error.localizedDescription
            )
        }
    }

    private func latestSessionId(in conversationId: String) -> String? {
        executorJobs
            .filter { ($0.conversationId?.nonEmpty ?? defaultConversationId) == conversationId }
            .max { $0.createdDate < $1.createdDate }?
            .sessionId
    }

    private func topicTitle(for conversationId: String, jobs: [AgentHomeExecutorJob]) -> String {
        if conversationId == defaultConversationId {
            return "General"
        }

        if conversationId.hasPrefix("channel-") {
            let label = conversationId
                .dropFirst("channel-".count)
                .replacing("-", with: " ")
                .uppercased()
            return label.isEmpty ? "Channel" : label
        }

        let candidate = jobs.first?.transcript?.nonEmpty
            ?? jobs.first?.instruction?.nonEmpty
            ?? jobs.first?.ack.nonEmpty
        guard let candidate else {
            return conversationId.replacing("-", with: " ")
        }

        return candidate.count > 38 ? String(candidate.prefix(35)) + "..." : candidate
    }

    private func topicSubtitle(
        for conversationId: String,
        jobs: [AgentHomeExecutorJob],
        activeCount: Int
    ) -> String {
        if jobs.isEmpty {
            return conversationId == defaultConversationId ? "General Talkie conversation" : "New conversation"
        }

        let turnCount = jobs.count
        let turnLabel = turnCount == 1 ? "1 turn" : "\(turnCount) turns"
        if activeCount > 0 {
            let activeLabel = activeCount == 1 ? "working now" : "\(activeCount) replies working"
            return "\(activeLabel) · \(turnLabel)"
        }
        return turnLabel
    }

    private func topicIcon(for conversationId: String, jobs: [AgentHomeExecutorJob]) -> String {
        if jobs.contains(where: { $0.source?.contains("voice") == true }) {
            return "waveform"
        }
        if jobs.contains(where: { $0.status == .running || $0.status == .waiting }) {
            return "bolt.horizontal"
        }
        return conversationId == defaultConversationId ? "bubble.left.and.bubble.right" : "number"
    }
}
