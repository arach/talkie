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
    let intent: String?

    init(
        id: String,
        name: String,
        icon: String,
        color: Color,
        workflowId: String? = nil,
        intent: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.workflowId = workflowId
        self.intent = intent
    }

    static let go = WatchPreset(
        id: "go",
        name: "Go",
        icon: "bolt.fill",
        color: .red
    )

    static let ai = WatchPreset(
        id: "ai",
        name: "AI",
        icon: "sparkles",
        color: .cyan,
        intent: "ai"
    )

    static let thought = WatchPreset(
        id: "thought",
        name: "Thought",
        icon: "note.text",
        color: .purple,
        workflowId: "thought"
    )

    static let meeting = WatchPreset(
        id: "meeting",
        name: "Meeting",
        icon: "person.2.fill",
        color: .blue,
        workflowId: "meeting"
    )

    static let task = WatchPreset(
        id: "task",
        name: "Task",
        icon: "checkmark.circle.fill",
        color: .green,
        workflowId: "task"
    )

    static let presets: [WatchPreset] = [
        go,
        ai,
        thought,
        meeting,
        task
    ]
}
