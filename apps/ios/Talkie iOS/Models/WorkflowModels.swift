//
//  WorkflowModels.swift
//  Talkie iOS
//
//  Shared data shapes for the workflows hub and WorkflowsStore.
//

import Foundation

struct WorkflowTemplate: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let blurb: String
    let icon: String
}

struct WorkflowSchedule: Identifiable, Equatable, Codable {
    let id: String
    let templateID: String
    let templateName: String
    let cadence: String
    let nextRunLabel: String
}

struct WorkflowHistoryEntry: Identifiable, Equatable, Codable {
    enum Outcome: Equatable, Codable {
        case success
        case failure(String)
    }

    let id: String
    let templateName: String
    let target: String?
    let timestampLabel: String
    let outcome: Outcome
}
