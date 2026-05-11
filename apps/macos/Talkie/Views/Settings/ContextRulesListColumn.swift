//
//  ContextRulesListColumn.swift
//  Talkie macOS
//
//  Middle column: list of context rules with app icons
//  Follows WorkflowListItem pattern for 3-column NavigationSplitView
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct ContextRulesListColumn: View {
    @Binding var selectedRuleID: UUID?
    @Binding var editingRule: ContextRule?

    @State private var rules: [ContextRule] = []
    @State private var isEnabled: Bool = ContextRuleStore.shared.isEnabled
    @State private var showingTemplatePopover = false

    var body: some View {
        VStack(spacing: 0) {
            // Header — master toggle inline, templates via + popover
            PageHeaderBar {
                TalkieText("Context Rules", style: .pageTitle)

                Text("\(rules.count)")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .onChange(of: isEnabled) { _, newValue in
                        ContextRuleStore.shared.isEnabled = newValue
                    }

                Button { showingTemplatePopover = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.current.foreground.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingTemplatePopover, arrowEdge: .bottom) {
                    templatePopover
                }
            }

            // Rules list — dims when master toggle is off
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(rules) { rule in
                        ContextRuleRow(
                            rule: rule,
                            isSelected: selectedRuleID == rule.id,
                            isGlobalEnabled: isEnabled
                        ) {
                            selectedRuleID = rule.id
                            editingRule = rule
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
            .opacity(isEnabled ? 1.0 : 0.4)
        }
        .background(Theme.current.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.current.border)
                .frame(width: 1)
                .padding(.top, PageLayout.headerHeight)
        }
        .onAppear { loadRules() }
        .onReceive(NotificationCenter.default.publisher(for: .contextRulesDidChange)) { _ in
            loadRules()
        }
    }

    // MARK: - Template Popover

    private var templatePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Blank rule
            Button {
                showingTemplatePopover = false
                createNewRule()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "doc")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Blank Rule")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Start from scratch")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, Spacing.sm)

            // Template presets
            ForEach(ContextRulePreset.allCases, id: \.name) { preset in
                Button {
                    showingTemplatePopover = false
                    createNewRule(withPreset: preset)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.name)
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)
                            Text(preset.prompt)
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Helpers

    private func createNewRule(withPreset preset: ContextRulePreset? = nil) {
        let newRule = ContextRule(
            name: preset?.name ?? "",
            appBundleIDs: [],
            prompt: preset?.prompt ?? ""
        )
        editingRule = newRule
        selectedRuleID = newRule.id
    }

    private func loadRules() {
        rules = ContextRuleStore.shared.rules
    }
}

// MARK: - Row (WorkflowListItem pattern)

private struct ContextRuleRow: View {
    let rule: ContextRule
    let isSelected: Bool
    let isGlobalEnabled: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // App icon cluster
                appIconCluster
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(rule.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                            .lineLimit(1)

                        // Disabled badge
                        if !rule.isEnabled {
                            Text("DISABLED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.current.foregroundSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Theme.current.foreground.opacity(0.08))
                                .cornerRadius(3)
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        // Behavior badge
                        Text(rule.behavior == .autoRefine ? "REFINE" : "EDIT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(rule.behavior == .autoRefine ? .green : .blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                (rule.behavior == .autoRefine ? Color.green : Color.blue)
                                    .opacity(0.15)
                            )
                            .cornerRadius(3)

                        Text(rule.appSummary)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(rowBackground)
            .overlay(rowBorder)
            .cornerRadius(CornerRadius.sm)
            .opacity(rule.isEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - App Icon Cluster

    @ViewBuilder
    private var appIconCluster: some View {
        let ids = rule.appBundleIDs
        if ids.isEmpty {
            // No apps — placeholder
            Image(systemName: "app")
                .font(.system(size: 22))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if ids.count == 1 {
            // Single app — full size icon
            appIcon(for: ids[0])
        } else {
            // Multi-app — overlapping pair + badge
            ZStack {
                appIcon(for: ids[0])
                    .frame(width: 28, height: 28)
                    .offset(x: -3, y: -2)

                appIcon(for: ids[1])
                    .frame(width: 22, height: 22)
                    .offset(x: 5, y: 4)

                if ids.count > 2 {
                    Text("+\(ids.count - 2)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Theme.current.foreground.opacity(0.12))
                        .cornerRadius(5)
                        .offset(x: 10, y: -6)
                }
            }
        }
    }

    // MARK: - Row Background (WorkflowListItem glass pattern)

    @ViewBuilder
    private var rowBackground: some View {
        ZStack {
            if isSelected || isHovered {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(.ultraThinMaterial)
                    .opacity(isSelected ? 0.6 : 0.3)
            }

            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.12)
                    : (isHovered ? Theme.current.foreground.opacity(0.04) : Color.clear))

            if isSelected {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm)
            .strokeBorder(
                isSelected
                    ? Color.accentColor.opacity(0.3)
                    : (isHovered ? Theme.current.border.opacity(0.1) : Color.clear),
                lineWidth: isSelected ? 1 : 0.5
            )
    }

    // MARK: - App Icon

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
        } else {
            Image(systemName: "app")
                .font(.system(size: 22))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
