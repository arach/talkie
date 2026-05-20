//
//  SkillStarterLoader.swift
//  Talkie
//
//  Loads bundled .skill.md starters from Resources/Starters/.
//  The parser (SkillFileFormat) turns each into a WorkflowDefinition that
//  the Skills surface uses as the source of truth for SAVE and RUN.
//
//  Starters without a corresponding .skill.md file fall back to the inline
//  stub data in ScopeSkillsLandingView — that fallback goes away as codex
//  ships the remaining .skill.md files.
//

import Foundation
import os

struct BundledStarter {
    let fileName: String          // e.g. "daily-standup"
    let definition: WorkflowDefinition
    let rawBody: String           // post-frontmatter content, for rendering
}

enum SkillStarterLoader {
    private static let logger = Logger(subsystem: "com.jdi.talkie", category: "SkillStarterLoader")

    static func loadBundledStarters() -> [String: BundledStarter] {
        guard let dir = startersDirectory() else { return [:] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return [:]
        }

        var byFileName: [String: BundledStarter] = [:]
        for url in contents where url.lastPathComponent.hasSuffix(".skill.md") {
            let fileName = url.lastPathComponent.replacingOccurrences(of: ".skill.md", with: "")
            do {
                let markdown = try String(contentsOf: url, encoding: .utf8)
                let definition = try parseSkillFile(markdown)
                let rawBody = extractBody(from: markdown)
                byFileName[fileName] = BundledStarter(
                    fileName: fileName,
                    definition: definition,
                    rawBody: rawBody
                )
            } catch {
                logger.error("Failed to parse \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return byFileName
    }

    private static func startersDirectory() -> URL? {
        // Folder reference doubles the path: Resources/Starters lives under
        // Bundle.main.resourceURL/Resources/ (see AppsRuntime for the same pattern).
        Bundle.main.resourceURL?.appendingPathComponent("Resources/Starters", isDirectory: true)
    }

    private static func extractBody(from markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return markdown
        }
        guard let endIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return markdown
        }

        let bodyStart = lines.index(after: endIndex)
        guard bodyStart < lines.endIndex else { return "" }
        return lines[bodyStart..<lines.endIndex]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
