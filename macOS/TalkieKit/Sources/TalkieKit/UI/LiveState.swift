//
//  LiveState.swift
//  TalkieKit
//
//  Recording state for TalkieLive
//

import Foundation

public enum LiveState: String {
    case idle
    case listening
    case transcribing
    case routing
}
