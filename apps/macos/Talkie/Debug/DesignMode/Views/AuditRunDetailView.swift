//
//  AuditRunDetailView.swift
//  Talkie macOS
//
//  Run detail view for Design System Audit - right pane in master-detail view
//  Shows run metadata, stats, screens list, and selected screen details
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import TalkieKit

#if DEBUG

struct AuditRunDetailView: View {
    let report: FullAuditReport
    @Binding var selectedScreen: AppScreen?
    @State private var showScreenshotGrid = false

    var body: some View {
        VStack(spacing: 0) {
            // Run header with metadata
            runHeader

            Divider()

            // Screens content (grid or list+detail)
            screenContent
        }
        .background(Theme.current.background)
    }

    // MARK: - Run Header

    /// Thin monospaced font for technical display
    private var monoFont: Font {
        .system(size: 11, weight: .light, design: .monospaced)
    }

    private var monoFontMedium: Font {
        .system(size: 11, weight: .regular, design: .monospaced)
    }

    @ViewBuilder
    private var runHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Top row: run info + view toggle
            HStack {
                HStack(spacing: Spacing.sm) {
                    if let runNumber = report.runNumber {
                        Text("run-\(String(format: "%03d", runNumber))")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundColor(Theme.current.foreground)
                    }

                    if let branch = report.gitBranch {
                        Text(branch)
                            .font(monoFont)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Text(formattedDate(report.timestamp))
                        .font(monoFont)
                        .foregroundColor(Theme.current.foregroundMuted)

                    if let version = report.appVersion {
                        Text("v\(version)")
                            .font(monoFont)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }

                Spacer()

                // View toggle
                Picker("View", selection: $showScreenshotGrid) {
                    Image(systemName: "list.bullet")
                        .tag(false)
                    Image(systemName: "square.grid.2x2")
                        .tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 56)
            }

            // Stats cards row
            HStack(spacing: Spacing.sm) {
                statCard(
                    value: "\(report.overallScore)%",
                    label: report.grade,
                    valueColor: gradeColor(report.grade)
                )

                statCard(
                    value: "\(report.screens.count)",
                    label: "screens",
                    valueColor: Theme.current.foregroundSecondary
                )

                statCard(
                    value: "\(report.totalIssues)",
                    label: "issues",
                    valueColor: report.totalIssues == 0 ? SemanticColor.success : SemanticColor.warning
                )
            }
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
    }

    @ViewBuilder
    private func statCard(value: String, label: String, valueColor: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(value)
                .font(.system(size: 12, weight: .light, design: .monospaced))
                .foregroundColor(valueColor)
            Text(label)
                .font(.system(size: 10, weight: .light, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Theme.current.surface2)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.current.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Screen Content

    @ViewBuilder
    private var screenContent: some View {
        if showScreenshotGrid {
            screenshotGridView
        } else {
            screenListAndDetail
        }
    }

    @ViewBuilder
    private var screenshotGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 280, maximum: 350), spacing: Spacing.lg)
            ], spacing: Spacing.lg) {
                ForEach(report.screens, id: \.screen.id) { result in
                    screenshotGridCard(result: result)
                }
            }
            .padding(Spacing.lg)
        }
    }

    @ViewBuilder
    private var screenListAndDetail: some View {
        HSplitView {
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
                .padding(Spacing.md)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            .background(Theme.current.surface1)

            // Right: Selected screen detail
            if let screen = selectedScreen,
               let screenResult = report.screens.first(where: { $0.screen == screen }) {
                ScrollView {
                    screenDetailView(result: screenResult)
                        .padding(Spacing.lg)
                }
            } else {
                placeholderDetailView
            }
        }
    }

    // MARK: - Screenshot Grid Card

    @ViewBuilder
    private func screenshotGridCard(result: ScreenAuditResult) -> some View {
        let isSelected = selectedScreen == result.screen

        Button(action: {
            selectedScreen = result.screen
            showScreenshotGrid = false
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Screenshot thumbnail
                ZStack {
                    if let screenshot = loadScreenshot(for: result.screen) {
                        Image(nsImage: screenshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 160)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Theme.current.surface2)
                            .frame(height: 160)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 32))
                                    .foregroundColor(Theme.current.foregroundMuted)
                            )
                    }

                    // Grade badge overlay
                    VStack {
                        HStack {
                            Spacer()
                            Text(result.grade)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(gradeColor(result.grade))
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        }
                        Spacer()
                    }
                    .padding(Spacing.sm)
                }

                // Info bar
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(result.screen.title)
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)

                    HStack(spacing: Spacing.sm) {
                        Text("\(result.overallScore)%")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        if result.totalIssues > 0 {
                            Text("\(result.totalIssues) issues")
                                .font(Theme.current.fontXS)
                                .foregroundColor(SemanticColor.warning)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
            }
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isSelected ? TalkieTheme.accent : Theme.current.divider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen List Views

    @ViewBuilder
    private func screenSectionView(section: ScreenSection, screens: [ScreenAuditResult]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
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

            ForEach(screens, id: \.screen.id) { screen in
                screenRowView(result: screen)
            }
        }
    }

    @ViewBuilder
    private func screenRowView(result: ScreenAuditResult) -> some View {
        let isSelected = selectedScreen == result.screen

        Button(action: { selectedScreen = result.screen }) {
            HStack(spacing: Spacing.sm) {
                Text(result.grade)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(gradeColor(result.grade))
                    .frame(width: 24, height: 24)
                    .background(gradeColor(result.grade).opacity(Opacity.light))
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.screen.title)
                        .font(Theme.current.fontSM)
                        .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                    HStack(spacing: Spacing.xs) {
                        Text("\(result.overallScore)%")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)

                        if result.totalIssues > 0 {
                            Text("\(result.totalIssues) issues")
                                .font(Theme.current.fontXS)
                                .foregroundColor(SemanticColor.warning)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Circle()
                        .fill(TalkieTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(isSelected ? Theme.current.surface2 : Color.clear)
        .cornerRadius(CornerRadius.sm)
    }

    // MARK: - Screen Detail View

    @ViewBuilder
    private func screenDetailView(result: ScreenAuditResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(result.screen.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)

                    Text(result.screen.section.rawValue)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Text(result.grade)
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .foregroundColor(gradeColor(result.grade))
            }

            // Screenshot preview
            screenshotPreview(for: result.screen)

            Divider()

            // Category scores
            categoryScoresView(result: result)

            Divider()

            // Issue breakdown
            issueBreakdownView(result: result)
        }
    }

    @ViewBuilder
    private func screenshotPreview(for screen: AppScreen) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Screenshot")
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .textCase(.uppercase)

                Spacer()

                if let url = screenshotURL(for: screen) {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Reveal")
                                .font(Theme.current.fontXS)
                        }
                        .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let screenshot = loadScreenshot(for: screen) {
                Image(nsImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Theme.current.divider, lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Theme.current.surface2)
                        .frame(height: 150)

                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.current.foregroundMuted)

                        Text("No screenshot available")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryScoresView(result: ScreenAuditResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Category Scores")
                .font(.system(size: 15, weight: .medium))
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
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.current.foregroundMuted)

            Text("\(score)%")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(scoreColor(score))

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
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.current.foreground)

            let allIssues = (result.fontUsage + result.colorUsage + result.spacingUsage + result.opacityUsage)
                .filter { !$0.isCompliant }

            if allIssues.isEmpty {
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
                Text("\(totalCount)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.current.surface2)
                    .cornerRadius(4)
            }

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
                Text(issue.pattern)
                    .font(Theme.current.fontSM)
                    .foregroundColor(SemanticColor.warning)
                    .fontDesign(.monospaced)

                Spacer()

                Text("\(issue.count)")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

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
    }

    // MARK: - Placeholder

    @ViewBuilder
    private var placeholderDetailView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Helpers

    private func screenshotURL(for screen: AppScreen) -> URL? {
        guard let directory = report.screenshotDirectory else { return nil }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(screen.rawValue).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadScreenshot(for screen: AppScreen) -> NSImage? {
        guard let url = screenshotURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return SemanticColor.success
        case "B": return Color.green.opacity(0.7)
        case "C": return SemanticColor.warning
        case "D": return Color.orange
        default: return SemanticColor.error
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...100: return SemanticColor.success
        case 70..<90: return SemanticColor.warning
        default: return SemanticColor.error
        }
    }

    private func categorySeverityColor(_ severity: String) -> Color {
        switch severity {
        case "error": return SemanticColor.error
        case "warning": return SemanticColor.warning
        case "info": return TalkieTheme.accent
        default: return Theme.current.foregroundMuted
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#endif
