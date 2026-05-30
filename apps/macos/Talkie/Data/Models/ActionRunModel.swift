//
//  ActionRunModel.swift
//  Talkie
//
//  Canonical run model for the Actions workbench.
//

import Foundation
import GRDB

struct ActionRunModel: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var actionId: String
    var actionKind: Kind
    var title: String
    var inputPackageId: UUID?
    var status: Status
    var originDeviceId: String?
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var summary: String?
    var primaryResult: String?
    var errorMessage: String?
    var errorDetails: String?

    enum Kind: String, Codable, Hashable, Sendable {
        case workflow
        case skill
        case agentCommand
    }

    enum Status: String, Codable, Hashable, Sendable {
        case queued
        case running
        case completed
        case failed
        case cancelled
    }

    init(
        id: UUID = UUID(),
        actionId: String,
        actionKind: Kind,
        title: String,
        inputPackageId: UUID? = nil,
        status: Status = .queued,
        originDeviceId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        summary: String? = nil,
        primaryResult: String? = nil,
        errorMessage: String? = nil,
        errorDetails: String? = nil
    ) {
        self.id = id
        self.actionId = actionId
        self.actionKind = actionKind
        self.title = title
        self.inputPackageId = inputPackageId
        self.status = status
        self.originDeviceId = originDeviceId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.summary = summary
        self.primaryResult = primaryResult
        self.errorMessage = errorMessage
        self.errorDetails = errorDetails
    }
}

extension ActionRunModel: FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_runs"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let actionId = Column(CodingKeys.actionId)
        static let actionKind = Column(CodingKeys.actionKind)
        static let title = Column(CodingKeys.title)
        static let inputPackageId = Column(CodingKeys.inputPackageId)
        static let status = Column(CodingKeys.status)
        static let originDeviceId = Column(CodingKeys.originDeviceId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let startedAt = Column(CodingKeys.startedAt)
        static let completedAt = Column(CodingKeys.completedAt)
        static let summary = Column(CodingKeys.summary)
        static let primaryResult = Column(CodingKeys.primaryResult)
        static let errorMessage = Column(CodingKeys.errorMessage)
        static let errorDetails = Column(CodingKeys.errorDetails)
    }
}

extension ActionRunModel {
    var isRunning: Bool {
        status == .queued || status == .running
    }

    var isFailed: Bool {
        status == .failed
    }
}
