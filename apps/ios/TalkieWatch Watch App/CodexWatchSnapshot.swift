//
//  CodexWatchSnapshot.swift
//  TalkieWatch
//
//  A compact project catalogue published by iPhone through WatchConnectivity.
//

import Foundation

struct CodexWatchSnapshot: Equatable {
    let revision: Int
    let hostID: String
    let selectedTaskID: String?
    let channels: [CodexWatchChannel]

    init?(propertyList: [String: Any]) {
        let revision: Int
        if let value = propertyList["revision"] as? Int {
            revision = value
        } else if let value = propertyList["revision"] as? NSNumber {
            revision = value.intValue
        } else {
            return nil
        }

        guard revision >= 0,
              let hostID = propertyList["hostID"] as? String,
              let rawChannels = propertyList["channels"] as? [[String: Any]] else {
            return nil
        }

        var taskIDs = Set<String>()
        let channels = rawChannels.compactMap(CodexWatchChannel.init(propertyList:)).filter {
            taskIDs.insert($0.taskID).inserted
        }

        let normalizedHostID = hostID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHostID.isEmpty || channels.isEmpty else { return nil }

        self.revision = revision
        self.hostID = normalizedHostID
        self.channels = channels

        if let selectedTaskID = propertyList["selectedTaskID"] as? String,
           channels.contains(where: { $0.taskID == selectedTaskID }) {
            self.selectedTaskID = selectedTaskID
        } else {
            self.selectedTaskID = nil
        }
    }
}
