//
//  TalkieMobileRuntimeIdentifiers.swift
//  TalkieMobileKit
//
//  Runtime identifiers injected from build settings into Info.plist.
//

import Foundation

public enum TalkieMobileRuntimeIdentifiers {
    public static var appIdentifier: String {
        infoDictionaryString("TalkieAppIdentifier", fallback: "com.example.talkie")
    }

    public static var cloudKitContainerIdentifier: String {
        infoDictionaryString("TalkieCloudKitContainerIdentifier", fallback: "iCloud.com.example.talkie")
    }

    public static var appGroupIdentifier: String {
        infoDictionaryString("TalkieAppGroupIdentifier", fallback: "group.com.example.talkie")
    }

    public static var refreshTaskIdentifier: String {
        "\(appIdentifier).refresh"
    }

    public static var syncTaskIdentifier: String {
        "\(appIdentifier).sync"
    }

    private static func infoDictionaryString(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return fallback
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// Shared App Group identifier for app and keyboard-extension data.
public var kTalkieAppGroup: String {
    TalkieMobileRuntimeIdentifiers.appGroupIdentifier
}
