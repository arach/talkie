//
//  WorkflowControlPlaneService.swift
//  Talkie macOS
//
//  Lightweight coordinator for Talkie-owned live workflow execution.
//  It stays dormant until enabled, uses the current Talkie account session,
//  and polls lazily while idle so background cost stays negligible.
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.workflow)

@MainActor
@Observable
final class WorkflowControlPlaneService {
    static let shared = WorkflowControlPlaneService()
    private let minimumIdlePollInterval: TimeInterval = 60

    enum State: String {
        case disabled = "Disabled"
        case signedOut = "Signed Out"
        case armed = "Armed"
        case polling = "Polling"
        case executing = "Executing"
        case error = "Error"
    }

    private let settings = SettingsManager.shared
    private let authManager = AuthManager.shared
    private let recordingRepository = TalkieObjectRepository()
    private let backendID = "talkie-mac-swift"

    @ObservationIgnored private var runLoopTask: Task<Void, Never>?
    @ObservationIgnored private var executionTask: Task<Void, Never>?
    @ObservationIgnored private var authStateObserver: NSObjectProtocol?
    @ObservationIgnored private var isPollInFlight = false

    private(set) var state: State = .disabled
    private(set) var lastPollAt: Date?
    private(set) var lastWakeReason: String?
    private(set) var lastErrorMessage: String?
    private(set) var activeRunId: String?
    private(set) var activeWorkflowName: String?

    private init() {
        AppMode.guard(.lite, "WorkflowControlPlaneService")

        authStateObserver = NotificationCenter.default.addObserver(
            forName: .talkieAuthStateDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAuthStateChange()
            }
        }
    }

    var isRunning: Bool {
        runLoopTask != nil
    }

    var isEnabled: Bool {
        settings.workflowControlPlaneEnabled
    }

    var isConfigured: Bool {
        isEnabled && isAuthenticated
    }

    private var isAuthenticated: Bool {
        authManager.isSignedIn && authManager.authToken?.isEmpty == false
    }

    func startIfNeeded() {
        guard isEnabled else {
            stop(reason: nil)
            state = .disabled
            return
        }

        guard isAuthenticated else {
            stop(reason: nil)
            state = .signedOut
            return
        }

        guard runLoopTask == nil else { return }

        lastErrorMessage = nil
        state = .armed

        let intervalSeconds = max(minimumIdlePollInterval, settings.workflowControlPlaneIdlePollInterval)
        runLoopTask = Task(priority: .utility) { [weak self] in
            await self?.runLoop(idlePollInterval: intervalSeconds)
        }

        log.info("Live workflow executor armed with \(Int(intervalSeconds))s idle polling")
        wake(reason: "start")
    }

    func stop(reason: String?) {
        runLoopTask?.cancel()
        runLoopTask = nil
        isPollInFlight = false

        if let reason {
            log.info("Live workflow executor stopped: \(reason)")
        }
    }

    func wake(reason: String) {
        lastWakeReason = reason

        guard isEnabled else {
            state = .disabled
            return
        }

        guard isAuthenticated else {
            state = .signedOut
            return
        }

        if runLoopTask == nil {
            startIfNeeded()
        }

        Task(priority: .utility) { [weak self] in
            await self?.requestPoll(trigger: reason)
        }
    }

    private func handleAuthStateChange() {
        guard isEnabled else {
            state = .disabled
            return
        }

        if isAuthenticated {
            startIfNeeded()
            wake(reason: "auth_state_changed")
        } else {
            stop(reason: "auth_state_changed")
            state = .signedOut
        }
    }

    private func runLoop(idlePollInterval: TimeInterval) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(idlePollInterval))
            } catch {
                break
            }

            guard !Task.isCancelled else { break }
            await requestPoll(trigger: "idle")
        }
    }

    private func requestPoll(trigger: String) async {
        guard !isPollInFlight else { return }

        isPollInFlight = true
        defer { isPollInFlight = false }

        await performLightweightPoll(trigger: trigger)
    }

    private func performLightweightPoll(trigger: String) async {
        guard isEnabled else {
            state = .disabled
            return
        }

        guard isAuthenticated else {
            state = .signedOut
            return
        }

        state = .polling
        lastPollAt = Date()
        lastErrorMessage = nil

        do {
            let client = try makeClient()
            let descriptor = executorDescriptor()

            try await client.upsertExecutor(descriptor)
            let heartbeat = try await client.heartbeatExecutor(
                deviceId: descriptor.deviceId,
                status: "online",
                claimedRunId: activeRunId,
                metadata: [
                    "trigger": trigger,
                    "phase": executionTask == nil ? "idle" : "executing",
                ]
            )

            if heartbeat.ok == false {
                throw WorkflowControlPlaneClient.ClientError.server(
                    status: 500,
                    message: heartbeat.reason ?? "Live workflow heartbeat failed."
                )
            }

            guard executionTask == nil else {
                state = .executing
                return
            }

            let runs = try await client.listClaimableRuns(limit: 1)
            if let run = runs.first {
                beginExecution(for: run)
            } else {
                state = .armed
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            state = .error
            log.error("Live workflow poll failed (\(trigger)): \(error.localizedDescription)")
        }
    }

    private func beginExecution(for run: WorkflowControlPlaneClient.WorkflowRunEnvelope) {
        guard executionTask == nil else { return }

        activeRunId = run.runId
        activeWorkflowName = run.workflowName
        state = .executing

        executionTask = Task(priority: .utility) { [weak self] in
            await self?.execute(run: run)
        }
    }

    private func execute(run: WorkflowControlPlaneClient.WorkflowRunEnvelope) async {
        var leaseToken: String?

        do {
            let client = try makeClient()
            let descriptor = executorDescriptor()
            let claim = try await client.claimRun(
                runId: run.runId,
                deviceId: descriptor.deviceId,
                backendId: backendID
            )

            guard claim.granted, let grantedLeaseToken = claim.leaseToken else {
                await finishExecution()
                return
            }

            leaseToken = grantedLeaseToken

            try await client.markRunStarted(
                runId: run.runId,
                deviceId: descriptor.deviceId,
                leaseToken: grantedLeaseToken,
                backendId: backendID
            )

            let renewalTask = startLeaseRenewal(runId: run.runId, leaseToken: grantedLeaseToken)
            defer { renewalTask.cancel() }

            let result = try await executeRunLocally(run)
            try await client.completeRun(
                runId: run.runId,
                deviceId: descriptor.deviceId,
                leaseToken: grantedLeaseToken,
                backendId: backendID,
                finalOutputs: result.finalOutputs,
                output: result.output,
                stepOutputsJSON: result.stepOutputsJSON
            )

            log.info("Completed live workflow run \(run.runId) (\(run.workflowName))")
            await finishExecution()
        } catch {
            if let leaseToken {
                do {
                    let client = try makeClient()
                    let descriptor = executorDescriptor()
                    try await client.failRun(
                        runId: run.runId,
                        deviceId: descriptor.deviceId,
                        leaseToken: leaseToken,
                        backendId: backendID,
                        message: error.localizedDescription
                    )
                } catch {
                    log.error("Failed to report live workflow error: \(error.localizedDescription)")
                }
            }

            lastErrorMessage = error.localizedDescription
            state = .error
            log.error("Live workflow run failed (\(run.runId)): \(error.localizedDescription)")
            await finishExecution()
        }
    }

    private func executeRunLocally(
        _ run: WorkflowControlPlaneClient.WorkflowRunEnvelope
    ) async throws -> LiveWorkflowExecutionResult {
        guard let workflowID = UUID(uuidString: run.workflowId) else {
            throw WorkflowControlPlaneError.invalidWorkflowID(run.workflowId)
        }

        let workflow = await resolveWorkflow(id: workflowID)
        guard let workflow else {
            throw WorkflowControlPlaneError.workflowNotFound(workflowID)
        }

        guard let memoID = UUID(uuidString: run.memoId) else {
            throw WorkflowControlPlaneError.invalidMemoID(run.memoId)
        }

        guard let recording = try await recordingRepository.fetchRecording(id: memoID) else {
            throw WorkflowControlPlaneError.memoNotFound(memoID)
        }

        let finalOutputs = try await WorkflowExecutor.shared.executeWorkflow(workflow.definition, for: recording)
        return LiveWorkflowExecutionResult(
            finalOutputs: finalOutputs,
            output: preferredOutput(from: finalOutputs),
            stepOutputsJSON: encodedStepOutputs(finalOutputs)
        )
    }

    private func resolveWorkflow(id: UUID) async -> Workflow? {
        if let workflow = WorkflowService.shared.workflow(byID: id) {
            return workflow
        }

        await WorkflowService.shared.reload()
        return WorkflowService.shared.workflow(byID: id)
    }

    private func startLeaseRenewal(runId: String, leaseToken: String) -> Task<Void, Never> {
        let interval: Duration = .seconds(10)
        return Task(priority: .utility) { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await self.renewLease(runId: runId, leaseToken: leaseToken)
            }
        }
    }

    private func renewLease(runId: String, leaseToken: String) async {
        do {
            let client = try makeClient()
            let descriptor = executorDescriptor()
            let renewal = try await client.renewLease(
                runId: runId,
                deviceId: descriptor.deviceId,
                leaseToken: leaseToken
            )

            if renewal.ok == false {
                throw WorkflowControlPlaneClient.ClientError.server(
                    status: 500,
                    message: renewal.reason ?? "Live workflow lease renewal failed."
                )
            }

            _ = try await client.heartbeatExecutor(
                deviceId: descriptor.deviceId,
                status: "online",
                claimedRunId: runId,
                metadata: [
                    "trigger": "lease_renewal",
                    "phase": "executing",
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            log.error("Live workflow lease renewal failed (\(runId)): \(error.localizedDescription)")
        }
    }

    private func finishExecution() async {
        executionTask = nil
        activeRunId = nil
        activeWorkflowName = nil

        if state != .error {
            if !isEnabled {
                state = .disabled
            } else if !isAuthenticated {
                state = .signedOut
            } else {
                state = .armed
            }
        }

        wake(reason: "post_execution")
    }

    private func makeClient() throws -> WorkflowControlPlaneClient {
        guard let authToken = authManager.authToken, !authToken.isEmpty else {
            throw WorkflowControlPlaneError.notSignedIn
        }

        return try WorkflowControlPlaneClient(
            baseURLString: TalkieEnvironment.current.workflowAPIBaseURL,
            authToken: authToken
        )
    }

    private func executorDescriptor() -> WorkflowControlPlaneClient.ExecutorDescriptor {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let name = Host.current().localizedName ?? "Talkie Mac"
        let appVersion: String?

        if let version, let build {
            appVersion = "\(version) (\(build))"
        } else {
            appVersion = version ?? build
        }

        return .init(
            deviceId: settings.workflowControlPlaneDeviceId,
            name: name,
            platform: "macos",
            status: "online",
            priority: 100,
            capabilities: ["workflow", "local-files", "memos"],
            installId: settings.workflowControlPlaneDeviceId,
            appVersion: appVersion,
            tailscaleHostname: BridgeManager.shared.tailscaleStatus.hostname,
            metadata: [
                "environment": TalkieEnvironment.current.rawValue,
                "host": name,
            ]
        )
    }

    private func preferredOutput(from outputs: [String: String]) -> String? {
        let priorityKeys = ["OUTPUT", "PREVIOUS_OUTPUT", "final", "summary", "result"]
        for key in priorityKeys {
            if let value = outputs[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        return outputs
            .filter { $0.key != "WORKFLOW_NAME" && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.value.count > $1.value.count }
            .first?
            .value
    }

    private func encodedStepOutputs(_ outputs: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(outputs),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
}

private struct LiveWorkflowExecutionResult {
    let finalOutputs: [String: String]
    let output: String?
    let stepOutputsJSON: String?
}

private enum WorkflowControlPlaneError: LocalizedError {
    case notSignedIn
    case invalidWorkflowID(String)
    case workflowNotFound(UUID)
    case invalidMemoID(String)
    case memoNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign into Talkie before this Mac can claim live workflows."
        case .invalidWorkflowID(let value):
            return "Live workflow run has an invalid workflow ID: \(value)"
        case .workflowNotFound(let id):
            return "Workflow \(id.uuidString) is not available on this Mac."
        case .invalidMemoID(let value):
            return "Live workflow run has an invalid memo ID: \(value)"
        case .memoNotFound(let id):
            return "Memo \(id.uuidString) is not available on this Mac."
        }
    }
}
