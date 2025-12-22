//
//  SettingsStoryboardGenerator.swift
//  Talkie macOS
//
//  Captures screenshots of all settings pages for UI analysis
//  Includes styling analysis and grid-based composite views
//

import SwiftUI
import DebugKit
import RegexBuilder

/// Settings pages to capture (subset of SettingsSection with Int raw values for StoryboardGenerator)
enum SettingsPage: Int, CaseIterable, Hashable {
    case appearance = 0
    case dictationCapture = 1
    case dictationOutput = 2
    case quickActions = 3
    case quickOpen = 4
    case autoRun = 5
    case aiProviders = 6
    case transcriptionModels = 7
    case llmModels = 8
    case database = 9
    case files = 10
    case permissions = 11
    case debugInfo = 12

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .dictationCapture: return "Dictation Capture"
        case .dictationOutput: return "Dictation Output"
        case .quickActions: return "Quick Actions"
        case .quickOpen: return "Quick Open"
        case .autoRun: return "Auto-Run"
        case .aiProviders: return "AI Providers"
        case .transcriptionModels: return "Transcription Models"
        case .llmModels: return "LLM Models"
        case .database: return "Database"
        case .files: return "Files"
        case .permissions: return "Permissions"
        case .debugInfo: return "Debug Info"
        }
    }

    var category: String {
        switch self {
        case .appearance: return "Appearance"
        case .dictationCapture, .dictationOutput: return "Dictation"
        case .quickActions, .quickOpen, .autoRun: return "Memos"
        case .aiProviders, .transcriptionModels, .llmModels: return "AI Models"
        case .database, .files: return "Storage"
        case .permissions, .debugInfo: return "System"
        }
    }

    /// Source file for styling analysis
    var sourceFile: String {
        switch self {
        case .appearance: return "AppearanceSettings.swift"
        case .dictationCapture: return "DictationSettings.swift"
        case .dictationOutput: return "DictationSettings.swift"
        case .quickActions: return "QuickActionsSettings.swift"
        case .quickOpen: return "QuickOpenSettings.swift"
        case .autoRun: return "AutoRunSettings.swift"
        case .aiProviders: return "APISettings.swift"
        case .transcriptionModels: return "TranscriptionModelsSettingsView.swift"
        case .llmModels: return "ModelLibrarySettings.swift"
        case .database: return "StorageSettings.swift"
        case .files: return "LocalFilesSettings.swift"
        case .permissions: return "PermissionsSettings.swift"
        case .debugInfo: return "DebugSettings.swift"
        }
    }
}

// MARK: - Styling Analysis

struct StyleAnalysis {
    let page: SettingsPage
    var fonts: [String: Int] = [:]           // font pattern -> count
    var colors: [String: Int] = [:]          // color pattern -> count
    var spacing: [String: Int] = [:]         // spacing pattern -> count
    var opacity: [String: Int] = [:]         // opacity pattern -> count
    var issues: [String] = []                // detected issues

    var totalFontIssues: Int {
        fonts.filter { $0.key.contains(".system(size:") }.values.reduce(0, +)
    }

    var totalColorIssues: Int {
        colors.filter { !$0.key.contains("Theme.current") && !$0.key.contains(".accentColor") }.values.reduce(0, +)
    }

    func markdownReport() -> String {
        var report = "## \(page.title)\n"
        report += "**Category:** \(page.category) | **Source:** `\(page.sourceFile)`\n\n"

        // Fonts
        report += "### Fonts\n"
        let sortedFonts = fonts.sorted { $0.value > $1.value }
        for (pattern, count) in sortedFonts {
            let status = pattern.contains("Theme.current") ? "✅" : "⚠️"
            report += "- \(status) `\(pattern)` ×\(count)\n"
        }

        // Colors
        report += "\n### Colors\n"
        let sortedColors = colors.sorted { $0.value > $1.value }
        for (pattern, count) in sortedColors {
            let status = pattern.contains("Theme.current") || pattern.contains(".accentColor") ? "✅" : "⚠️"
            report += "- \(status) `\(pattern)` ×\(count)\n"
        }

        // Spacing
        report += "\n### Spacing\n"
        let sortedSpacing = spacing.sorted { $0.value > $1.value }
        for (pattern, count) in sortedSpacing {
            let status = pattern.contains("Spacing.") ? "✅" : "⚠️"
            report += "- \(status) `\(pattern)` ×\(count)\n"
        }

        // Opacity
        if !opacity.isEmpty {
            report += "\n### Opacity\n"
            let sortedOpacity = opacity.sorted { $0.value > $1.value }
            for (pattern, count) in sortedOpacity {
                let status = pattern.contains("Opacity.") ? "✅" : "⚠️"
                report += "- \(status) `\(pattern)` ×\(count)\n"
            }
        }

        // Issues summary
        if totalFontIssues > 0 || totalColorIssues > 0 {
            report += "\n### Issues\n"
            if totalFontIssues > 0 {
                report += "- ⚠️ **\(totalFontIssues)** hardcoded font sizes (should use Theme.current)\n"
            }
            if totalColorIssues > 0 {
                report += "- ⚠️ **\(totalColorIssues)** non-theme colors (should use Theme.current)\n"
            }
        } else {
            report += "\n### Status: ✅ On-brand\n"
        }

        return report
    }
}

@MainActor
class SettingsStoryboardGenerator {
    static let shared = SettingsStoryboardGenerator()

    private init() {}

    private lazy var generator: StoryboardGenerator<SettingsPage> = {
        // Settings window is typically 800x600+
        let screenSize = CGSize(width: 900, height: 700)

        // Define layout zones for settings
        let layoutZones: [LayoutZone] = [
            LayoutZone(
                label: "SIDEBAR",
                frame: .custom(x: 0, y: 0, width: 220, height: screenSize.height),
                color: .blue,
                style: .subtle
            ),
            LayoutZone(
                label: "CONTENT",
                frame: .custom(x: 220, y: 0, width: screenSize.width - 220, height: screenSize.height),
                color: .cyan,
                style: .subtle
            )
        ]

        return StoryboardGenerator<SettingsPage>(
            config: .init(
                screenSize: screenSize,
                arrowWidth: 40,
                arrowSpacing: 10,
                showLayoutGrid: false,  // Cleaner for analysis
                layoutZones: layoutZones,
                gridSpacing: 8,
                scenarios: [Scenario(name: "all-pages")]
            ),
            viewBuilder: { [weak self] page in
                self?.createView(for: page) ?? AnyView(EmptyView())
            }
        )
    }()

    /// Generate storyboard headlessly (for CLI)
    func generateAndExit(outputPath: String? = nil) async {
        await generator.generate(outputPath: outputPath)
    }

    /// Generate storyboard in-app
    func generateImage() async -> NSImage? {
        await generator.generateImage()
    }

    /// Capture individual page screenshots to a directory
    func captureAllPages(to directory: URL) async -> [SettingsPage: URL] {
        var results: [SettingsPage: URL] = [:]

        // Create directory if needed
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let window = createRenderWindow()

        for page in SettingsPage.allCases {
            print("📸 Capturing \(page.title)...")

            let view = createView(for: page)
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)

            try? await Task.sleep(for: .milliseconds(500))

            if let screenshot = captureWindow(window) {
                let filename = "settings-\(String(format: "%02d", page.rawValue))-\(page.title.lowercased().replacingOccurrences(of: " ", with: "-")).png"
                let fileURL = directory.appendingPathComponent(filename)

                if let tiffData = screenshot.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                    results[page] = fileURL
                    print("  ✅ Saved: \(filename)")
                }
            }
        }

        window.close()
        return results
    }

    /// Capture all pages as a grid composite image
    func captureGrid(columns: Int = 4, withOverlay: Bool = false, to outputPath: URL) async {
        let pages = SettingsPage.allCases
        let rows = Int(ceil(Double(pages.count) / Double(columns)))

        // Thumbnail size (scaled down for grid)
        let thumbWidth: CGFloat = 450
        let thumbHeight: CGFloat = 350
        let padding: CGFloat = 20
        let labelHeight: CGFloat = 30

        let totalWidth = CGFloat(columns) * thumbWidth + CGFloat(columns + 1) * padding
        let totalHeight = CGFloat(rows) * (thumbHeight + labelHeight) + CGFloat(rows + 1) * padding + 60  // +60 for title

        // Create composite image
        let compositeImage = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        compositeImage.lockFocus()

        // Background
        NSColor(white: 0.08, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: compositeImage.size).fill()

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let title = "Settings UI - All Pages"
        title.draw(at: NSPoint(x: padding, y: totalHeight - 50), withAttributes: titleAttributes)

        // Capture and place each page
        let window = createRenderWindow()

        for (index, page) in pages.enumerated() {
            print("📸 Grid: Capturing \(page.title)...")

            let view = withOverlay ? createViewWithOverlay(for: page) : createView(for: page)
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)

            try? await Task.sleep(for: .milliseconds(300))

            if let screenshot = captureWindow(window) {
                let col = index % columns
                let row = index / columns

                let x = padding + CGFloat(col) * (thumbWidth + padding)
                let y = totalHeight - 60 - padding - CGFloat(row + 1) * (thumbHeight + labelHeight + padding) + padding

                // Draw thumbnail
                let thumbRect = NSRect(x: x, y: y + labelHeight, width: thumbWidth, height: thumbHeight)
                screenshot.draw(in: thumbRect, from: .zero, operation: .copy, fraction: 1.0)

                // Draw border
                NSColor.white.withAlphaComponent(0.2).setStroke()
                let borderPath = NSBezierPath(roundedRect: thumbRect, xRadius: 8, yRadius: 8)
                borderPath.lineWidth = 1
                borderPath.stroke()

                // Draw label
                let labelAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
                ]
                let label = "\(String(format: "%02d", index)). \(page.title)"
                label.draw(at: NSPoint(x: x, y: y + 8), withAttributes: labelAttributes)

                // Category badge
                let categoryAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: NSColor.cyan
                ]
                page.category.uppercased().draw(at: NSPoint(x: x + thumbWidth - 80, y: y + 8), withAttributes: categoryAttributes)
            }
        }

        window.close()
        compositeImage.unlockFocus()

        // Save
        if let tiffData = compositeImage.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: outputPath)
            print("✅ Grid saved to: \(outputPath.path)")
        }
    }

    /// Analyze styling patterns in source files
    func analyzeAllPages() -> [StyleAnalysis] {
        let settingsDir = "/Users/arach/dev/talkie/macOS/Talkie/Views/Settings"
        var results: [StyleAnalysis] = []

        for page in SettingsPage.allCases {
            let filePath = "\(settingsDir)/\(page.sourceFile)"
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                print("⚠️ Could not read: \(page.sourceFile)")
                continue
            }

            var analysis = StyleAnalysis(page: page)

            // Extract font patterns
            let fontPatterns = [
                #"\.font\(Theme\.current\.[a-zA-Z]+\)"#,
                #"\.font\(SettingsManager\.shared\.[a-zA-Z]+\)"#,
                #"\.font\(\.system\(size:\s*\d+[^)]*\)\)"#,
                #"\.font\(\.system\(size:\s*\d+,\s*weight:\s*\.[a-zA-Z]+[^)]*\)\)"#
            ]

            for pattern in fontPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                    for match in matches {
                        if let range = Range(match.range, in: content) {
                            let found = String(content[range])
                            analysis.fonts[found, default: 0] += 1
                        }
                    }
                }
            }

            // Extract color patterns
            let colorPatterns = [
                #"Theme\.current\.[a-zA-Z]+"#,
                #"SettingsManager\.shared\.[a-zA-Z]*[Cc]olor[a-zA-Z]*"#,
                #"SettingsManager\.shared\.midnight[a-zA-Z]+"#,
                #"\.foregroundColor\(\.[a-zA-Z]+\)"#,
                #"\.background\(Color\.[a-zA-Z]+[^)]*\)"#,
                #"Color\.[a-zA-Z]+\.opacity\([0-9.]+\)"#,
                #"\.accentColor"#
            ]

            for pattern in colorPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                    for match in matches {
                        if let range = Range(match.range, in: content) {
                            let found = String(content[range])
                            analysis.colors[found, default: 0] += 1
                        }
                    }
                }
            }

            // Extract spacing patterns
            let spacingPatterns = [
                #"Spacing\.[a-zA-Z]+"#,
                #"\.padding\(\d+\)"#,
                #"\.padding\(\.[a-zA-Z]+,\s*\d+\)"#,
                #"spacing:\s*\d+"#
            ]

            for pattern in spacingPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                    for match in matches {
                        if let range = Range(match.range, in: content) {
                            let found = String(content[range])
                            analysis.spacing[found, default: 0] += 1
                        }
                    }
                }
            }

            // Extract opacity patterns
            let opacityPatterns = [
                #"Opacity\.[a-zA-Z]+"#,
                #"\.opacity\([0-9.]+\)"#
            ]

            for pattern in opacityPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                    for match in matches {
                        if let range = Range(match.range, in: content) {
                            let found = String(content[range])
                            analysis.opacity[found, default: 0] += 1
                        }
                    }
                }
            }

            results.append(analysis)
        }

        return results
    }

    /// Generate full analysis report as markdown
    func generateAnalysisReport(to outputPath: URL) {
        let analyses = analyzeAllPages()

        var report = """
        # Settings UI Styling Analysis

        **Generated:** \(Date().formatted())
        **Pages Analyzed:** \(analyses.count)

        ---

        ## Summary

        | Page | Fonts | Colors | Spacing | Issues |
        |------|-------|--------|---------|--------|

        """

        // Summary table
        var totalFontIssues = 0
        var totalColorIssues = 0

        for analysis in analyses {
            let fontIssues = analysis.totalFontIssues
            let colorIssues = analysis.totalColorIssues
            totalFontIssues += fontIssues
            totalColorIssues += colorIssues

            let status = (fontIssues == 0 && colorIssues == 0) ? "✅" : "⚠️"
            report += "| \(analysis.page.title) | \(analysis.fonts.count) | \(analysis.colors.count) | \(analysis.spacing.count) | \(status) \(fontIssues + colorIssues) |\n"
        }

        report += "\n**Total Issues:** \(totalFontIssues) font, \(totalColorIssues) color\n\n"
        report += "---\n\n"

        // Detailed reports
        for analysis in analyses {
            report += analysis.markdownReport()
            report += "\n---\n\n"
        }

        try? report.write(to: outputPath, atomically: true, encoding: .utf8)
        print("✅ Analysis report saved to: \(outputPath.path)")
    }

    // MARK: - Private

    private func createRenderWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 900, height: 700)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        return window
    }

    private func captureWindow(_ window: NSWindow) -> NSImage? {
        guard let contentView = window.contentView else { return nil }

        let bounds = contentView.bounds
        guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        contentView.cacheDisplay(in: bounds, to: bitmapRep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)
        return image
    }

    private func createView(for page: SettingsPage) -> AnyView {
        let view = HStack(spacing: 0) {
            // Sidebar (simplified - just show selected state)
            VStack(alignment: .leading, spacing: 8) {
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                ForEach(SettingsPage.allCases, id: \.self) { p in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(p == page ? Color.accentColor : Color.clear)
                            .frame(width: 6, height: 6)

                        Text(p.title.uppercased())
                            .font(.system(size: 9, weight: p == page ? .semibold : .regular))
                            .foregroundColor(p == page ? .white : .gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(p == page ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                }

                Spacer()
            }
            .frame(width: 220)
            .background(Color(white: 0.12))

            // Content
            contentView(for: page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900, height: 700)
        .background(Color(white: 0.1))
        .environment(SettingsManager.shared)
        .environment(LiveSettings.shared)
        .environment(EngineClient.shared)

        return AnyView(view)
    }

    /// Create view with layout grid overlay
    private func createViewWithOverlay(for page: SettingsPage) -> AnyView {
        let view = ZStack {
            createView(for: page)

            // Layout grid overlay
            HStack(spacing: 0) {
                // Sidebar zone indicator
                Rectangle()
                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    .frame(width: 220)
                    .overlay(
                        VStack {
                            Text("SIDEBAR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(8)
                    )

                // Content zone indicator
                Rectangle()
                    .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                    .overlay(
                        VStack {
                            HStack {
                                Text("CONTENT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.cyan)
                                    .padding(4)
                                    .background(Color.cyan.opacity(0.2))
                                    .cornerRadius(4)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(8)
                    )
            }
        }

        return AnyView(view)
    }

    @ViewBuilder
    private func contentView(for page: SettingsPage) -> some View {
        switch page {
        case .appearance:
            AppearanceSettingsView()
        case .dictationCapture:
            DictationCaptureSettingsView()
        case .dictationOutput:
            DictationOutputSettingsView()
        case .quickActions:
            QuickActionsSettingsView()
        case .quickOpen:
            QuickOpenSettingsView()
        case .autoRun:
            AutoRunSettingsView()
        case .aiProviders:
            APISettingsView()
        case .transcriptionModels:
            TranscriptionModelsSettingsView()
        case .llmModels:
            ModelLibraryView()
        case .database:
            DatabaseSettingsView()
        case .files:
            LocalFilesSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .debugInfo:
            DebugInfoView()
        }
    }
}

