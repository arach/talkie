//
//  BuildInfo.swift
//  Talkie iOS
//
//  Build info - git info is embedded at build time via build phase script
//  or defaults to placeholder values.
//

import Foundation

enum BuildInfo {
    /// Git branch - set via GIT_BRANCH build setting or defaults to "dev"
    static var gitBranch: String {
        Bundle.main.infoDictionary?["GitBranch"] as? String ?? "dev"
    }

    /// Git commit short hash - set via GIT_COMMIT build setting or defaults to "local"
    static var gitCommit: String {
        Bundle.main.infoDictionary?["GitCommit"] as? String ?? "local"
    }

    /// Build date
    static var buildDate: String {
        if let buildDateString = Bundle.main.infoDictionary?["BuildDate"] as? String {
            return buildDateString
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: Date())
    }
}
