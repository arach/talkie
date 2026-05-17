//
//  ContextSettingsView.swift
//  Talkie macOS
//
//  Unified context settings: app profiles, processing rules, dictionary, actions
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Context Tab

enum ContextTab: String, CaseIterable {
    case overview
    case apps
    case processing
    case dictionary
    case actions
    case playground

    func label(isConsumer: Bool) -> String {
        switch self {
        case .overview: return "Overview"
        case .apps: return "Apps"
        case .processing: return isConsumer ? "Cleanup" : "Processing"
        case .dictionary: return "Dictionary"
        case .actions: return isConsumer ? "Buttons" : "Actions"
        case .playground: return "Playground"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.3.layers.3d"
        case .apps: return "app.badge.checkmark"
        case .processing: return "arrow.right.arrow.left"
        case .dictionary: return "character.book.closed"
        case .actions: return "sparkles"
        case .playground: return "terminal"
        }
    }
}

// MARK: - Context Settings View

enum ContextSettingsPresentation: String, Sendable {
    case settings
    case consumer
}

struct ContextSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    let presentation: ContextSettingsPresentation
    @State private var selectedTab: ContextTab = .overview

    init(
        presentation: ContextSettingsPresentation = .settings,
        initialTab: ContextTab = .overview
    ) {
        self.presentation = presentation
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            switch presentation {
            case .settings:
                SettingsPageContainer {
                    SettingsPageHeader(
                        icon: "square.stack.3d.forward.dottedline",
                        title: "CONTEXT",
                        subtitle: "What happens to your text, and where."
                    )
                } content: {
                    contextContent
                }
            case .consumer:
                if settingsManager.isScopeTheme {
                    ScopeContextView(initialTab: selectedTab)
                } else {
                    TalkiePage("ContextRules", title: "Context") {
                        consumerIntro
                        contextContent
                    }
                }
            }
        }
        .onAppear {
            ensureSelectedTabIsVisible()
        }
        .onChange(of: settingsManager.settingsAudience) { _, _ in
            ensureSelectedTabIsVisible()
        }
    }

    private var consumerIntro: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "square.stack.3d.forward.dottedline")
                .font(Theme.current.fontHeadline)
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Shape how Talkie cleans up text, adapts to apps, and surfaces one-tap buttons.")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text("Advanced controls still live in Settings.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            Button("Open Advanced Controls") {
                NavigationState.shared.navigateToSettings(.context)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    @ViewBuilder
    private var contextContent: some View {
        tabPicker

        switch selectedTab {
        case .overview:
            ContextOverviewContent(presentation: presentation) { tab in
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTab = tab
                }
            }
        case .apps:
            ContextAppsContent(presentation: presentation)
        case .processing:
            ContextProcessingContent()
        case .dictionary:
            DictionarySettingsContent()
        case .actions:
            ActionsSettingsContent(presentation: presentation)
        case .playground:
            ContextPlaygroundContent()
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    private var availableTabs: [ContextTab] {
        if presentation == .settings && settingsManager.settingsAudience.canAccess(.pro) {
            return ContextTab.allCases
        }

        return ContextTab.allCases.filter { $0 != .playground }
    }

    private func tabButton(_ tab: ContextTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: presentation == .consumer ? 11 : 9))
                Text(tab.label(isConsumer: presentation == .consumer))
                    .font(presentation == .consumer ? Theme.current.fontSMBold : Theme.current.fontXSBold)
            }
            .foregroundColor(selectedTab == tab ? Theme.current.foreground : Theme.current.foregroundSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                selectedTab == tab
                    ? Theme.current.backgroundTertiary
                    : Color.clear
            )
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
    }

    private func ensureSelectedTabIsVisible() {
        if !availableTabs.contains(selectedTab) {
            selectedTab = .overview
        }
    }
}

// MARK: - Overview Tab Content

private struct ContextOverviewContent: View {
    @ObservedObject private var dictionaryManager = DictionaryManager.shared
    private let workflowService = WorkflowService.shared
    private let workflowPreferences = WorkflowPreferencesRepository()

    let presentation: ContextSettingsPresentation
    @State private var rules: [ContextRule] = []

    let onSelectTab: (ContextTab) -> Void

    private var isConsumer: Bool {
        presentation == .consumer
    }

    private var enabledRules: [ContextRule] {
        rules.filter(\.isEnabled)
    }

    private var interstitialCount: Int {
        workflowService.actionsForInterstitial().count
    }

    private var draftsCount: Int {
        workflowService.actionsForDrafts().count
    }

    private var enabledDictionaryCount: Int {
        dictionaryManager.dictionaries.filter(\.isEnabled).count
    }

    private var enabledDictionaries: [TalkieDictionary] {
        dictionaryManager.dictionaries
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.enabledEntryCount != rhs.enabledEntryCount {
                    return lhs.enabledEntryCount > rhs.enabledEntryCount
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var sortedPreviewRules: [ContextRule] {
        enabledRules.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var activeProcessingItems: Int {
        var count = 0
        if dictionaryManager.isGloballyEnabled { count += 1 }
        if dictionaryManager.isSymbolicMappingEnabled { count += 1 }
        if dictionaryManager.isFillerRemovalEnabled { count += 1 }
        return count
    }

    private var processingPreviewItems: [OverviewPreviewItem] {
        var items: [OverviewPreviewItem] = []

        if dictionaryManager.isGloballyEnabled {
            items.append(OverviewPreviewItem(
                id: "dictionary-processing",
                title: "Dictionary replacements",
                detail: "\(dictionaryManager.enabledEntryCount) enabled entries available",
                tint: .cyan
            ))
        }

        if dictionaryManager.isSymbolicMappingEnabled {
            items.append(OverviewPreviewItem(
                id: "symbolic-mapping",
                title: "Symbolic mapping",
                detail: "Converts spoken protocol words into symbols",
                tint: .cyan
            ))
        }

        if dictionaryManager.isFillerRemovalEnabled {
            items.append(OverviewPreviewItem(
                id: "filler-removal",
                title: "Filler removal",
                detail: "Strips common ums, uhs, and verbal padding",
                tint: .cyan
            ))
        }

        return items
    }

    private var dictionaryPreviewItems: [OverviewPreviewItem] {
        enabledDictionaries.prefix(3).map { dictionary in
            let detail: String

            if let firstEntry = dictionary.enabledEntries.first {
                let extraCount = max(0, dictionary.enabledEntryCount - 1)
                let suffix = extraCount > 0 ? " +\(extraCount) more" : ""
                detail = "\(firstEntry.trigger) -> \(firstEntry.replacement)\(suffix)"
            } else {
                detail = "No enabled entries yet"
            }

            return OverviewPreviewItem(
                id: dictionary.id.uuidString,
                title: dictionary.name,
                detail: detail,
                tint: .blue
            )
        }
    }

    private var appRulePreviewItems: [OverviewPreviewItem] {
        sortedPreviewRules.prefix(3).map { rule in
            let behaviorLabel: String = switch rule.behavior {
            case .autoRefine:
                "Refines in \(rule.appSummary)"
            case .autoInterstitial:
                "Opens interstitial in \(rule.appSummary)"
            case .protocolProcessor:
                "Runs protocol processor in \(rule.appSummary)"
            }

            return OverviewPreviewItem(
                id: rule.id.uuidString,
                title: rule.name,
                detail: behaviorLabel,
                tint: color(for: rule.behavior)
            )
        }
    }

    private var interstitialActions: [Workflow] {
        workflowService.actionsForInterstitial()
    }

    private var draftsActions: [Workflow] {
        workflowService.actionsForDrafts()
    }

    private var actionPreviewItems: [OverviewPreviewItem] {
        var previews: [OverviewPreviewItem] = []
        var seenIDs = Set<UUID>()

        for workflow in interstitialActions + draftsActions {
            guard seenIDs.insert(workflow.id).inserted else { continue }

            let scope = actionScopeSummary(for: workflow.id)
            let appearsInInterstitial = interstitialActions.contains(workflow)
            let appearsInDrafts = draftsActions.contains(workflow)
            let contextLabel: String

            if appearsInInterstitial && appearsInDrafts {
                contextLabel = "Interstitial and drafts"
            } else if appearsInInterstitial {
                contextLabel = "Interstitial"
            } else {
                contextLabel = "Drafts"
            }

            previews.append(OverviewPreviewItem(
                id: workflow.id.uuidString,
                title: workflow.name,
                detail: scope == "All apps" ? contextLabel : "\(contextLabel) · \(scope)",
                tint: workflow.color.color
            ))

            if previews.count == 3 {
                break
            }
        }

        return previews
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: isConsumer ? "At a Glance" : "RULES OVERVIEW",
                subtitle: isConsumer
                    ? "See how Talkie currently cleans up text, adapts to apps, and shows buttons."
                    : "One place to understand what is applied before text is pasted."
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                alignment: .leading,
                spacing: Spacing.sm
            ) {
                summaryCard(
                    title: isConsumer ? "Cleanup" : "Global Processing",
                    value: isConsumer ? "\(activeProcessingItems) helpers on" : "\(activeProcessingItems) active",
                    detail: isConsumer
                        ? "Filler words, symbols, and other cleanup before paste."
                        : "What gets applied before text is pasted.",
                    color: .cyan,
                    previews: processingPreviewItems,
                    emptyPreview: isConsumer
                        ? "No cleanup helpers are turned on right now."
                        : "No global processing helpers are enabled right now."
                ) {
                    onSelectTab(.processing)
                }

                summaryCard(
                    title: isConsumer ? "Dictionary" : "Dictionary Rules",
                    value: isConsumer ? "\(dictionaryManager.enabledEntryCount) saved replacements" : "\(dictionaryManager.enabledEntryCount) enabled entries",
                    detail: isConsumer
                        ? "Saved replacements and preferred terminology."
                        : (enabledDictionaryCount == 1 ? "1 dictionary is currently active." : "\(enabledDictionaryCount) dictionaries are currently active."),
                    color: .blue,
                    previews: dictionaryPreviewItems,
                    emptyPreview: isConsumer
                        ? "Turn on a dictionary to preview replacements here."
                        : "Enable a dictionary to preview example replacements here."
                ) {
                    onSelectTab(.dictionary)
                }

                summaryCard(
                    title: isConsumer ? "App Profiles" : "App Rules",
                    value: isConsumer ? "\(enabledRules.count) active" : "\(enabledRules.count) enabled",
                    detail: isConsumer
                        ? "Different writing behavior for specific apps."
                        : "Per-app prompts and model overrides.",
                    color: .green,
                    previews: appRulePreviewItems,
                    emptyPreview: isConsumer
                        ? "No app profiles are active."
                        : "No app rules are enabled."
                ) {
                    onSelectTab(.apps)
                }

                summaryCard(
                    title: isConsumer ? "Buttons" : "Action Rules",
                    value: isConsumer ? "\(interstitialCount + draftsCount) placements" : "\(interstitialCount) interstitial, \(draftsCount) drafts",
                    detail: isConsumer
                        ? "One-tap workflow buttons after recording or in drafts."
                        : "Workflow buttons available from context-aware surfaces.",
                    color: .orange,
                    previews: actionPreviewItems,
                    emptyPreview: isConsumer
                        ? "No workflow buttons are configured yet."
                        : "No workflow actions are configured for these contexts."
                ) {
                    onSelectTab(.actions)
                }
            }
        }
        .onAppear {
            if !dictionaryManager.isLoaded {
                Task { await dictionaryManager.load() }
            }
            loadRules()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextRulesDidChange)) { _ in
            loadRules()
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(isConsumer ? Theme.current.fontSMBold : Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)
            Text(subtitle)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        detail: String,
        color: Color,
        previews: [OverviewPreviewItem],
        emptyPreview: String,
        action: @escaping () -> Void
    ) -> some View {
        OverviewSummaryCard(
            title: title,
            value: value,
            detail: detail,
            color: color,
            previews: previews,
            emptyPreview: emptyPreview,
            ctaLabel: isConsumer ? "Review" : "Open section",
            usesUppercaseTitle: !isConsumer,
            action: action
        )
    }

    private func displayName(for bundleID: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        let appName = FileManager.default
            .displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
        return appName.isEmpty ? bundleID : appName
    }

    private func loadRules() {
        rules = ContextRuleStore.shared.rules
    }

    private func color(for behavior: ContextRuleBehavior) -> Color {
        switch behavior {
        case .autoRefine:
            .green
        case .autoInterstitial:
            .orange
        case .protocolProcessor:
            .cyan
        }
    }

    private func actionScopeSummary(for workflowID: UUID) -> String {
        guard let preference = try? workflowPreferences.fetch(for: workflowID) else {
            return "All apps"
        }

        let totalCount = preference.appBundleIDs.count
        let appNames = preference.appBundleIDs.prefix(2).map(displayName(for:))
        switch appNames.count {
        case 0:
            return "All apps"
        case 1:
            return appNames[0]
        case 2:
            return "\(appNames[0]) +\(totalCount - 1)"
        default:
            return "\(appNames[0]) +\(totalCount - 1)"
        }
    }
}

private struct OverviewPreviewItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let tint: Color
}

private struct OverviewSummaryCard: View {
    private static let maxVisiblePreviews = 2
    private static let cardHeight: CGFloat = 164

    let title: String
    let value: String
    let detail: String
    let color: Color
    let previews: [OverviewPreviewItem]
    let emptyPreview: String
    let ctaLabel: String
    let usesUppercaseTitle: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var visiblePreviews: [OverviewPreviewItem] {
        Array(previews.prefix(Self.maxVisiblePreviews))
    }

    private var remainingPreviewCount: Int {
        max(0, previews.count - visiblePreviews.count)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 3, height: 14)

                    Text(usesUppercaseTitle ? title.uppercased() : title)
                        .font(usesUppercaseTitle ? Theme.current.fontXSBold : Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                }

                Text(value)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text(detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if previews.isEmpty {
                    Text(emptyPreview)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.75))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.xs)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(visiblePreviews) { preview in
                            HStack(alignment: .top, spacing: Spacing.xs) {
                                Circle()
                                    .fill(preview.tint.opacity(0.9))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preview.title)
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(Theme.current.foreground)
                                        .lineLimit(1)

                                    Text(preview.detail)
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        if remainingPreviewCount > 0 {
                            Text("+\(remainingPreviewCount) more")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.75))
                        }
                    }
                    .padding(.top, Spacing.xs)
                }

                Spacer(minLength: 0)

                HStack(spacing: Spacing.xs) {
                    Text(ctaLabel)
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(color)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color)
                }
                .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, minHeight: Self.cardHeight, maxHeight: Self.cardHeight, alignment: .topLeading)
            .opacity(isHovered ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .settingsSectionCard(padding: Spacing.md)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Playground Tab Content

private struct ContextPlaygroundContent: View {
    @ObservedObject private var dictionaryManager = DictionaryManager.shared
    private let workflowService = WorkflowService.shared
    private let workflowPreferences = WorkflowPreferencesRepository()

    @State private var rules: [ContextRule] = []
    @State private var selectedBundleID: String = ""
    @State private var inputText: String = SampleScenario.slack.sampleText
    @State private var result: ContextPlaygroundResult?
    @State private var lastRunAt: Date?

    private enum SampleScenario: String, CaseIterable {
        case slack = "Slack"
        case email = "Email"
        case terminal = "Terminal"

        var sampleText: String {
            switch self {
            case .slack:
                return "Hey team um the build is green now and I pushed the fix to main. Can someone sanity check the onboarding flow before we ship it?"
            case .email:
                return "Hi there uh I wanted to follow up on the Q2 review. Could you send me the latest draft by tomorrow afternoon so I can incorporate feedback?"
            case .terminal:
                return "git checkout dash b feature slash context playground && pnpm test dash dash filter context"
            }
        }
    }

    private struct PlaygroundAppOption: Identifiable {
        let bundleID: String
        let name: String

        var id: String { bundleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerCard
            configurationCard

            if let result {
                stageGrid(result)
                outputCard(result)
            }
        }
        .task {
            if !dictionaryManager.isLoaded {
                await dictionaryManager.load()
            }
            loadRules()
            if selectedBundleID.isEmpty {
                selectedBundleID = appOptions.first?.bundleID ?? ""
            }
            runSimulation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextRulesDidChange)) { _ in
            loadRules()
            runSimulation()
        }
        .onChange(of: selectedBundleID) { _, _ in
            runSimulation()
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "terminal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 30, height: 30)
                .background(.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("CONTEXT PLAYGROUND")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Developer-only simulator for a target app. Pick an app, enter sample dictation, and inspect which processing, app rules, and actions would be involved.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            if let lastRunAt {
                Text(lastRunAt, format: .dateTime.hour().minute().second())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Scenario")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Nothing here changes live rules or the rest of Settings.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Button("Simulate") {
                    runSimulation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedBundleID.isEmpty)
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("App")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 44, alignment: .leading)

                Picker("", selection: $selectedBundleID) {
                    ForEach(appOptions) { option in
                        Text(option.name).tag(option.bundleID)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 280, alignment: .leading)

                if !selectedBundleID.isEmpty {
                    HStack(spacing: Spacing.xs) {
                        AppIconView(bundleIdentifier: selectedBundleID, size: 18)
                        Text(selectedBundleID)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()
            }

            HStack(spacing: Spacing.xs) {
                ForEach(SampleScenario.allCases, id: \.self) { scenario in
                    Button(scenario.rawValue) {
                        inputText = scenario.sampleText
                        runSimulation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Sample Dictation")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                TextEditor(text: $inputText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .frame(minHeight: 140)
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func stageGrid(_ result: ContextPlaygroundResult) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: Spacing.sm
        ) {
            stageCard(title: "Processing", color: .cyan) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    stageLine("Filler Removal", enabled: dictionaryManager.isFillerRemovalEnabled, detail: result.fillerRemovalCount == 0 ? "No filler words removed" : "\(result.fillerRemovalCount) removed")
                    stageLine("Symbolic Mapping", enabled: dictionaryManager.isSymbolicMappingEnabled, detail: result.symbolicReplacementCount == 0 ? "No symbol phrases matched" : "\(result.symbolicReplacementCount) phrase matches")
                    stageLine("Dictionary", enabled: dictionaryManager.isGloballyEnabled, detail: result.dictionaryReplacementCount == 0 ? "No dictionary replacements" : "\(result.dictionaryReplacementCount) replacements")
                }
            }

            stageCard(title: "App Rule", color: .green) {
                if let rule = result.matchedRule {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(rule.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text(ruleBehaviorSummary(rule.behavior))
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text(rule.prompt)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .lineLimit(4)
                    }
                } else {
                    Text(ContextRuleStore.shared.isEnabled ? "No enabled app rule matches this app." : "App profiles are disabled.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            stageCard(title: "Actions", color: .orange) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    actionPreviewLine(
                        label: "Interstitial",
                        actions: result.interstitialActions,
                        empty: "No matching interstitial actions"
                    )
                    actionPreviewLine(
                        label: "Drafts",
                        actions: result.draftsActions,
                        empty: "No matching drafts actions"
                    )
                }
            }

            stageCard(title: "Outcome", color: .purple) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(result.outcomeTitle)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(result.outcomeDetail)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func outputCard(_ result: ContextPlaygroundResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.purple)
                    .frame(width: 3, height: 14)

                Text("PREPARED TEXT")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("\(result.processedText.count) chars")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            ScrollView {
                Text(result.processedText.isEmpty ? "No prepared text yet." : result.processedText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 140)
            .padding(Spacing.sm)
            .background(Theme.current.backgroundTertiary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(Theme.current.divider, lineWidth: 0.5)
            )

            if !result.replacements.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Triggered Replacements")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    ForEach(result.replacements, id: \.trigger) { replacement in
                        HStack(spacing: Spacing.xs) {
                            Text(replacement.trigger)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.current.foreground)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text(replacement.replacement)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                            Spacer()
                            Text("x\(replacement.count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func stageCard<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: 14)

                Text(title.uppercased())
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            content()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .settingsSectionCard(padding: Spacing.md)
    }

    private func stageLine(_ title: String, enabled: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(enabled ? Color.green : Theme.current.foregroundMuted.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foreground)
            }

            Text(detail)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
    }

    private func actionPreviewLine(label: String, actions: [Workflow], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foreground)

            if actions.isEmpty {
                Text(empty)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            } else {
                Text(actions.prefix(3).map(\.name).joined(separator: ", "))
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var appOptions: [PlaygroundAppOption] {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var orderedBundleIDs: [String] = []
        var seen = Set<String>()

        func append(_ bundleID: String?) {
            guard let bundleID, !bundleID.isEmpty, seen.insert(bundleID).inserted else { return }
            orderedBundleIDs.append(bundleID)
        }

        append(frontmostBundleID)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            append(app.bundleIdentifier)
        }

        for rule in rules {
            for bundleID in rule.appBundleIDs {
                append(bundleID)
            }
        }

        for action in workflowService.allActions {
            let pref = getPreference(for: action.id)
            for bundleID in pref.appBundleIDs {
                append(bundleID)
            }
        }

        return orderedBundleIDs.map { bundleID in
            PlaygroundAppOption(bundleID: bundleID, name: displayName(for: bundleID))
        }
    }

    private func displayName(for bundleID: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }

        let appName = FileManager.default
            .displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")

        return appName.isEmpty ? bundleID : appName
    }

    private func loadRules() {
        rules = ContextRuleStore.shared.rules
    }

    private func getPreference(for workflowId: UUID) -> WorkflowPreference {
        (try? workflowPreferences.fetch(for: workflowId)) ?? WorkflowPreference.defaults(for: workflowId)
    }

    private func runSimulation() {
        guard !selectedBundleID.isEmpty else { return }

        let processing = ContextPlaygroundProcessor.process(
            text: inputText,
            dictionaryManager: dictionaryManager
        )

        let matchedRule = ContextRuleStore.shared.matchingRule(for: selectedBundleID)
        let interstitialActions = matchingActions(for: selectedBundleID, context: .interstitial)
        let draftsActions = matchingActions(for: selectedBundleID, context: .drafts)

        result = ContextPlaygroundResult(
            processedText: processing.processedText,
            replacements: processing.replacements,
            fillerRemovalCount: processing.fillerRemovalCount,
            symbolicReplacementCount: processing.symbolicReplacementCount,
            dictionaryReplacementCount: processing.dictionaryReplacementCount,
            matchedRule: matchedRule,
            interstitialActions: interstitialActions,
            draftsActions: draftsActions,
            outcomeTitle: outcomeTitle(for: matchedRule),
            outcomeDetail: outcomeDetail(for: matchedRule)
        )
        lastRunAt = Date()
    }

    private func matchingActions(for bundleID: String, context: PlaygroundActionContext) -> [Workflow] {
        workflowService.allActions.filter { workflow in
            let pref = getPreference(for: workflow.id)
            let enabledInContext: Bool = switch context {
            case .interstitial: pref.showInInterstitial
            case .drafts: pref.showInDrafts
            }

            guard enabledInContext else { return false }
            return pref.appBundleIDs.isEmpty || pref.appBundleIDs.contains(bundleID)
        }
    }

    private func ruleBehaviorSummary(_ behavior: ContextRuleBehavior) -> String {
        switch behavior {
        case .autoRefine:
            return "Would send prepared text through this refinement prompt."
        case .autoInterstitial:
            return "Would open the interstitial with this prompt and prepared text."
        case .protocolProcessor:
            return "Would route into the deterministic protocol processor."
        }
    }

    private func outcomeTitle(for rule: ContextRule?) -> String {
        guard let rule else {
            return ContextRuleStore.shared.isEnabled ? "Default Flow" : "App Profiles Disabled"
        }

        switch rule.behavior {
        case .autoRefine: return "Auto-Refine"
        case .autoInterstitial: return "Open Interstitial"
        case .protocolProcessor: return "Protocol Processor"
        }
    }

    private func outcomeDetail(for rule: ContextRule?) -> String {
        guard let rule else {
            return ContextRuleStore.shared.isEnabled
                ? "Prepared text would continue without an app-specific prompt."
                : "Prepared text would continue with app profile matching turned off."
        }

        switch rule.behavior {
        case .autoRefine:
            return "Talkie would wait for an LLM rewrite, then paste the refined result into \(displayName(for: selectedBundleID))."
        case .autoInterstitial:
            return "Talkie would open the scratchpad/interstitial flow in this context instead of pasting directly."
        case .protocolProcessor:
            return "Talkie would keep this in deterministic syntax mode rather than handing it to an LLM."
        }
    }
}

private enum PlaygroundActionContext {
    case interstitial
    case drafts
}

private struct ContextPlaygroundResult {
    let processedText: String
    let replacements: [DictionaryProcessingResult.ReplacementInfo]
    let fillerRemovalCount: Int
    let symbolicReplacementCount: Int
    let dictionaryReplacementCount: Int
    let matchedRule: ContextRule?
    let interstitialActions: [Workflow]
    let draftsActions: [Workflow]
    let outcomeTitle: String
    let outcomeDetail: String
}

private enum ContextPlaygroundProcessor {
    private struct SymbolicMappingRule: Decodable {
        let enabled: Bool
        let spoken: String
        let symbol: String
        let wordBoundary: Bool
    }

    @MainActor
    static func process(text: String, dictionaryManager: DictionaryManager) -> (
        processedText: String,
        replacements: [DictionaryProcessingResult.ReplacementInfo],
        fillerRemovalCount: Int,
        symbolicReplacementCount: Int,
        dictionaryReplacementCount: Int
    ) {
        var workingText = text
        var fillerRemovalCount = 0
        var symbolicReplacementCount = 0
        var dictionaryResult = DictionaryProcessingResult(original: workingText, processed: workingText, replacements: [])

        if dictionaryManager.isFillerRemovalEnabled {
            let fillerResult = removeFillerWords(from: workingText)
            workingText = fillerResult.text
            fillerRemovalCount = fillerResult.count
        }

        if dictionaryManager.isSymbolicMappingEnabled {
            let symbolicResult = applySymbolicMapping(to: workingText)
            workingText = symbolicResult.text
            symbolicReplacementCount = symbolicResult.count
        }

        if dictionaryManager.isGloballyEnabled {
            dictionaryResult = applyDictionaryEntries(
                to: workingText,
                entries: dictionaryManager.allEnabledEntries
            )
            workingText = dictionaryResult.processed
        }

        let dictionaryReplacementCount = dictionaryResult.replacements.reduce(0) { $0 + $1.count }

        return (
            processedText: workingText,
            replacements: dictionaryResult.replacements,
            fillerRemovalCount: fillerRemovalCount,
            symbolicReplacementCount: symbolicReplacementCount,
            dictionaryReplacementCount: dictionaryReplacementCount
        )
    }

    private static func removeFillerWords(from text: String) -> (text: String, count: Int) {
        let pattern = #"(?i)\b(?:um+|uh+|uhm|erm|ah|like)\b[\s,]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, 0)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return (text, 0) }

        var updated = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        updated = updated.replacingOccurrences(of: #"\s+([,.;!?])"#, with: "$1", options: .regularExpression)
        updated = updated.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        updated = updated.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        updated = updated.trimmingCharacters(in: .whitespacesAndNewlines)

        return (updated, matches.count)
    }

    private static func applySymbolicMapping(to text: String) -> (text: String, count: Int) {
        guard let rules = loadSymbolicMappingRules(), !rules.isEmpty else {
            return (text, 0)
        }

        var result = text
        var totalCount = 0

        for rule in rules.sorted(by: { $0.spoken.count > $1.spoken.count }) where rule.enabled {
            let escaped = NSRegularExpression.escapedPattern(for: rule.spoken)
            let pattern = rule.wordBoundary ? #"(?i)\b\#(escaped)\b"# : #"(?i)\#(escaped)"#

            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            guard !matches.isEmpty else { continue }

            totalCount += matches.count
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(matchRange, with: rule.symbol)
            }
        }

        return (result, totalCount)
    }

    private static func loadSymbolicMappingRules() -> [SymbolicMappingRule]? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupport else { return nil }

        let fileURL = appSupport.appendingPathComponent("TalkieEngine/symbolic-mapping.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([SymbolicMappingRule].self, from: data)
    }

    private static func applyDictionaryEntries(to text: String, entries: [DictionaryEntry]) -> DictionaryProcessingResult {
        guard !entries.isEmpty else {
            return DictionaryProcessingResult(original: text, processed: text, replacements: [])
        }

        var result = text
        var replacementInfos: [DictionaryProcessingResult.ReplacementInfo] = []

        let trieEntries = entries.filter { $0.matchType == .word || $0.matchType == .phrase }
        for entry in trieEntries {
            let (newResult, count) = applyTrieReplacement(entry, to: result)
            if count > 0 {
                result = newResult
                replacementInfos.append(.init(trigger: entry.trigger, replacement: entry.replacement, count: count))
            }
        }

        let regexEntries = entries.filter { $0.matchType == .regex }
        for entry in regexEntries {
            let (newResult, count) = applyRegexReplacement(entry, to: result)
            if count > 0 {
                result = newResult
                replacementInfos.append(.init(trigger: entry.trigger, replacement: entry.replacement, count: count))
            }
        }

        let fuzzyEntries = entries.filter { $0.matchType == .fuzzy }
        if !fuzzyEntries.isEmpty {
            let (newResult, fuzzyInfos) = applyFuzzyMatching(to: result, entries: fuzzyEntries)
            result = newResult
            replacementInfos.append(contentsOf: fuzzyInfos)
        }

        return DictionaryProcessingResult(original: text, processed: result, replacements: replacementInfos)
    }

    private static func applyTrieReplacement(_ entry: DictionaryEntry, to text: String) -> (String, Int) {
        var result = text
        var count = 0

        switch entry.matchType {
        case .word:
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.trigger))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                let matches = regex.matches(in: result, options: [], range: range)
                count = matches.count

                for match in matches.reversed() {
                    guard let matchRange = Range(match.range, in: result) else { continue }
                    result.replaceSubrange(matchRange, with: entry.replacement)
                }
            }

        case .phrase:
            var searchRange = result.startIndex..<result.endIndex

            while let range = result.range(of: entry.trigger, options: .caseInsensitive, range: searchRange) {
                result.replaceSubrange(range, with: entry.replacement)
                count += 1

                let newStart = result.index(range.lowerBound, offsetBy: entry.replacement.count, limitedBy: result.endIndex) ?? result.endIndex
                searchRange = newStart..<result.endIndex
            }

        case .regex, .fuzzy:
            break
        }

        return (result, count)
    }

    private static func applyRegexReplacement(_ entry: DictionaryEntry, to text: String) -> (String, Int) {
        guard entry.matchType == .regex else { return (text, 0) }

        do {
            let regex = try NSRegularExpression(pattern: entry.trigger, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            guard !matches.isEmpty else { return (text, 0) }

            var result = text
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else { continue }

                var replacement = entry.replacement
                for index in 1..<match.numberOfRanges {
                    let groupRange = match.range(at: index)
                    if groupRange.location != NSNotFound,
                       let range = Range(groupRange, in: result) {
                        replacement = replacement.replacingOccurrences(of: "$\(index)", with: String(result[range]))
                    }
                }

                result.replaceSubrange(matchRange, with: replacement)
            }

            return (result, matches.count)
        } catch {
            return (text, 0)
        }
    }

    private struct WordToken {
        let text: String
        let startOffset: Int
        let endOffset: Int
    }

    private static func applyFuzzyMatching(
        to text: String,
        entries: [DictionaryEntry]
    ) -> (String, [DictionaryProcessingResult.ReplacementInfo]) {
        let tokens = tokenize(text)
        guard !tokens.isEmpty, !entries.isEmpty else { return (text, []) }

        let knownTriggers = Set(entries.map { $0.trigger.lowercased() })
        var replacements: [(token: WordToken, entry: DictionaryEntry)] = []

        for token in tokens {
            guard token.text.count >= 4 else { continue }
            if knownTriggers.contains(token.text.lowercased()) { continue }

            var bestMatch: (entry: DictionaryEntry, score: Double)?
            var secondBestScore = 0.0

            for entry in entries {
                let score = similarityScore(token.text, entry.trigger)
                if score >= 0.7 {
                    if bestMatch == nil || score > bestMatch!.score {
                        secondBestScore = bestMatch?.score ?? 0
                        bestMatch = (entry, score)
                    } else if score > secondBestScore {
                        secondBestScore = score
                    }
                }
            }

            if let bestMatch, bestMatch.score - secondBestScore >= 0.1 {
                replacements.append((token, bestMatch.entry))
            }
        }

        guard !replacements.isEmpty else { return (text, []) }

        var result = text
        var counts: [UUID: (entry: DictionaryEntry, count: Int)] = [:]

        for (token, entry) in replacements.reversed() {
            let startIndex = result.index(result.startIndex, offsetBy: token.startOffset)
            let endIndex = result.index(result.startIndex, offsetBy: token.endOffset)
            result.replaceSubrange(startIndex..<endIndex, with: entry.replacement)

            if let existing = counts[entry.id] {
                counts[entry.id] = (existing.entry, existing.count + 1)
            } else {
                counts[entry.id] = (entry, 1)
            }
        }

        let infos = counts.values.map { entry, count in
            DictionaryProcessingResult.ReplacementInfo(
                trigger: entry.trigger,
                replacement: entry.replacement,
                count: count
            )
        }

        return (result, infos)
    }

    private static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var currentWord = ""
        var wordStart = 0

        for (offset, char) in text.enumerated() {
            if char.isLetter || char.isNumber {
                if currentWord.isEmpty {
                    wordStart = offset
                }
                currentWord.append(char)
            } else if !currentWord.isEmpty {
                tokens.append(WordToken(text: currentWord, startOffset: wordStart, endOffset: offset))
                currentWord = ""
            }
        }

        if !currentWord.isEmpty {
            tokens.append(WordToken(text: currentWord, startOffset: wordStart, endOffset: text.count))
        }

        return tokens
    }

    private static func similarityScore(_ lhs: String, _ rhs: String) -> Double {
        let distance = damerauLevenshtein(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLength))
    }

    private static func damerauLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.lowercased())
        let right = Array(rhs.lowercased())
        let rows = left.count
        let columns = right.count

        if rows == 0 { return columns }
        if columns == 0 { return rows }

        var matrix = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
        for row in 0...rows { matrix[row][0] = row }
        for column in 0...columns { matrix[0][column] = column }

        for row in 1...rows {
            for column in 1...columns {
                let cost = left[row - 1] == right[column - 1] ? 0 : 1
                matrix[row][column] = min(
                    matrix[row - 1][column] + 1,
                    matrix[row][column - 1] + 1,
                    matrix[row - 1][column - 1] + cost
                )

                if row > 1, column > 1,
                   left[row - 1] == right[column - 2],
                   left[row - 2] == right[column - 1] {
                    matrix[row][column] = min(matrix[row][column], matrix[row - 2][column - 2] + 1)
                }
            }
        }

        return matrix[rows][columns]
    }
}

// MARK: - Apps Tab Content

struct ContextAppsContent: View {
    let presentation: ContextSettingsPresentation
    @State private var rules: [ContextRule] = []
    @State private var isEnabled: Bool = ContextRuleStore.shared.isEnabled
    @State private var expandedRuleID: UUID?

    init(presentation: ContextSettingsPresentation = .settings) {
        self.presentation = presentation
    }

    private var isConsumer: Bool {
        presentation == .consumer
    }

    var body: some View {
        // Master toggle
        masterToggle

        if isEnabled {
            if rules.isEmpty {
                emptyState
            } else {
                rulesList
            }

            addButton

            presetSection
        }
    }

    // MARK: - Master Toggle

    private var masterToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(isConsumer ? "Use app-specific writing" : "Enable App Profiles")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(isConsumer
                    ? "Talkie can rewrite differently depending on the app you're using."
                    : "Automatically apply LLM prompts based on the target app")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    ContextRuleStore.shared.isEnabled = newValue
                }
        }
        .padding(Spacing.md)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
        .onAppear { loadRules() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 24))
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))

            Text("No app profiles yet")
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(isConsumer
                ? "Create a profile so Talkie writes differently in Slack, Mail, Notes, and more."
                : "Create a profile to auto-refine dictations for specific apps.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Rules List

    private var rulesList: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(rules) { rule in
                appProfileCard(rule)
            }
        }
    }

    // MARK: - App Profile Card

    @ViewBuilder
    private func appProfileCard(_ rule: ContextRule) -> some View {
        let isExpanded = expandedRuleID == rule.id

        VStack(spacing: 0) {
            // Collapsed header — always visible
            HStack(spacing: Spacing.sm) {
                appIconCluster(for: rule.appBundleIDs)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    HStack(spacing: Spacing.xs) {
                        behaviorBadge(rule.behavior)

                        if let model = rule.llmModelId {
                            Text(model)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .lineLimit(1)
                        } else {
                            Text("Default model")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { newValue in
                        var updated = rule
                        updated.isEnabled = newValue
                        ContextRuleStore.shared.update(updated)
                        loadRules()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedRuleID = isExpanded ? nil : rule.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedRuleID = isExpanded ? nil : rule.id
                }
            }

            // Expanded editor
            if isExpanded {
                Divider().opacity(0.3)

                AppProfileEditor(rule: rule) {
                    loadRules()
                }
                .padding(Spacing.sm)
            }
        }
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    private func behaviorBadge(_ behavior: ContextRuleBehavior) -> some View {
        let isRefine = behavior == .autoRefine
        let label = isRefine ? "REFINE" : "EDIT"
        let color: Color = isRefine ? .green : .blue

        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .cornerRadius(3)
    }

    @ViewBuilder
    private func appIconCluster(for bundleIDs: [String]) -> some View {
        if bundleIDs.isEmpty {
            Image(systemName: "app")
                .font(.system(size: 20))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if bundleIDs.count == 1 {
            appIcon(bundleIDs[0])
        } else {
            ZStack {
                appIcon(bundleIDs[0])
                    .frame(width: 22, height: 22)
                    .offset(x: -3, y: -2)
                appIcon(bundleIDs[1])
                    .frame(width: 18, height: 18)
                    .offset(x: 4, y: 3)
            }
        }
    }

    @ViewBuilder
    private func appIcon(_ bundleID: String) -> some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
        } else {
            Image(systemName: "app")
                .font(.system(size: 16))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            let newRule = ContextRule(
                id: UUID(),
                name: "",
                appBundleIDs: [],
                isEnabled: true,
                behavior: .autoRefine,
                prompt: "",
                createdAt: Date(),
                updatedAt: Date()
            )
            ContextRuleStore.shared.add(newRule)
            loadRules()
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedRuleID = newRule.id
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                Text(isConsumer ? "New App Profile" : "Add App Profile")
                    .font(Theme.current.fontSMMedium)
            }
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.purple)
                    .frame(width: 3, height: 14)

                Text(isConsumer ? "SUGGESTED SETUPS" : "TEMPLATES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Text(isConsumer
                ? "Start from a ready-made prompt and tailor it to an app."
                : "Suggested prompts for common app categories.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))

            VStack(spacing: Spacing.xs) {
                ForEach(ContextRulePreset.allCases, id: \.name) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: ContextRulePreset) -> some View {
        Button {
            let newRule = ContextRule(
                id: UUID(),
                name: preset.name,
                appBundleIDs: [],
                isEnabled: true,
                behavior: .autoRefine,
                prompt: preset.prompt,
                createdAt: Date(),
                updatedAt: Date()
            )
            ContextRuleStore.shared.add(newRule)
            loadRules()
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedRuleID = newRule.id
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(preset.prompt)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.sm)
            .background(Theme.current.backgroundSecondary.opacity(0.5))
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadRules() {
        rules = ContextRuleStore.shared.rules
    }
}

// MARK: - App Profile Inline Editor

private struct AppProfileEditor: View {
    let rule: ContextRule
    let onUpdate: () -> Void

    private var registry: LLMProviderRegistry { LLMProviderRegistry.shared }

    @State private var name: String
    @State private var appBundleIDs: [String]
    @State private var behavior: ContextRuleBehavior
    @State private var prompt: String
    @State private var llmProviderId: String
    @State private var llmModelId: String

    init(rule: ContextRule, onUpdate: @escaping () -> Void) {
        self.rule = rule
        self.onUpdate = onUpdate
        _name = State(initialValue: rule.name)
        _appBundleIDs = State(initialValue: rule.appBundleIDs)
        _behavior = State(initialValue: rule.behavior)
        _prompt = State(initialValue: rule.prompt)
        _llmProviderId = State(initialValue: rule.llmProviderId ?? "")
        _llmModelId = State(initialValue: rule.llmModelId ?? "")
    }

    private var modelsForProvider: [LLMModel] {
        registry.allModels.filter { $0.provider == llmProviderId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Name
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Name")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                TextField("e.g. Slack - Casual", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _, _ in saveRule() }
            }

            // App selection
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Apps")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: Spacing.xs) {
                    ForEach(runningApps(), id: \.bundleIdentifier) { app in
                        appButton(app)
                    }
                }

                if !appBundleIDs.isEmpty {
                    Text(appBundleIDs.count == 1 ? appBundleIDs[0] : "\(appBundleIDs.count) apps selected")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            // Behavior
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Behavior")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Picker("", selection: $behavior) {
                    Text("Auto-refine (paste refined text)").tag(ContextRuleBehavior.autoRefine)
                    Text("Auto-interstitial (open scratchpad)").tag(ContextRuleBehavior.autoInterstitial)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: behavior) { _, _ in saveRule() }

                Text(behavior == .autoRefine
                    ? "Silently refines text via LLM before pasting. Falls back to raw text on timeout (5s)."
                    : "Opens the scratchpad with the prompt pre-applied. You can review and edit before pasting."
                )
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))
            }

            // Prompt
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Prompt")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Menu("Templates") {
                        ForEach(ContextRulePreset.allCases, id: \.name) { preset in
                            Button(preset.name) {
                                prompt = preset.prompt
                                saveRule()
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .font(Theme.current.fontXS)
                }

                TextEditor(text: $prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 80)
                    .padding(4)
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )
                    .onChange(of: prompt) { _, _ in saveRule() }
            }

            // LLM Override
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("LLM Override")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Text("Leave as \"Default\" to use your global LLM settings.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(0.7))

                HStack {
                    Text("Provider")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 60, alignment: .leading)

                    Picker("", selection: $llmProviderId) {
                        Text("Default").tag("")
                        ForEach(registry.providers, id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: llmProviderId) { _, newValue in
                        if newValue.isEmpty {
                            llmModelId = ""
                        } else if let defaultModel = LLMConfig.shared.defaultModel(for: newValue) {
                            llmModelId = defaultModel
                        } else if let first = modelsForProvider.first {
                            llmModelId = first.id
                        }
                        saveRule()
                    }
                }

                if !llmProviderId.isEmpty {
                    HStack {
                        Text("Model")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(width: 60, alignment: .leading)

                        Picker("", selection: $llmModelId) {
                            Text("Select model...").tag("")
                            ForEach(modelsForProvider, id: \.id) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: llmModelId) { _, _ in saveRule() }
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.backgroundTertiary)
            .cornerRadius(CornerRadius.sm)

            // Delete
            HStack {
                Spacer()
                Button(role: .destructive) {
                    ContextRuleStore.shared.delete(id: rule.id)
                    onUpdate()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Delete Profile")
                            .font(Theme.current.fontXS)
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - App Button

    private func appButton(_ app: NSRunningApplication) -> some View {
        let bid = app.bundleIdentifier ?? ""
        let isActive = appBundleIDs.contains(bid)

        return Button {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? []
            if modifiers.contains(.option) {
                if let idx = appBundleIDs.firstIndex(of: bid) {
                    appBundleIDs.remove(at: idx)
                } else {
                    appBundleIDs.append(bid)
                }
            } else {
                appBundleIDs = [bid]
                if name.isEmpty {
                    name = app.localizedName ?? bid
                }
            }
            saveRule()
        } label: {
            VStack(spacing: 2) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(4)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
        .help(app.localizedName ?? bid)
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: - Save

    private func saveRule() {
        let updated = ContextRule(
            id: rule.id,
            name: name.trimmingCharacters(in: .whitespaces),
            appBundleIDs: appBundleIDs,
            isEnabled: rule.isEnabled,
            behavior: behavior,
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            llmProviderId: llmProviderId.isEmpty ? nil : llmProviderId,
            llmModelId: llmModelId.isEmpty ? nil : llmModelId,
            createdAt: rule.createdAt,
            updatedAt: Date()
        )
        ContextRuleStore.shared.update(updated)
        onUpdate()
    }
}

// MARK: - Processing Tab Content

struct ContextProcessingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            EnginePickerSection()
            TransformRulesContent()
            RulePackStudioSection()
            ManagedAgentLabSection()
        }
    }
}

// MARK: - Rule Pack Studio

private struct RulePackStudioSection: View {
    @State private var model = RulePackStudioModel()

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.orange)
                    .frame(width: 3, height: 14)

                Text("RULE PACKS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("\(model.validDocumentCount)/\(model.documents.count) VALID")
                    .font(.techLabelSmall)
                    .foregroundColor(.orange.opacity(Opacity.prominent))
            }

            Text("User-authored TOML files in ~/Documents/Talkie/Rules. Edit source, preview rewrites, and keep tests beside each pack.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            HStack(alignment: .top, spacing: Spacing.md) {
                packList(model)
                    .frame(width: 240, alignment: .topLeading)

                editorPanel(model)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
        .onAppear {
            model.load()
        }
    }

    @ViewBuilder
    private func packList(_ model: RulePackStudioModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("FILES")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Button {
                    model.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    model.revealDirectory()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("New", systemImage: "plus") {
                    model.createPack()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if model.documents.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("No packs loaded.")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text("Create a pack to start writing rewrites in TOML.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(model.documents) { document in
                        Button {
                            model.select(document)
                        } label: {
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Circle()
                                    .fill(document.pack == nil ? .orange : .cyan)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.pack?.name ?? document.url.deletingPathExtension().deletingPathExtension().lastPathComponent)
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(Theme.current.foreground)
                                        .lineLimit(1)

                                    Text(document.url.lastPathComponent)
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if let pack = document.pack {
                                    Text("\(pack.rules.count)R")
                                        .font(.techLabelSmall)
                                        .foregroundColor(.cyan.opacity(Opacity.prominent))
                                } else {
                                    Text("INVALID")
                                        .font(.techLabelSmall)
                                        .foregroundColor(.orange.opacity(Opacity.prominent))
                                }
                            }
                            .padding(Spacing.sm)
                            .background(model.selectedDocumentID == document.id ? Theme.current.backgroundTertiary : Theme.current.surface1)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .stroke(
                                        model.selectedDocumentID == document.id
                                            ? Color.orange.opacity(0.45)
                                            : Theme.current.divider,
                                        lineWidth: 1
                                    )
                            )
                            .cornerRadius(CornerRadius.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editorPanel(_ model: RulePackStudioModel) -> some View {
        if model.selectedDocument == nil {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Select a rule pack")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text("Choose a file from the list to edit its TOML and preview its rewrites.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(model.selectedDisplayName)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text(model.selectedFileName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    if let lastSavedAt = model.lastSavedAt {
                        Text(lastSavedAt, format: .dateTime.hour().minute().second())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Button("Reveal", systemImage: "folder") {
                        model.revealSelectedDocument()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Revert", systemImage: "arrow.uturn.backward") {
                        model.revert()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!model.isDirty)

                    Button("Save", systemImage: "checkmark") {
                        model.save()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!model.canSave)
                }

                Picker("", selection: $model.editorMode) {
                    ForEach(RulePackEditorMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                statusBanner(model)

                if model.editorMode == .builder {
                    builderPanel(model)
                } else {
                    TextEditor(
                        text: Binding(
                            get: { model.draftSource },
                            set: { model.updateDraftSource($0) }
                        )
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 240)
                    .padding(Spacing.xs)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(
                                model.draftError == nil
                                    ? Theme.current.divider
                                    : Color.orange.opacity(0.45),
                                lineWidth: 1
                            )
                    )
                }

                HStack(alignment: .top, spacing: Spacing.md) {
                    previewPanel(model)
                    testsPanel(model)
                }
            }
        }
    }

    @ViewBuilder
    private func builderPanel(_ model: RulePackStudioModel) -> some View {
        if let draftPack = model.draftPack {
            RulePackBuilderView(
                pack: Binding(
                    get: { model.draftPack ?? draftPack },
                    set: { model.applyBuilderPack($0) }
                )
            )
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Builder unavailable")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Text("Fix the TOML errors in Source mode first, then come back to Builder mode.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
    }

    private func statusBanner(_ model: RulePackStudioModel) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: model.draftError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(model.draftError == nil ? .green : .orange)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let pack = model.draftPack, model.draftError == nil {
                    Text("\(pack.rules.count) rules · \(pack.tests.count) tests")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)

                    Text(model.isDirty ? "Unsaved changes. Save to make this pack live." : "This pack is valid and ready to run.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else if let draftError = model.draftError {
                    Text("Invalid TOML")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)

                    Text(draftError)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    Text("No parsed pack")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)

                    Text("Add TOML source to parse a pack.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(
            model.draftError == nil
                ? Color.green.opacity(0.08)
                : Color.orange.opacity(0.08)
        )
        .cornerRadius(CornerRadius.sm)
    }

    private func previewPanel(_ model: RulePackStudioModel) -> some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("PREVIEW")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Picker("", selection: $model.previewScope) {
                    ForEach(TalkieRulePack.Scope.allCases, id: \.self) { scope in
                        Text(scope.rawValue.capitalized).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            Text("Run the current draft against sample input before you save it.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            TextEditor(text: $model.previewInput)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 100)
                .padding(Spacing.xs)
                .background(Theme.current.backgroundSecondary)
                .cornerRadius(CornerRadius.sm)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(model.previewMatch == nil ? "RESULT" : "MATCHED \(model.previewMatch?.ruleID.uppercased() ?? "")")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if let previewOutput = model.previewRenderedOutput {
                    Text(previewOutput)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.sm)
                        .background(Theme.current.backgroundSecondary)
                        .cornerRadius(CornerRadius.sm)
                } else {
                    Text("Enter sample text to run the preview.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private func testsPanel(_ model: RulePackStudioModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text("TESTS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if model.draftPack != nil {
                    Text("\(model.passedTestCount)/\(model.testResults.count) PASS")
                        .font(.techLabelSmall)
                        .foregroundColor((model.testResults.allSatisfy(\.passed) ? Color.green : Color.orange).opacity(Opacity.prominent))
                }
            }

            if model.draftPack == nil {
                Text("Fix the pack source to run inline tests.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            } else if model.testResults.isEmpty {
                Text("No tests defined yet. Add `[[tests]]` blocks to keep the pack self-checking.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(model.testResults) { result in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(result.passed ? .green : .orange)
                                    .frame(width: 8, height: 8)

                                Text(result.test.rule)
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foreground)

                                Spacer()

                                Text(result.test.scope.rawValue.uppercased())
                                    .font(.techLabelSmall)
                                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                            }

                            Text(result.test.input)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .lineLimit(2)

                            if result.passed {
                                Text(result.actualOutput)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                    .lineLimit(2)
                            } else {
                                Text("Actual: \(result.actualOutput)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                                    .lineLimit(2)

                                Text("Expected: \(result.test.output)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.current.backgroundSecondary)
                        .cornerRadius(CornerRadius.sm)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }
}

private enum RulePackEditorMode: String, CaseIterable, Sendable {
    case builder
    case source

    var label: String {
        switch self {
        case .builder:
            "Builder"
        case .source:
            "Source"
        }
    }
}

private struct RulePackBuilderView: View {
    @Binding var pack: TalkieRulePack

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            metadataSection
            rulesSection
            testsSection
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("PACK")

            HStack(alignment: .top, spacing: Spacing.sm) {
                labeledField("Pack ID", binding: binding(\.id))
                labeledField("Name", binding: binding(\.name))
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Description")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)

                TextField("Optional description", text: descriptionBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.current.fontSM)
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                sectionHeader("RULES")

                Spacer()

                Menu {
                    ForEach(RulePackRuleTemplate.allCases, id: \.self) { template in
                        Button(template.label) {
                            addRule(from: template)
                        }
                    }
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if pack.rules.isEmpty {
                emptyCard("Add a rule to define a match, transforms, and emitted output.")
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(pack.rules.indices), id: \.self) { index in
                        RulePackRuleCard(
                            rule: ruleBinding(at: index),
                            canMoveUp: index > 0,
                            canMoveDown: index < pack.rules.count - 1,
                            onMoveUp: { moveRule(from: index, to: index - 1) },
                            onMoveDown: { moveRule(from: index, to: index + 1) },
                            onDelete: { removeRule(at: index) }
                        )
                    }
                }
            }
        }
    }

    private var testsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                sectionHeader("TESTS")

                Spacer()

                Button("Add Test", systemImage: "plus") {
                    addTest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if pack.tests.isEmpty {
                emptyCard("Add example inputs and expected outputs so the pack explains itself.")
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(pack.tests.indices), id: \.self) { index in
                        RulePackTestCard(
                            test: testBinding(at: index),
                            availableRuleIDs: pack.rules.map(\.id),
                            canMoveUp: index > 0,
                            canMoveDown: index < pack.tests.count - 1,
                            onMoveUp: { moveTest(from: index, to: index - 1) },
                            onMoveDown: { moveTest(from: index, to: index + 1) },
                            onDelete: { removeTest(at: index) }
                        )
                    }
                }
            }
        }
    }

    private func labeledField(_ title: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            TextField(title, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(Theme.current.fontSM)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.current.fontXSBold)
            .foregroundColor(Theme.current.foregroundSecondary)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(Theme.current.fontXS)
            .foregroundColor(Theme.current.foregroundSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TalkieRulePack, T>) -> Binding<T> {
        Binding(
            get: { pack[keyPath: keyPath] },
            set: { newValue in
                var updated = pack
                updated[keyPath: keyPath] = newValue
                pack = updated
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { pack.description ?? "" },
            set: { newValue in
                var updated = pack
                updated.description = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newValue
                pack = updated
            }
        )
    }

    private func ruleBinding(at index: Int) -> Binding<TalkieRulePack.Rule> {
        Binding(
            get: { pack.rules[index] },
            set: { newValue in
                var updated = pack
                guard updated.rules.indices.contains(index) else { return }
                updated.rules[index] = newValue
                pack = updated
            }
        )
    }

    private func testBinding(at index: Int) -> Binding<TalkieRulePack.Test> {
        Binding(
            get: { pack.tests[index] },
            set: { newValue in
                var updated = pack
                guard updated.tests.indices.contains(index) else { return }
                updated.tests[index] = newValue
                pack = updated
            }
        )
    }

    private func addRule(from template: RulePackRuleTemplate) {
        var updated = pack
        let nextID = uniqueRuleID(
            preferred: template.baseRuleID,
            existing: Set(updated.rules.map(\.id))
        )
        updated.rules.append(template.makeRule(id: nextID))
        pack = updated
    }

    private func removeRule(at index: Int) {
        var updated = pack
        guard updated.rules.indices.contains(index) else { return }
        let removedRuleID = updated.rules[index].id
        updated.rules.remove(at: index)

        if let fallbackRuleID = updated.rules.first?.id {
            updated.tests = updated.tests.map { test in
                guard test.rule == removedRuleID else { return test }
                var copy = test
                copy.rule = fallbackRuleID
                return copy
            }
        } else {
            updated.tests.removeAll { $0.rule == removedRuleID }
        }

        pack = updated
    }

    private func moveRule(from sourceIndex: Int, to destinationIndex: Int) {
        var updated = pack
        guard updated.rules.indices.contains(sourceIndex),
              updated.rules.indices.contains(destinationIndex) else { return }

        let movedRule = updated.rules.remove(at: sourceIndex)
        updated.rules.insert(movedRule, at: destinationIndex)
        pack = updated
    }

    private func addTest() {
        var updated = pack
        let ruleID = updated.rules.first?.id ?? "new-rule"
        updated.tests.append(
            .init(
                rule: ruleID,
                scope: .terminal,
                input: "Sample input",
                output: "Sample output"
            )
        )
        pack = updated
    }

    private func removeTest(at index: Int) {
        var updated = pack
        guard updated.tests.indices.contains(index) else { return }
        updated.tests.remove(at: index)
        pack = updated
    }

    private func moveTest(from sourceIndex: Int, to destinationIndex: Int) {
        var updated = pack
        guard updated.tests.indices.contains(sourceIndex),
              updated.tests.indices.contains(destinationIndex) else { return }

        let movedTest = updated.tests.remove(at: sourceIndex)
        updated.tests.insert(movedTest, at: destinationIndex)
        pack = updated
    }

    private func uniqueRuleID(preferred: String, existing: Set<String>) -> String {
        guard existing.contains(preferred) else { return preferred }

        var counter = 2
        while existing.contains("\(preferred)-\(counter)") {
            counter += 1
        }

        return "\(preferred)-\(counter)"
    }
}

private enum RulePackRuleTemplate: CaseIterable, Hashable {
    case blank
    case colonizedScript
    case hyphenatedScript
    case phraseRewrite

    var label: String {
        switch self {
        case .blank:
            "Blank Rule"
        case .colonizedScript:
            "Colonized Command"
        case .hyphenatedScript:
            "Hyphenated Command"
        case .phraseRewrite:
            "Phrase Rewrite"
        }
    }

    var baseRuleID: String {
        switch self {
        case .blank:
            "new-rule"
        case .colonizedScript:
            "colonized-script"
        case .hyphenatedScript:
            "hyphenated-script"
        case .phraseRewrite:
            "phrase-rewrite"
        }
    }

    func makeRule(id: String) -> TalkieRulePack.Rule {
        switch self {
        case .blank:
            return .init(
                id: id,
                scope: [.terminal],
                priority: 0,
                match: "command {value...}",
                emit: "{{value}}"
            )

        case .colonizedScript:
            return .init(
                id: id,
                scope: [.natural, .terminal],
                priority: 100,
                match: "bun run {script...}",
                emit: "bun run {{script}}",
                transforms: [
                    "script": [
                        .init(op: .lowercase),
                        .init(op: .split, mode: .words),
                        .init(op: .join, separator: ":"),
                    ]
                ]
            )

        case .hyphenatedScript:
            return .init(
                id: id,
                scope: [.terminal],
                priority: 50,
                match: "pnpm create {script...}",
                emit: "pnpm create {{script}}",
                transforms: [
                    "script": [
                        .init(op: .lowercase),
                        .init(op: .split, mode: .words),
                        .init(op: .join, separator: "-"),
                    ]
                ]
            )

        case .phraseRewrite:
            return .init(
                id: id,
                scope: [.natural],
                priority: 10,
                match: "ship it",
                emit: "ship it"
            )
        }
    }
}

private struct RulePackRuleCard: View {
    @Binding var rule: TalkieRulePack.Rule
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    private var sortedCaptureNames: [String] {
        rule.transforms.keys.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(rule.id.isEmpty ? "Untitled Rule" : rule.id)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Text(rule.kind.rawValue.uppercased())
                    .font(.techLabelSmall)
                    .foregroundColor(.cyan.opacity(Opacity.prominent))

                ruleActionButton("arrow.up") {
                    onMoveUp()
                }
                .disabled(!canMoveUp)

                ruleActionButton("arrow.down") {
                    onMoveDown()
                }
                .disabled(!canMoveDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                labeledField("Rule ID", binding: binding(\.id))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Priority")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Stepper(value: binding(\.priority), in: -999...999) {
                        Text("\(rule.priority)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                    }
                }
                .frame(width: 110, alignment: .leading)
            }

            HStack(spacing: Spacing.sm) {
                scopeToggle(.natural)
                scopeToggle(.terminal)
                Spacer()
            }

            labeledField("Match", binding: binding(\.match))
            labeledField("Emit", binding: binding(\.emit))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text("Transforms")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if !sortedCaptureNames.isEmpty {
                        Text("\(sortedCaptureNames.count) CAPTURES")
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                    }

                    Spacer()

                    Button("Add Capture", systemImage: "plus") {
                        addCapture()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if sortedCaptureNames.isEmpty {
                    Text("No capture transforms. Add one when a capture needs normalization before `emit`.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    VStack(spacing: Spacing.sm) {
                        ForEach(sortedCaptureNames, id: \.self) { captureName in
                            RuleTransformCaptureCard(
                                captureName: captureName,
                                transforms: rule.transforms[captureName] ?? [],
                                onRename: { renameCapture(from: captureName, to: $0) },
                                onTransformsChange: { updateTransforms($0, for: captureName) },
                                onDelete: { removeCapture(captureName) }
                            )
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private func ruleActionButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func labeledField(_ title: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            TextField(title, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(Theme.current.fontSM)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TalkieRulePack.Rule, T>) -> Binding<T> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { newValue in
                var updated = rule
                updated[keyPath: keyPath] = newValue
                rule = updated
            }
        )
    }

    private func scopeToggle(_ scope: TalkieRulePack.Scope) -> some View {
        let isSelected = rule.scope.contains(scope)

        return Button {
            var updated = rule
            if isSelected {
                guard updated.scope.count > 1 else { return }
                updated.scope.removeAll { $0 == scope }
            } else {
                updated.scope.append(scope)
                updated.scope.sort { $0.rawValue < $1.rawValue }
            }
            rule = updated
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                Text(scope.rawValue.capitalized)
                    .font(Theme.current.fontXS)
            }
            .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? Theme.current.backgroundTertiary : Theme.current.backgroundSecondary)
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }

    private func addCapture() {
        var updated = rule
        let existing = Set(updated.transforms.keys)
        let base = "capture"
        var name = base
        var counter = 2

        while existing.contains(name) {
            name = "\(base)\(counter)"
            counter += 1
        }

        updated.transforms[name] = [.init(op: .lowercase)]
        rule = updated
    }

    private func renameCapture(from oldName: String, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != oldName else { return }

        var updated = rule
        let existingTransforms = updated.transforms.removeValue(forKey: oldName) ?? []
        updated.transforms[trimmedName] = existingTransforms
        rule = updated
    }

    private func updateTransforms(_ transforms: [TalkieRulePack.Transform], for captureName: String) {
        var updated = rule
        updated.transforms[captureName] = transforms
        rule = updated
    }

    private func removeCapture(_ captureName: String) {
        var updated = rule
        updated.transforms.removeValue(forKey: captureName)
        rule = updated
    }
}

private struct RuleTransformCaptureCard: View {
    let captureName: String
    let transforms: [TalkieRulePack.Transform]
    let onRename: (String) -> Void
    let onTransformsChange: ([TalkieRulePack.Transform]) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                TextField("Capture", text: Binding(
                    get: { captureName },
                    set: { onRename($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: Spacing.xs) {
                recipeButton("Lowercase") {
                    onTransformsChange([.init(op: .lowercase)])
                }
                recipeButton("Trim") {
                    onTransformsChange([.init(op: .trim)])
                }
                recipeButton("Words -> :") {
                    onTransformsChange([
                        .init(op: .lowercase),
                        .init(op: .split, mode: .words),
                        .init(op: .join, separator: ":"),
                    ])
                }
                recipeButton("Words -> -") {
                    onTransformsChange([
                        .init(op: .lowercase),
                        .init(op: .split, mode: .words),
                        .init(op: .join, separator: "-"),
                    ])
                }
                Spacer()
            }

            VStack(spacing: Spacing.xs) {
                ForEach(Array(transforms.indices), id: \.self) { index in
                    RuleTransformRow(
                        transform: transformBinding(at: index),
                        canMoveUp: index > 0,
                        canMoveDown: index < transforms.count - 1,
                        onMoveUp: { moveTransform(from: index, to: index - 1) },
                        onMoveDown: { moveTransform(from: index, to: index + 1) },
                        onDelete: { removeTransform(at: index) }
                    )
                }
            }

            Button("Add Transform", systemImage: "plus") {
                var updated = transforms
                updated.append(.init(op: .lowercase))
                onTransformsChange(updated)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundSecondary)
        .cornerRadius(CornerRadius.sm)
    }

    private func recipeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }

    private func transformBinding(at index: Int) -> Binding<TalkieRulePack.Transform> {
        Binding(
            get: { transforms[index] },
            set: { newValue in
                var updated = transforms
                guard updated.indices.contains(index) else { return }
                updated[index] = normalize(newValue)
                onTransformsChange(updated)
            }
        )
    }

    private func removeTransform(at index: Int) {
        var updated = transforms
        guard updated.indices.contains(index) else { return }
        updated.remove(at: index)
        onTransformsChange(updated)
    }

    private func moveTransform(from sourceIndex: Int, to destinationIndex: Int) {
        var updated = transforms
        guard updated.indices.contains(sourceIndex),
              updated.indices.contains(destinationIndex) else { return }

        let movedTransform = updated.remove(at: sourceIndex)
        updated.insert(movedTransform, at: destinationIndex)
        onTransformsChange(updated)
    }

    private func normalize(_ transform: TalkieRulePack.Transform) -> TalkieRulePack.Transform {
        switch transform.op {
        case .split:
            return .init(op: .split, mode: transform.mode ?? .words)
        case .join:
            return .init(op: .join, separator: transform.separator ?? ":")
        default:
            return .init(op: transform.op)
        }
    }
}

private struct RuleTransformRow: View {
    @Binding var transform: TalkieRulePack.Transform
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Picker("", selection: opBinding) {
                ForEach(TalkieRulePack.Operation.allCases, id: \.self) { operation in
                    Text(operation.rawValue).tag(operation)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            switch transform.op {
            case .split:
                Picker("", selection: splitModeBinding) {
                    ForEach(TalkieRulePack.SplitMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

            case .join:
                TextField("Separator", text: separatorBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

            default:
                Text("No parameters")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            Button(action: onMoveUp) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)

            Button(action: onMoveDown) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private var opBinding: Binding<TalkieRulePack.Operation> {
        Binding(
            get: { transform.op },
            set: { newOp in
                switch newOp {
                case .split:
                    transform = .init(op: .split, mode: .words)
                case .join:
                    transform = .init(op: .join, separator: ":")
                default:
                    transform = .init(op: newOp)
                }
            }
        )
    }

    private var splitModeBinding: Binding<TalkieRulePack.SplitMode> {
        Binding(
            get: { transform.mode ?? .words },
            set: { newMode in
                transform = .init(op: .split, mode: newMode)
            }
        )
    }

    private var separatorBinding: Binding<String> {
        Binding(
            get: { transform.separator ?? ":" },
            set: { newValue in
                transform = .init(op: .join, separator: newValue)
            }
        )
    }
}

private struct RulePackTestCard: View {
    @Binding var test: TalkieRulePack.Test
    let availableRuleIDs: [String]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(test.rule)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                reorderButton("arrow.up", action: onMoveUp)
                    .disabled(!canMoveUp)

                reorderButton("arrow.down", action: onMoveDown)
                    .disabled(!canMoveDown)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Rule")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: ruleBinding) {
                        if availableRuleIDs.isEmpty {
                            Text("No Rules").tag(test.rule)
                        } else {
                            ForEach(availableRuleIDs, id: \.self) { ruleID in
                                Text(ruleID).tag(ruleID)
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Scope")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Picker("", selection: binding(\.scope)) {
                        ForEach(TalkieRulePack.Scope.allCases, id: \.self) { scope in
                            Text(scope.rawValue.capitalized).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            labeledField("Input", binding: binding(\.input))
            labeledField("Expected Output", binding: binding(\.output))
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private func labeledField(_ title: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            TextField(title, text: binding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<TalkieRulePack.Test, T>) -> Binding<T> {
        Binding(
            get: { test[keyPath: keyPath] },
            set: { newValue in
                var updated = test
                updated[keyPath: keyPath] = newValue
                test = updated
            }
        )
    }

    private var ruleBinding: Binding<String> {
        Binding(
            get: { test.rule },
            set: { newValue in
                var updated = test
                updated.rule = newValue
                test = updated
            }
        )
    }

    private func reorderButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

@MainActor @Observable
private final class RulePackStudioModel {
    struct TestResult: Identifiable {
        let test: TalkieRulePack.Test
        let actualOutput: String
        let passed: Bool

        var id: String {
            "\(test.rule)-\(test.scope.rawValue)-\(test.input)"
        }
    }

    var documents: [TalkieRulePackFileStore.Document] = []
    var selectedDocumentID: String?
    var draftSource: String = ""
    var draftPack: TalkieRulePack?
    var draftError: String?
    var editorMode: RulePackEditorMode = .builder
    var previewScope: TalkieRulePack.Scope = .terminal
    var previewInput: String = "Bun run Native App Build"
    var lastSavedAt: Date?

    private let store: TalkieRulePackFileStore
    private let executor: TalkieRuleExecutor

    init(
        store: TalkieRulePackFileStore = .init(),
        executor: TalkieRuleExecutor = .shared
    ) {
        self.store = store
        self.executor = executor
    }

    var selectedDocument: TalkieRulePackFileStore.Document? {
        documents.first { $0.id == selectedDocumentID }
    }

    var validDocumentCount: Int {
        documents.filter { $0.pack != nil }.count
    }

    var selectedDisplayName: String {
        draftPack?.name
            ?? selectedDocument?.pack?.name
            ?? selectedDocument?.url.deletingPathExtension().deletingPathExtension().lastPathComponent
            ?? "Rule Pack"
    }

    var selectedFileName: String {
        selectedDocument?.url.lastPathComponent ?? ""
    }

    var isDirty: Bool {
        draftSource != (selectedDocument?.source ?? "")
    }

    var canSave: Bool {
        selectedDocument != nil && draftPack != nil && isDirty
    }

    var previewMatch: TalkieRuleExecutor.Match? {
        guard let draftPack else { return nil }

        let input = previewInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        return executor.rewrite(
            input,
            scope: previewScope,
            packs: [draftPack]
        )
    }

    var previewRenderedOutput: String? {
        let input = previewInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        return previewMatch?.output ?? input
    }

    var testResults: [TestResult] {
        guard let draftPack else { return [] }

        return draftPack.tests.map { test in
            let actualOutput = executor.rewrite(
                test.input,
                scope: test.scope,
                packs: [draftPack]
            )?.output ?? test.input.trimmingCharacters(in: .whitespacesAndNewlines)

            return TestResult(
                test: test,
                actualOutput: actualOutput,
                passed: actualOutput == test.output
            )
        }
    }

    var passedTestCount: Int {
        testResults.filter(\.passed).count
    }

    func load() {
        documents = store.loadDocuments()

        if let selectedDocumentID,
           documents.contains(where: { $0.id == selectedDocumentID }) {
            syncDraftFromSelection()
            return
        }

        guard let firstDocument = documents.first else {
            selectedDocumentID = nil
            draftSource = ""
            draftPack = nil
            draftError = nil
            return
        }

        selectedDocumentID = firstDocument.id
        syncDraftFromSelection()
    }

    func select(_ document: TalkieRulePackFileStore.Document) {
        selectedDocumentID = document.id
        syncDraftFromSelection()
    }

    func updateDraftSource(_ source: String) {
        draftSource = source
        validateDraft()
    }

    func applyBuilderPack(_ pack: TalkieRulePack) {
        let serialized = store.serialize(pack)

        do {
            draftPack = try store.parse(serialized)
            draftSource = serialized
            draftError = nil
        } catch {
            draftPack = nil
            draftSource = serialized
            draftError = error.localizedDescription
        }
    }

    func save() {
        guard let selectedURL = selectedDocument?.url, draftPack != nil else { return }

        do {
            try store.save(source: draftSource, at: selectedURL)
            lastSavedAt = Date()
            load()
        } catch {
            draftError = error.localizedDescription
        }
    }

    func revert() {
        syncDraftFromSelection()
    }

    func createPack() {
        do {
            let document = try store.createPack(named: "rule-pack")
            lastSavedAt = Date()
            load()
            selectedDocumentID = document.id
            syncDraftFromSelection()
        } catch {
            draftError = error.localizedDescription
        }
    }

    func revealDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([store.directoryURL])
    }

    func revealSelectedDocument() {
        guard let selectedURL = selectedDocument?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedURL])
    }

    private func syncDraftFromSelection() {
        guard let selectedDocument else {
            draftSource = ""
            draftPack = nil
            draftError = nil
            return
        }

        draftSource = selectedDocument.source

        if let pack = selectedDocument.pack {
            draftPack = pack
            draftError = nil
        } else {
            validateDraft()
        }
    }

    private func validateDraft() {
        let trimmedSource = draftSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            draftPack = nil
            draftError = nil
            return
        }

        do {
            draftPack = try store.parse(draftSource)
            draftError = nil
        } catch {
            draftPack = nil
            draftError = error.localizedDescription
        }
    }
}

// MARK: - Actions Tab Content (extracted from ActionsSettingsView)

struct ActionsSettingsContent: View {
    @Environment(SettingsManager.self) private var settingsManager
    private let workflowService = WorkflowService.shared

    let presentation: ContextSettingsPresentation
    @State private var selectedAction: Workflow?
    @State private var showingNewActionSheet = false

    init(presentation: ContextSettingsPresentation = .settings) {
        self.presentation = presentation
    }

    private var isConsumer: Bool {
        presentation == .consumer
    }

    var body: some View {
        @Bindable var settings = settingsManager

        // What Are Actions
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(Theme.current.fontHeadline)
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(isConsumer ? "Buttons are one-tap workflows" : "What are Actions?")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(isConsumer
                    ? "Choose which workflows should appear right after recording or while editing in drafts."
                    : "Actions are workflows packaged as buttons. When you enable a workflow for a specific context (interstitial or drafts), it becomes an action\u{2014}a one-tap transformation for your text.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .background(Color.yellow.opacity(Opacity.light))
        .cornerRadius(CornerRadius.sm)

        // Assistant Personality
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.teal)
                    .frame(width: 3, height: 14)

                Text(isConsumer ? "DEFAULT WRITING STYLE" : "ASSISTANT PERSONALITY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            Text(isConsumer
                ? "Used when Talkie needs a default prompt for notes and quick buttons."
                : "Used by both Notes and Interstitial voice commands.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            TextEditor(text: $settings.composeAssistantPrompt)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 110, maxHeight: 170)
                .padding(Spacing.xs)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Theme.current.divider, lineWidth: 1)
                )

            HStack(spacing: Spacing.sm) {
                Button(isConsumer ? "Reset Style" : "Reset Default") {
                    settings.composeAssistantPrompt = SettingsManager.defaultComposeAssistantPrompt
                }
                .buttonStyle(.bordered)

                if let provider = settings.composeLLMProviderId,
                   let model = settings.composeLLMModelId {
                    Text("Sticky model: \(provider) / \(model)")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                } else {
                    Text("Sticky model: auto")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()
            }
        }
        .settingsSectionCard(padding: Spacing.md)

        // Available Workflows
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.blue)
                    .frame(width: 3, height: 14)

                Text(isConsumer ? "AVAILABLE WORKFLOWS" : "WORKFLOWS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("\(availableWorkflows.count) AVAILABLE")
                    .font(.techLabelSmall)
                    .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
            }

            Text(isConsumer
                ? "Choose where each workflow should show up as a button."
                : "Toggle where each workflow appears as an action button.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            if availableWorkflows.isEmpty {
                actionsEmptyState(
                    icon: "tray",
                    title: "No workflows yet",
                    subtitle: isConsumer
                        ? "Create a workflow to turn it into a button"
                        : "Create a workflow to use it as an action"
                )
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(availableWorkflows) { workflow in
                        workflowRow(workflow)
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)

        // New Action Button
        Button(action: { showingNewActionSheet = true }) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(Theme.current.fontHeadline)
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("New Workflow")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)
                    Text("Create a custom LLM prompt workflow")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)

        // Interstitial Actions
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cyan)
                    .frame(width: 3, height: 14)

                Text(isConsumer ? "AFTER RECORDING" : "INTERSTITIAL ACTIONS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                let count = interstitialActions.count
                if count > 0 {
                    Text("\(count) ENABLED")
                        .font(.techLabelSmall)
                        .foregroundColor(.cyan.opacity(Opacity.prominent))
                }
            }

            Text(isConsumer
                ? "Buttons shown right after you finish recording."
                : "Actions shown in the popup after you finish recording.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            if interstitialActions.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text(isConsumer
                        ? "Turn on \"After Recording\" for a workflow above to see it here"
                        : "Enable \"Interstitial\" on a workflow above to see it here")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(interstitialActions) { action in
                        actionRow(action, context: .interstitial)
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)

        // Drafts Actions
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.purple)
                    .frame(width: 3, height: 14)

                Text(isConsumer ? "IN DRAFTS" : "DRAFTS ACTIONS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                let count = draftsActions.count
                if count > 0 {
                    Text("\(count) ENABLED")
                        .font(.techLabelSmall)
                        .foregroundColor(.purple.opacity(Opacity.prominent))
                }
            }

            Text(isConsumer
                ? "Buttons shown while editing in Compose and Drafts."
                : "Actions shown in the Quick Edit / Drafts screen.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)

            if draftsActions.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text(isConsumer
                        ? "Turn on \"Drafts\" for a workflow above to see it here"
                        : "Enable \"Drafts\" on a workflow above to see it here")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(draftsActions) { action in
                        actionRow(action, context: .drafts)
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)

        // Sheets
        EmptyView()
            .sheet(isPresented: $showingNewActionSheet) {
                ActionEditorSheet(
                    isNew: true,
                    onSave: { definition in
                        Task {
                            try? await workflowService.save(definition)
                        }
                        showingNewActionSheet = false
                    },
                    onCancel: {
                        showingNewActionSheet = false
                    }
                )
                .frame(minWidth: 500, minHeight: 450)
            }
            .sheet(item: $selectedAction) { action in
                ActionEditorSheet(
                    workflow: action.definition,
                    isNew: false,
                    onSave: { definition in
                        Task {
                            try? await workflowService.save(definition)
                        }
                        selectedAction = nil
                    },
                    onCancel: {
                        selectedAction = nil
                    }
                )
                .frame(minWidth: 500, minHeight: 450)
            }
    }

    // MARK: - Data

    private var interstitialActions: [Workflow] {
        workflowService.actionsForInterstitial()
    }

    private var draftsActions: [Workflow] {
        workflowService.actionsForDrafts()
    }

    private var availableWorkflows: [Workflow] {
        workflowService.enabledWorkflows
    }

    // MARK: - Views

    @ViewBuilder
    private func actionsEmptyState(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text(subtitle)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    @ViewBuilder
    private func actionRow(_ workflow: Workflow, context: ActionContext) -> some View {
        let pref = getPreference(for: workflow.id)

        HStack(spacing: Spacing.sm) {
            Image(systemName: workflow.icon)
                .font(.headlineSmall)
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.xs)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workflow.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                if !pref.appBundleIDs.isEmpty {
                    Text(appScopeLabel(for: pref.appBundleIDs))
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(1)
                } else {
                    Text(isConsumer ? "Works in all apps" : "All apps")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            Spacer()

            HStack(spacing: Spacing.xxs) {
                if pref.showInInterstitial {
                    contextBadge("INT", color: .cyan)
                }
                if pref.showInDrafts {
                    contextBadge("DFT", color: .purple)
                }
            }

            Button(action: { selectedAction = workflow }) {
                Image(systemName: "pencil")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
            .help("Edit action")

            Button(action: { toggleContext(workflow, context: context) }) {
                Image(systemName: "xmark")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.xs)
            }
            .buttonStyle(.plain)
            .help("Remove from \(context == .interstitial ? "interstitial" : "drafts")")
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    @ViewBuilder
    private func workflowRow(_ workflow: Workflow) -> some View {
        let pref = getPreference(for: workflow.id)

        HStack(spacing: Spacing.sm) {
            Image(systemName: workflow.icon)
                .font(.headlineSmall)
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(Opacity.medium))
                .cornerRadius(CornerRadius.xs)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workflow.name)
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)
                Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                Toggle("", isOn: Binding(
                    get: { pref.showInInterstitial },
                    set: { newValue in
                        Task {
                            try? await workflowService.setActionContext(
                                for: workflow.id,
                                showInInterstitial: newValue
                            )
                        }
                    }
                ))
                .toggleStyle(ContextToggleStyle(label: "INT", color: .cyan))

                Toggle("", isOn: Binding(
                    get: { pref.showInDrafts },
                    set: { newValue in
                        Task {
                            try? await workflowService.setActionContext(
                                for: workflow.id,
                                showInDrafts: newValue
                            )
                        }
                    }
                ))
                .toggleStyle(ContextToggleStyle(label: "DFT", color: .purple))
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    @ViewBuilder
    private func contextBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(2)
    }

    private func getPreference(for workflowId: UUID) -> WorkflowPreference {
        let repo = WorkflowPreferencesRepository()
        return (try? repo.fetch(for: workflowId)) ?? WorkflowPreference.defaults(for: workflowId)
    }

    private func appScopeLabel(for bundleIDs: [String]) -> String {
        let names = bundleIDs.map(displayName(for:))
        guard !names.isEmpty else {
            return isConsumer ? "Works in all apps" : "All apps"
        }

        if names.count <= 2 {
            return "Apps: \(names.joined(separator: ", "))"
        }

        return "Apps: \(names[0]), \(names[1]) +\(names.count - 2)"
    }

    private func displayName(for bundleID: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }

        let appName = FileManager.default
            .displayName(atPath: appURL.path)
            .replacingOccurrences(of: ".app", with: "")
        return appName.isEmpty ? bundleID : appName
    }

    private func toggleContext(_ workflow: Workflow, context: ActionContext) {
        Task {
            switch context {
            case .interstitial:
                try? await workflowService.setActionContext(for: workflow.id, showInInterstitial: false)
            case .drafts:
                try? await workflowService.setActionContext(for: workflow.id, showInDrafts: false)
            }
        }
    }
}
