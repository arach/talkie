//
//  ScopeModelsView.swift
//  Talkie macOS
//
//  Cream-phosphor Models — reframes model management as an instrument
//  bank instead of a marketplace. The page now reads as a sandwich:
//  LOCAL speech on top (the part of the stack that ships on-device and
//  has the strongest story), CLOUD intelligence + voice in the middle
//  (where most of the action actually lives), and LOCAL intelligence +
//  voice on the bottom (placeholder real-estate for the on-device LLM /
//  system-voice tier).
//
//  "What's live" is communicated inline via the amber inset stripe and
//  IN USE badge on the currently-routed row in each section — no
//  separate dispatch panel. Only mounted when
//  SettingsManager.shared.isScopeTheme is true. AppNavigation branches
//  on theme and renders ModelsContentView() for every other theme —
//  defaults stay untouched.
//

import SwiftUI
import TalkieKit
import os

private let log = Logger(subsystem: "to.talkie.app.mac", category: "ScopeModels")

// MARK: - Scope display fonts
// Cormorant Garamond is the homepage's `--font-display-modern`. Falls
// back to system serif if the font isn't installed.
// Display font lookup centralized in ScopeType.display(size:weight:) — see TalkieKit/UI/ScopeDesign.swift.

// MARK: - State enum

/// Channel state used by both STT and LLM rows. Drives the right-hand
/// badge and the inset stripe.
private enum ChannelState {
    case inUse        // selected default — amber stripe + tint
    case resident     // downloaded / installed
    case downloading  // progress in flight
    case available    // catalog-listed, not installed
    case unconfigured // API key not present

    var label: String {
        switch self {
        case .inUse:        return "IN USE"
        case .resident:     return "RESIDENT"
        case .downloading:  return "DOWNLOADING"
        case .available:    return "DOWNLOAD"
        case .unconfigured: return "NOT SET"
        }
    }

    var tint: Color {
        switch self {
        case .inUse:        return ScopeAmber.solid
        case .resident:     return ScopeInk.dim
        case .downloading:  return ScopeAmber.solid
        case .available:    return ScopeInk.faint
        case .unconfigured: return Color(red: 0.72, green: 0.32, blue: 0.18)
        }
    }
}

// MARK: - ScopeModelsView

struct ScopeModelsView: View {
    private let registry = LLMProviderRegistry.shared
    @Environment(SettingsManager.self) private var settings: SettingsManager
    private let whisperService = WhisperService.shared
    private let parakeetService = ParakeetService.shared

    @State private var downloadingWhisperModel: WhisperModel?
    @State private var whisperDownloadTask: Task<Void, Never>?
    @State private var downloadingParakeetModel: ParakeetModel?
    @State private var parakeetDownloadTask: Task<Void, Never>?
    @State private var appleIntelligenceAvailable: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScopeTopBand(
                title: "Models",
                chrome: "\(installedCount) INSTALLED · \(activeCount) ACTIVE"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section1_speech
                    section2_cloud
                    section3_local
                    ownershipFooter
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await registry.refreshModels()
            let provider = AppleLocalProvider()
            appleIntelligenceAvailable = await provider.isAvailable
        }
    }

    // MARK: - Metadata strip (legacy)
    //
    // The install/active chrome moved into the universal `ScopeTopBand`
    // at the top of the page. This computed property is left in place
    // because nothing else references it; remove on the next sweep.

    private var metaStrip: some View {
        ScopePageStrip(
            chrome: "\(installedCount) INSTALLED · \(activeCount) ACTIVE",
            framed: false
        )
    }

    // MARK: - Counts (computed)

    private var installedSTTCount: Int {
        var count = 0
        #if arch(arm64)
        count += ParakeetModel.allCases.filter { parakeetService.isModelDownloaded($0) }.count
        count += WhisperModel.allCases.filter { whisperService.isModelDownloaded($0) }.count
        #endif
        return count
    }

    private var configuredCloudCount: Int {
        var count = 0
        if settings.openaiApiKey != nil { count += 1 }
        if settings.anthropicApiKey != nil { count += 1 }
        if settings.hasValidApiKey { count += 1 } // gemini
        if settings.groqApiKey != nil { count += 1 }
        return count
    }

    private var configuredCloudTTSCount: Int {
        var count = 0
        if settings.openaiApiKey != nil { count += 1 }
        if settings.hasElevenLabsKey() { count += 1 }
        return count
    }

    private var installedCount: Int {
        installedSTTCount + configuredCloudCount + configuredCloudTTSCount
    }

    private var activeCount: Int {
        var n = 0
        if dispatchSTT != nil { n += 1 }
        if dispatchLLM != nil { n += 1 }
        return n
    }

    // MARK: - Dispatch (used for inline IN USE marker)

    /// The currently-routed STT — first resident Parakeet, else first
    /// resident Whisper. Used to mark the IN USE row inside Section 1.
    private var dispatchSTT: (family: STTFamily, name: String)? {
        #if arch(arm64)
        for m in ParakeetModel.allCases where parakeetService.isModelDownloaded(m) {
            return (.parakeet, m.sttCardName)
        }
        for m in WhisperModel.allCases where whisperService.isModelDownloaded(m) {
            return (.whisper, m.sttCardName)
        }
        #endif
        return nil
    }

    /// First configured cloud LLM provider — used to mark IN USE in
    /// the cloud intelligence column.
    private var dispatchLLM: (providerId: String, model: String)? {
        let providerOrder: [(id: String, configured: Bool)] = [
            ("anthropic", settings.anthropicApiKey != nil),
            ("openai",    settings.openaiApiKey != nil),
            ("groq",      settings.groqApiKey != nil),
            ("gemini",    settings.hasValidApiKey),
        ]
        guard let chosen = providerOrder.first(where: { $0.configured }) else {
            return nil
        }
        let defaultModelId = LLMConfig.shared.providers[chosen.id]?.defaultModel
            ?? fallbackDefaultModel(for: chosen.id)
        return (chosen.id, simplifyModelName(defaultModelId))
    }

    // MARK: - Section 1 — Local Speech (full-width sandwich top)

    private var section1_speech: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Speech · ASR",
                tag: "LOCAL",
                trailing: "\(installedSTTCount) RESIDENT · \(parakeetShown.count + whisperShown.count) HIGHLIGHTED"
            )

            #if arch(arm64)
            HStack(alignment: .top, spacing: 0) {
                speechColumn_parakeet
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(ScopeEdge.faint)
                    .frame(width: 1)
                speechColumn_whisper
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopeCanvas.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            #else
            nonAppleSiliconNotice
            #endif
        }
    }

    /// Parakeet ships 2 variants; both are worth surfacing. Add more
    /// here when the catalog grows.
    private var parakeetShown: [ParakeetModel] {
        Array(ParakeetModel.allCases.prefix(2))
    }

    /// Whisper has 4 catalog entries but only two are interesting for
    /// most users: a light one for fast turnaround and a distilled
    /// large for quality. Update this list when a better pair lands.
    private var whisperShown: [WhisperModel] {
        [.base, .distilLargeV3]
    }

    @ViewBuilder
    private var speechColumn_parakeet: some View {
        #if arch(arm64)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parakeetShown.enumerated()), id: \.element) { idx, model in
                parakeetSTTRow(model, pin: String(format: "STT-P%d", idx + 1))
                if idx < parakeetShown.count - 1 {
                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                }
            }
        }
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var speechColumn_whisper: some View {
        #if arch(arm64)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(whisperShown.enumerated()), id: \.element) { idx, model in
                whisperSTTRow(model, pin: String(format: "STT-W%d", idx + 1))
                if idx < whisperShown.count - 1 {
                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                }
            }
        }
        #else
        EmptyView()
        #endif
    }

    #if arch(arm64)
    private func parakeetSTTRow(_ model: ParakeetModel, pin: String) -> some View {
        let state = parakeetState(model)
        let menu: [ProviderRowMenuItem]? = parakeetService.isModelDownloaded(model)
            ? [ProviderRowMenuItem(label: "Delete", systemImage: "trash", action: { deleteParakeetModel(model) })]
            : nil
        return ProviderRowCell(
            pin: pin,
            name: model.sttCardName,
            caption: model.sttLanguages.uppercased(),
            metaLine: "PARAKEET · \(model.sttCardSize.uppercased())",
            state: state,
            primaryActionLabel: sttActionLabel(state),
            onPrimary: { handleParakeetTap(model) },
            menuItems: menu
        )
    }

    private func whisperSTTRow(_ model: WhisperModel, pin: String) -> some View {
        let state = whisperState(model)
        let menu: [ProviderRowMenuItem]? = whisperService.isModelDownloaded(model)
            ? [ProviderRowMenuItem(label: "Delete", systemImage: "trash", action: { deleteWhisperModel(model) })]
            : nil
        return ProviderRowCell(
            pin: pin,
            name: model.sttCardName,
            caption: model.sttLanguages.uppercased(),
            metaLine: "WHISPER · \(model.sttCardSize.uppercased())",
            state: state,
            primaryActionLabel: sttActionLabel(state),
            onPrimary: { handleWhisperTap(model) },
            menuItems: menu
        )
    }

    private func sttActionLabel(_ state: ChannelState) -> String {
        switch state {
        case .inUse:        return "ACTIVE"
        case .resident:     return "USE"
        case .downloading:  return "…"
        case .available:    return "DOWNLOAD"
        case .unconfigured: return "SET UP"
        }
    }
    #endif

    private var nonAppleSiliconNotice: some View {
        HStack(spacing: 10) {
            PhosphorDot(color: Color(red: 0.72, green: 0.32, blue: 0.18), size: 5)
            Text("APPLE SILICON REQUIRED · LOCAL STT OFFLINE")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.muted)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeEdge.faint, lineWidth: 1)
        )
    }

    private func parakeetState(_ model: ParakeetModel) -> ChannelState {
        if downloadingParakeetModel == model { return .downloading }
        if parakeetService.isModelDownloaded(model) {
            if let first = ParakeetModel.allCases.first(where: { parakeetService.isModelDownloaded($0) }),
               first == model {
                return .inUse
            }
            return .resident
        }
        return .available
    }

    private func whisperState(_ model: WhisperModel) -> ChannelState {
        if downloadingWhisperModel == model { return .downloading }
        if whisperService.isModelDownloaded(model) {
            let anyParakeet = ParakeetModel.allCases.contains(where: { parakeetService.isModelDownloaded($0) })
            if !anyParakeet,
               let first = WhisperModel.allCases.first(where: { whisperService.isModelDownloaded($0) }),
               first == model {
                return .inUse
            }
            return .resident
        }
        return .available
    }

    private func speedTierLabel(_ tier: STTModelCard.SpeedTier) -> String {
        switch tier {
        case .realtime: return "REALTIME"
        case .fast:     return "FAST"
        case .balanced: return "BALANCED"
        case .accurate: return "ACCURATE"
        }
    }

    // MARK: - Section 2 — Cloud sandwich middle (intelligence + voice)

    /// Cloud LLM providers, hand-rolled because the marketing surface
    /// doesn't want to wait on `registry.providers` to enumerate at
    /// runtime. The four rows are stable and ordered the way the user
    /// asked: OpenAI, Anthropic, Gemini, Groq.
    fileprivate struct CloudIntelligenceRow {
        let id: String
        let name: String
        let tagline: String
        let isConfigured: Bool
    }

    private var cloudIntelligenceRows: [CloudIntelligenceRow] {
        [
            CloudIntelligenceRow(
                id: "openai",
                name: "OpenAI",
                tagline: "Reasoning + vision",
                isConfigured: settings.openaiApiKey != nil
            ),
            CloudIntelligenceRow(
                id: "anthropic",
                name: "Anthropic",
                tagline: "Extended thinking",
                isConfigured: settings.anthropicApiKey != nil
            ),
            CloudIntelligenceRow(
                id: "gemini",
                name: "Gemini",
                tagline: "Multimodal · long context",
                isConfigured: settings.hasValidApiKey
            ),
            CloudIntelligenceRow(
                id: "groq",
                name: "Groq",
                tagline: "Open models · fast inference",
                isConfigured: settings.groqApiKey != nil
            ),
        ]
    }

    fileprivate struct CloudVoiceRow {
        let id: String
        let name: String
        let tagline: String
        let voiceCount: Int
        let isConfigured: Bool
    }

    private var cloudVoiceRows: [CloudVoiceRow] {
        [
            CloudVoiceRow(
                id: "openai-tts",
                name: "OpenAI TTS",
                tagline: "Alloy · Echo · Nova",
                voiceCount: OpenAITTSVoiceCatalog.voices.count,
                isConfigured: settings.openaiApiKey != nil
            ),
            CloudVoiceRow(
                id: "elevenlabs",
                name: "ElevenLabs",
                tagline: "Studio-grade narration",
                voiceCount: TTSVoiceCatalog.elevenLabsVoices.count,
                isConfigured: settings.hasElevenLabsKey()
            ),
        ]
    }

    private var section2_cloud: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Cloud · Hosted",
                tag: "INTELLIGENCE · VOICE",
                trailing: "\(configuredCloudCount + configuredCloudTTSCount) CONFIGURED"
            )

            HStack(alignment: .top, spacing: 0) {
                cloudIntelligenceColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(ScopeEdge.faint)
                    .frame(width: 1)
                cloudVoiceColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopeCanvas.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var cloudIntelligenceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            subEyebrow(
                "Intelligence · Cloud LLMs",
                trailing: "\(configuredCloudCount)/\(cloudIntelligenceRows.count)"
            )
            ForEach(Array(cloudIntelligenceRows.enumerated()), id: \.element.id) { idx, row in
                if idx > 0 {
                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                }
                let isDispatch = (dispatchLLM?.providerId == row.id)
                let defaultModel = LLMConfig.shared.providers[row.id]?.defaultModel
                    ?? fallbackDefaultModel(for: row.id)
                let totalCount = providerModelCount(for: row.id)
                ProviderRowCell(
                    pin: String(format: "CL-%02d", idx + 1),
                    name: row.name,
                    caption: row.tagline,
                    metaLine: "\(totalCount) MODELS · \(simplifyModelName(defaultModel).uppercased())",
                    state: row.isConfigured
                        ? (isDispatch ? .inUse : .resident)
                        : .unconfigured,
                    primaryActionLabel: row.isConfigured ? "MANAGE" : "CONFIGURE",
                    onPrimary: {
                        NavigationState.shared.navigateToSettings(.aiProviders)
                    },
                    menuItems: [
                        ProviderRowMenuItem(label: "Configure API key", systemImage: "key") {
                            NavigationState.shared.navigateToSettings(.aiProviders)
                        },
                        ProviderRowMenuItem(label: "Open settings", systemImage: "gear") {
                            NavigationState.shared.navigateToSettings(.aiProviders)
                        },
                    ]
                )
            }
        }
    }

    private var cloudVoiceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            subEyebrow(
                "Voice · Cloud TTS",
                trailing: "\(configuredCloudTTSCount)/\(cloudVoiceRows.count)"
            )
            ForEach(Array(cloudVoiceRows.enumerated()), id: \.element.id) { idx, row in
                if idx > 0 {
                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                }
                let isDispatch = isCloudTTSDispatch(row.id)
                ProviderRowCell(
                    pin: String(format: "CV-%02d", idx + 1),
                    name: row.name,
                    caption: row.tagline,
                    metaLine: "\(row.voiceCount) VOICES",
                    state: row.isConfigured
                        ? (isDispatch ? .inUse : .resident)
                        : .unconfigured,
                    primaryActionLabel: row.isConfigured ? "MANAGE" : "CONFIGURE",
                    onPrimary: {
                        NavigationState.shared.navigateToSettings(.aiProviders)
                    },
                    menuItems: [
                        ProviderRowMenuItem(label: "Configure API key", systemImage: "key") {
                            NavigationState.shared.navigateToSettings(.aiProviders)
                        },
                        ProviderRowMenuItem(label: "Voice settings", systemImage: "waveform") {
                            NavigationState.shared.navigateToSettings(.aiProviders)
                        },
                    ]
                )
            }
        }
    }

    private func isCloudTTSDispatch(_ id: String) -> Bool {
        let selected = settings.selectedTTSVoiceId
        switch id {
        case "openai-tts":  return selected.hasPrefix("openai:")
        case "elevenlabs":  return selected.hasPrefix("elevenlabs:")
        default:            return false
        }
    }

    // MARK: - Section 3 — Local sandwich bottom (intelligence + voice)

    fileprivate struct LocalIntelligenceRow {
        let id: String
        let name: String
        let tagline: String
        let isAvailable: Bool
    }

    private var localIntelligenceRows: [LocalIntelligenceRow] {
        [
            LocalIntelligenceRow(
                id: "apple-local",
                name: "Apple Intelligence",
                tagline: "On-device · macOS 26+",
                isAvailable: appleIntelligenceAvailable
            ),
        ]
    }

    private var systemVoiceCount: Int {
        TTSVoiceCatalog.systemVoices().count
    }

    private var section3_local: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Local · On Device",
                tag: "INTELLIGENCE · VOICE",
                trailing: localSectionTrailing
            )

            HStack(alignment: .top, spacing: 0) {
                localIntelligenceColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(ScopeEdge.faint)
                    .frame(width: 1)
                localVoiceColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(ScopeCanvas.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var localSectionTrailing: String {
        let llms = localIntelligenceRows.filter { $0.isAvailable }.count
        return "\(llms) LLM · \(systemVoiceCount) VOICES"
    }

    private var localIntelligenceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            subEyebrow(
                "Intelligence · Local LLMs",
                trailing: "\(localIntelligenceRows.filter { $0.isAvailable }.count)/\(localIntelligenceRows.count)"
            )
            ForEach(Array(localIntelligenceRows.enumerated()), id: \.element.id) { idx, row in
                if idx > 0 {
                    Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
                }
                ProviderRowCell(
                    pin: String(format: "LL-%02d", idx + 1),
                    name: row.name,
                    caption: row.tagline,
                    metaLine: row.isAvailable ? "ON-DEVICE · 1 MODEL" : "UNAVAILABLE · macOS 26+",
                    state: row.isAvailable ? .resident : .unconfigured,
                    primaryActionLabel: row.isAvailable ? "DETAILS" : "REQUIRES UPDATE",
                    onPrimary: {
                        NavigationState.shared.navigateToSettings(.aiProviders)
                    },
                    menuItems: nil
                )
            }
            if localIntelligenceRows.isEmpty {
                emptyLocalRow(message: "No local LLMs · cloud is where the action lives")
            }
        }
    }

    private var localVoiceColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            subEyebrow(
                "Voice · Local TTS",
                trailing: "\(systemVoiceCount)"
            )
            let isDispatch = settings.selectedTTSVoiceId.hasPrefix("com.apple.")
                || (!settings.selectedTTSVoiceId.hasPrefix("openai:")
                    && !settings.selectedTTSVoiceId.hasPrefix("elevenlabs:"))
            ProviderRowCell(
                pin: "LV-01",
                name: "System Voices",
                caption: "Apple-installed voices",
                metaLine: "\(systemVoiceCount) VOICES · ON-DEVICE",
                state: systemVoiceCount > 0
                    ? (isDispatch ? .inUse : .resident)
                    : .unconfigured,
                primaryActionLabel: "BROWSE",
                onPrimary: {
                    NavigationState.shared.navigateToSettings(.aiProviders)
                },
                menuItems: [
                    ProviderRowMenuItem(label: "Voice settings", systemImage: "waveform") {
                        NavigationState.shared.navigateToSettings(.aiProviders)
                    },
                ]
            )
        }
    }

    private func emptyLocalRow(message: String) -> some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopeInk.faint, size: 4)
            Text(message)
                .font(ScopeType.display(size: 13))
                .italic()
                .foregroundStyle(ScopeInk.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: - Provider counts (used by cloud intelligence rows)

    private func providerModelCount(for providerId: String) -> Int {
        let count = registry.recommendedModels(for: providerId).count
        return count == 0 ? 1 : count
    }

    // MARK: - Ownership footer

    private var ownershipFooter: some View {
        HStack(spacing: 14) {
            footerNode(pin: "P1", label: "Local", detail: "STT · ON-DEVICE")
            SignalPath(color: ScopeAmber.solid, width: 24)
            footerNode(pin: "P2", label: "Cloud", detail: "LLM · YOUR KEYS")
            SignalPath(color: ScopeAmber.solid, width: 24)
            footerNode(pin: "P3", label: "Polish", detail: "INTERSTITIAL · OPT-IN", dim: true)
        }
        .padding(.top, 4)
    }

    private func footerNode(pin: String, label: String, detail: String, dim: Bool = false) -> some View {
        HStack(spacing: 8) {
            ChannelLabel(pin)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(dim ? ScopeInk.faint : ScopeInk.primary)
                Text(detail)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Headers

    private func sectionHeader(title: String, tag: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Eyebrow(title)
                Text("· \(tag)")
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            Spacer()
            Text(trailing)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
        }
    }

    /// Sub-eyebrow used at the top of each half-column inside Sections
    /// 2 and 3. Lower-key than the section header — narrower spacing and
    /// no leading PhosphorDot (the section already established one).
    private func subEyebrow(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("· \(title.uppercased())")
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
            Spacer()
            Text(trailing)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.subtle)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScopeEdge.subtle).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func handleParakeetTap(_ model: ParakeetModel) {
        #if arch(arm64)
        if parakeetService.isModelDownloaded(model) { return }
        downloadParakeetModel(model)
        #endif
    }

    private func handleWhisperTap(_ model: WhisperModel) {
        #if arch(arm64)
        if whisperService.isModelDownloaded(model) { return }
        downloadWhisperModel(model)
        #endif
    }

    private func downloadWhisperModel(_ model: WhisperModel) {
        #if arch(arm64)
        guard !whisperService.isModelDownloaded(model) else { return }
        downloadingWhisperModel = model
        whisperDownloadTask = Task {
            do {
                try await whisperService.downloadModel(model)
            } catch is CancellationError {
                log.debug("Whisper download cancelled")
            } catch {
                log.error("Whisper download failed: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run {
                downloadingWhisperModel = nil
                whisperDownloadTask = nil
            }
        }
        #endif
    }

    private func deleteWhisperModel(_ model: WhisperModel) {
        #if arch(arm64)
        do {
            try whisperService.deleteModel(model)
        } catch {
            log.error("Whisper delete failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func downloadParakeetModel(_ model: ParakeetModel) {
        #if arch(arm64)
        guard !parakeetService.isModelDownloaded(model) else { return }
        downloadingParakeetModel = model
        parakeetDownloadTask = Task {
            do {
                try await parakeetService.downloadModel(model)
            } catch is CancellationError {
                log.debug("Parakeet download cancelled")
            } catch {
                log.error("Parakeet download failed: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run {
                downloadingParakeetModel = nil
                parakeetDownloadTask = nil
            }
        }
        #endif
    }

    private func deleteParakeetModel(_ model: ParakeetModel) {
        #if arch(arm64)
        do {
            try parakeetService.deleteModel(model)
        } catch {
            log.error("Parakeet delete failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    // MARK: - Helpers

    private func fallbackDefaultModel(for providerId: String) -> String {
        switch providerId {
        case "openai":    return "gpt-4o-mini"
        case "anthropic": return "claude-3-5-sonnet-20241022"
        case "gemini":    return "gemini-1.5-flash-latest"
        case "groq":      return "llama-3.3-70b-versatile"
        default:          return ""
        }
    }

    private func simplifyModelName(_ id: String) -> String {
        id
            .replacingOccurrences(of: "claude-opus-4-6", with: "Opus 4.6")
            .replacingOccurrences(of: "claude-sonnet-4-6", with: "Sonnet 4.6")
            .replacingOccurrences(of: "claude-sonnet-4-5-20250929", with: "Sonnet 4.5")
            .replacingOccurrences(of: "claude-sonnet-4-20250514", with: "Sonnet 4")
            .replacingOccurrences(of: "claude-3-5-sonnet-20241022", with: "Sonnet 3.5")
            .replacingOccurrences(of: "claude-3-haiku-20240307", with: "Haiku 3")
            .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
            .replacingOccurrences(of: "gpt-4o", with: "4o")
            .replacingOccurrences(of: "gpt-5.2-chat-latest", with: "5.2 Chat")
            .replacingOccurrences(of: "gemini-1.5-flash-latest", with: "1.5 Flash")
            .replacingOccurrences(of: "gemini-2.0-flash", with: "2.0 Flash")
            .replacingOccurrences(of: "llama-3.3-70b-versatile", with: "Llama 3.3 70B")
    }
}

// MARK: - STT family tag

private enum STTFamily {
    case parakeet
    case whisper

    var icon: String {
        switch self {
        case .parakeet: return "waveform.path.ecg"
        case .whisper:  return "waveform"
        }
    }
}


// MARK: - Provider row cell (shared by Sections 2 + 3)

private struct ProviderRowMenuItem {
    let label: String
    let systemImage: String
    let action: () -> Void
}

/// Compact horizontal row shared by all four sub-columns in Sections 2
/// and 3. Single-line title row, single-line meta row, trailing
/// `CONFIGURE →` / `MANAGE →` affordance. Hover lifts the trailing
/// arrow only — no whole-row translate, since rows are stacked tightly.
private struct ProviderRowCell: View {
    let pin: String
    let name: String
    let caption: String
    let metaLine: String
    let state: ChannelState
    let primaryActionLabel: String
    let onPrimary: () -> Void
    let menuItems: [ProviderRowMenuItem]?

    @State private var isHovered = false

    var body: some View {
        Button(action: onPrimary) {
            HStack(alignment: .center, spacing: 12) {
                pinChip
                VStack(alignment: .leading, spacing: 3) {
                    titleLine
                    metaSubline
                }
                Spacer(minLength: 8)
                stateBadge
                trailingActions
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if state == .inUse {
                    Rectangle().fill(ScopeAmber.solid).frame(width: 2).allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var pinChip: some View {
        Text(pin)
            .font(ScopeType.channel)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(state == .inUse ? ScopeAmber.solid : ScopeInk.faint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(state == .inUse ? ScopeAmber.solid.opacity(0.45) : ScopeEdge.faint, lineWidth: 0.5)
            )
    }

    private var titleLine: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(ScopeType.display(size: 15))
                .foregroundStyle(state == .unconfigured ? ScopeInk.muted : ScopeInk.primary)
                .tracking(-0.2)
                .lineLimit(1)
            Text("·")
                .font(ScopeType.chrome)
                .foregroundStyle(ScopeInk.faint)
            Text(caption)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var metaSubline: some View {
        Text(metaLine)
            .font(ScopeType.chrome)
            .tracking(ScopeType.Tracking.wide)
            .foregroundStyle(ScopeInk.subtle)
            .lineLimit(1)
    }

    @ViewBuilder
    private var stateBadge: some View {
        HStack(spacing: 5) {
            if state == .inUse {
                PhosphorDot(color: ScopeAmber.solid, size: 5)
            } else if state == .resident {
                PhosphorDot(color: ScopeAmber.solid, size: 4)
            }
            Text(badgeLabel)
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(badgeTint)
                .phosphorGlow(
                    color: badgeTint,
                    radius: state == .inUse ? 3 : 0,
                    opacity: state == .inUse ? 0.32 : 0
                )
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(state == .inUse ? ScopeAmber.solid.opacity(0.4) : ScopeEdge.faint, lineWidth: 0.5)
        )
    }

    private var badgeLabel: String {
        switch state {
        case .inUse:        return "IN USE"
        case .resident:     return "CONNECTED"
        case .downloading:  return "DOWNLOADING"
        case .available:    return "AVAILABLE"
        case .unconfigured: return "NOT SET"
        }
    }

    private var badgeTint: Color {
        switch state {
        case .inUse, .resident, .downloading: return ScopeAmber.solid
        case .available:                       return ScopeInk.faint
        case .unconfigured:                    return Color(red: 0.72, green: 0.32, blue: 0.18)
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(primaryActionLabel)
                    .font(ScopeType.channel)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(state == .unconfigured ? ScopeAmber.solid : ScopeInk.subtle)
                    .phosphorGlow(
                        color: ScopeAmber.solid,
                        radius: state == .unconfigured ? (isHovered ? 4 : 0) : 0,
                        opacity: state == .unconfigured ? (isHovered ? 0.32 : 0) : 0
                    )
                Text("→")
                    .font(ScopeType.channel)
                    .foregroundStyle(state == .unconfigured ? ScopeAmber.solid : ScopeInk.subtle)
                    .offset(x: isHovered ? 2 : 0)
                    .animation(ScopeMotion.snap, value: isHovered)
            }
            if let menuItems = menuItems, !menuItems.isEmpty {
                Menu {
                    ForEach(Array(menuItems.enumerated()), id: \.offset) { _, item in
                        Button(action: item.action) {
                            Label(item.label, systemImage: item.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ScopeInk.faint)
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var rowBackground: some View {
        ZStack {
            Color.clear
            if state == .inUse {
                ScopeAmber.tintSubtle
            } else if isHovered {
                ScopeCanvas.canvasAlt.opacity(0.30)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScopeModelsView()
        .environment(SettingsManager.shared)
        .frame(width: 1000, height: 900)
        .background(ScopeCanvas.canvas)
}
