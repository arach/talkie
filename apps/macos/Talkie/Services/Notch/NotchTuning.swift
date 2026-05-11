//
//  NotchTuning.swift
//  Talkie
//
//  Debug tuning parameters for the notch overlay.
//  Values match Agent's NotchTuning exactly.
//

import Foundation

@MainActor
@Observable
final class NotchTuning {
    static let shared = NotchTuning()

    nonisolated static let liveSuiteName = "jdi.talkie.notch.lab"
    nonisolated static let liveHoverPokeOutKey = "hoverPokeOut"
    nonisolated static let liveActivePokeOutKey = "activePokeOut"
    nonisolated static let liveTopOuterRadiusKey = "topOuterRadius"
    nonisolated static let liveLeftTopOuterRadiusKey = "leftTopOuterRadius"
    nonisolated static let liveRightTopOuterRadiusKey = "rightTopOuterRadius"
    nonisolated static let liveTopInnerRadiusKey = "topInnerRadius"
    nonisolated static let liveBottomRadiusKey = "bottomRadius"
    nonisolated static let liveNotchOverlapKey = "notchOverlap"
    nonisolated static let liveInnerCurveModeKey = "innerCurveMode"
    nonisolated static let liveHeightInsetKey = "heightInset"

    // MARK: - Particle Parameters (match Agent)

    var particleCount: Int = 14
    var particleSpeed: Double = 0.35
    var particleSize: Double = 2.0
    var particleOpacity: Double = 0.5

    // MARK: - Line / Pulse (match Agent)

    var lineWidth: Double = 60
    var lineHeight: Double = 2
    var pulseSpeed: Double = 1.2

    // MARK: - Animation (match Agent)

    var showAnimationDuration: Double = 0.15
    var springResponse: Double = 0.2
    var springDamping: Double = 0.75

    // MARK: - Notch Geometry (live configurable)

    var hoverPokeOut: Double = 38 {
        didSet { persist(\.hoverPokeOut, value: hoverPokeOut, liveKey: Self.liveHoverPokeOutKey) }
    }
    var activePokeOut: Double = 58 {
        didSet { persist(\.activePokeOut, value: activePokeOut, liveKey: Self.liveActivePokeOutKey) }
    }
    // Legacy mirrored control (kept for harness/back-compat).
    var topOuterRadius: Double = 15 {
        didSet { persist(\.topOuterRadius, value: topOuterRadius, liveKey: Self.liveTopOuterRadiusKey) }
    }
    var leftTopOuterRadius: Double = 15 {
        didSet { persist(\.leftTopOuterRadius, value: leftTopOuterRadius, liveKey: Self.liveLeftTopOuterRadiusKey) }
    }
    var rightTopOuterRadius: Double = 15 {
        didSet { persist(\.rightTopOuterRadius, value: rightTopOuterRadius, liveKey: Self.liveRightTopOuterRadiusKey) }
    }
    var topInnerRadius: Double = 0 {
        didSet { persist(\.topInnerRadius, value: topInnerRadius, liveKey: Self.liveTopInnerRadiusKey) }
    }
    var bottomRadius: Double = 14 {
        didSet { persist(\.bottomRadius, value: bottomRadius, liveKey: Self.liveBottomRadiusKey) }
    }
    var notchOverlap: Double = 7 {
        didSet { persist(\.notchOverlap, value: notchOverlap, liveKey: Self.liveNotchOverlapKey) }
    }
    var heightInset: Double = 2 {
        didSet { persist(\.heightInset, value: heightInset, liveKey: Self.liveHeightInsetKey) }
    }
    var innerCurveModeRawValue: String = NotchInnerCurveMode.canonicalDownward.rawValue {
        didSet { persist(\.innerCurveModeRawValue, value: innerCurveModeRawValue, liveKey: Self.liveInnerCurveModeKey) }
    }

    var innerCurveMode: NotchInnerCurveMode {
        NotchInnerCurveMode(rawValue: innerCurveModeRawValue) ?? .canonicalDownward
    }

    @ObservationIgnored
    private let liveDefaults = UserDefaults(suiteName: NotchTuning.liveSuiteName)

    @ObservationIgnored
    private var isLoading = true

    private init() {
        let config = TalkieSettingsConfigurationStore.shared.configuration.notchLab
        hoverPokeOut = config.hoverPokeOut
        activePokeOut = config.activePokeOut
        topOuterRadius = config.topOuterRadius
        leftTopOuterRadius = config.leftTopOuterRadius
        rightTopOuterRadius = config.rightTopOuterRadius
        topInnerRadius = config.topInnerRadius
        bottomRadius = config.bottomRadius
        notchOverlap = config.notchOverlap
        heightInset = config.heightInset
        innerCurveModeRawValue = config.innerCurveModeRawValue
        isLoading = false
        syncMirrors()
    }

    func syncMirrors() {
        liveDefaults?.set(hoverPokeOut, forKey: Self.liveHoverPokeOutKey)
        liveDefaults?.set(activePokeOut, forKey: Self.liveActivePokeOutKey)
        liveDefaults?.set(topOuterRadius, forKey: Self.liveTopOuterRadiusKey)
        liveDefaults?.set(leftTopOuterRadius, forKey: Self.liveLeftTopOuterRadiusKey)
        liveDefaults?.set(rightTopOuterRadius, forKey: Self.liveRightTopOuterRadiusKey)
        liveDefaults?.set(topInnerRadius, forKey: Self.liveTopInnerRadiusKey)
        liveDefaults?.set(bottomRadius, forKey: Self.liveBottomRadiusKey)
        liveDefaults?.set(notchOverlap, forKey: Self.liveNotchOverlapKey)
        liveDefaults?.set(heightInset, forKey: Self.liveHeightInsetKey)
        liveDefaults?.set(innerCurveModeRawValue, forKey: Self.liveInnerCurveModeKey)
    }

    private func persist<Value>(
        _ keyPath: WritableKeyPath<TalkieSettingsConfiguration.NotchLab, Value>,
        value: Value,
        liveKey: String
    ) {
        guard !isLoading else { return }
        TalkieSettingsConfigurationStore.shared.update { configuration in
            configuration.notchLab[keyPath: keyPath] = value
        }
        liveDefaults?.set(value, forKey: liveKey)
    }
}
