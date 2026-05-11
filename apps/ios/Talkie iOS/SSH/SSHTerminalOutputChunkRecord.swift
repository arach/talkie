//
//  SSHTerminalOutputChunkRecord.swift
//  Talkie iOS
//
//  Ordered record of terminal output chunks for renderer debugging.
//

import Foundation

struct SSHTerminalOutputChunkRecord: Codable, Equatable {
    let sequence: Int
    let byteCount: Int
    let data: Data

    init(sequence: Int, data: Data) {
        self.sequence = sequence
        self.byteCount = data.count
        self.data = data
    }
}
