//
//  CloudKitContainerProvider.swift
//  Talkie iOS
//
//  Creates CloudKit containers only after runtime configuration validation.
//

import CloudKit
import Foundation
import TalkieMobileKit

enum CloudKitContainerProvider {
    static var containerIdentifier: String {
        TalkieMobileRuntimeIdentifiers.cloudKitContainerIdentifier
    }

    static var unavailableReason: String? {
        let identifier = containerIdentifier

        guard !identifier.contains("$(") else {
            return "CloudKit container build setting was not resolved"
        }

        guard identifier.hasPrefix("iCloud.") else {
            return "CloudKit container identifier is invalid: \(identifier)"
        }

        guard isCodeSigningAllowed else {
            return "CloudKit requires a signed build"
        }

        return nil
    }

    static func container() -> CKContainer? {
        guard unavailableReason == nil else {
            return nil
        }

        return CKContainer(identifier: containerIdentifier)
    }

    private static var isCodeSigningAllowed: Bool {
        let value = infoDictionaryString("TalkieCodeSigningAllowed", fallback: "NO")
        return value == "YES"
    }

    private static func infoDictionaryString(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return fallback
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
