//
//  ScopeContextView.swift
//  Talkie macOS
//
//  Cream-phosphor Context hub — the consumer-facing surface for app
//  profiles, processing rules, dictionary, and one-tap action buttons.
//  Reskins ContextSettingsView's `.consumer` presentation in the Scope
//  vocabulary: dark instrument bays for hero readouts, cream paper
//  cards for lists, channel-tag rows, monospaced eyebrow chrome.
//
//  Underlying managers (ContextRuleStore, DictionaryManager,
//  WorkflowService) are reused verbatim — this file is style only.
//

import SwiftUI
import TalkieKit

// MARK: - Scope display fonts
// Mirrors ScopeHomeView / ScopeDraftsScreen. Cormorant Garamond is the
// homepage's `--font-display-modern`. Falls back to system serif if
// the font isn't installed.
// Display font lookup centralized in ScopeType.display(size:weight:) — see TalkieKit/UI/ScopeDesign.swift.

// MARK: - ScopeContextView

/// Consumer-presentation Context hub re-skinned in the Scope language.
/// Mounted by ContextSettingsView when `SettingsManager.shared.isScopeTheme`
/// is true. Everything functional flows through the existing tab content
/// views; this file only reshapes the chrome.
struct ScopeContextView: View {
    @Environment(SettingsManager.self) private var settings

    @ObservedObject private var dictionaryManager = DictionaryManager.shared
    private let workflowService = WorkflowService.shared

    @State private var selectedTab: ContextTab
    @State private var rules: [ContextRule] = []

    init(initialTab: ContextTab = .overview) {
        _selectedTab = State(initialValue: initialTab)
    }

    private var availableTabs: [ContextTab] {
        // Consumer presentation hides Playground (matches base view).
        ContextTab.allCases.filter { $0 != .playground }
    }

    private var enabledRules: [ContextRule] {
        rules.filter(\.isEnabled)
    }

    private var enabledDictionaryCount: Int {
        dictionaryManager.dictionaries.filter(\.isEnabled).count
    }

    private var activeProcessingItems: Int {
        var count = 0
        if dictionaryManager.isGloballyEnabled { count += 1 }
        if dictionaryManager.isSymbolicMappingEnabled { count += 1 }
        if dictionaryManager.isFillerRemovalEnabled { count += 1 }
        return count
    }

    private var interstitialCount: Int { workflowService.actionsForInterstitial().count }
    private var draftsCount: Int { workflowService.actionsForDrafts().count }

    var body: some View {
        VStack(spacing: 0) {
            hero

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    tabRail
                    tabContent
                    ownershipStrip
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas.ignoresSafeArea())
        .onAppear {
            loadRules()
            if !dictionaryManager.isLoaded {
                Task { await dictionaryManager.load() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextRulesDidChange)) { _ in
            loadRules()
        }
    }

    // MARK: - Header strip
    //
    // Universal 44pt top band — title names the active tab, trailing
    // chrome carries the count for that tab. Baseline-aligned with the
    // sidebar wordmark via `ScopeTopBand`.

    private var hero: some View {
        ScopeTopBand(
            title: currentTabEyebrow,
            chrome: currentTabChrome
        )
    }

    private var currentTabEyebrow: String {
        switch selectedTab {
        case .overview:    return "Context"
        case .apps:        return "Apps"
        case .processing:  return "Cleanup"
        case .dictionary:  return "Dictionary"
        case .actions:     return "Buttons"
        case .playground:  return "Playground"
        }
    }

    private var currentTabChrome: String {
        switch selectedTab {
        case .overview:    return "AT A GLANCE"
        case .apps:        return "\(enabledRules.count) PROFILE\(enabledRules.count == 1 ? "" : "S") ENABLED"
        case .processing:  return "\(activeProcessingItems) HELPER\(activeProcessingItems == 1 ? "" : "S") LIVE"
        case .dictionary:  return "\(dictionaryManager.enabledEntryCount) ENTRIES"
        case .actions:     return "\(interstitialCount + draftsCount) PLACEMENT\(interstitialCount + draftsCount == 1 ? "" : "S")"
        case .playground:  return "DEV"
        }
    }

    // MARK: - Tab rail (channel buttons)

    private var tabRail: some View {
        HStack(spacing: 0) {
            ForEach(Array(availableTabs.enumerated()), id: \.element) { idx, tab in
                tabButton(tab, channel: String(format: "CX-%02d", idx + 1))
                if idx < availableTabs.count - 1 {
                    Rectangle()
                        .fill(ScopeEdge.subtle)
                        .frame(width: 1, height: 24)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeEdge.normal, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(ScopeCanvas.surface)
        )
    }

    private func tabButton(_ tab: ContextTab, channel: String) -> some View {
        let isActive = selectedTab == tab

        return Button {
            withAnimation(ScopeMotion.snap) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(channel)
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(isActive ? ScopeAmber.solid : ScopeInk.subtle)
                    Text(tab.label(isConsumer: true).uppercased())
                        .font(ScopeType.eyebrow)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(isActive ? ScopeInk.primary : ScopeInk.faint)
                }
                Rectangle()
                    .fill(isActive ? ScopeAmber.solid : Color.clear)
                    .frame(height: 1)
                    .shadow(color: isActive ? ScopeAmber.glow : .clear, radius: 3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab content router

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            ScopeOverviewSection(
                rules: rules,
                dictionaryManager: dictionaryManager,
                workflowService: workflowService,
                onSelectTab: { newTab in
                    withAnimation(ScopeMotion.snap) {
                        selectedTab = newTab
                    }
                }
            )
        case .apps:
            ScopeAppsSection(rules: rules, onReload: loadRules)
        case .processing:
            ScopeProcessingSection()
        case .dictionary:
            ScopeDictionarySection()
        case .actions:
            ScopeActionsSection()
        case .playground:
            // Consumer presentation never shows Playground; falling back
            // to the default content for safety if someone wires it in.
            ContextPlaygroundContentBridge()
        }
    }

    // MARK: - Ownership strip

    private var ownershipStrip: some View {
        HStack(spacing: 14) {
            ownershipNode(pin: "P1", label: "Your apps", detail: "\(enabledRules.count) PROFILED")
            SignalPath(color: ScopeAmber.solid, width: 28)
            ownershipNode(pin: "P2", label: "Your rules", detail: "\(activeProcessingItems) ACTIVE · \(enabledDictionaryCount) DICTIONAR\(enabledDictionaryCount == 1 ? "Y" : "IES")")
            SignalPath(color: ScopeAmber.solid, width: 28)
            ownershipNode(pin: "P3", label: "Your text", detail: "LOCAL · NO TELEMETRY")
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func ownershipNode(pin: String, label: String, detail: String) -> some View {
        HStack(spacing: 10) {
            ChannelLabel(pin)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ScopeInk.primary)
                Text(detail)
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Helpers

    private func loadRules() {
        rules = ContextRuleStore.shared.rules
    }
}

// MARK: - Overview section (Scope-styled)

private struct ScopeOverviewSection: View {
    let rules: [ContextRule]
    @ObservedObject var dictionaryManager: DictionaryManager
    let workflowService: WorkflowService
    let onSelectTab: (ContextTab) -> Void

    private var enabledRules: [ContextRule] { rules.filter(\.isEnabled) }
    private var enabledDictionaries: [TalkieDictionary] {
        dictionaryManager.dictionaries
            .filter(\.isEnabled)
            .sorted { $0.enabledEntryCount > $1.enabledEntryCount }
    }
    private var activeProcessingItems: Int {
        var n = 0
        if dictionaryManager.isGloballyEnabled { n += 1 }
        if dictionaryManager.isSymbolicMappingEnabled { n += 1 }
        if dictionaryManager.isFillerRemovalEnabled { n += 1 }
        return n
    }
    private var interstitialCount: Int { workflowService.actionsForInterstitial().count }
    private var draftsCount: Int { workflowService.actionsForDrafts().count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Live Readout")
                Spacer()
                Text("LOCAL · NO TELEMETRY")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            instrumentBay

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                summaryCard(
                    channel: "OV-01",
                    title: "Cleanup",
                    value: "\(activeProcessingItems) helpers on",
                    detail: "Filler words, symbols, and other cleanup before paste.",
                    tab: .processing
                )
                summaryCard(
                    channel: "OV-02",
                    title: "Dictionary",
                    value: "\(dictionaryManager.enabledEntryCount) saved replacements",
                    detail: enabledDictionaries.isEmpty
                        ? "Turn on a dictionary to see replacements."
                        : "\(enabledDictionaries.count) dictionar\(enabledDictionaries.count == 1 ? "y" : "ies") active.",
                    tab: .dictionary
                )
                summaryCard(
                    channel: "OV-03",
                    title: "App Profiles",
                    value: "\(enabledRules.count) active",
                    detail: enabledRules.isEmpty
                        ? "No app profiles are active."
                        : "Different writing behavior for specific apps.",
                    tab: .apps
                )
                summaryCard(
                    channel: "OV-04",
                    title: "Buttons",
                    value: "\(interstitialCount + draftsCount) placements",
                    detail: "One-tap workflow buttons after recording or in drafts.",
                    tab: .actions
                )
            }
        }
    }

    // The dark instrument bay summarizing all four signals at once.
    private var instrumentBay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(ScopePanel.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ScopePanel.Edge.normal, lineWidth: 1)
                )
            GraticuleBackground(pitch: 24, color: ScopePanel.traceFaint, opacity: 0.55)
                .mask(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 0) {
                panelHeader
                panelBody
                panelFooter
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 196)
        .shadow(color: .black.opacity(0.20), radius: 24, y: 14)
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopePanel.trace, size: 6)
            Text("LIVE · CX-00 / CONTEXT.PIPELINE")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text("STAGES · 4")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ScopePanel.stripTop)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ScopePanel.Edge.faint)
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    private var panelBody: some View {
        HStack(spacing: 0) {
            panelTile(pin: "S1", value: "\(activeProcessingItems)", label: "CLEANUP HELPERS")
            tileDivider
            panelTile(pin: "S2", value: "\(dictionaryManager.enabledEntryCount)", label: "DICTIONARY ENTRIES")
            tileDivider
            panelTile(pin: "S3", value: "\(enabledRules.count)", label: "APP PROFILES")
            tileDivider
            panelTile(pin: "S4", value: "\(interstitialCount + draftsCount)", label: "BUTTON PLACEMENTS")
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    private var tileDivider: some View {
        Rectangle()
            .fill(ScopePanel.Edge.faint)
            .frame(width: 1)
            .padding(.vertical, 18)
    }

    private func panelTile(pin: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pin)
                .font(ScopeType.channel)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(ScopePanel.Edge.faint, lineWidth: 0.5)
                )
            Text(value)
                .font(ScopeType.display(size: 44))
                .foregroundStyle(ScopePanel.trace)
                .tracking(-0.6)
                .shadow(color: ScopePanel.traceGlow, radius: 5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var panelFooter: some View {
        HStack(spacing: 12) {
            Text("· TRIG · LIVE · SIGNAL PATH · LOCAL")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text(Date().formatted(date: .omitted, time: .shortened).uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ScopePanel.stripBottom)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ScopePanel.Edge.faint)
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    private func summaryCard(
        channel: String,
        title: String,
        value: String,
        detail: String,
        tab: ContextTab
    ) -> some View {
        ScopeOverviewCard(
            channel: channel,
            title: title,
            value: value,
            detail: detail,
            action: { onSelectTab(tab) }
        )
    }
}

// Single overview tile — cream surface, hairline border, channel pin,
// hover lifts and intensifies the amber stripe.
private struct ScopeOverviewCard: View {
    let channel: String
    let title: String
    let value: String
    let detail: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeCanvas.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHovered ? ScopeEdge.strong : ScopeEdge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 18, color: ScopeTrace.faint, opacity: 0.30)
                    .mask(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ChannelLabel(channel)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isHovered ? ScopeAmber.solid : ScopeInk.faint)
                    }

                    Text(title)
                        .font(ScopeType.display(size: 22))
                        .foregroundStyle(ScopeInk.primary)
                        .tracking(-0.3)

                    Text(value)
                        .font(ScopeType.eyebrow)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                        .phosphorGlow(radius: 3, opacity: 0.30)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(ScopeInk.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(14)
            }
            .frame(minHeight: 138, alignment: .topLeading)
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ScopeMotion.snap, value: isHovered)
    }
}

// MARK: - Apps section

private struct ScopeAppsSection: View {
    let rules: [ContextRule]
    let onReload: () -> Void

    @State private var isEnabled: Bool = ContextRuleStore.shared.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Master toggle row, channel-tagged.
            channelRow(
                channel: "A-00",
                title: "Use app-specific writing",
                detail: "Talkie rewrites differently depending on the app.",
                trailing: {
                    AnyView(
                        Toggle("", isOn: $isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: isEnabled) { _, newValue in
                                ContextRuleStore.shared.isEnabled = newValue
                            }
                    )
                }
            )

            if isEnabled {
                if rules.isEmpty {
                    emptyRow
                } else {
                    // Channel-tagged list — A-01 .. A-NN
                    VStack(spacing: 0) {
                        // Wraps the existing ContextAppsContent's data via the
                        // shared store, then renders it with our chrome. We
                        // intentionally delegate the inline editor + add UI
                        // back to the existing ContextAppsContent because it
                        // has a deep editor (LLM picker, app picker, etc).
                        ContextAppsContent(presentation: .consumer)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ScopeCanvas.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ScopeEdge.normal, lineWidth: 1)
                    )
                }
            } else {
                Text("App profiles are off. Toggle above to start matching rules to specific apps.")
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(ScopeInk.faint)
            }
        }
        .onAppear {
            isEnabled = ContextRuleStore.shared.isEnabled
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 10) {
            PhosphorDot(color: ScopeAmber.solid.opacity(0.55), size: 5)
            Text("NO PROFILES ON FILE")
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
            Spacer()
            Text("Use ContextAppsContent below to add one.")
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(ScopeInk.subtle)
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ScopeEdge.faint, lineWidth: 1)
        )
    }
}

// MARK: - Processing section

private struct ScopeProcessingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Pipeline")
                Spacer()
                Text("DETERMINISTIC · BEFORE LLM")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            // Re-skin shell wrapping the existing processing content.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ContextProcessingContent()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeCanvas.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
        }
    }
}

// MARK: - Dictionary section

private struct ScopeDictionarySection: View {
    @ObservedObject private var manager = DictionaryManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Triggers")
                Spacer()
                Text("\(manager.enabledEntryCount) ENABLED · \(manager.dictionaries.count) DICTIONAR\(manager.dictionaries.count == 1 ? "Y" : "IES")")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            // Cream paper shell over the existing dictionary content.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                DictionarySettingsContent()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(ScopeCanvas.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
        }
    }
}

// MARK: - Actions section

private struct ScopeActionsSection: View {
    @Environment(SettingsManager.self) private var settings
    private let workflowService = WorkflowService.shared

    @State private var selectedAction: Workflow?
    @State private var showingNewActionSheet = false

    private var availableWorkflows: [Workflow] { workflowService.enabledWorkflows }
    private var interstitialActions: [Workflow] { workflowService.actionsForInterstitial() }
    private var draftsActions: [Workflow] { workflowService.actionsForDrafts() }

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 22) {

            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Placements")
                Spacer()
                Text("INTERSTITIAL · DRAFTS")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
            }

            // Intro note
            HStack(alignment: .top, spacing: 10) {
                PhosphorDot(color: ScopeAmber.solid, size: 5)
                    .padding(.top, 5)
                Text("Buttons are one-tap workflows. Choose where each appears — right after recording, or while editing in drafts.")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(ScopeInk.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Default writing style card
            scopeCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardHeader("B-00", title: "Default Writing Style")
                    Text("Used when Talkie needs a default prompt for notes and quick buttons.")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(ScopeInk.muted)

                    TextEditor(text: $settings.composeAssistantPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 160)
                        .padding(10)
                        .background(ScopeCanvas.canvas)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ScopeEdge.normal, lineWidth: 0.5)
                        )

                    HStack {
                        Button("Reset style") {
                            settings.composeAssistantPrompt = SettingsManager.defaultComposeAssistantPrompt
                        }
                        .font(ScopeType.chrome)
                        .buttonStyle(.plain)
                        .foregroundStyle(ScopeInk.faint)

                        Spacer()

                        if let provider = settings.composeLLMProviderId,
                           let model = settings.composeLLMModelId {
                            Text("sticky: \(provider) / \(model)")
                                .font(ScopeType.chrome)
                                .tracking(ScopeType.Tracking.wide)
                                .foregroundStyle(ScopeInk.faint)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // Available workflows card
            scopeCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        cardHeader("B-01", title: "Available Workflows")
                        Spacer()
                        Text("\(availableWorkflows.count) AVAILABLE")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.subtle)
                    }
                    Text("Choose where each workflow should show up as a button.")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(ScopeInk.muted)

                    if availableWorkflows.isEmpty {
                        emptyHint("No workflows yet — create one below to turn it into a button.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(availableWorkflows.enumerated()), id: \.element.id) { idx, wf in
                                workflowToggleRow(wf, isLast: idx == availableWorkflows.count - 1)
                            }
                        }
                    }
                }
            }

            // New workflow row
            Button(action: { showingNewActionSheet = true }) {
                HStack(spacing: 12) {
                    ChannelLabel("NEW")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Workflow")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ScopeInk.primary)
                        Text("Create a custom LLM prompt workflow")
                            .font(ScopeType.chrome)
                            .tracking(ScopeType.Tracking.normal)
                            .foregroundStyle(ScopeInk.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ScopeInk.faint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(ScopeCanvas.surface))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ScopeEdge.normal, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // After recording card
            placementCard(
                channel: "PL-01",
                title: "After Recording",
                detail: "Buttons shown right after you finish recording.",
                workflows: interstitialActions,
                emptyHint: "Turn on \"After Recording\" for a workflow above to see it here."
            )

            // In drafts card
            placementCard(
                channel: "PL-02",
                title: "In Drafts",
                detail: "Buttons shown while editing in Compose and Drafts.",
                workflows: draftsActions,
                emptyHint: "Turn on \"Drafts\" for a workflow above to see it here."
            )
        }
        .sheet(isPresented: $showingNewActionSheet) {
            ActionEditorSheet(
                isNew: true,
                onSave: { definition in
                    Task { try? await workflowService.save(definition) }
                    showingNewActionSheet = false
                },
                onCancel: { showingNewActionSheet = false }
            )
            .frame(minWidth: 500, minHeight: 450)
        }
        .sheet(item: $selectedAction) { action in
            ActionEditorSheet(
                workflow: action.definition,
                isNew: false,
                onSave: { definition in
                    Task { try? await workflowService.save(definition) }
                    selectedAction = nil
                },
                onCancel: { selectedAction = nil }
            )
            .frame(minWidth: 500, minHeight: 450)
        }
    }

    // MARK: - Card shell

    @ViewBuilder
    private func scopeCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 6).fill(ScopeCanvas.surface))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ScopeEdge.normal, lineWidth: 1))
    }

    private func cardHeader(_ channel: String, title: String) -> some View {
        HStack(spacing: 8) {
            ChannelLabel(channel)
            Text(title.uppercased())
                .font(ScopeType.eyebrow)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.primary)
        }
    }

    // MARK: - Workflow toggle row

    @ViewBuilder
    private func workflowToggleRow(_ workflow: Workflow, isLast: Bool) -> some View {
        let pref = getPreference(for: workflow.id)

        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(workflow.color.color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(workflow.color.color.opacity(0.32), lineWidth: 0.5)
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: workflow.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(workflow.color.color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ScopeInk.primary)
                Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.normal)
                    .foregroundStyle(ScopeInk.faint)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { pref.showInInterstitial },
                set: { newValue in
                    Task { try? await workflowService.setActionContext(for: workflow.id, showInInterstitial: newValue) }
                }
            ))
            .toggleStyle(ScopePlacementToggle(label: "INT"))
            .labelsHidden()

            Toggle("", isOn: Binding(
                get: { pref.showInDrafts },
                set: { newValue in
                    Task { try? await workflowService.setActionContext(for: workflow.id, showInDrafts: newValue) }
                }
            ))
            .toggleStyle(ScopePlacementToggle(label: "DFT"))
            .labelsHidden()

            Button(action: { selectedAction = workflow }) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ScopeInk.faint)
                    .frame(width: 22, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(ScopeEdge.faint, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Edit workflow")
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(ScopeEdge.faint.opacity(0.6))
                    .frame(height: 0.5)
            }
        }
    }

    // MARK: - Placement card

    private func placementCard(channel: String, title: String, detail: String, workflows: [Workflow], emptyHint: String) -> some View {
        scopeCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(channel, title: title)
                Text(detail)
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(ScopeInk.muted)

                if workflows.isEmpty {
                    self.emptyHint(emptyHint)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(workflows.enumerated()), id: \.element.id) { idx, wf in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(wf.color.color.opacity(0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(wf.color.color.opacity(0.32), lineWidth: 0.5)
                                    )
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Image(systemName: wf.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(wf.color.color)
                                    )
                                Text(wf.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ScopeInk.primary)
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .overlay(alignment: .bottom) {
                                if idx < workflows.count - 1 {
                                    Rectangle()
                                        .fill(ScopeEdge.faint.opacity(0.6))
                                        .frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty hint

    private func emptyHint(_ text: String) -> some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopeInk.faint, size: 4)
            Text(text)
                .font(.system(size: 12, design: .serif).italic())
                .foregroundStyle(ScopeInk.faint)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func getPreference(for workflowId: UUID) -> WorkflowPreference {
        let repo = WorkflowPreferencesRepository()
        return (try? repo.fetch(for: workflowId)) ?? WorkflowPreference.defaults(for: workflowId)
    }
}

// MARK: - Scope placement toggle chip

private struct ScopePlacementToggle: ToggleStyle {
    let label: String

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(configuration.isOn ? ScopeAmber.solid : ScopeInk.subtle)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    configuration.isOn
                        ? ScopeAmber.solid.opacity(0.12)
                        : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            configuration.isOn ? ScopeAmber.solid.opacity(0.45) : ScopeEdge.normal,
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playground bridge (consumer never sees this; safety net)

private struct ContextPlaygroundContentBridge: View {
    var body: some View {
        // The base playground content is private to ContextSettingsView;
        // consumer mode hides this tab so the placeholder is acceptable.
        Text("Playground available in advanced settings.")
            .font(.system(size: 13, design: .serif).italic())
            .foregroundStyle(ScopeInk.faint)
            .padding(20)
    }
}

// MARK: - Channel row helper (file-scope)

private func channelRow(
    channel: String,
    title: String,
    detail: String,
    trailing: @escaping () -> AnyView
) -> some View {
    HStack(spacing: 12) {
        ChannelLabel(channel)
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ScopeInk.primary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(ScopeInk.muted)
        }
        Spacer()
        trailing()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
        RoundedRectangle(cornerRadius: 6)
            .fill(ScopeCanvas.surface)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 6)
            .stroke(ScopeEdge.normal, lineWidth: 1)
    )
}

#Preview {
    ScopeContextView()
        .frame(width: 1000, height: 800)
        .environment(SettingsManager.shared)
}
