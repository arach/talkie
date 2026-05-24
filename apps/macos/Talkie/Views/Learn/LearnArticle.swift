//
//  LearnArticle.swift
//  Talkie macOS
//
//  Native manifest model for the Learn knowledge base. The article body
//  is intentionally web-rendered, but the index, search, and bridge
//  actions stay native so Learn remains an app surface, not a browser.
//

import Foundation

struct LearnArticle: Identifiable, Hashable {
    let id: String
    let eyebrow: String
    let title: String
    let summary: String
    let tags: [String]
    let shortcuts: [LearnShortcut]
    let actions: [LearnArticleAction]
    let relatedIDs: [String]
    let fileURL: URL?
    let bodyMarkdown: String?
    let fallback: LearnArticleFallback

    init(
        id: String,
        eyebrow: String,
        title: String,
        summary: String,
        tags: [String],
        shortcuts: [LearnShortcut],
        actions: [LearnArticleAction],
        relatedIDs: [String],
        fileURL: URL?,
        bodyMarkdown: String? = nil,
        fallback: LearnArticleFallback
    ) {
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.summary = summary
        self.tags = tags
        self.shortcuts = shortcuts
        self.actions = actions
        self.relatedIDs = relatedIDs
        self.fileURL = fileURL
        self.bodyMarkdown = bodyMarkdown
        self.fallback = fallback
    }

    var searchableText: String {
        ([id, eyebrow, title, summary, bodyMarkdown ?? ""] + tags + shortcuts.map(\.keys) + actions.map(\.title))
            .joined(separator: " ")
            .localizedLowercase
    }
}

struct LearnShortcut: Hashable, Decodable {
    let keys: String
    let label: String
}

struct LearnArticleAction: Identifiable, Hashable, Decodable {
    var id: String { url }

    let title: String
    let detail: String
    let url: String
}

struct LearnArticleMetadata: Hashable {
    let label: String
    let value: String
}

struct LearnArticleFallback: Hashable {
    let metadata: [LearnArticleMetadata]
    let lead: String
    /// Optional callout shown between the article body and the action
    /// rows. Pass both fields when the article has something specific
    /// to say at that boundary; leave nil to skip the section entirely.
    /// We deliberately don't default to a generic "Native bridge" /
    /// "use the action rows" line — that's filler that adds visual
    /// weight without information.
    let calloutTitle: String?
    let calloutBody: String?
    let steps: [String]
}

enum LearnArticleStore {
    static func load() -> [LearnArticle] {
        if let articles = loadPreRenderedSite(), !articles.isEmpty {
            return articles
        }
        if let articles = loadMarkdownContent(), !articles.isEmpty {
            return articles
        }
        return fallbackArticles
    }

    private static func learnRootURL() -> URL? {
        guard let learnRoot = Bundle.main.resourceURL?.appending(path: "Resources/Learn"),
              FileManager.default.fileExists(atPath: learnRoot.path) else {
            return nil
        }
        return learnRoot
    }

    private static func loadPreRenderedSite() -> [LearnArticle]? {
        guard let learnRoot = learnRootURL() else { return nil }
        let siteRoot = learnRoot.appending(path: "Site")
        let indexURL = siteRoot.appending(path: "index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(BundledLearnIndex.self, from: data) else {
            return nil
        }

        return index.articles.map { item in
            let fileURL: URL?
            if let file = item.file {
                let candidate = siteRoot.appending(path: file)
                fileURL = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            } else {
                fileURL = nil
            }

            return LearnArticle(
                id: item.id,
                eyebrow: item.eyebrow ?? "Learn",
                title: item.title,
                summary: item.summary,
                tags: item.tags ?? [],
                shortcuts: item.shortcuts ?? [],
                actions: item.actions ?? [],
                relatedIDs: item.relatedIDs ?? [],
                fileURL: fileURL,
                fallback: LearnArticleFallback(
                    metadata: item.metadata ?? [],
                    lead: item.lead ?? item.summary,
                    calloutTitle: item.calloutTitle,
                    calloutBody: item.calloutBody,
                    steps: item.steps ?? []
                )
            )
        }
    }

    private static func loadMarkdownContent() -> [LearnArticle]? {
        guard let learnRoot = learnRootURL() else { return nil }
        let contentRoot = learnRoot.appending(path: "Content")
        let indexURL = contentRoot.appending(path: "index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(ContentIndex.self, from: data) else {
            return nil
        }

        let categoryLabels = Dictionary(uniqueKeysWithValues: index.categories.map { ($0.id, $0.label) })
        return index.articles.compactMap { item in
            let articleURL = contentRoot.appending(path: item.path)
            guard let source = try? String(contentsOf: articleURL, encoding: .utf8),
                  let parsed = MarkdownArticle(source: source) else {
                return nil
            }

            let shortcuts = parsed.shortcuts.map {
                LearnShortcut(keys: $0.chord, label: $0.action)
            }
            let actions = parsed.surfaces.map {
                LearnArticleAction(title: $0.label, detail: "Open in Talkie", url: $0.url)
            }
            let categoryLabel = categoryLabels[parsed.category] ?? parsed.category.localizedCapitalized
            return LearnArticle(
                id: parsed.id,
                eyebrow: categoryLabel,
                title: parsed.title,
                summary: parsed.summary,
                tags: parsed.tags,
                shortcuts: shortcuts,
                actions: actions,
                relatedIDs: parsed.related,
                fileURL: nil,
                bodyMarkdown: parsed.body,
                fallback: LearnArticleFallback(
                    metadata: [
                        LearnArticleMetadata(label: "Category", value: categoryLabel),
                        LearnArticleMetadata(label: "Updated", value: parsed.updated),
                        LearnArticleMetadata(label: "Source", value: "Local Markdown")
                    ],
                    lead: parsed.firstParagraph ?? parsed.summary,
                    calloutTitle: parsed.calloutTitle,
                    calloutBody: parsed.calloutBody,
                    steps: []
                )
            )
        }
    }

    private struct BundledLearnIndex: Decodable {
        let articles: [BundledLearnArticle]
    }

    private struct BundledLearnArticle: Decodable {
        let id: String
        let eyebrow: String?
        let title: String
        let summary: String
        let tags: [String]?
        let shortcuts: [LearnShortcut]?
        let actions: [LearnArticleAction]?
        let relatedIDs: [String]?
        let file: String?
        let metadata: [LearnArticleMetadata]?
        let lead: String?
        let calloutTitle: String?
        let calloutBody: String?
        let steps: [String]?

        enum CodingKeys: String, CodingKey {
            case id, eyebrow, title, summary, tags, shortcuts, actions, file, metadata, lead, steps
            case relatedIDs = "related"
            case calloutTitle
            case calloutBody
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            eyebrow = try container.decodeIfPresent(String.self, forKey: .eyebrow)
            title = try container.decode(String.self, forKey: .title)
            summary = try container.decode(String.self, forKey: .summary)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            shortcuts = try container.decodeIfPresent([LearnShortcut].self, forKey: .shortcuts)
            actions = try container.decodeIfPresent([LearnArticleAction].self, forKey: .actions)
            relatedIDs = try container.decodeIfPresent([String].self, forKey: .relatedIDs)
            file = try container.decodeIfPresent(String.self, forKey: .file)
            lead = try container.decodeIfPresent(String.self, forKey: .lead)
            calloutTitle = try container.decodeIfPresent(String.self, forKey: .calloutTitle)
            calloutBody = try container.decodeIfPresent(String.self, forKey: .calloutBody)
            steps = try container.decodeIfPresent([String].self, forKey: .steps)

            if let keyed = try container.decodeIfPresent([String: String].self, forKey: .metadata) {
                metadata = keyed
                    .sorted { $0.key < $1.key }
                    .map { LearnArticleMetadata(label: $0.key, value: $0.value) }
            } else {
                metadata = nil
            }
        }
    }

    private struct ContentIndex: Decodable {
        let categories: [ContentCategory]
        let articles: [ContentArticle]
    }

    private struct ContentCategory: Decodable {
        let id: String
        let label: String
    }

    private struct ContentArticle: Decodable {
        let id: String
        let path: String
    }

    private struct MarkdownArticle {
        let id: String
        let title: String
        let summary: String
        let category: String
        let tags: [String]
        let updated: String
        let surfaces: [Surface]
        let shortcuts: [Shortcut]
        let related: [String]
        /// Optional per-article callout. Both fields must be set for
        /// the renderer to show the NOTE block. Use snake_case keys
        /// in the frontmatter: `callout_title:` + `callout_body:`.
        let calloutTitle: String?
        let calloutBody: String?
        let body: String

        init?(source: String) {
            guard source.hasPrefix("---"),
                  let closing = source.range(of: "\n---", range: source.index(source.startIndex, offsetBy: 3)..<source.endIndex) else {
                return nil
            }

            let frontMatterStart = source.index(source.startIndex, offsetBy: 3)
            let frontMatter = String(source[frontMatterStart..<closing.lowerBound])
            let bodyStart = source.index(closing.upperBound, offsetBy: 0)
            body = String(source[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

            let fields = MarkdownFrontMatter(frontMatter)
            guard let id = fields.scalar("id"),
                  let title = fields.scalar("title"),
                  let summary = fields.scalar("summary"),
                  let category = fields.scalar("category"),
                  let updated = fields.scalar("updated") else {
                return nil
            }

            self.id = id
            self.title = title
            self.summary = summary
            self.category = category
            self.tags = fields.inlineList("tags")
            self.updated = updated
            surfaces = fields.objectList("surfaces").compactMap(Surface.init(fields:))
            shortcuts = fields.objectList("shortcuts").compactMap(Shortcut.init(fields:))
            related = fields.inlineList("related")
            calloutTitle = fields.scalar("callout_title")
            calloutBody = fields.scalar("callout_body")
        }

        var firstParagraph: String? {
            body
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { paragraph in
                    !paragraph.isEmpty && !paragraph.hasPrefix("#") && !paragraph.hasPrefix("- ")
                }
        }

        struct Surface {
            let label: String
            let url: String

            init?(fields: [String: String]) {
                guard let label = fields["label"], let url = fields["url"] else { return nil }
                self.label = label
                self.url = url
            }
        }

        struct Shortcut {
            let chord: String
            let action: String

            init?(fields: [String: String]) {
                guard let chord = fields["chord"], let action = fields["action"] else { return nil }
                self.chord = chord
                self.action = action
            }
        }
    }

    private struct MarkdownFrontMatter {
        private let lines: [String]

        init(_ source: String) {
            lines = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
        }

        func scalar(_ key: String) -> String? {
            guard let value = rawValue(for: key), !value.hasPrefix("[") else { return nil }
            return value.unquoted
        }

        func inlineList(_ key: String) -> [String] {
            guard let value = rawValue(for: key),
                  value.hasPrefix("["),
                  value.hasSuffix("]") else {
                return []
            }
            return String(value.dropFirst().dropLast())
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).unquoted }
                .filter { !$0.isEmpty }
        }

        func objectList(_ key: String) -> [[String: String]] {
            guard let startIndex = lines.firstIndex(where: { $0 == "\(key):" }) else { return [] }
            var objects: [[String: String]] = []
            for line in lines.dropFirst(startIndex + 1) {
                guard line.hasPrefix("  - ") else {
                    if !line.hasPrefix("    ") { break }
                    continue
                }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("- {"), trimmed.hasSuffix("}") else { continue }
                let objectBody = trimmed
                    .dropFirst(3)
                    .dropLast()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                objects.append(parseInlineObject(String(objectBody)))
            }
            return objects
        }

        private func rawValue(for key: String) -> String? {
            let prefix = "\(key):"
            guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
            return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func parseInlineObject(_ objectBody: String) -> [String: String] {
            var values: [String: String] = [:]
            for pair in objectBody.commaSeparatedRespectingQuotes {
                let pieces = pair.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { continue }
                let key = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines).unquoted
                values[key] = value
            }
            return values
        }
    }
}

private extension String {
    var unquoted: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              trimmed.first == "\"",
              trimmed.last == "\"" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    var commaSeparatedRespectingQuotes: [String] {
        var parts: [String] = []
        var current = ""
        var isQuoted = false

        for character in self {
            switch character {
            case "\"":
                isQuoted.toggle()
                current.append(character)
            case "," where !isQuoted:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }
        return parts
    }
}

private extension LearnArticleStore {
    static let fallbackArticles: [LearnArticle] = [
        LearnArticle(
            id: "tray-shelf",
            eyebrow: "Capture",
            title: "Tray Shelf and Screenshots",
            summary: "Use the tray to keep screen captures with the work they explain, then jump into the larger viewer when you need selection, copy, or drag.",
            tags: ["tray", "screenshots", "capture", "hyper", "shelf"],
            shortcuts: [
                LearnShortcut(keys: "Hyper+S", label: "Start a screen capture"),
                LearnShortcut(keys: "Hyper+T", label: "Toggle Tray Shelf")
            ],
            actions: [
                LearnArticleAction(title: "Open Tray", detail: "Show the larger capture viewer", url: "talkie://tray"),
                LearnArticleAction(title: "Open Shelf", detail: "Toggle the quick shelf", url: "talkie://tray/shelf"),
                LearnArticleAction(title: "Shortcut Settings", detail: "Manage capture bindings", url: "talkie://settings/surface")
            ],
            relatedIDs: ["hyper-keys", "privacy-local-sync"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Surface", value: "Tray"),
                    LearnArticleMetadata(label: "Source", value: "Screenshots"),
                    LearnArticleMetadata(label: "Mode", value: "Local")
                ],
                lead: "The tray is the holding surface for screenshots and clips that belong with your current work. It keeps capture material close without turning every screenshot into a standalone note.",
                calloutTitle: "Bridge rule",
                calloutBody: "The web article teaches the capture flow; the action rows jump back to the real tray and shortcut settings.",
                steps: [
                    "Press Hyper+S to start a capture chord.",
                    "Choose region, window, or fullscreen from the capture overlay.",
                    "Use Hyper+T when you want the shelf without opening the full viewer."
                ]
            )
        ),
        LearnArticle(
            id: "hyper-keys",
            eyebrow: "Shortcuts",
            title: "Hyper Keys",
            summary: "Talkie's global shortcuts are grouped around capture, dictation, paste, and tray access so muscle memory stays compact.",
            tags: ["hotkeys", "shortcuts", "hyper", "keyboard", "surface"],
            shortcuts: [
                LearnShortcut(keys: "Hyper+S", label: "Capture"),
                LearnShortcut(keys: "Hyper+T", label: "Tray Shelf")
            ],
            actions: [
                LearnArticleAction(title: "Manage Shortcuts", detail: "Open Surface settings", url: "talkie://settings/surface")
            ],
            relatedIDs: ["tray-shelf", "compose-diffs"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Group", value: "Surface"),
                    LearnArticleMetadata(label: "Scope", value: "Global"),
                    LearnArticleMetadata(label: "Status", value: "Registered")
                ],
                lead: "Hyper chords keep Talkie's surface controls distinct from normal app shortcuts. Capture and tray commands stay reachable even when another app is frontmost.",
                calloutTitle: "Keep the chord small",
                calloutBody: "Use Hyper for Talkie-wide commands, then let the destination surface handle the detailed interaction.",
                steps: [
                    "Open Surface settings to review registered bindings.",
                    "Keep capture and tray shortcuts adjacent so they are easy to remember.",
                    "Use the tray viewer when you need more space than the shelf gives you."
                ]
            )
        ),
        LearnArticle(
            id: "compose-diffs",
            eyebrow: "Compose",
            title: "Compose Edits and Diffs",
            summary: "Dictate an edit, review the diff, and accept only the changes you want before they become final text.",
            tags: ["compose", "diff", "drafts", "editing", "dictation"],
            shortcuts: [],
            actions: [
                LearnArticleAction(title: "Open Compose", detail: "Jump to the draft editor", url: "talkie://open/compose")
            ],
            relatedIDs: ["workflows-triggers", "llm-providers"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Surface", value: "Compose"),
                    LearnArticleMetadata(label: "Input", value: "Voice"),
                    LearnArticleMetadata(label: "Review", value: "Diff")
                ],
                lead: "Compose turns spoken edits into a reviewable change set. The point is not to trust the model blindly; it is to make revision faster while keeping the final say in front of you.",
                calloutTitle: "Review before commit",
                calloutBody: "Learn can explain the model-assisted edit flow, but accepting the text always happens in native Compose.",
                steps: [
                    "Open Compose with existing text or a fresh draft.",
                    "Dictate the change you want.",
                    "Review the inline diff before accepting."
                ]
            )
        ),
        LearnArticle(
            id: "workflows-triggers",
            eyebrow: "Automation",
            title: "Workflows and Triggers",
            summary: "Workflows turn transcripts into summaries, actions, reminders, files, notifications, and other structured outputs.",
            tags: ["workflows", "triggers", "automation", "twf"],
            shortcuts: [],
            actions: [
                LearnArticleAction(title: "Open Workflows", detail: "Browse and run workflows", url: "talkie://open/workflows")
            ],
            relatedIDs: ["context-rules", "console-agents"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Format", value: "TWF"),
                    LearnArticleMetadata(label: "Run", value: "Manual or trigger"),
                    LearnArticleMetadata(label: "Output", value: "Structured")
                ],
                lead: "A workflow is a small pipeline. It can transcribe, ask an LLM, transform data, create reminders, save files, speak results, or call services.",
                calloutTitle: "Source of truth",
                calloutBody: "Workflow behavior lives in TWF. Learn should explain the shape and link to the real editor for changes.",
                steps: [
                    "Start with a workflow template that matches the outcome.",
                    "Check each step's input and output variables.",
                    "Run manually first, then attach triggers when the result is stable."
                ]
            )
        ),
        LearnArticle(
            id: "context-rules",
            eyebrow: "Context",
            title: "Context Rules",
            summary: "Rules let Talkie adapt capture and post-processing to the app or situation where dictation happened.",
            tags: ["context", "rules", "apps", "automation"],
            shortcuts: [],
            actions: [
                LearnArticleAction(title: "Manage Context Rules", detail: "Open the context surface", url: "talkie://open/context-rules")
            ],
            relatedIDs: ["workflows-triggers", "privacy-local-sync"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Matcher", value: "Foreground app"),
                    LearnArticleMetadata(label: "Use", value: "Post-processing"),
                    LearnArticleMetadata(label: "Scope", value: "Per app")
                ],
                lead: "Context rules let Talkie notice where a capture happened and choose a more appropriate transformation. A rule can target one app, several apps, or an everywhere-except list.",
                calloutTitle: "Keep rules explainable",
                calloutBody: "Rules should describe when they run and what they change. Learn can expose that map before users edit anything.",
                steps: [
                    "Pick the app or context that should change behavior.",
                    "Choose the workflow or transformation to run.",
                    "Test with a recent capture before enabling broadly."
                ]
            )
        ),
        LearnArticle(
            id: "console-agents",
            eyebrow: "Console",
            title: "Console and Agents",
            summary: "The console is Talkie's local workspace for agent sessions, shell tasks, workflow debugging, and project-aware assistance.",
            tags: ["console", "agents", "codex", "claude", "terminal"],
            shortcuts: [],
            actions: [
                LearnArticleAction(title: "Open Console", detail: "Jump to agent sessions", url: "talkie://open/console")
            ],
            relatedIDs: ["workflows-triggers", "llm-providers"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Surface", value: "Console"),
                    LearnArticleMetadata(label: "Tabs", value: "Agents and shells"),
                    LearnArticleMetadata(label: "Mode", value: "Local")
                ],
                lead: "The console keeps helper sessions close to the app. It is useful for inspecting workflow files, running local tools, and handing focused work to project-aware agents.",
                calloutTitle: "Agent work stays scoped",
                calloutBody: "Learn can link into the console, but agent actions stay inside the native console where project context and permissions are visible.",
                steps: [
                    "Open the console from Learn or Home.",
                    "Choose an existing tab or start a project-aware session.",
                    "Use notes and prompts to keep each agent task bounded."
                ]
            )
        ),
        LearnArticle(
            id: "llm-providers",
            eyebrow: "AI",
            title: "LLM Providers",
            summary: "Talkie can use on-device, local, or API-backed models depending on the feature and the privacy/performance tradeoff you choose.",
            tags: ["llm", "providers", "openai", "anthropic", "local", "apple"],
            shortcuts: [],
            actions: [
                LearnArticleAction(title: "Open AI Providers", detail: "Configure keys and defaults", url: "talkie://settings/ai-providers")
            ],
            relatedIDs: ["privacy-local-sync", "compose-diffs"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Providers", value: "Apple · Anthropic · OpenAI · Local"),
                    LearnArticleMetadata(label: "Keys", value: "User-owned"),
                    LearnArticleMetadata(label: "Scope", value: "Per feature")
                ],
                lead: "Different work wants different models. Lightweight local work can stay private; more complex reasoning can use a configured API provider.",
                calloutTitle: "Provider choice is product behavior",
                calloutBody: "Learn should explain the tradeoff, then bridge to settings where the actual key and model choices live.",
                steps: [
                    "Open AI Providers and add any API keys you want Talkie to use.",
                    "Choose defaults for features that need model assistance.",
                    "Prefer local or on-device paths for sensitive material when they are good enough."
                ]
            )
        ),
        LearnArticle(
            id: "privacy-local-sync",
            eyebrow: "Privacy",
            title: "Privacy, Local Work, and Sync",
            summary: "Talkie is designed around local capture first, with explicit sync and provider choices for the pieces that leave the machine.",
            tags: ["privacy", "local", "sync", "icloud", "providers"],
            shortcuts: [],
            actions: [
                LearnArticleAction(title: "Open Sync Settings", detail: "Review iCloud and iOS sync", url: "talkie://settings/sync"),
                LearnArticleAction(title: "Open Storage", detail: "Review local data", url: "talkie://settings/storage")
            ],
            relatedIDs: ["llm-providers", "tray-shelf"],
            fileURL: nil,
            fallback: LearnArticleFallback(
                metadata: [
                    LearnArticleMetadata(label: "Default", value: "Local first"),
                    LearnArticleMetadata(label: "Sync", value: "iCloud"),
                    LearnArticleMetadata(label: "Network", value: "Explicit providers")
                ],
                lead: "Capture starts locally. Sync, provider calls, and bridge services are separate choices so you can understand what is stored, what is shared, and why.",
                calloutTitle: "No mystery transport",
                calloutBody: "The KB should make every boundary visible, then send the user to the native settings that control it.",
                steps: [
                    "Review sync settings for iCloud and iOS handoff.",
                    "Review storage settings for local files and database inventory.",
                    "Review AI provider settings before sending text to an API model."
                ]
            )
        )
    ]
}
