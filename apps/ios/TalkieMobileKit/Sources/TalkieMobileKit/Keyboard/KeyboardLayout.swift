//
//  KeyboardLayout.swift
//  TalkieMobileKit
//
//  Layout and Mode system for configurable keyboards
//

import Foundation

// MARK: - Layout (Physical Structure)

/// Defines the physical structure of a keyboard layout
public struct KeyboardLayout: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String

    /// Grid configuration
    public let rows: Int
    public let columns: Int

    /// Which slots are merged into a 2x2 region (nil = no merge)
    public let mergedRegion: MergedRegion?

    /// What element fills the merged region
    public let mergedContent: MergedContent

    /// Whether there's a dedicated record row at bottom
    public let hasRecordRow: Bool

    /// Visual features
    public let features: LayoutFeatures

    public init(
        id: String,
        name: String,
        description: String,
        rows: Int = 3,
        columns: Int = 4,
        mergedRegion: MergedRegion? = nil,
        mergedContent: MergedContent = .record,
        hasRecordRow: Bool = true,
        features: LayoutFeatures = LayoutFeatures()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.rows = rows
        self.columns = columns
        self.mergedRegion = mergedRegion
        self.mergedContent = mergedContent
        self.hasRecordRow = hasRecordRow
        self.features = features
    }
}

/// Defines which slots are merged into a 2x2 region
public struct MergedRegion: Codable, Sendable {
    /// The 4 slot indices that form the 2x2 (bottom-left, bottom-right, top-left, top-right)
    public let slots: [Int]

    public init(slots: [Int]) {
        self.slots = slots
    }

    /// Center of a 4x4 grid (slots 6,7,10,11)
    public static let center = MergedRegion(slots: [6, 7, 10, 11])

    /// Top-right of a 4x4 grid (slots 11,12,15,16)
    public static let topRight = MergedRegion(slots: [11, 12, 15, 16])

    /// Bottom-right of a 4x4 grid (slots 3,4,7,8)
    public static let bottomRight = MergedRegion(slots: [3, 4, 7, 8])
}

/// What type of element fills a merged region
public enum MergedContent: String, Codable, Sendable {
    case record      // Large record button
    case waveform    // Audio visualization
    case contextPad  // 4 mini context buttons
}

/// Visual features that can be enabled/disabled per layout
public struct LayoutFeatures: Codable, Sendable {
    public var accentBand: Bool
    public var statusBar: Bool
    public var serialPlate: Bool
    public var embossedLabels: Bool
    public var floatingIsland: Bool

    public init(
        accentBand: Bool = false,
        statusBar: Bool = true,
        serialPlate: Bool = false,
        embossedLabels: Bool = false,
        floatingIsland: Bool = false
    ) {
        self.accentBand = accentBand
        self.statusBar = statusBar
        self.serialPlate = serialPlate
        self.embossedLabels = embossedLabels
        self.floatingIsland = floatingIsland
    }
}

// MARK: - Built-in Layouts

extension KeyboardLayout {
    /// Current compact 3x4 grid with record button below
    public static let compact = KeyboardLayout(
        id: "compact",
        name: "Compact",
        description: "12-slot grid with record button",
        rows: 3,
        columns: 4,
        mergedRegion: nil,
        mergedContent: .record,
        hasRecordRow: true,
        features: LayoutFeatures(statusBar: true)
    )

    /// V0-style voice-first with large center record
    public static let voiceFirst = KeyboardLayout(
        id: "voiceFirst",
        name: "Voice First",
        description: "Large center mic, quick actions around",
        rows: 4,
        columns: 4,
        mergedRegion: .center,
        mergedContent: .record,
        hasRecordRow: false,
        features: LayoutFeatures(accentBand: true, statusBar: true, embossedLabels: true)
    )

    /// Single-row minimal layout for terminal-focused use
    public static let minimal = KeyboardLayout(
        id: "minimal",
        name: "Minimal",
        description: "Single row: dictate + utility keys",
        rows: 1,
        columns: 6,
        hasRecordRow: false,
        features: LayoutFeatures(statusBar: false)
    )

    /// All built-in layouts
    public static let builtIn: [KeyboardLayout] = [compact, voiceFirst, minimal]
}
