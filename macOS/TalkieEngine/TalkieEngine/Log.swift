//
//  Log.swift
//  TalkieEngine
//
//  Simple logging that actually shows values
//

import Foundation

/// Debug log - just prints, no privacy BS
func dlog(_ message: String, file: String = #file, line: Int = #line) {
    let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    print("[\(filename):\(line)] \(message)")
}
