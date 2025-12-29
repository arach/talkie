//
//  DesignAuditView.swift
//  Talkie macOS
//
//  Design System Audit Viewer - In-app display of compliance reports
//  Shows overall scores, per-screen breakdowns, and issue details
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

struct DesignAuditView: View {
    @State private var auditReport: FullAuditReport?
    @State private var isRunningAudit = false
    @State private var selectedScreen: AppScreen?
    @State private var availableRuns: [DesignAuditor.AuditRunInfo] = []
    @State private var selectedRunNumber: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Header with Run Audit button and run picker
            VStack(spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Design System Audit")
                            .font(Theme.current.fontTitle)
                            .foregroundColor(Theme.current.foreground)

                        if let report = auditReport {
                            HStack(spacing: Spacing.sm) {
                                Text(report.runSummary)
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                Text("•")
                                    .foregroundColor(Theme.current.foregroundMuted)

                                Text(report.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                        }
                    }

                    Spacer()

                    // Run history picker
                    if !availableRuns.isEmpty {
                        Picker("Run", selection: $selectedRunNumber) {
                            ForEach(availableRuns) { run in
                                HStack {
                                    Text("Run #\(run.id)")
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    Text(run.gitBranch ?? "unknown")
                                        .foregroundColor(.secondary)
                                    Text("(\(run.grade))")
                                        .foregroundColor(gradeColor(run.grade))
                                }
                                .tag(run.id as Int?)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                        .onChange(of: selectedRunNumber) { _, newValue in
                            if let runNumber = newValue {
                                loadRun(runNumber)
                            }
                        }
                    }

                    Button(action: runAudit) {
                        HStack(spacing: Spacing.xs) {
                            if isRunningAudit {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 14))
                            }
                            Text(isRunningAudit ? "Running..." : "Run Audit")
                                .font(Theme.current.fontBodyMedium)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(TalkieTheme.accent.opacity(Opacity.light))
                        .foregroundColor(TalkieTheme.accent)
                        .cornerRadius(CornerRadius.sm)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunningAudit)
                }
            }
            .padding(Spacing.lg)
            .background(Theme.current.surface1)

            Divider()
                .background(Theme.current.divider)

            // Content
            if let report = auditReport {
                auditResultsView(report: report)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
        .onAppear {
            loadCachedAudit()
        }
    }

    // MARK: - Actions

    private func loadCachedAudit() {
        // Load available runs
        availableRuns = DesignAuditor.shared.listAllRuns()

        // Load latest audit if not already loaded
        if auditReport == nil {
            auditReport = DesignAuditor.shared.loadLatestAudit()
            // Set the picker to the latest run
            if let report = auditReport, let runNumber = report.runNumber {
                selectedRunNumber = runNumber
            } else if let firstRun = availableRuns.first {
                selectedRunNumber = firstRun.id
            }
        }
    }

    private func loadRun(_ runNumber: Int) {
        auditReport = DesignAuditor.shared.loadRun(runNumber)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var placeholderView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("No audit results yet")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Click 'Run Audit' to analyze design system compliance")
                .font(Theme.current.fontBody)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func auditResultsView(report: FullAuditReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Summary cards
                HStack(spacing: Spacing.md) {
                    summaryCard(
                        title: "Overall Grade",
                        value: report.grade,
                        subtitle: "\(report.overallScore)%",
                        color: gradeColor(report.grade)
                    )

                    summaryCard(
                        title: "Total Issues",
                        value: "\(report.totalIssues)",
                        subtitle: "violations found",
                        color: report.totalIssues == 0 ? SemanticColor.success : SemanticColor.warning
                    )

                    summaryCard(
                        title: "Screens Audited",
                        value: "\(report.screens.count)",
                        subtitle: "app screens",
                        color: TalkieTheme.accent
                    )
                }

                Divider()
                    .background(Theme.current.divider)

                // Screen list and detail view
                screenListAndDetailView(report: report)
            }
            .padding(Spacing.xl)
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(subtitle)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.md)
    }

    @ViewBuilder
    private func screenListAndDetailView(report: FullAuditReport) -> some View {
        HStack(spacing: 0) {
            // Left: Screen list grouped by section
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(ScreenSection.allCases, id: \.rawValue) { section in
                        let sectionScreens = report.screens.filter { $0.screen.section == section }
                        if !sectionScreens.isEmpty {
                            screenSectionView(section: section, screens: sectionScreens)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .frame(width: 320)
            .background(Theme.current.surface1)

            Divider()
                .background(Theme.current.divider)

            // Right: Selected screen detail
            if let selectedScreen = selectedScreen,
               let screenResult = report.screens.first(where: { $0.screen == selectedScreen }) {
                ScrollView {
                    screenDetailView(result: screenResult)
                        .padding(Spacing.xl)
                }
                .frame(maxWidth: .infinity)
            } else {
                placeholderDetailView
            }
        }
    }

    @ViewBuilder
    private func screenSectionView(section: ScreenSection, screens: [ScreenAuditResult]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Section header
            HStack {
                Text(section.rawValue)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .textCase(.uppercase)

                Spacer()

                Text("\(screens.count)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.current.surface2)
                    .cornerRadius(4)
            }
            .padding(.bottom, Spacing.xs)

            // Screen rows
            ForEach(screens, id: \.screen.id) { screen in
                screenRowView(result: screen)
            }
        }
    }

    @ViewBuilder
    private func screenRowView(result: ScreenAuditResult) -> some View {
        let isSelected = selectedScreen == result.screen

        Button(action: {
            selectedScreen = result.screen
        }) {
            HStack(spacing: Spacing.sm) {
                // Grade badge
                Text(result.grade)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(gradeColor(result.grade))
                    .frame(width: 24, height: 24)
                    .background(gradeColor(result.grade).opacity(Opacity.light))
                    .cornerRadius(4)

                // Screen name and stats
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.screen.title)
                        .font(Theme.current.fontSM)
                        .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                    HStack(spacing: Spacing.xs) {
                        Text("\(result.overallScore)%")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if result.totalIssues > 0 {
                            Text("•")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)

                            Text("\(result.totalIssues) issues")
                                .font(Theme.current.fontXS)
                                .foregroundColor(SemanticColor.warning)
                        }
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Circle()
                        .fill(TalkieTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Theme.current.surface2 : Color.clear)
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var placeholderDetailView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "arrow.left.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("Select a screen")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Choose a screen from the list to see detailed audit results")
                .font(Theme.current.fontBody)
                .foregroundColor(Theme.current.foregroundMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    @ViewBuilder
    private func screenDetailView(result: ScreenAuditResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(result.screen.title)
                            .font(Theme.current.fontTitle)
                            .foregroundColor(Theme.current.foreground)

                        Text(result.screen.section.rawValue)
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Spacer()

                    // Large grade badge
                    Text(result.grade)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(gradeColor(result.grade))
                }

                // Source files
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.screen.sourceFiles, id: \.self) { file in
                        Text(file)
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .fontDesign(.monospaced)
                    }
                }
                .padding(.top, Spacing.xs)
            }

            Divider()
                .background(Theme.current.divider)

            // Category scores
            categoryScoresView(result: result)

            Divider()
                .background(Theme.current.divider)

            // Issue breakdown
            issueBreakdownView(result: result)
        }
    }

    @ViewBuilder
    private func categoryScoresView(result: ScreenAuditResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Category Scores")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foreground)

            HStack(spacing: Spacing.lg) {
                categoryScoreCard(title: "Fonts", score: result.fontScore)
                categoryScoreCard(title: "Colors", score: result.colorScore)
                categoryScoreCard(title: "Spacing", score: result.spacingScore)
                categoryScoreCard(title: "Opacity", score: result.opacityScore)
            }
        }
    }

    @ViewBuilder
    private func categoryScoreCard(title: String, score: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
                .textCase(.uppercase)

            Text("\(score)%")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(scoreColor(score))

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.current.surface2)
                        .frame(height: 4)

                    Rectangle()
                        .fill(scoreColor(score))
                        .frame(width: geometry.size.width * CGFloat(score) / 100, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.md)
    }

    @ViewBuilder
    private func issueBreakdownView(result: ScreenAuditResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Issue Breakdown")
                .font(Theme.current.fontHeadline)
                .foregroundColor(Theme.current.foreground)

            let allIssues = (result.fontUsage + result.colorUsage + result.spacingUsage + result.opacityUsage)
                .filter { !$0.isCompliant }

            if allIssues.isEmpty {
                // Success state
                HStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(SemanticColor.success)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("No issues found")
                            .font(Theme.current.fontBodyMedium)
                            .foregroundColor(SemanticColor.success)

                        Text("This screen is fully compliant with the design system")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SemanticColor.success.opacity(Opacity.subtle))
                .cornerRadius(CornerRadius.md)
            } else {
                // Group issues by category
                let issuesByCategory = Dictionary(grouping: allIssues) { $0.category }
                let sortedCategories = issuesByCategory.keys.sorted { $0.rawValue < $1.rawValue }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(sortedCategories, id: \.rawValue) { category in
                        if let categoryIssues = issuesByCategory[category] {
                            issueCategoryView(category: category, issues: categoryIssues)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func issueCategoryView(category: IssueCategory, issues: [PatternUsage]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Category header
            HStack(spacing: Spacing.sm) {
                Text(category.icon)
                    .font(.system(size: 14))

                Text(category.rawValue)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(categorySeverityColor(category.severity))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categorySeverityColor(category.severity).opacity(Opacity.light))
                    .cornerRadius(4)

                Text(category.title)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                let totalCount = issues.reduce(0) { $0 + $1.count }
                Text("×\(totalCount)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.current.surface2)
                    .cornerRadius(4)
            }

            // Issue items
            VStack(spacing: 0) {
                ForEach(issues.sorted(by: { $0.count > $1.count }), id: \.id) { issue in
                    issueItemView(issue: issue)
                }
            }
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
    }

    @ViewBuilder
    private func issueItemView(issue: PatternUsage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                // Pattern
                Text(issue.pattern)
                    .font(Theme.current.fontSM)
                    .foregroundColor(SemanticColor.warning)
                    .fontDesign(.monospaced)

                Spacer()

                // Count
                Text("×\(issue.count)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            // Suggestion
            if let suggestion = issue.suggestion {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(SemanticColor.success)

                    Text(suggestion)
                        .font(Theme.current.fontSM)
                        .foregroundColor(SemanticColor.success)
                        .fontDesign(.monospaced)
                }
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.background)
        .cornerRadius(CornerRadius.xs)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Actions

    private func runAudit() {
        isRunningAudit = true

        Task.detached(priority: .userInitiated) {
            let report = await DesignAuditor.shared.auditAll()

            await MainActor.run {
                auditReport = report
                isRunningAudit = false

                // Refresh available runs list
                availableRuns = DesignAuditor.shared.listAllRuns()

                // Select the new run
                if let runNumber = report.runNumber {
                    selectedRunNumber = runNumber
                }
            }
        }
    }

    // MARK: - Helpers

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return SemanticColor.success
        case "B": return Color.green.opacity(0.7)
        case "C": return SemanticColor.warning
        case "D": return Color.orange.opacity(0.8)
        default: return SemanticColor.error
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return SemanticColor.success
        case 80..<90: return Color.green.opacity(0.7)
        case 70..<80: return SemanticColor.warning
        case 60..<70: return Color.orange.opacity(0.8)
        default: return SemanticColor.error
        }
    }

    private func categorySeverityColor(_ severity: String) -> Color {
        switch severity {
        case "error": return SemanticColor.error
        case "warning": return SemanticColor.warning
        default: return SemanticColor.success
        }
    }
}

#Preview("Design Audit") {
    DesignAuditView()
        .frame(width: 900, height: 700)
}

#endif
