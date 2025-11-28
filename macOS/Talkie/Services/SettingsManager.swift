//
//  SettingsManager.swift
//  Talkie macOS
//
//  Manages app settings stored in Core Data
//

import Foundation
import CoreData
import SwiftUI
import AppKit

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - Accent Color Options
enum AccentColorOption: String, CaseIterable {
    case system = "system"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case gray = "gray"

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .gray: return .gray
        }
    }
}

// MARK: - Font Style Options
enum FontStyleOption: String, CaseIterable {
    case system = "system"
    case monospace = "monospace"
    case rounded = "rounded"
    case serif = "serif"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .monospace: return "Monospace"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        }
    }

    var icon: String {
        switch self {
        case .system: return "textformat"
        case .monospace: return "chevron.left.forwardslash.chevron.right"
        case .rounded: return "a.circle"
        case .serif: return "text.book.closed"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .monospace:
            return .system(size: size, weight: weight, design: .monospaced)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        }
    }
}

// MARK: - Font Size Options
enum FontSizeOption: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        rawValue.capitalized
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.15
        }
    }

    var icon: String {
        switch self {
        case .small: return "textformat.size.smaller"
        case .medium: return "textformat.size"
        case .large: return "textformat.size.larger"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // MARK: - Appearance Settings (UserDefaults - device-specific)

    private let appearanceModeKey = "appearanceMode"
    private let accentColorKey = "accentColor"
    private let fontStyleKey = "fontStyle"
    private let fontSizeKey = "fontSize"

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            applyAppearanceMode()
        }
    }

    @Published var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        }
    }

    @Published var fontStyle: FontStyleOption {
        didSet {
            UserDefaults.standard.set(fontStyle.rawValue, forKey: fontStyleKey)
        }
    }

    @Published var fontSize: FontSizeOption {
        didSet {
            UserDefaults.standard.set(fontSize.rawValue, forKey: fontSizeKey)
        }
    }

    /// Get a font with the current style and size settings applied
    func themedFont(baseSize: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaledSize = baseSize * fontSize.scale
        return fontStyle.font(size: scaledSize, weight: weight)
    }

    func applyAppearanceMode() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    // MARK: - Local File Storage Settings (UserDefaults - device-specific)
    // Where transcript and audio files live on disk - your data, your files
    // These are independent opt-in features for users who want local file ownership

    private let saveTranscriptsLocallyKey = "saveTranscriptsLocally"
    private let transcriptsFolderPathKey = "transcriptsFolderPath"
    private let saveAudioLocallyKey = "saveAudioLocally"
    private let audioFolderPathKey = "audioFolderPath"

    /// Default transcripts folder: ~/Documents/Talkie/Transcripts
    static var defaultTranscriptsFolderPath: String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Talkie/Transcripts").path
    }

    /// Default audio folder: ~/Documents/Talkie/Audio
    static var defaultAudioFolderPath: String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("Talkie/Audio").path
    }

    /// Whether to save transcripts as Markdown files locally (default: false)
    @Published var saveTranscriptsLocally: Bool {
        didSet {
            UserDefaults.standard.set(saveTranscriptsLocally, forKey: saveTranscriptsLocallyKey)
        }
    }

    /// Where transcript files are saved
    @Published var transcriptsFolderPath: String {
        didSet {
            UserDefaults.standard.set(transcriptsFolderPath, forKey: transcriptsFolderPathKey)
        }
    }

    /// Whether to save M4A audio files locally (default: false)
    @Published var saveAudioLocally: Bool {
        didSet {
            UserDefaults.standard.set(saveAudioLocally, forKey: saveAudioLocallyKey)
        }
    }

    /// Where audio files are saved
    @Published var audioFolderPath: String {
        didSet {
            UserDefaults.standard.set(audioFolderPath, forKey: audioFolderPathKey)
        }
    }

    // Convenience accessors
    var localFilesEnabled: Bool { saveTranscriptsLocally || saveAudioLocally }
    var transcriptFilesEnabled: Bool { saveTranscriptsLocally }
    var localFilesIncludeAudio: Bool { saveAudioLocally }

    // Internal storage
    @Published private var _geminiApiKey: String = ""
    @Published private var _openaiApiKey: String?
    @Published private var _anthropicApiKey: String?
    @Published private var _groqApiKey: String?
    @Published private var _selectedModel: String = "gemini-1.5-flash-latest"

    // Public accessors that ensure initialization
    var geminiApiKey: String {
        get { ensureInitialized(); return _geminiApiKey }
        set { _geminiApiKey = newValue }
    }

    var openaiApiKey: String? {
        get { ensureInitialized(); return _openaiApiKey }
        set { _openaiApiKey = newValue }
    }

    var anthropicApiKey: String? {
        get { ensureInitialized(); return _anthropicApiKey }
        set { _anthropicApiKey = newValue }
    }

    var groqApiKey: String? {
        get { ensureInitialized(); return _groqApiKey }
        set { _groqApiKey = newValue }
    }

    var selectedModel: String {
        get { ensureInitialized(); return _selectedModel }
        set { _selectedModel = newValue }
    }

    private var context: NSManagedObjectContext {
        return PersistenceController.shared.container.viewContext
    }

    private var isInitialized = false

    private init() {
        // Initialize appearance settings from UserDefaults
        if let modeString = UserDefaults.standard.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: modeString) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        if let colorString = UserDefaults.standard.string(forKey: accentColorKey),
           let color = AccentColorOption(rawValue: colorString) {
            self.accentColor = color
        } else {
            self.accentColor = .system
        }

        if let fontStyleString = UserDefaults.standard.string(forKey: fontStyleKey),
           let style = FontStyleOption(rawValue: fontStyleString) {
            self.fontStyle = style
        } else {
            self.fontStyle = .monospace  // Default to monospace for code-style UI
        }

        if let fontSizeString = UserDefaults.standard.string(forKey: fontSizeKey),
           let size = FontSizeOption(rawValue: fontSizeString) {
            self.fontSize = size
        } else {
            self.fontSize = .medium
        }

        // Initialize local file storage settings from UserDefaults
        // Default: DISABLED - these are opt-in advanced features for data ownership
        self.saveTranscriptsLocally = UserDefaults.standard.object(forKey: saveTranscriptsLocallyKey) as? Bool ?? false
        self.transcriptsFolderPath = UserDefaults.standard.string(forKey: transcriptsFolderPathKey) ?? SettingsManager.defaultTranscriptsFolderPath
        self.saveAudioLocally = UserDefaults.standard.object(forKey: saveAudioLocallyKey) as? Bool ?? false
        self.audioFolderPath = UserDefaults.standard.string(forKey: audioFolderPathKey) ?? SettingsManager.defaultAudioFolderPath

        // Apply appearance mode on launch
        applyAppearanceMode()

        // Defer Core Data access until first use
    }

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true
        performLoadSettings()
    }

    // MARK: - Load Settings
    func loadSettings() {
        // Public method - always reload
        performLoadSettings()
    }

    private func performLoadSettings() {
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            if let settings = results.first {
                self._geminiApiKey = settings.geminiApiKey ?? ""
                self._openaiApiKey = settings.openaiApiKey
                self._anthropicApiKey = settings.anthropicApiKey
                self._groqApiKey = settings.groqApiKey
                self._selectedModel = settings.selectedModel ?? "gemini-1.5-flash-latest"
                print("✅ Loaded settings: model=\(_selectedModel)")
                print("   - Gemini API key: \(_geminiApiKey.isEmpty ? "not set" : "set (\(_geminiApiKey.prefix(8))...)")")
                print("   - OpenAI API key: \(_openaiApiKey == nil ? "not set" : "set")")
                print("   - Anthropic API key: \(_anthropicApiKey == nil ? "not set" : "set")")
                print("   - Groq API key: \(_groqApiKey == nil ? "not set" : "set")")
            } else {
                print("⚠️ No settings found in Core Data, creating defaults...")
                createDefaultSettings()
            }
        } catch {
            print("❌ Failed to load settings: \(error)")
        }
    }

    // MARK: - Save Settings
    func saveSettings() {
        ensureInitialized()
        let fetchRequest: NSFetchRequest<AppSettings> = AppSettings.fetchRequest()

        do {
            let results = try context.fetch(fetchRequest)
            let settings: AppSettings

            if let existingSettings = results.first {
                settings = existingSettings
            } else {
                settings = AppSettings(context: context)
                settings.id = UUID()
            }

            settings.geminiApiKey = geminiApiKey
            settings.openaiApiKey = openaiApiKey
            settings.anthropicApiKey = anthropicApiKey
            settings.groqApiKey = groqApiKey
            settings.selectedModel = selectedModel
            settings.lastModified = Date()

            try context.save()
            print("✅ Settings saved successfully")
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }

    // MARK: - Create Default Settings
    private func createDefaultSettings() {
        let settings = AppSettings(context: context)
        settings.id = UUID()
        settings.geminiApiKey = ""
        settings.selectedModel = "gemini-1.5-flash-latest"
        settings.lastModified = Date()

        do {
            try context.save()
            self._geminiApiKey = ""
            self._selectedModel = "gemini-1.5-flash-latest"
            print("✅ Created default settings")
        } catch {
            print("❌ Failed to create default settings: \(error)")
        }
    }

    // MARK: - Validation
    var hasValidApiKey: Bool {
        ensureInitialized()
        return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
