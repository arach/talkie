//
//  PendingActionsManager.swift
//  Talkie macOS
//
//  Tracks pending/running workflow executions globally.
//  Enables visibility into active operations across the app.
//  Also maintains a history of recent actions for retry capability.
//

import Foundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "PendingActionsManager")

// MARK: - Pending Action Model

struct PendingAction: Identifiable, Equatable {
    let id: UUID
    let workflowId: UUID?
    let workflowName: String
    let workflowIcon: String
    let memoId: UUID?
    let memoTitle: String
    let startedAt: Date
    var currentStep: String?
    var stepIndex: Int = 0
    var totalSteps: Int = 1

    /// Computed progress (0.0 - 1.0)
    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(stepIndex) / Double(totalSteps)
    }

    /// Time elapsed since start
    var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    static func == (lhs: PendingAction, rhs: PendingAction) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Recent Action Model (completed or failed)

enum ActionStatus: Equatable {
    case completed
    case failed(error: String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

struct RecentAction: Identifiable, Equatable {
    let id: UUID
    let workflowId: UUID?
    let workflowName: String
    let workflowIcon: String
    let memoId: UUID?
    let memoTitle: String
    let startedAt: Date
    let completedAt: Date
    let status: ActionStatus
    let duration: TimeInterval

    static func == (lhs: RecentAction, rhs: RecentAction) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Pending Actions Manager

@Observable
@MainActor
class PendingActionsManager {
    static let shared = PendingActionsManager()

    /// Currently running actions
    private(set) var pendingActions: [PendingAction] = []

    /// Recent completed/failed actions (keeps last 20)
    private(set) var recentActions: [RecentAction] = []

    /// Maximum number of recent actions to keep
    @ObservationIgnored private let maxRecentActions = 20

    /// Quick check if any actions are running
    var hasActiveActions: Bool {
        !pendingActions.isEmpty
    }

    /// Count of active actions
    var activeCount: Int {
        pendingActions.count
    }

    /// Count of failed actions in recent history
    var failedCount: Int {
        recentActions.filter { $0.status.isFailed }.count
    }

    /// Recent failed actions only
    var failedActions: [RecentAction] {
        recentActions.filter { $0.status.isFailed }
    }

    private init() {}

    // MARK: - Action Lifecycle

    /// Register a new pending action when a workflow starts
    /// - Returns: The action ID to use for updates/completion
    @discardableResult
    func startAction(
        workflowId: UUID?,
        workflowName: String,
        workflowIcon: String = "bolt.fill",
        memoId: UUID?,
        memoTitle: String,
        totalSteps: Int = 1
    ) -> UUID {
        let actionId = UUID()
        let action = PendingAction(
            id: actionId,
            workflowId: workflowId,
            workflowName: workflowName,
            workflowIcon: workflowIcon,
            memoId: memoId,
            memoTitle: memoTitle,
            startedAt: Date(),
            currentStep: nil,
            stepIndex: 0,
            totalSteps: totalSteps
        )

        pendingActions.append(action)
        logger.info("Started action: \(workflowName) on '\(memoTitle)' (id: \(actionId.uuidString))")

        return actionId
    }

    /// Update progress for a running action
    func updateAction(
        id: UUID,
        currentStep: String? = nil,
        stepIndex: Int? = nil
    ) {
        guard let index = pendingActions.firstIndex(where: { $0.id == id }) else {
            logger.warning("Tried to update unknown action: \(id.uuidString)")
            return
        }

        if let step = currentStep {
            pendingActions[index].currentStep = step
        }
        if let idx = stepIndex {
            pendingActions[index].stepIndex = idx
        }

        logger.debug("Updated action \(id.uuidString): step=\(currentStep ?? "nil"), index=\(stepIndex ?? -1)")
    }

    /// Mark an action as completed (moves to recent list)
    func completeAction(id: UUID) {
        guard let index = pendingActions.firstIndex(where: { $0.id == id }) else {
            logger.warning("Tried to complete unknown action: \(id.uuidString)")
            return
        }

        let action = pendingActions[index]
        let duration = action.elapsed
        logger.info("Completed action: \(action.workflowName) (elapsed: \(String(format: "%.1f", duration))s)")

        // Add to recent actions
        let recentAction = RecentAction(
            id: action.id,
            workflowId: action.workflowId,
            workflowName: action.workflowName,
            workflowIcon: action.workflowIcon,
            memoId: action.memoId,
            memoTitle: action.memoTitle,
            startedAt: action.startedAt,
            completedAt: Date(),
            status: .completed,
            duration: duration
        )
        addToRecentActions(recentAction)

        pendingActions.remove(at: index)
    }

    /// Mark an action as failed (moves to recent list with error)
    func failAction(id: UUID, error: String? = nil) {
        guard let index = pendingActions.firstIndex(where: { $0.id == id }) else {
            logger.warning("Tried to fail unknown action: \(id.uuidString)")
            return
        }

        let action = pendingActions[index]
        let duration = action.elapsed
        let errorMessage = error ?? "Unknown error"
        logger.error("Failed action: \(action.workflowName) - \(errorMessage)")

        // Add to recent actions with error
        let recentAction = RecentAction(
            id: action.id,
            workflowId: action.workflowId,
            workflowName: action.workflowName,
            workflowIcon: action.workflowIcon,
            memoId: action.memoId,
            memoTitle: action.memoTitle,
            startedAt: action.startedAt,
            completedAt: Date(),
            status: .failed(error: errorMessage),
            duration: duration
        )
        addToRecentActions(recentAction)

        pendingActions.remove(at: index)
    }

    /// Add to recent actions, maintaining max limit
    private func addToRecentActions(_ action: RecentAction) {
        recentActions.insert(action, at: 0)
        if recentActions.count > maxRecentActions {
            recentActions = Array(recentActions.prefix(maxRecentActions))
        }
    }

    /// Clear a specific recent action (e.g., after successful retry)
    func clearRecentAction(id: UUID) {
        recentActions.removeAll { $0.id == id }
    }

    /// Clear all recent actions
    func clearAllRecentActions() {
        recentActions.removeAll()
        logger.info("Cleared all recent actions")
    }

    /// Get all pending actions for a specific memo
    func actionsForMemo(_ memoId: UUID) -> [PendingAction] {
        pendingActions.filter { $0.memoId == memoId }
    }

    /// Check if a specific workflow is running on a specific memo
    func isRunning(workflowId: UUID, on memoId: UUID) -> Bool {
        pendingActions.contains { $0.workflowId == workflowId && $0.memoId == memoId }
    }

    /// Cancel all actions (for cleanup)
    func cancelAll() {
        let count = pendingActions.count
        logger.info("Cancelling all \(count) pending actions")
        pendingActions.removeAll()
    }
}
