//
//  TabEnvResolver.swift
//  Talkie
//
//  Resolves environment variables for console tab sessions.
//  Supports ${env:NAME}, ${file:PATH:KEY}, ${keychain:SERVICE} placeholders.
//

import Foundation
import Security

enum TabEnvResolver {

    struct ResolutionResult: Sendable {
        var resolved: [String: String]
        var errors: [String]
    }

    static func resolve(
        tabEnv: [String: String],
        globalEnv: [String: String],
        secretsFiles: [String],
        processEnv: [String: String] = ProcessInfo.processInfo.environment
    ) -> ResolutionResult {
        var merged: [String: String] = [:]
        var errors: [String] = []

        for (key, value) in processEnv {
            merged[key] = value
        }

        for (key, value) in globalEnv {
            merged[key] = value
        }

        for path in secretsFiles {
            let expanded = (path as NSString).expandingTildeInPath
            if let contents = try? String(contentsOfFile: expanded, encoding: .utf8) {
                let dotenv = parseDotenv(contents)
                for (key, value) in dotenv {
                    merged[key] = value
                }
            }
        }

        for (key, rawValue) in tabEnv {
            let result = resolvePlaceholder(rawValue, processEnv: processEnv)
            if let value = result.value {
                merged[key] = value
            } else if let error = result.error {
                errors.append("\(key): \(error)")
            }
        }

        return ResolutionResult(resolved: merged, errors: errors)
    }

    private struct PlaceholderResult {
        var value: String?
        var error: String?
    }

    private static func resolvePlaceholder(
        _ value: String,
        processEnv: [String: String]
    ) -> PlaceholderResult {
        if value.hasPrefix("${env:") && value.hasSuffix("}") {
            let envKey = String(value.dropFirst(6).dropLast(1))
            guard let resolved = processEnv[envKey] else {
                return PlaceholderResult(error: "Environment variable \(envKey) not found")
            }
            return PlaceholderResult(value: resolved)
        }

        if value.hasPrefix("${file:") && value.hasSuffix("}") {
            let inner = String(value.dropFirst(7).dropLast(1))
            let parts = inner.components(separatedBy: ":")
            guard parts.count == 2 else {
                return PlaceholderResult(error: "Invalid file reference: expected ${file:PATH:KEY}")
            }
            let path = (parts[0] as NSString).expandingTildeInPath
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                return PlaceholderResult(error: "Cannot read file: \(parts[0])")
            }
            let dotenv = parseDotenv(contents)
            guard let resolved = dotenv[parts[1]] else {
                return PlaceholderResult(error: "Key \(parts[1]) not found in \(parts[0])")
            }
            return PlaceholderResult(value: resolved)
        }

        if value.hasPrefix("${keychain:") && value.hasSuffix("}") {
            let service = String(value.dropFirst(11).dropLast(1))
            guard let resolved = readKeychain(service: service) else {
                return PlaceholderResult(error: "Keychain item '\(service)' not found")
            }
            return PlaceholderResult(value: resolved)
        }

        return PlaceholderResult(value: value)
    }

    private static func parseDotenv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<equalsIndex]
                .trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespaces)

            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            result[key] = value
        }
        return result
    }

    private static func readKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "jdi.talkie.core",
            kSecAttrAccount as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
