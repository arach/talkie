//
//  TalkiePage.swift
//  Talkie
//
//  Standard page layout wrapper for consistent header positioning, content areas, and spacing.
//  Every page should use TalkiePage for visual consistency across the app.
//

import SwiftUI
import TalkieKit

// MARK: - Page Style

/// Page layout styles for TalkiePage
enum PageStyle {
    /// Standard scrolling page with header
    case page
    /// Fixed content (no scroll) with header
    case fixed
    /// Full screen, no standard header (for custom layouts like LogsScreen)
    case full
    /// Scrollable content without header bar (for views with an external universal header)
    case pageOnly
}

// MARK: - Split Column Width

/// Column width configuration for split layouts
enum SplitColumnWidth {
    /// Narrow left column (200-280pt) - settings sidebar, icon-only navigation
    case narrow
    /// Balanced columns (350-600pt) - list views with meaningful content
    case balanced

    var minWidth: CGFloat {
        switch self {
        case .narrow: return 200
        case .balanced: return 350
        }
    }

    var idealWidth: CGFloat {
        switch self {
        case .narrow: return 240
        case .balanced: return 450
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .narrow: return 280
        case .balanced: return 600
        }
    }
}

// MARK: - Talkie Page

/// Standard page wrapper with consistent header and content layout.
///
/// Three page types:
/// - `.page` - Header at top, scrollable content below (default)
/// - `.fixed` - Header at top, fixed content (no scroll)
/// - `.full` - No standard header, content fills entire area
///
/// Usage:
/// ```swift
/// // Simple page with title
/// TalkiePage("Stats", title: "Stats") {
///     statsContent
/// }
///
/// // Page with custom header
/// TalkiePage("Recordings", style: .page) {
///     TitleWithToggle(...)
/// } content: {
///     recordingsList
/// }
///
/// // Full page (custom layout)
/// TalkiePage("Logs", style: .full) {
///     logsContent
/// }
/// ```
struct TalkiePage<Header: View, Content: View>: View {
    let name: String
    let style: PageStyle
    let header: Header
    let content: Content

    /// Standard header height for consistent positioning (44pt matches macOS toolbar)
    static var headerHeight: CGFloat { PageLayout.headerHeight }

    init(
        _ name: String,
        style: PageStyle = .page,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.style = style
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header section (unless full page or pageOnly)
            if style != .full && style != .pageOnly {
                headerSection
            }

            // Content section
            contentSection
        }
        .background(Theme.current.background)
        .environment(\.instrumentationSection, name)
    }

    private var headerSection: some View {
        PageHeaderBar {
            header
            Spacer(minLength: 0)
        }
        .background(Theme.current.background)
    }

    @ViewBuilder
    private var contentSection: some View {
        switch style {
        case .page, .pageOnly:
            ScrollView {
                contentWithPadding
            }
        case .fixed:
            contentWithPadding
        case .full:
            content
        }
    }

    private var contentWithPadding: some View {
        VStack(alignment: .leading, spacing: PageLayout.sectionSpacing) {
            content
            Spacer(minLength: Spacing.xxl)
        }
        .padding(.horizontal, PageLayout.horizontalPadding)
        .padding(.top, PageLayout.topPadding)
        .padding(.bottom, PageLayout.bottomPadding)
    }
}

// MARK: - Page Header Bar

/// Shared header bar used by TalkiePage and split-view pages.
/// Owns the alignment, height, and padding — one source of truth.
///
///   PageHeaderBar {
///       TalkieText("Library", style: .pageTitle)
///       Spacer()
///       SearchField(...)
///   }
struct PageHeaderBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            content
        }
        .frame(height: PageLayout.headerHeight)
        .padding(.horizontal, PageLayout.horizontalPadding)
    }
}

// MARK: - Convenience Initializers

/// Convenience init for pages with just a title header
extension TalkiePage where Header == PageHeader {
    init(
        _ name: String,
        title: String,
        style: PageStyle = .page,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.style = style
        self.header = PageHeader(title)
        self.content = content()
    }
}

/// Convenience init for full pages (no header)
extension TalkiePage where Header == EmptyView {
    init(
        _ name: String,
        style: PageStyle = .full,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.style = style
        self.header = EmptyView()
        self.content = content()
    }
}

// MARK: - Section Style

/// Visual style for section headers
/// Automatically adapts to the current theme (Linear vs default)
enum SectionStyle {
    /// Compact: 10pt uppercase monospace, muted color (for dense UIs)
    case compact
    /// Standard: Theme-aware section header (11pt medium for Linear, 10pt uppercase for default)
    case standard
    /// Prominent: 13pt semibold, primary color (for important sections)
    case prominent

    @MainActor
    private var isTechnical: Bool {
        SettingsManager.shared.isTechnicalTheme
    }

    @MainActor
    var font: Font {
        switch self {
        case .compact:
            return .system(size: 10, weight: .bold, design: .monospaced)
        case .standard:
            return isTechnical
                ? .system(size: 11, weight: .medium)
                : .system(size: 10, weight: .bold, design: .monospaced)
        case .prominent:
            return .system(size: 13, weight: .semibold)
        }
    }

    @MainActor
    var color: Color {
        switch self {
        case .compact:
            return Theme.current.foregroundMuted
        case .standard:
            return isTechnical ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted
        case .prominent:
            return Theme.current.foreground
        }
    }

    @MainActor
    var tracking: CGFloat {
        switch self {
        case .compact:
            return Tracking.wide
        case .standard:
            return isTechnical ? 0 : Tracking.wide
        case .prominent:
            return 0
        }
    }

    @MainActor
    var uppercase: Bool {
        switch self {
        case .compact:
            return true
        case .standard:
            return !isTechnical  // Uppercase only for non-Linear themes
        case .prominent:
            return false
        }
    }
}

// MARK: - Section Title

/// Theme-driven section title with optional subtitle.
/// Use directly when you need just the title, or use TalkieSection for title + content wrapper.
///
/// Usage:
/// ```swift
/// SectionTitle("Overview")
/// SectionTitle("Recent Activity", subtitle: "Last 7 days")
/// SectionTitle("METADATA", style: .compact)
/// ```
struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var style: SectionStyle = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(style.uppercase ? title.uppercased() : title)
                .font(style.font)
                .tracking(style.tracking)
                .foregroundColor(style.color)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
    }
}

// MARK: - Content Section

/// Standard content section with theme-driven title and consistent spacing.
/// Groups related content under a titled header.
///
/// Usage:
/// ```swift
/// // Simple section
/// ContentSection("Overview") {
///     statsCards
/// }
///
/// // Section with subtitle
/// ContentSection("Recent Activity", subtitle: "Last 7 days") {
///     activityList
/// }
///
/// // Compact style for dense UIs
/// ContentSection("METADATA", style: .compact) {
///     metadataRows
/// }
/// ```
struct ContentSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var style: SectionStyle = .standard
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        style: SectionStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionTitle(title: title, subtitle: subtitle, style: style)
            content
        }
    }
}

// MARK: - Preview

#Preview("TalkiePage Styles") {
    VStack(spacing: 0) {
        // Standard page with title
        TalkiePage("Stats", title: "Stats") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Overview Section")
                    .font(.headline)
                Text("Content goes here with consistent padding and spacing.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 200)

        Divider()

        // Page with custom header
        TalkiePage("Recordings", style: .page) {
            HStack(spacing: 12) {
                Text("Recordings")
                    .font(.system(size: 20, weight: .light))
                Text("All")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.secondary)
            }
        } content: {
            Text("List content with custom header")
        }
        .frame(height: 200)
    }
    .frame(width: 600)
}

#Preview("ContentSection Styles") {
    VStack(alignment: .leading, spacing: Spacing.xl) {
        // Simple section
        ContentSection("Overview") {
            Text("Content here")
        }

        // Compact style
        ContentSection("Metadata", subtitle: nil, style: .compact) {
            Text("Compact content")
        }

        // With subtitle
        ContentSection("Activity", subtitle: "Last 7 days") {
            Text("Activity content")
        }
    }
    .padding(24)
    .frame(width: 400)
    .background(Color(NSColor.windowBackgroundColor))
}
