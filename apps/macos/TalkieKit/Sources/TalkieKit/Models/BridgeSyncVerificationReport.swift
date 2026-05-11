//
//  BridgeSyncVerificationReport.swift
//  TalkieKit
//
//  Result of Core Data <-> GRDB bridge consistency verification.
//

import Foundation

public struct BridgeSyncVerificationReport: Codable, Sendable {
    public let checkedAt: Date
    public let since: Date?
    public let sampledCoreDataCount: Int
    public let sampledGRDBCount: Int
    public let missingInGRDBCount: Int
    public let staleInGRDBCount: Int
    public let extraInGRDBCount: Int

    public var isConsistent: Bool {
        missingInGRDBCount == 0 && staleInGRDBCount == 0
    }

    public init(
        checkedAt: Date,
        since: Date?,
        sampledCoreDataCount: Int,
        sampledGRDBCount: Int,
        missingInGRDBCount: Int,
        staleInGRDBCount: Int,
        extraInGRDBCount: Int
    ) {
        self.checkedAt = checkedAt
        self.since = since
        self.sampledCoreDataCount = sampledCoreDataCount
        self.sampledGRDBCount = sampledGRDBCount
        self.missingInGRDBCount = missingInGRDBCount
        self.staleInGRDBCount = staleInGRDBCount
        self.extraInGRDBCount = extraInGRDBCount
    }
}
