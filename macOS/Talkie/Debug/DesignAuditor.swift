//
//  DesignAuditor.swift
//  Talkie macOS
//
//  Comprehensive design system audit tool for analyzing UI consistency
//  across all screens in the app. Checks fonts, colors, spacing, and opacity
//  against the established design tokens.
//

import SwiftUI
import AppKit

// MARK: - Screen Registry

/// All auditable screens in the app, organized by section
enum AppScreen: String, CaseIterable, Identifiable, Codable {
    // Settings
    case settingsAppearance = "settings-appearance"
    case settingsDictationCapture = "settings-dictation-capture"
    case settingsDictationOutput = "settings-dictation-output"
    case settingsQuickActions = "settings-quick-actions"
    case settingsQuickOpen = "settings-quick-open"
    case settingsAutoRun = "settings-auto-run"
    case settingsAIProviders = "settings-ai-providers"
    case settingsTranscription = "settings-transcription"
    case settingsLLM = "settings-llm"
    case settingsDatabase = "settings-database"
    case settingsFiles = "settings-files"
    case settingsPermissions = "settings-permissions"
    case settingsDebug = "settings-debug"

    // Live
    case liveMain = "live-main"
    case liveSettings = "live-settings"
    case liveHistory = "live-history"

    // Memos
    case memosAllMemos = "memos-all"
    case memoDetail = "memo-detail"
    case memoEditor = "memo-editor"

    // Onboarding
    case onboardingWelcome = "onboarding-welcome"
    case onboardingPermissions = "onboarding-permissions"
    case onboardingComplete = "onboarding-complete"

    // Navigation
    case navigationSidebar = "navigation-sidebar"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settingsAppearance: return "Appearance"
        case .settingsDictationCapture: return "Dictation Capture"
        case .settingsDictationOutput: return "Dictation Output"
        case .settingsQuickActions: return "Quick Actions"
        case .settingsQuickOpen: return "Quick Open"
        case .settingsAutoRun: return "Auto-Run"
        case .settingsAIProviders: return "AI Providers"
        case .settingsTranscription: return "Transcription Models"
        case .settingsLLM: return "LLM Models"
        case .settingsDatabase: return "Database"
        case .settingsFiles: return "Files"
        case .settingsPermissions: return "Permissions"
        case .settingsDebug: return "Debug Info"
        case .liveMain: return "Live Main"
        case .liveSettings: return "Live Settings"
        case .liveHistory: return "Live History"
        case .memosAllMemos: return "All Memos"
        case .memoDetail: return "Memo Detail"
        case .memoEditor: return "Memo Editor"
        case .onboardingWelcome: return "Onboarding Welcome"
        case .onboardingPermissions: return "Onboarding Permissions"
        case .onboardingComplete: return "Onboarding Complete"
        case .navigationSidebar: return "Navigation Sidebar"
        }
    }

    var section: ScreenSection {
        switch self {
        case .settingsAppearance, .settingsDictationCapture, .settingsDictationOutput,
             .settingsQuickActions, .settingsQuickOpen, .settingsAutoRun,
             .settingsAIProviders, .settingsTranscription, .settingsLLM,
             .settingsDatabase, .settingsFiles, .settingsPermissions, .settingsDebug:
            return .settings
        case .liveMain, .liveSettings, .liveHistory:
            return .live
        case .memosAllMemos, .memoDetail, .memoEditor:
            return .memos
        case .onboardingWelcome, .onboardingPermissions, .onboardingComplete:
            return .onboarding
        case .navigationSidebar:
            return .navigation
        }
    }

    var sourceFiles: [String] {
        switch self {
        case .settingsAppearance: return ["Views/Settings/AppearanceSettings.swift"]
        case .settingsDictationCapture, .settingsDictationOutput: return ["Views/Settings/DictationSettings.swift"]
        case .settingsQuickActions: return ["Views/Settings/QuickActionsSettings.swift"]
        case .settingsQuickOpen: return ["Views/Settings/QuickOpenSettings.swift"]
        case .settingsAutoRun: return ["Views/Settings/AutoRunSettings.swift"]
        case .settingsAIProviders: return ["Views/Settings/APISettings.swift"]
        case .settingsTranscription: return ["Views/Settings/TranscriptionModelsSettingsView.swift"]
        case .settingsLLM: return ["Views/Settings/ModelLibrarySettings.swift"]
        case .settingsDatabase: return ["Views/Settings/StorageSettings.swift"]
        case .settingsFiles: return ["Views/Settings/LocalFilesSettings.swift"]
        case .settingsPermissions: return ["Views/Settings/PermissionsSettings.swift"]
        case .settingsDebug: return ["Views/Settings/DebugSettings.swift"]
        case .liveMain: return ["Views/Live/DictationListView.swift"]
        case .liveSettings: return ["Views/Live/LiveSettingsView.swift", "Views/Live/Components/LivePreviewScreen.swift"]
        case .liveHistory: return ["Views/Live/History/HistoryView.swift"]
        case .memosAllMemos: return ["Views/MemosList/AllMemosView.swift"]
        case .memoDetail: return ["Views/MemoDetail/MemoDetailView.swift", "Views/MemoDetail/MemoDetailComponents.swift"]
        case .memoEditor: return ["Views/MemoDetail/MemoEditorView.swift"]
        case .onboardingWelcome, .onboardingPermissions, .onboardingComplete: return ["Views/Onboarding/OnboardingView.swift"]
        case .navigationSidebar: return ["Views/NavigationView.swift"]
        }
    }
}

enum ScreenSection: String, CaseIterable {
    case settings = "Settings"
    case live = "Live"
    case memos = "Memos"
    case onboarding = "Onboarding"
    case navigation = "Navigation"

    var screens: [AppScreen] {
        AppScreen.allCases.filter { $0.section == self }
    }
}

// MARK: - Design Tokens (Expected Values)

struct DesignTokens {
    // Font sizes from Theme.current
    static let validFontPatterns = [
        "Theme.current.fontXS",
        "Theme.current.fontXSMedium",
        "Theme.current.fontXSBold",
        "Theme.current.fontSM",
        "Theme.current.fontSMBold",
        "Theme.current.fontMD",
        "Theme.current.fontLG",
        "Theme.current.fontHeadline",
        "Theme.current.fontTitle"
    ]

    // Spacing values from Spacing enum
    static let validSpacing: [String: CGFloat] = [
        "Spacing.xxs": 2,
        "Spacing.xs": 6,
        "Spacing.sm": 10,
        "Spacing.md": 14,
        "Spacing.lg": 20,
        "Spacing.xl": 28,
        "Spacing.xxl": 40
    ]

    // Opacity values from Opacity enum
    static let validOpacity: [String: Double] = [
        "Opacity.subtle": 0.03,
        "Opacity.light": 0.08,
        "Opacity.medium": 0.15,
        "Opacity.strong": 0.25,
        "Opacity.half": 0.5,
        "Opacity.prominent": 0.7
    ]

    // Color patterns that are on-brand
    static let validColorPatterns = [
        "Theme.current.",
        ".accentColor",
        "Color.accentColor",
        "SemanticColor."
    ]
}

// MARK: - Responsive Sizes

enum ResponsiveSize: String, CaseIterable {
    case compact = "compact"      // 800x500
    case standard = "standard"    // 1000x700
    case expanded = "expanded"    // 1400x900

    var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 800, height: 500)
        case .standard: return CGSize(width: 1000, height: 700)
        case .expanded: return CGSize(width: 1400, height: 900)
        }
    }

    var label: String {
        switch self {
        case .compact: return "Compact (800x500)"
        case .standard: return "Standard (1000x700)"
        case .expanded: return "Expanded (1400x900)"
        }
    }
}

// MARK: - Audit Results

struct ScreenAuditResult: Codable {
    let screen: AppScreen
    let timestamp: Date
    var fontUsage: [PatternUsage] = []
    var colorUsage: [PatternUsage] = []
    var spacingUsage: [PatternUsage] = []
    var opacityUsage: [PatternUsage] = []

    var fontScore: Int {
        let total = fontUsage.reduce(0) { $0 + $1.count }
        let compliant = fontUsage.filter { $0.isCompliant }.reduce(0) { $0 + $1.count }
        return total > 0 ? Int(Double(compliant) / Double(total) * 100) : 100
    }

    var colorScore: Int {
        let total = colorUsage.reduce(0) { $0 + $1.count }
        let compliant = colorUsage.filter { $0.isCompliant }.reduce(0) { $0 + $1.count }
        return total > 0 ? Int(Double(compliant) / Double(total) * 100) : 100
    }

    var spacingScore: Int {
        let total = spacingUsage.reduce(0) { $0 + $1.count }
        let compliant = spacingUsage.filter { $0.isCompliant }.reduce(0) { $0 + $1.count }
        return total > 0 ? Int(Double(compliant) / Double(total) * 100) : 100
    }

    var opacityScore: Int {
        let total = opacityUsage.reduce(0) { $0 + $1.count }
        let compliant = opacityUsage.filter { $0.isCompliant }.reduce(0) { $0 + $1.count }
        return total > 0 ? Int(Double(compliant) / Double(total) * 100) : 100
    }

    var overallScore: Int {
        (fontScore + colorScore + spacingScore + opacityScore) / 4
    }

    var grade: String {
        switch overallScore {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }

    var totalIssues: Int {
        fontUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
            + colorUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
            + spacingUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
            + opacityUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Issue Categories (Compiler-style)

enum IssueCategory: String, CaseIterable, Codable {
    case fontHardcoded = "FONT-001"
    case fontWrongAccessor = "FONT-002"
    case colorHardcoded = "COLOR-001"
    case colorSystemColor = "COLOR-002"
    case spacingHardcoded = "SPACING-001"
    case spacingNonStandard = "SPACING-002"
    case opacityHardcoded = "OPACITY-001"
    case compliant = "OK"

    var title: String {
        switch self {
        case .fontHardcoded: return "Hard-coded font size"
        case .fontWrongAccessor: return "Wrong font accessor"
        case .colorHardcoded: return "Hard-coded color"
        case .colorSystemColor: return "System color instead of theme"
        case .spacingHardcoded: return "Hard-coded spacing"
        case .spacingNonStandard: return "Non-standard spacing value"
        case .opacityHardcoded: return "Hard-coded opacity"
        case .compliant: return "Compliant"
        }
    }

    var icon: String {
        switch self {
        case .compliant: return "✓"
        default: return "⚠️"
        }
    }

    var severity: String {
        switch self {
        case .compliant: return "ok"
        case .fontWrongAccessor, .colorSystemColor: return "warning"
        default: return "error"
        }
    }
}

struct PatternUsage: Identifiable, Codable {
    let id: UUID
    let pattern: String
    let count: Int
    let isCompliant: Bool
    let suggestion: String?
    let category: IssueCategory

    init(pattern: String, count: Int, isCompliant: Bool, suggestion: String? = nil, category: IssueCategory = .compliant) {
        self.id = UUID()
        self.pattern = pattern
        self.count = count
        self.isCompliant = isCompliant
        self.suggestion = suggestion
        self.category = isCompliant ? .compliant : category
    }
}

struct FullAuditReport: Codable {
    let timestamp: Date
    let screens: [ScreenAuditResult]
    let screenshotDirectory: String?  // Path to screenshots directory

    var overallScore: Int {
        guard !screens.isEmpty else { return 0 }
        return screens.reduce(0) { $0 + $1.overallScore } / screens.count
    }

    var grade: String {
        switch overallScore {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }

    var totalIssues: Int {
        screens.reduce(0) { total, screen in
            total + screen.fontUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
                  + screen.colorUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
                  + screen.spacingUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
                  + screen.opacityUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
        }
    }
}

// MARK: - Design Auditor

@MainActor
class DesignAuditor {
    static let shared = DesignAuditor()

    // Dynamically find the project root by looking for DesignAuditor.swift's location
    private var basePath: String {
        // Get the directory containing this file
        let currentFile = #file
        let currentFileURL = URL(fileURLWithPath: currentFile)
        // Navigate up from Debug/DesignAuditor.swift to macOS/Talkie/
        let talkieDir = currentFileURL.deletingLastPathComponent().deletingLastPathComponent()
        return talkieDir.path
    }

    // Cache directory for audit results
    nonisolated var cacheDirectory: URL {
        // Use Desktop for easier access during development
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktop.appendingPathComponent("talkie-audit")
    }

    private init() {}

    // MARK: - Persistence

    /// Get the next run number
    nonisolated func getNextRunNumber() -> Int {
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else {
            return 1
        }

        let existingRuns = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        let runNumbers = existingRuns.compactMap { dirname -> Int? in
            guard dirname.hasPrefix("run-") else { return nil }
            return Int(dirname.replacingOccurrences(of: "run-", with: ""))
        }

        return (runNumbers.max() ?? 0) + 1
    }

    /// Load the latest audit report from disk
    func loadLatestAudit() -> FullAuditReport? {
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else {
            return nil
        }

        let existingRuns = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        let runDirectories = existingRuns.filter { $0.hasPrefix("run-") }
            .compactMap { dirname -> (String, Int)? in
                guard let num = Int(dirname.replacingOccurrences(of: "run-", with: "")) else { return nil }
                return (dirname, num)
            }
            .sorted { $0.1 > $1.1 }  // Sort descending

        guard let latestRun = runDirectories.first else {
            return nil
        }

        let reportPath = cacheDirectory.appendingPathComponent("\(latestRun.0)/audit.json")
        guard let data = try? Data(contentsOf: reportPath),
              let report = try? JSONDecoder().decode(FullAuditReport.self, from: data) else {
            return nil
        }

        print("📂 Loaded audit from: \(latestRun.0)")
        return report
    }

    /// Save audit report and screenshots to disk
    private func saveAudit(_ report: FullAuditReport) {
        let runNumber = getNextRunNumber()
        let runDirectory = cacheDirectory.appendingPathComponent("run-\(String(format: "%03d", runNumber))")

        do {
            try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

            // Save JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try data.write(to: runDirectory.appendingPathComponent("audit.json"))

            print("✅ Saved audit to: run-\(String(format: "%03d", runNumber))")
        } catch {
            print("❌ Failed to save audit: \(error)")
        }
    }

    /// Capture screenshots of all screens
    private func captureScreenshots(to directory: URL) async {
        // Find the main Talkie window
        guard let mainWindow = NSApp.windows.first(where: { $0.title.contains("Talkie") && !$0.title.contains("Settings") }) else {
            print("⚠️ No main window found for screenshot capture")
            return
        }

        mainWindow.makeKeyAndOrderFront(nil)

        for screen in AppScreen.allCases {
            // Build debug navigation path for this screen
            let debugPath = buildDebugPath(for: screen)

            print("📸 Capturing \(screen.title) (talkie://d/\(debugPath))...")

            // Navigate to screen using debug URL system
            #if DEBUG
            NotificationCenter.default.post(
                name: .debugNavigate,
                object: nil,
                userInfo: ["path": debugPath]
            )
            #endif

            // Wait for navigation + render
            try? await Task.sleep(for: .milliseconds(500))

            // Capture window
            if let screenshot = captureWindow(mainWindow) {
                let filename = "\(screen.rawValue).png"
                let fileURL = directory.appendingPathComponent(filename)

                if let tiffData = screenshot.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                    print("  ✅ Saved: \(filename)")
                }
            }
        }
    }

    /// Build debug navigation path for a screen
    private func buildDebugPath(for screen: AppScreen) -> String {
        switch screen {
        // Settings
        case .settingsAppearance: return "settings/appearance"
        case .settingsDictationCapture: return "settings/dictation-capture"
        case .settingsDictationOutput: return "settings/dictation-output"
        case .settingsQuickActions: return "settings/quick-actions"
        case .settingsQuickOpen: return "settings/quick-open"
        case .settingsAutoRun: return "settings/auto-run"
        case .settingsAIProviders: return "settings/ai-providers"
        case .settingsTranscription: return "settings/transcription"
        case .settingsLLM: return "settings/llm"
        case .settingsDatabase: return "settings/database"
        case .settingsFiles: return "settings/files"
        case .settingsPermissions: return "settings/permissions"
        case .settingsDebug: return "settings/debug"

        // Live
        case .liveMain: return "live"
        case .liveSettings: return "live/settings"
        case .liveHistory: return "live/history"

        // Memos
        case .memosAllMemos: return "memos"
        case .memoDetail: return "memos/detail"
        case .memoEditor: return "memos/editor"

        // Onboarding
        case .onboardingWelcome: return "onboarding/welcome"
        case .onboardingPermissions: return "onboarding/permissions"
        case .onboardingComplete: return "onboarding/complete"

        // Navigation
        case .navigationSidebar: return "navigation"
        }
    }

    /// Capture a window using CGWindowListCreateImage
    private func captureWindow(_ window: NSWindow) -> NSImage? {
        guard let windowNumber = window.windowNumber as? CGWindowID else {
            return nil
        }

        // Small delay for rendering
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Capture the full window
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowNumber,
            [.boundsIgnoreFraming]
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Public API

    /// Audit a single screen - code analysis only
    private func performCodeAnalysis(screen: AppScreen) -> ScreenAuditResult {
        var result = ScreenAuditResult(screen: screen, timestamp: Date())

        for sourceFile in screen.sourceFiles {
            let filePath = "\(basePath)/\(sourceFile)"
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                print("  Could not read: \(sourceFile)")
                continue
            }

            // Analyze fonts
            let fonts = extractFontPatterns(from: content)
            for (pattern, count) in fonts {
                let isCompliant = DesignTokens.validFontPatterns.contains(where: { pattern.contains($0) })
                let suggestion = isCompliant ? nil : suggestFontReplacement(for: pattern)
                let category: IssueCategory = isCompliant ? .compliant :
                    pattern.contains("SettingsManager.shared") ? .fontWrongAccessor : .fontHardcoded
                result.fontUsage.append(PatternUsage(pattern: pattern, count: count, isCompliant: isCompliant, suggestion: suggestion, category: category))
            }

            // Analyze colors
            let colors = extractColorPatterns(from: content)
            for (pattern, count) in colors {
                let isCompliant = DesignTokens.validColorPatterns.contains(where: { pattern.contains($0) })
                let suggestion = isCompliant ? nil : suggestColorReplacement(for: pattern)
                let category: IssueCategory = isCompliant ? .compliant :
                    (pattern.contains(".primary") || pattern.contains(".secondary")) ? .colorSystemColor : .colorHardcoded
                result.colorUsage.append(PatternUsage(pattern: pattern, count: count, isCompliant: isCompliant, suggestion: suggestion, category: category))
            }

            // Analyze spacing
            let spacing = extractSpacingPatterns(from: content)
            for (pattern, count) in spacing {
                let isCompliant = pattern.contains("Spacing.")
                let suggestion = isCompliant ? nil : suggestSpacingReplacement(for: pattern)
                let category: IssueCategory = isCompliant ? .compliant : .spacingHardcoded
                result.spacingUsage.append(PatternUsage(pattern: pattern, count: count, isCompliant: isCompliant, suggestion: suggestion, category: category))
            }

            // Analyze opacity
            let opacity = extractOpacityPatterns(from: content)
            for (pattern, count) in opacity {
                let isCompliant = pattern.contains("Opacity.")
                let suggestion = isCompliant ? nil : suggestOpacityReplacement(for: pattern)
                let category: IssueCategory = isCompliant ? .compliant : .opacityHardcoded
                result.opacityUsage.append(PatternUsage(pattern: pattern, count: count, isCompliant: isCompliant, suggestion: suggestion, category: category))
            }
        }

        return result
    }

    /// Audit all screens with screenshot capture
    func auditAll() async -> FullAuditReport {
        print("🔍 Starting full design audit...")
        var results: [ScreenAuditResult] = []

        // Run static code analysis
        for screen in AppScreen.allCases {
            print("  Auditing \(screen.title)...")
            let result = performCodeAnalysis(screen: screen)
            results.append(result)
        }

        // Capture screenshots
        let runNumber = getNextRunNumber()
        let runDirectory = cacheDirectory.appendingPathComponent("run-\(String(format: "%03d", runNumber))")
        let screenshotsDirectory = runDirectory.appendingPathComponent("screenshots")

        do {
            try FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create screenshots directory: \(error)")
        }

        print("📸 Capturing screenshots...")
        await captureScreenshots(to: screenshotsDirectory)

        let report = FullAuditReport(
            timestamp: Date(),
            screens: results,
            screenshotDirectory: screenshotsDirectory.path
        )

        // Save to disk
        saveAudit(report)

        print("✅ Audit complete!")
        return report
    }

    /// Audit a specific section
    func audit(section: ScreenSection) -> FullAuditReport {
        print("🔍 Auditing \(section.rawValue) section...")
        var results: [ScreenAuditResult] = []

        for screen in section.screens {
            print("  Auditing \(screen.title)...")
            let result = performCodeAnalysis(screen: screen)
            results.append(result)
        }

        return FullAuditReport(timestamp: Date(), screens: results, screenshotDirectory: nil)
    }

    /// Audit a single screen with optional screenshot capture
    func audit(screen: AppScreen, withScreenshot: Bool = false, screenshotDirectory: URL? = nil) async -> ScreenAuditResult {
        print("🔍 Auditing \(screen.title)...")
        var result = performCodeAnalysis(screen: screen)

        if withScreenshot, let screenshotDir = screenshotDirectory {
            // Ensure directory exists
            try? FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)
            
            // Capture screenshot for this screen
            await captureScreenshot(for: screen, to: screenshotDir)
        }

        return result
    }

    /// Capture screenshot for a single screen
    func captureScreenshot(for screen: AppScreen, to directory: URL) async {
        // Find the main Talkie window
        guard let mainWindow = NSApp.windows.first(where: { $0.title.contains("Talkie") && !$0.title.contains("Settings") }) else {
            print("⚠️ No main window found for screenshot capture")
            return
        }

        mainWindow.makeKeyAndOrderFront(nil)

        // Build debug navigation path for this screen
        let debugPath = buildDebugPath(for: screen)

        print("📸 Capturing \(screen.title) (talkie://d/\(debugPath))...")

        // Navigate to screen using debug URL system
        #if DEBUG
        NotificationCenter.default.post(
            name: .debugNavigate,
            object: nil,
            userInfo: ["path": debugPath]
        )
        #endif

        // Wait for navigation + render
        try? await Task.sleep(for: .milliseconds(500))

        // Capture window
        if let screenshot = captureWindow(mainWindow) {
            let filename = "\(screen.rawValue).png"
            let fileURL = directory.appendingPathComponent(filename)

            if let tiffData = screenshot.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                print("  ✅ Saved: \(filename)")
            }
        }
    }

    // MARK: - Report Generation

    /// Generate HTML report
    func generateHTMLReport(from report: FullAuditReport, to outputPath: URL) {
        let html = buildHTMLReport(report)
        try? html.write(to: outputPath, atomically: true, encoding: .utf8)
        print("✅ HTML report saved to: \(outputPath.path)")
    }

    /// Generate Markdown report
    func generateMarkdownReport(from report: FullAuditReport, to outputPath: URL) {
        let markdown = buildMarkdownReport(report)
        try? markdown.write(to: outputPath, atomically: true, encoding: .utf8)
        print("✅ Markdown report saved to: \(outputPath.path)")
    }

    // MARK: - Pattern Extraction

    private func extractFontPatterns(from content: String) -> [String: Int] {
        var results: [String: Int] = [:]

        let patterns = [
            #"\.font\(Theme\.current\.[a-zA-Z]+\)"#,
            #"\.font\(SettingsManager\.shared\.[a-zA-Z]+\)"#,
            #"\.font\(\.system\(size:\s*\d+[^)]*\)\)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range, in: content) {
                        let found = String(content[range])
                        results[found, default: 0] += 1
                    }
                }
            }
        }

        return results
    }

    private func extractColorPatterns(from content: String) -> [String: Int] {
        var results: [String: Int] = [:]

        let patterns = [
            #"Theme\.current\.[a-zA-Z]+"#,
            #"\.foregroundColor\(\.[a-zA-Z]+\)"#,
            #"\.background\(Color\.[a-zA-Z]+[^)]*\)"#,
            #"Color\.[a-zA-Z]+\.opacity\([0-9.]+\)"#,
            #"\.accentColor"#,
            #"SemanticColor\.[a-zA-Z]+"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range, in: content) {
                        let found = String(content[range])
                        results[found, default: 0] += 1
                    }
                }
            }
        }

        return results
    }

    private func extractSpacingPatterns(from content: String) -> [String: Int] {
        var results: [String: Int] = [:]

        let patterns = [
            #"Spacing\.[a-zA-Z]+"#,
            #"\.padding\(\d+\)"#,
            #"\.padding\(\.[a-zA-Z]+,\s*\d+\)"#,
            #"spacing:\s*\d+"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range, in: content) {
                        let found = String(content[range])
                        results[found, default: 0] += 1
                    }
                }
            }
        }

        return results
    }

    private func extractOpacityPatterns(from content: String) -> [String: Int] {
        var results: [String: Int] = [:]

        let patterns = [
            #"Opacity\.[a-zA-Z]+"#,
            #"\.opacity\([0-9.]+\)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range, in: content) {
                        let found = String(content[range])
                        results[found, default: 0] += 1
                    }
                }
            }
        }

        return results
    }

    // MARK: - Suggestions

    private func suggestFontReplacement(for pattern: String) -> String {
        if pattern.contains("size: 8") || pattern.contains("size: 9") || pattern.contains("size: 10") {
            return "Theme.current.fontXS or fontXSBold"
        } else if pattern.contains("size: 11") || pattern.contains("size: 12") {
            return "Theme.current.fontSM or fontSMBold"
        } else if pattern.contains("size: 13") || pattern.contains("size: 14") {
            return "Theme.current.fontMD"
        } else if pattern.contains("size: 16") || pattern.contains("size: 18") {
            return "Theme.current.fontLG or fontHeadline"
        } else if pattern.contains("SettingsManager.shared.font") {
            return "Replace SettingsManager.shared with Theme.current"
        }
        return "Use Theme.current font tokens"
    }

    private func suggestColorReplacement(for pattern: String) -> String {
        if pattern.contains(".secondary") {
            return "Theme.current.foregroundSecondary or foregroundMuted"
        } else if pattern.contains(".primary") {
            return "Theme.current.foreground"
        } else if pattern.contains(".green") {
            return "SemanticColor.success"
        } else if pattern.contains(".red") {
            return "SemanticColor.error"
        } else if pattern.contains(".orange") || pattern.contains(".yellow") {
            return "SemanticColor.warning"
        } else if pattern.contains(".blue") {
            return "Theme.current.accent or .accentColor"
        }
        return "Use Theme.current color tokens"
    }

    private func suggestSpacingReplacement(for pattern: String) -> String {
        // Extract number from pattern
        if let match = pattern.range(of: #"\d+"#, options: .regularExpression) {
            let numStr = String(pattern[match])
            if let num = Int(numStr) {
                switch num {
                case 0...3: return "Spacing.xxs (2pt)"
                case 4...7: return "Spacing.xs (6pt)"
                case 8...12: return "Spacing.sm (10pt)"
                case 13...17: return "Spacing.md (14pt)"
                case 18...24: return "Spacing.lg (20pt)"
                case 25...34: return "Spacing.xl (28pt)"
                default: return "Spacing.xxl (40pt)"
                }
            }
        }
        return "Use Spacing enum"
    }

    private func suggestOpacityReplacement(for pattern: String) -> String {
        if let match = pattern.range(of: #"0\.\d+"#, options: .regularExpression) {
            let numStr = String(pattern[match])
            if let num = Double(numStr) {
                switch num {
                case 0...0.05: return "Opacity.subtle (0.03)"
                case 0.06...0.12: return "Opacity.light (0.08)"
                case 0.13...0.20: return "Opacity.medium (0.15)"
                case 0.21...0.35: return "Opacity.strong (0.25)"
                case 0.36...0.60: return "Opacity.half (0.5)"
                default: return "Opacity.prominent (0.7)"
                }
            }
        }
        return "Use Opacity enum"
    }

    // MARK: - HTML Report Builder (Dossier Style)

    private func buildHTMLReport(_ report: FullAuditReport, screenshotDir: String = "screenshots") -> String {
        let gradeColor: String = {
            switch report.grade {
            case "A": return "#22c55e"
            case "B": return "#84cc16"
            case "C": return "#eab308"
            case "D": return "#f97316"
            default: return "#ef4444"
            }
        }()

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Talkie Design Audit Report</title>
            <style>
                :root {
                    --bg: #0a0a0a;
                    --surface: #141414;
                    --surface2: #1f1f1f;
                    --border: #2a2a2a;
                    --text: #ffffff;
                    --text-secondary: #a0a0a0;
                    --accent: #00d4ff;
                    --success: #22c55e;
                    --warning: #eab308;
                    --error: #ef4444;
                }

                * { box-sizing: border-box; margin: 0; padding: 0; }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif;
                    background: var(--bg);
                    color: var(--text);
                    line-height: 1.6;
                    padding: 40px;
                }

                .container { max-width: 1400px; margin: 0 auto; }

                header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 40px;
                    padding-bottom: 20px;
                    border-bottom: 1px solid var(--border);
                }

                h1 { font-size: 28px; font-weight: 600; }
                h2 { font-size: 20px; font-weight: 600; margin-bottom: 16px; }
                h3 { font-size: 16px; font-weight: 500; margin-bottom: 12px; color: var(--text-secondary); }

                .grade-badge {
                    font-size: 48px;
                    font-weight: 700;
                    color: \(gradeColor);
                    text-shadow: 0 0 20px \(gradeColor)40;
                }

                .stats {
                    display: grid;
                    grid-template-columns: repeat(4, 1fr);
                    gap: 20px;
                    margin-bottom: 40px;
                }

                .stat-card {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 12px;
                    padding: 20px;
                }

                .stat-value {
                    font-size: 32px;
                    font-weight: 600;
                    margin-bottom: 4px;
                }

                .stat-label {
                    font-size: 12px;
                    color: var(--text-secondary);
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }

                .section-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
                    gap: 20px;
                    margin-bottom: 40px;
                }

                .screen-card {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 12px;
                    padding: 20px;
                    transition: border-color 0.2s;
                }

                .screen-card:hover {
                    border-color: var(--accent);
                }

                .screen-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 16px;
                }

                .screen-title {
                    font-weight: 600;
                }

                .screen-grade {
                    font-size: 14px;
                    font-weight: 600;
                    padding: 4px 10px;
                    border-radius: 6px;
                }

                .score-bar {
                    height: 6px;
                    background: var(--surface2);
                    border-radius: 3px;
                    margin-bottom: 8px;
                    overflow: hidden;
                }

                .score-fill {
                    height: 100%;
                    border-radius: 3px;
                    transition: width 0.3s ease;
                }

                .score-labels {
                    display: flex;
                    justify-content: space-between;
                    font-size: 11px;
                    color: var(--text-secondary);
                }

                .issues-list {
                    margin-top: 12px;
                    font-size: 12px;
                }

                .issue {
                    display: flex;
                    align-items: center;
                    gap: 6px;
                    padding: 6px 0;
                    border-top: 1px solid var(--border);
                }

                .issue:first-child { border-top: none; }

                .issue-icon { font-size: 10px; }
                .compliant { color: var(--success); }
                .non-compliant { color: var(--warning); }

                .timestamp {
                    font-size: 12px;
                    color: var(--text-secondary);
                }

                .section-header {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    margin-bottom: 20px;
                }

                .section-badge {
                    font-size: 11px;
                    padding: 4px 8px;
                    background: var(--accent);
                    color: var(--bg);
                    border-radius: 4px;
                    font-weight: 600;
                }

                /* Thumbnail grid for overview */
                .thumbnail-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
                    gap: 16px;
                    margin-bottom: 40px;
                }

                .thumbnail-card {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 8px;
                    overflow: hidden;
                    cursor: pointer;
                    transition: all 0.2s;
                }

                .thumbnail-card:hover {
                    border-color: var(--accent);
                    transform: translateY(-2px);
                }

                .thumbnail-img {
                    width: 100%;
                    aspect-ratio: 16/10;
                    object-fit: cover;
                    background: var(--surface2);
                }

                .thumbnail-info {
                    padding: 12px;
                }

                .thumbnail-title {
                    font-size: 13px;
                    font-weight: 600;
                    margin-bottom: 4px;
                }

                .thumbnail-grade {
                    display: inline-block;
                    font-size: 11px;
                    font-weight: 600;
                    padding: 2px 6px;
                    border-radius: 4px;
                }

                /* Dossier detail view */
                .dossier {
                    display: none;
                    background: var(--bg);
                    position: fixed;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    z-index: 100;
                    overflow-y: auto;
                    padding: 40px;
                }

                .dossier.active { display: block; }

                .dossier-nav {
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    z-index: 101;
                }

                .dossier-nav button {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    color: var(--text);
                    width: 40px;
                    height: 40px;
                    border-radius: 8px;
                    cursor: pointer;
                    font-size: 18px;
                    transition: all 0.15s;
                }

                .dossier-nav button:hover {
                    border-color: var(--accent);
                    background: var(--surface2);
                }

                .nav-counter {
                    font-size: 12px;
                    color: var(--text-secondary);
                    padding: 0 12px;
                    font-family: 'SF Mono', monospace;
                }

                .nav-hint {
                    position: fixed;
                    bottom: 20px;
                    left: 50%;
                    transform: translateX(-50%);
                    background: var(--surface);
                    border: 1px solid var(--border);
                    padding: 8px 16px;
                    border-radius: 8px;
                    font-size: 11px;
                    color: var(--text-secondary);
                    z-index: 101;
                }

                .nav-hint kbd {
                    background: var(--surface2);
                    padding: 2px 6px;
                    border-radius: 4px;
                    margin: 0 2px;
                }

                .dossier-content {
                    max-width: 1600px;
                    margin: 0 auto;
                }

                .dossier-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 24px;
                }

                .dossier-title {
                    font-size: 28px;
                    font-weight: 700;
                }

                .dossier-main {
                    display: grid;
                    grid-template-columns: 60% 1fr;
                    gap: 24px;
                    margin-bottom: 32px;
                }

                .dossier-screenshot {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 12px;
                    overflow: hidden;
                }

                .dossier-screenshot img {
                    width: 100%;
                    display: block;
                }

                .dossier-sidebar {
                    display: flex;
                    flex-direction: column;
                    gap: 16px;
                }

                .token-section {
                    background: var(--surface);
                    border: 1px solid var(--border);
                    border-radius: 12px;
                    padding: 16px;
                }

                .token-section h4 {
                    font-size: 11px;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    color: var(--text-secondary);
                    margin-bottom: 12px;
                }

                .token-list {
                    display: flex;
                    flex-direction: column;
                    gap: 8px;
                }

                .token-item {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    font-size: 12px;
                }

                .token-name { color: var(--text-secondary); }
                .token-value { font-family: monospace; }
                .token-count {
                    background: var(--surface2);
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-size: 10px;
                }

                .color-swatch {
                    display: flex;
                    gap: 4px;
                    flex-wrap: wrap;
                }

                .swatch {
                    width: 24px;
                    height: 24px;
                    border-radius: 4px;
                    border: 1px solid var(--border);
                }

                /* Compiler-style issues section */
                .dossier-issues {
                    background: #1a1a1a;
                    border: 1px solid var(--border);
                    border-radius: 12px;
                    overflow: hidden;
                }

                .dossier-issues h3 {
                    font-size: 12px;
                    font-weight: 600;
                    padding: 12px 16px;
                    background: #252525;
                    border-bottom: 1px solid var(--border);
                    color: var(--text-secondary);
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }

                .compiler-output {
                    font-family: 'SF Mono', 'Menlo', monospace;
                    font-size: 12px;
                    line-height: 1.5;
                }

                .compiler-summary {
                    display: flex;
                    gap: 16px;
                    padding: 12px 16px;
                    background: #1f1f1f;
                    border-bottom: 1px solid var(--border);
                }

                .error-count { color: var(--error); }
                .warning-count { color: var(--warning); }

                .compiler-success {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    padding: 20px 16px;
                    color: var(--success);
                }

                .success-icon { font-size: 16px; }

                .issue-category {
                    border-bottom: 1px solid var(--border);
                }

                .issue-category:last-child {
                    border-bottom: none;
                }

                .category-header {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                    padding: 10px 16px;
                    background: #1f1f1f;
                    cursor: pointer;
                }

                .category-code {
                    font-size: 10px;
                    font-weight: 700;
                    padding: 2px 6px;
                    border-radius: 3px;
                }

                .category-code.error {
                    background: var(--error);
                    color: var(--bg);
                }

                .category-code.warning {
                    background: var(--warning);
                    color: var(--bg);
                }

                .category-title {
                    flex: 1;
                    color: var(--text);
                }

                .category-count {
                    color: var(--text-secondary);
                    font-size: 11px;
                }

                .category-issues {
                    padding: 0;
                }

                .compiler-line {
                    display: flex;
                    align-items: baseline;
                    gap: 12px;
                    padding: 6px 16px 6px 32px;
                    border-top: 1px solid #252525;
                }

                .compiler-line:hover {
                    background: #252525;
                }

                .line-pattern {
                    flex: 1;
                    color: var(--warning);
                    font-size: 11px;
                }

                .line-count {
                    color: var(--text-secondary);
                    font-size: 10px;
                    min-width: 30px;
                }

                .line-fix {
                    color: var(--success);
                    font-size: 11px;
                    opacity: 0.8;
                }

                /* Score meters */
                .score-meters {
                    display: grid;
                    grid-template-columns: repeat(4, 1fr);
                    gap: 12px;
                    margin-bottom: 16px;
                }

                .score-meter {
                    text-align: center;
                }

                .score-meter-value {
                    font-size: 24px;
                    font-weight: 700;
                }

                .score-meter-label {
                    font-size: 10px;
                    color: var(--text-secondary);
                    text-transform: uppercase;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <div>
                        <h1>Talkie Design Audit</h1>
                        <p class="timestamp">Generated: \(report.timestamp.formatted())</p>
                    </div>
                    <div class="grade-badge">\(report.grade)</div>
                </header>

                <div class="stats">
                    <div class="stat-card">
                        <div class="stat-value">\(report.overallScore)%</div>
                        <div class="stat-label">Overall Compliance</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value">\(report.screens.count)</div>
                        <div class="stat-label">Screens Audited</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value">\(report.totalIssues)</div>
                        <div class="stat-label">Total Issues</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value">\(ScreenSection.allCases.count)</div>
                        <div class="stat-label">Sections</div>
                    </div>
                </div>
        """

        // Add sections with thumbnail grid
        for section in ScreenSection.allCases {
            let sectionScreens = report.screens.filter { $0.screen.section == section }
            guard !sectionScreens.isEmpty else { continue }

            html += """
                <div class="section-header">
                    <h2>\(section.rawValue)</h2>
                    <span class="section-badge">\(sectionScreens.count) screens</span>
                </div>
                <div class="thumbnail-grid">
            """

            for screen in sectionScreens {
                let scoreColor = screen.overallScore >= 80 ? "var(--success)" : screen.overallScore >= 60 ? "var(--warning)" : "var(--error)"
                let screenshotPath = "\(screenshotDir)/\(screen.screen.rawValue).png"

                html += """
                    <div class="thumbnail-card" onclick="showDossier('\(screen.screen.rawValue)')">
                        <img class="thumbnail-img" src="\(screenshotPath)" alt="\(screen.screen.title)" onerror="this.style.display='none'">
                        <div class="thumbnail-info">
                            <div class="thumbnail-title">\(screen.screen.title)</div>
                            <span class="thumbnail-grade" style="background: \(scoreColor)20; color: \(scoreColor);">\(screen.grade) · \(screen.overallScore)%</span>
                        </div>
                    </div>
                """
            }

            html += "</div>"
        }

        // Add dossier detail views for each screen
        for screen in report.screens {
            let scoreColor = screen.overallScore >= 80 ? "var(--success)" : screen.overallScore >= 60 ? "var(--warning)" : "var(--error)"
            let screenshotPath = "\(screenshotDir)/\(screen.screen.rawValue).png"

            // Get all issues sorted by count
            let allIssues = (screen.fontUsage + screen.colorUsage + screen.spacingUsage + screen.opacityUsage)
                .filter { !$0.isCompliant }
                .sorted { $0.count > $1.count }

            // Get compliant patterns for tokens display
            let compliantFonts = screen.fontUsage.filter { $0.isCompliant }
            let compliantColors = screen.colorUsage.filter { $0.isCompliant }
            let compliantSpacing = screen.spacingUsage.filter { $0.isCompliant }

            html += """
                <div class="dossier" id="dossier-\(screen.screen.rawValue)">
                    <div class="dossier-nav">
                        <button class="nav-prev" onclick="navigatePrev()" title="Previous (←)">←</button>
                        <span class="nav-counter">1 of \(report.screens.count)</span>
                        <button class="nav-next" onclick="navigateNext()" title="Next (→)">→</button>
                        <button onclick="closeDossier()" title="Close (Esc)">&times;</button>
                    </div>
                    <div class="nav-hint">Use <kbd>←</kbd> <kbd>→</kbd> arrow keys to navigate · <kbd>Esc</kbd> to close</div>
                    <div class="dossier-content">
                        <div class="dossier-header">
                            <div>
                                <div class="dossier-title">\(screen.screen.title)</div>
                                <p style="color: var(--text-secondary); font-size: 13px;">\(screen.screen.section.rawValue) · \(screen.screen.sourceFiles.first ?? "")</p>
                            </div>
                            <div class="grade-badge" style="font-size: 36px; color: \(scoreColor);">\(screen.grade)</div>
                        </div>

                        <div class="score-meters">
                            <div class="score-meter">
                                <div class="score-meter-value" style="color: \(screen.fontScore >= 70 ? "var(--success)" : "var(--error)");">\(screen.fontScore)%</div>
                                <div class="score-meter-label">Fonts</div>
                            </div>
                            <div class="score-meter">
                                <div class="score-meter-value" style="color: \(screen.colorScore >= 70 ? "var(--success)" : "var(--error)");">\(screen.colorScore)%</div>
                                <div class="score-meter-label">Colors</div>
                            </div>
                            <div class="score-meter">
                                <div class="score-meter-value" style="color: \(screen.spacingScore >= 70 ? "var(--success)" : "var(--error)");">\(screen.spacingScore)%</div>
                                <div class="score-meter-label">Spacing</div>
                            </div>
                            <div class="score-meter">
                                <div class="score-meter-value" style="color: \(screen.opacityScore >= 70 ? "var(--success)" : "var(--error)");">\(screen.opacityScore)%</div>
                                <div class="score-meter-label">Opacity</div>
                            </div>
                        </div>

                        <div class="dossier-main">
                            <div class="dossier-screenshot">
                                <img src="\(screenshotPath)" alt="\(screen.screen.title)" onerror="this.parentElement.innerHTML='<div style=\\'padding:60px;text-align:center;color:var(--text-secondary)\\'>Screenshot not available</div>'">
                            </div>

                            <div class="dossier-sidebar">
                                <div class="token-section">
                                    <h4>Fonts Used</h4>
                                    <div class="token-list">
            """

            for font in compliantFonts.prefix(5) {
                html += """
                                        <div class="token-item">
                                            <span class="token-name">\(font.pattern)</span>
                                            <span class="token-count">×\(font.count)</span>
                                        </div>
                """
            }

            if compliantFonts.isEmpty {
                html += "<div class=\"token-item\"><span class=\"token-name\" style=\"color:var(--warning)\">No compliant fonts</span></div>"
            }

            html += """
                                    </div>
                                </div>

                                <div class="token-section">
                                    <h4>Colors Used</h4>
                                    <div class="token-list">
            """

            for color in compliantColors.prefix(5) {
                html += """
                                        <div class="token-item">
                                            <span class="token-name">\(color.pattern)</span>
                                            <span class="token-count">×\(color.count)</span>
                                        </div>
                """
            }

            if compliantColors.isEmpty {
                html += "<div class=\"token-item\"><span class=\"token-name\" style=\"color:var(--warning)\">No compliant colors</span></div>"
            }

            html += """
                                    </div>
                                </div>

                                <div class="token-section">
                                    <h4>Spacing Used</h4>
                                    <div class="token-list">
            """

            for spacing in compliantSpacing.prefix(5) {
                html += """
                                        <div class="token-item">
                                            <span class="token-name">\(spacing.pattern)</span>
                                            <span class="token-count">×\(spacing.count)</span>
                                        </div>
                """
            }

            if compliantSpacing.isEmpty {
                html += "<div class=\"token-item\"><span class=\"token-name\" style=\"color:var(--warning)\">No compliant spacing</span></div>"
            }

            html += """
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="dossier-issues">
                            <h3>Compiler Output</h3>
                            <div class="compiler-output">
            """

            // Group issues by category
            let issuesByCategory = Dictionary(grouping: allIssues) { $0.category }
            let sortedCategories = issuesByCategory.keys.sorted { $0.rawValue < $1.rawValue }

            if allIssues.isEmpty {
                html += """
                                <div class="compiler-success">
                                    <span class="success-icon">✓</span>
                                    <span>Build succeeded - 0 warnings, 0 errors</span>
                                </div>
                """
            } else {
                let errorCount = allIssues.filter { $0.category.severity == "error" }.count
                let warningCount = allIssues.filter { $0.category.severity == "warning" }.count

                html += """
                                <div class="compiler-summary">
                                    <span class="error-count">\(errorCount) errors</span>
                                    <span class="warning-count">\(warningCount) warnings</span>
                                </div>
                """

                for category in sortedCategories {
                    guard let categoryIssues = issuesByCategory[category] else { continue }
                    let totalCount = categoryIssues.reduce(0) { $0 + $1.count }

                    html += """
                                <div class="issue-category">
                                    <div class="category-header">
                                        <span class="category-code \(category.severity)">\(category.rawValue)</span>
                                        <span class="category-title">\(category.title)</span>
                                        <span class="category-count">×\(totalCount)</span>
                                    </div>
                                    <div class="category-issues">
                    """

                    for issue in categoryIssues.sorted(by: { $0.count > $1.count }) {
                        html += """
                                        <div class="compiler-line">
                                            <code class="line-pattern">\(issue.pattern)</code>
                                            <span class="line-count">×\(issue.count)</span>
                                            <span class="line-fix">→ \(issue.suggestion ?? "Use design tokens")</span>
                                        </div>
                        """
                    }

                    html += """
                                    </div>
                                </div>
                    """
                }
            }

            html += """
                            </div>
                        </div>
                    </div>
                </div>
            """
        }

        // Add JavaScript for dossier navigation with arrow keys
        let screenIds = report.screens.map { "'\($0.screen.rawValue)'" }.joined(separator: ", ")

        html += """
            </div>

            <script>
                const screenIds = [\(screenIds)];
                let currentIndex = -1;

                function showDossier(screenId) {
                    // Close any open dossier first
                    document.querySelectorAll('.dossier').forEach(d => d.classList.remove('active'));

                    // Open the requested dossier
                    document.getElementById('dossier-' + screenId).classList.add('active');
                    document.body.style.overflow = 'hidden';

                    // Update current index
                    currentIndex = screenIds.indexOf(screenId);
                    updateNavCounter();
                }

                function closeDossier() {
                    document.querySelectorAll('.dossier').forEach(d => d.classList.remove('active'));
                    document.body.style.overflow = '';
                    currentIndex = -1;
                }

                function navigatePrev() {
                    if (currentIndex > 0) {
                        showDossier(screenIds[currentIndex - 1]);
                    }
                }

                function navigateNext() {
                    if (currentIndex < screenIds.length - 1) {
                        showDossier(screenIds[currentIndex + 1]);
                    }
                }

                function updateNavCounter() {
                    document.querySelectorAll('.nav-counter').forEach(el => {
                        el.textContent = (currentIndex + 1) + ' of ' + screenIds.length;
                    });

                    // Update prev/next button states
                    document.querySelectorAll('.nav-prev').forEach(el => {
                        el.style.opacity = currentIndex > 0 ? '1' : '0.3';
                        el.style.pointerEvents = currentIndex > 0 ? 'auto' : 'none';
                    });
                    document.querySelectorAll('.nav-next').forEach(el => {
                        el.style.opacity = currentIndex < screenIds.length - 1 ? '1' : '0.3';
                        el.style.pointerEvents = currentIndex < screenIds.length - 1 ? 'auto' : 'none';
                    });
                }

                // Keyboard navigation
                document.addEventListener('keydown', function(e) {
                    if (currentIndex === -1) return; // No dossier open

                    switch(e.key) {
                        case 'Escape':
                            closeDossier();
                            break;
                        case 'ArrowLeft':
                            e.preventDefault();
                            navigatePrev();
                            break;
                        case 'ArrowRight':
                            e.preventDefault();
                            navigateNext();
                            break;
                    }
                });

                // Close on click outside
                document.querySelectorAll('.dossier').forEach(d => {
                    d.addEventListener('click', function(e) {
                        if (e.target === this) closeDossier();
                    });
                });
            </script>
        </body>
        </html>
        """

        return html
    }

    // MARK: - Design Critique Documentation
    
    /*
     * DESIGN CRITIQUE PROMPT GUIDE
     * 
     * When generating design critiques for audit screenshots, agents should follow this structure:
     * 
     * File Location:
     *   ~/Desktop/talkie-audit/run-XXX/{screen-id}-critique.md
     *   (e.g., ~/Desktop/talkie-audit/run-047/settings-appearance-critique.md)
     * 
     * Screenshot Location:
     *   ~/Desktop/talkie-audit/run-XXX/screenshots/{screen-id}.png
     * 
     * Expected Format:
     *   ## Overall Impression
     *   [Brief gut reaction - what stands out immediately]
     * 
     *   ## Issues (in priority order)
     *   1. [Specific issue with suggested fix]
     *   2. [Specific issue with suggested fix]
     *   ...
     * 
     *   ## What's Working Well
     *   [Be fair - note what's good too]
     * 
     * Focus Areas:
     *   1. Visual Hierarchy - Does the eye flow naturally? Are important elements prominent?
     *   2. Spacing & Rhythm - Look for cramped areas, inconsistent gaps, or awkward white space
     *   3. Information Density - Too dense? Too sparse? Overwhelming or empty?
     *   4. Balance & Alignment - Are elements properly aligned? Does it feel balanced?
     *   5. Typography - Font sizes, weights, line heights - what feels off?
     *   6. Color & Contrast - Any legibility issues? Harsh contrasts or washed-out text?
     *   7. Component Consistency - Do similar elements look similar?
     *   8. Practical Issues - Text wrapping, truncation, overflow, cramped hit areas
     * 
     * Style Guidelines:
     *   - Be SPECIFIC and ACTIONABLE
     *   - Instead of "spacing feels off", say: "Preview sidebar feels cramped - 'All Memos' 
     *     wrapping suggests need for 15-20px more width"
     *   - Instead of "too much padding", say: "MODE section has too much visual weight for a 
     *     simple 3-option choice - reduce padding by ~8px"
     *   - Keep it concise, opinionated, and useful for iteration
     *   - Reference the code audit results when relevant (font/color/spacing scores)
     * 
     * Example Prompt for Agent:
     *   "Analyze the screenshot at {screenshot-path} and write a design critique following 
     *   the format documented in DesignAuditor.swift. Focus on actionable, specific feedback 
     *   that will help improve the UI. Reference the audit results in {report-path} when 
     *   relevant."
     */

    // MARK: - Markdown Report Builder

    private func buildMarkdownReport(_ report: FullAuditReport) -> String {
        var md = """
        # Talkie Design Audit Report

        **Generated:** \(report.timestamp.formatted())
        **Overall Grade:** \(report.grade) (\(report.overallScore)%)
        **Total Issues:** \(report.totalIssues)

        ---

        ## Summary by Section

        | Section | Screens | Avg Score | Issues |
        |---------|---------|-----------|--------|

        """

        for section in ScreenSection.allCases {
            let sectionScreens = report.screens.filter { $0.screen.section == section }
            guard !sectionScreens.isEmpty else { continue }

            let avgScore = sectionScreens.reduce(0) { $0 + $1.overallScore } / sectionScreens.count
            let issues = sectionScreens.reduce(0) { total, screen in
                total + screen.fontUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
                      + screen.colorUsage.filter { !$0.isCompliant }.reduce(0) { $0 + $1.count }
            }

            md += "| \(section.rawValue) | \(sectionScreens.count) | \(avgScore)% | \(issues) |\n"
        }

        md += "\n---\n\n## Detailed Results\n\n"

        for screen in report.screens {
            md += """
            ### \(screen.screen.title)
            **Section:** \(screen.screen.section.rawValue) | **Grade:** \(screen.grade) | **Score:** \(screen.overallScore)%

            | Category | Score | Compliant | Non-Compliant |
            |----------|-------|-----------|---------------|
            | Fonts | \(screen.fontScore)% | \(screen.fontUsage.filter { $0.isCompliant }.count) | \(screen.fontUsage.filter { !$0.isCompliant }.count) |
            | Colors | \(screen.colorScore)% | \(screen.colorUsage.filter { $0.isCompliant }.count) | \(screen.colorUsage.filter { !$0.isCompliant }.count) |
            | Spacing | \(screen.spacingScore)% | \(screen.spacingUsage.filter { $0.isCompliant }.count) | \(screen.spacingUsage.filter { !$0.isCompliant }.count) |
            | Opacity | \(screen.opacityScore)% | \(screen.opacityUsage.filter { $0.isCompliant }.count) | \(screen.opacityUsage.filter { !$0.isCompliant }.count) |

            """

            let issues = (screen.fontUsage + screen.colorUsage + screen.spacingUsage + screen.opacityUsage)
                .filter { !$0.isCompliant }
                .sorted { $0.count > $1.count }

            if !issues.isEmpty {
                md += "**Top Issues:**\n"
                for issue in issues.prefix(5) {
                    md += "- `\(issue.pattern)` ×\(issue.count)"
                    if let suggestion = issue.suggestion {
                        md += " → \(suggestion)"
                    }
                    md += "\n"
                }
            }

            md += "\n---\n\n"
        }

        return md
    }
}
