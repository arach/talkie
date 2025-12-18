//
//  WorkflowRunModel.swift
//  Talkie
//
//  Pure Swift model for workflow runs
//

import Foundation
import GRDB

// MARK: - Workflow Run Model

struct WorkflowRunModel: Identifiable, Codable, Hashable {
    let id: UUID
    let memoId: UUID
    let workflowId: UUID
    var workflowName: String
    var workflowIcon: String?
    var output: String?
    var status: String  // "completed", "failed", "running"
    var runDate: Date
    var modelId: String?
    var providerName: String?
    var stepOutputsJSON: String?  // JSON array of step outputs

    init(
        id: UUID = UUID(),
        memoId: UUID,
        workflowId: UUID,
        workflowName: String,
        workflowIcon: String? = nil,
        output: String? = nil,
        status: String = "completed",
        runDate: Date = Date(),
        modelId: String? = nil,
        providerName: String? = nil,
        stepOutputsJSON: String? = nil
    ) {
        self.id = id
        self.memoId = memoId
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.workflowIcon = workflowIcon
        self.output = output
        self.status = status
        self.runDate = runDate
        self.modelId = modelId
        self.providerName = providerName
        self.stepOutputsJSON = stepOutputsJSON
    }
}

// MARK: - GRDB Record

extension WorkflowRunModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "workflow_runs"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let memoId = Column(CodingKeys.memoId)
        static let workflowId = Column(CodingKeys.workflowId)
        static let workflowName = Column(CodingKeys.workflowName)
        static let workflowIcon = Column(CodingKeys.workflowIcon)
        static let output = Column(CodingKeys.output)
        static let status = Column(CodingKeys.status)
        static let runDate = Column(CodingKeys.runDate)
        static let modelId = Column(CodingKeys.modelId)
        static let providerName = Column(CodingKeys.providerName)
        static let stepOutputsJSON = Column(CodingKeys.stepOutputsJSON)
    }

    /// Association back to memo
    static let memo = belongsTo(MemoModel.self)
}

// MARK: - Computed Properties

extension WorkflowRunModel {
    var isCompleted: Bool {
        status == "completed"
    }

    var isFailed: Bool {
        status == "failed"
    }

    var isRunning: Bool {
        status == "running"
    }

    /// Parsed step outputs
    var stepOutputs: [StepOutput]? {
        guard let json = stepOutputsJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([StepOutput].self, from: data)
    }
}

// MARK: - Supporting Types

struct StepOutput: Codable, Hashable {
    let stepName: String
    let output: String
    let timestamp: Date
}

// MARK: - Sendable Conformance

extension WorkflowRunModel: Sendable {}
extension StepOutput: Sendable {}
