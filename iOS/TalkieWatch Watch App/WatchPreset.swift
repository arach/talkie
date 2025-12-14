//
//  WatchPreset.swift
//  TalkieWatch
//
//  Presets for quick recording - like Timer app
//

import SwiftUI

struct WatchPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let workflowId: String?  // nil = just transcribe, no workflow

    static let presets: [WatchPreset] = [
        WatchPreset(
            id: "go",
            name: "Go",
            icon: "bolt.fill",
            color: .red,
            workflowId: nil
        ),
        WatchPreset(
            id: "thought",
            name: "Thought",
            icon: "brain.head.profile",
            color: .purple,
            workflowId: "thought"
        ),
        WatchPreset(
            id: "meeting",
            name: "Meeting",
            icon: "person.2.fill",
            color: .blue,
            workflowId: "meeting"
        ),
        WatchPreset(
            id: "task",
            name: "Task",
            icon: "checkmark.circle.fill",
            color: .green,
            workflowId: "task"
        )
    ]

    static let go = presets[0]
}
