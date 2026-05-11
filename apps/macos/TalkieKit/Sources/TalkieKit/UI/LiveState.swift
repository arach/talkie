//
//  LiveState.swift
//  TalkieKit
//
//  Recording state for TalkieAgent
//

import Foundation

public enum LiveState: String {
    case idle
    case listening
    case transcribing
    case routing
    case refining    // Visual-only: LLM auto-refine in progress (sub-phase of routing)
}
