//
//  ActionInputPackage.swift
//  Talkie
//
//  Resolved input snapshot for an action run.
//

import Foundation
import GRDB

struct ActionInputPackage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var actionRunId: UUID
    var parametersJSON: String
    var derivedContextRefsJSON: String
    var renderLogicVersion: String
    var renderedSnapshot: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        actionRunId: UUID,
        parametersJSON: String = "{}",
        derivedContextRefsJSON: String = "{}",
        renderLogicVersion: String = "action-workbench-v1",
        renderedSnapshot: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.actionRunId = actionRunId
        self.parametersJSON = parametersJSON
        self.derivedContextRefsJSON = derivedContextRefsJSON
        self.renderLogicVersion = renderLogicVersion
        self.renderedSnapshot = renderedSnapshot
        self.createdAt = createdAt
    }
}

extension ActionInputPackage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_input_packages"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let actionRunId = Column(CodingKeys.actionRunId)
        static let parametersJSON = Column(CodingKeys.parametersJSON)
        static let derivedContextRefsJSON = Column(CodingKeys.derivedContextRefsJSON)
        static let renderLogicVersion = Column(CodingKeys.renderLogicVersion)
        static let renderedSnapshot = Column(CodingKeys.renderedSnapshot)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
