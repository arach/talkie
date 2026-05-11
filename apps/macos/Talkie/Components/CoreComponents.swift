//
//  CoreComponents.swift
//  Talkie
//
//  Unified component library for consistent UI across the app.
//  These are the foundational building blocks - use these instead of
//  rebuilding glass backgrounds, rows, headers, etc. from scratch.
//
//  Components:
//  - GlassCard: Foundation for all card-like containers
//  - ListSectionHeader: Consistent section headers
//  - StatusBadge: Status indicators with semantic colors
//  - EmptyState: Empty/error state displays
//

import SwiftUI
import TalkieKit

// MARK: - Glass Card

/// Foundation component for all card-like containers.
/// Encapsulates the glass material, gradients, borders, and shadows.
///
/// Usage:
/// ```swift
/// GlassCard {
///     Text("Content goes here")
/// }
///
/// GlassCard(.prominent) {
///     Text("More visible card")
/// }
///
/// GlassCard(.subtle, cornerRadius: .lg) {
///     Text("Custom corner radius")
/// }
/// ```
struct GlassCard<Content: View>: View {
    let style: GlassCardStyle
    let cornerRadius: CGFloat
    let content: Content

    init(
        _ style: GlassCardStyle = .standard,
        cornerRadius: CGFloat = CornerRadius.sm,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    /// Convenience init using CornerRadius enum
    init(
        _ style: GlassCardStyle = .standard,
        cornerRadius: CornerRadiusPreset,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius.value
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    // Base glass material
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(style.materialOpacity)

                    // Gradient overlay for depth
                    if style.showGradient {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(style.gradientTopOpacity),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    // Border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            Color.white.opacity(style.borderOpacity),
                            lineWidth: style.borderWidth
                        )
                }
            )
            .shadow(
                color: Color.black.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowY
            )
    }
}

/// Glass card visual styles
enum GlassCardStyle {
    /// Subtle - minimal visual presence, for nested cards
    case subtle
    /// Standard - default card appearance
    case standard
    /// Prominent - more visible, for primary content
    case prominent
    /// Interactive - for hoverable/clickable cards
    case interactive(isHovered: Bool)

    var materialOpacity: Double {
        switch self {
        case .subtle: return 0.3
        case .standard: return 0.5
        case .prominent: return 0.7
        case .interactive(let isHovered): return isHovered ? 0.6 : 0.5
        }
    }

    var showGradient: Bool {
        switch self {
        case .subtle: return false
        case .standard, .prominent, .interactive: return true
        }
    }

    var gradientTopOpacity: Double {
        switch self {
        case .subtle: return 0
        case .standard: return 0.03
        case .prominent: return 0.05
        case .interactive(let isHovered): return isHovered ? 0.06 : 0.03
        }
    }

    var borderOpacity: Double {
        switch self {
        case .subtle: return 0.06
        case .standard: return 0.1
        case .prominent: return 0.15
        case .interactive(let isHovered): return isHovered ? 0.2 : 0.1
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .subtle: return 0.5
        case .standard, .prominent, .interactive: return 1
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .subtle: return 0
        case .standard: return 0.1
        case .prominent: return 0.15
        case .interactive(let isHovered): return isHovered ? 0.2 : 0.1
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .subtle: return 0
        case .standard: return 4
        case .prominent: return 8
        case .interactive(let isHovered): return isHovered ? 12 : 4
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .subtle: return 0
        case .standard: return 2
        case .prominent: return 4
        case .interactive(let isHovered): return isHovered ? 6 : 2
        }
    }
}

/// Corner radius presets for convenience
enum CornerRadiusPreset {
    case xs, sm, md, lg, xl

    var value: CGFloat {
        switch self {
        case .xs: return CornerRadius.xs
        case .sm: return CornerRadius.sm
        case .md: return CornerRadius.md
        case .lg: return CornerRadius.lg
        case .xl: return CornerRadius.xl
        }
    }
}

// MARK: - Glass Card View Modifier

/// Apply glass card styling as a modifier
struct GlassCardModifier: ViewModifier {
    let style: GlassCardStyle
    let cornerRadius: CGFloat
    let padding: CGFloat?

    func body(content: Content) -> some View {
        Group {
            if let padding = padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(style.materialOpacity)

                if style.showGradient {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(style.gradientTopOpacity),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color.white.opacity(style.borderOpacity),
                        lineWidth: style.borderWidth
                    )
            }
        )
        .shadow(
            color: Color.black.opacity(style.shadowOpacity),
            radius: style.shadowRadius,
            x: 0,
            y: style.shadowY
        )
    }
}

extension View {
    /// Apply glass card styling to any view
    func glassCard(
        _ style: GlassCardStyle = .standard,
        cornerRadius: CGFloat = CornerRadius.sm,
        padding: CGFloat? = nil
    ) -> some View {
        modifier(GlassCardModifier(style: style, cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Section Header

/// Consistent section header for use throughout the app.
///
/// Usage:
/// ```swift
/// ListSectionHeader("TRANSCRIPT")
/// ListSectionHeader("QUICK ACTIONS", icon: "bolt.fill")
/// ListSectionHeader("SETTINGS", icon: "gear", trailing: { Button("Edit") {} })
/// ```
struct ListSectionHeader<Trailing: View>: View {
    let title: String
    let icon: String?
    let trailing: Trailing

    init(
        _ title: String,
        icon: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(Tracking.wide)
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            trailing
        }
    }
}

// Convenience init without trailing
extension ListSectionHeader where Trailing == EmptyView {
    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
        self.trailing = EmptyView()
    }
}

// MARK: - Status Badge

/// Status indicator with semantic colors.
///
/// Usage:
/// ```swift
/// StatusBadge(.success, "Completed")
/// StatusBadge(.error, "Failed")
/// StatusBadge(.pending, "Processing...")
/// StatusBadge(.info, "3 items", icon: "doc.fill")
/// ```
struct StatusBadge: View {
    let status: StatusType
    let text: String
    let icon: String?
    let size: BadgeSize

    init(
        _ status: StatusType,
        _ text: String,
        icon: String? = nil,
        size: BadgeSize = .standard
    ) {
        self.status = status
        self.text = text
        self.icon = icon
        self.size = size
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize, weight: .medium))
            } else if status.defaultIcon != nil {
                Image(systemName: status.defaultIcon!)
                    .font(.system(size: size.iconSize, weight: .medium))
            }

            Text(text)
                .font(.system(size: size.fontSize, weight: .medium, design: .monospaced))
        }
        .foregroundColor(status.foregroundColor)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            Capsule()
                .fill(status.backgroundColor)
        )
    }

    enum StatusType {
        case success
        case error
        case warning
        case pending
        case info
        case neutral

        var backgroundColor: Color {
            switch self {
            case .success: return SemanticColor.success.opacity(0.2)
            case .error: return SemanticColor.error.opacity(0.2)
            case .warning: return SemanticColor.warning.opacity(0.2)
            case .pending: return SemanticColor.processing.opacity(0.2)
            case .info: return SemanticColor.info.opacity(0.2)
            case .neutral: return Color.secondary.opacity(0.2)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .success: return SemanticColor.success
            case .error: return SemanticColor.error
            case .warning: return SemanticColor.warning
            case .pending: return SemanticColor.processing
            case .info: return SemanticColor.info
            case .neutral: return .secondary
            }
        }

        var defaultIcon: String? {
            switch self {
            case .success: return "checkmark"
            case .error: return "xmark"
            case .warning: return "exclamationmark.triangle"
            case .pending: return nil // Use spinner separately
            case .info: return "info"
            case .neutral: return nil
            }
        }
    }

    enum BadgeSize {
        case compact
        case standard
        case large

        var fontSize: CGFloat {
            switch self {
            case .compact: return 9
            case .standard: return 10
            case .large: return 12
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .compact: return 8
            case .standard: return 10
            case .large: return 12
            }
        }

        var spacing: CGFloat {
            switch self {
            case .compact: return 2
            case .standard: return 4
            case .large: return 6
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 6
            case .standard: return 8
            case .large: return 10
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 2
            case .standard: return 4
            case .large: return 6
            }
        }
    }
}

// MARK: - Empty State

/// Consistent empty state display for when there's no content.
///
/// Usage:
/// ```swift
/// ListEmptyState(
///     icon: "doc.text",
///     title: "No Memos Yet",
///     subtitle: "Record your first memo to get started"
/// )
///
/// ListEmptyState(
///     icon: "magnifyingglass",
///     title: "No Results",
///     subtitle: "Try a different search term"
/// ) {
///     Button("Clear Search") { ... }
/// }
/// ```
struct ListEmptyState<Action: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let documentationURL: URL?
    let action: Action

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        documentationURL: URL? = nil,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.documentationURL = documentationURL
        self.action = action()
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.current.foregroundMuted)

            VStack(spacing: Spacing.xs) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(Tracking.wide)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .multilineTextAlignment(.center)
                }
            }

            action

            // Documentation link
            if let url = documentationURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "book")
                            .font(.system(size: 11))
                        Text("Learn more")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }
}

// Convenience init without action
extension ListEmptyState where Action == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, documentationURL: URL? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.documentationURL = documentationURL
        self.action = EmptyView()
    }
}

// MARK: - Duration Badge

/// Compact duration display badge (used in rows).
///
/// Usage:
/// ```swift
/// DurationBadge(seconds: 125)  // Shows "2:05"
/// DurationBadge(seconds: 3725) // Shows "1:02:05"
/// ```
struct DurationBadge: View {
    let seconds: Int

    var formattedDuration: String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    var body: some View {
        Text(formattedDuration)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.current.foregroundSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(Opacity.subtle))
            )
    }
}

// MARK: - Glass Pill Button

/// A beautiful pill-shaped button with liquid glass styling.
/// Designed for action buttons in headers and toolbars.
///
/// Usage:
/// ```swift
/// GlassPillButton("Save", icon: "checkmark", style: .accent) { }
/// GlassPillButton("Edit", icon: "pencil", style: .secondary) { }
/// GlassPillButton(icon: "trash", style: .destructive) { }
/// ```
struct GlassPillButton: View {
    let label: String?
    let icon: String?
    let style: GlassPillButtonStyle
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    init(
        _ label: String,
        icon: String? = nil,
        style: GlassPillButtonStyle = .secondary,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.style = style
        self.action = action
    }

    init(
        icon: String,
        style: GlassPillButtonStyle = .secondary,
        action: @escaping () -> Void
    ) {
        self.label = nil
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                if let label = label {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .default))
                }
            }
            .foregroundColor(style.foregroundColor(isHovered: isHovered))
            .padding(.horizontal, label != nil ? 10 : 8)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    // Base fill
                    Capsule()
                        .fill(style.backgroundColor(isHovered: isHovered))

                    // Gradient overlay for glass depth
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.15 : 0.08),
                                    Color.white.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Border
                    Capsule()
                        .strokeBorder(
                            style.borderColor(isHovered: isHovered),
                            lineWidth: 0.5
                        )
                }
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

/// Styles for GlassPillButton
@MainActor
enum GlassPillButtonStyle {
    case primary      // Accent color fill
    case secondary    // Subtle glass
    case accent       // Success green
    case destructive  // Red tint
    case ghost        // Minimal, border only on hover

    func foregroundColor(isHovered: Bool) -> Color {
        switch self {
        case .primary:
            return .white
        case .secondary:
            return Theme.current.foregroundSecondary
        case .accent:
            return .white
        case .destructive:
            return isHovered ? .white : SemanticColor.error
        case .ghost:
            return Theme.current.foregroundSecondary
        }
    }

    func backgroundColor(isHovered: Bool) -> Color {
        switch self {
        case .primary:
            return SettingsManager.shared.resolvedAccentColor.opacity(isHovered ? 0.9 : 0.8)
        case .secondary:
            return Theme.current.foreground.opacity(isHovered ? 0.12 : 0.08)
        case .accent:
            return SemanticColor.success.opacity(isHovered ? 0.9 : 0.8)
        case .destructive:
            return SemanticColor.error.opacity(isHovered ? 0.8 : 0.15)
        case .ghost:
            return isHovered ? Theme.current.foreground.opacity(0.06) : Color.clear
        }
    }

    func borderColor(isHovered: Bool) -> Color {
        switch self {
        case .primary:
            return Color.white.opacity(0.2)
        case .secondary:
            return Theme.current.border.opacity(isHovered ? 0.2 : 0.1)
        case .accent:
            return Color.white.opacity(0.2)
        case .destructive:
            return SemanticColor.error.opacity(isHovered ? 0.3 : 0.2)
        case .ghost:
            return isHovered ? Theme.current.border.opacity(0.15) : Color.clear
        }
    }
}

// MARK: - Glass Header Bar

/// A glass-styled header bar for editors and detail views.
/// Provides consistent styling with liquid glass background.
struct GlassHeaderBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                ZStack {
                    // Base material
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    // Subtle gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Bottom border
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Theme.current.border.opacity(0.15))
                            .frame(height: 1)
                    }
                }
            )
    }
}

// MARK: - Previews

#Preview("Glass Pill Buttons") {
    VStack(spacing: Spacing.lg) {
        Text("Glass Pill Buttons")
            .font(.headline)
            .foregroundColor(.white)

        HStack(spacing: Spacing.sm) {
            GlassPillButton("Primary", icon: "star.fill", style: .primary) {}
            GlassPillButton("Secondary", icon: "pencil", style: .secondary) {}
            GlassPillButton("Accent", icon: "checkmark", style: .accent) {}
        }

        HStack(spacing: Spacing.sm) {
            GlassPillButton("Ghost", style: .ghost) {}
            GlassPillButton("Destructive", icon: "trash", style: .destructive) {}
            GlassPillButton(icon: "xmark", style: .secondary) {}
        }
    }
    .padding(40)
    .background(Color.black)
}

#Preview("Glass Cards") {
    VStack(spacing: Spacing.lg) {
        GlassCard(.subtle) {
            Text("Subtle Card")
                .padding()
        }

        GlassCard(.standard) {
            Text("Standard Card")
                .padding()
        }

        GlassCard(.prominent) {
            Text("Prominent Card")
                .padding()
        }

        Text("Content with modifier")
            .padding()
            .glassCard(.standard)
    }
    .padding()
    .frame(width: 300, height: 400)
    .background(Color.black)
}

#Preview("Section Headers") {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        ListSectionHeader("TRANSCRIPT")
        ListSectionHeader("QUICK ACTIONS", icon: "bolt.fill")
        ListSectionHeader("RECENT RUNS", icon: "clock") {
            Button("View All") {}
                .font(.system(size: 10))
        }
    }
    .padding()
    .frame(width: 300)
    .background(Color.black)
}

#Preview("Status Badges") {
    VStack(spacing: Spacing.md) {
        StatusBadge(.success, "Completed")
        StatusBadge(.error, "Failed")
        StatusBadge(.warning, "Warning")
        StatusBadge(.pending, "Processing...")
        StatusBadge(.info, "3 items", icon: "doc.fill")
        StatusBadge(.neutral, "Draft")

        Divider()

        HStack {
            StatusBadge(.success, "OK", size: .compact)
            StatusBadge(.error, "Error", size: .compact)
        }
    }
    .padding()
    .frame(width: 300)
    .background(Color.black)
}

#Preview("Empty States") {
    VStack(spacing: Spacing.xl) {
        ListEmptyState(
            icon: "doc.text",
            title: "No Memos Yet",
            subtitle: "Record your first memo to get started"
        )

        Divider()

        ListEmptyState(
            icon: "magnifyingglass",
            title: "No Results",
            subtitle: "Try a different search term"
        ) {
            Button("Clear Search") {}
                .buttonStyle(.bordered)
        }
    }
    .frame(width: 400, height: 500)
    .background(Color.black)
}

// MARK: - Detail Row

/// Unified row component for list views.
/// Handles selection, hover, focus states and provides content slots.
///
/// Usage:
/// ```swift
/// DetailRow(
///     isSelected: isSelected,
///     onSelect: { event in handleSelect(event) }
/// ) {
///     // Leading slot (icon, checkbox, etc.)
///     Image(systemName: "doc.fill")
/// } content: {
///     // Main content
///     VStack(alignment: .leading) {
///         Text("Title")
///         Text("Subtitle")
///     }
/// } trailing: {
///     // Trailing slot (duration, date, etc.)
///     DurationBadge(seconds: 125)
/// }
/// ```
struct DetailRow<Leading: View, Content: View, Trailing: View>: View {
    // State
    let isSelected: Bool
    var isMultiSelectMode: Bool = false
    var isFocused: Bool = false
    var isAlternate: Bool = false  // For alternating row backgrounds

    // Interaction
    let onSelect: (NSEvent?) -> Void

    // Content slots
    let leading: Leading
    let content: Content
    let trailing: Trailing

    // Styling
    var style: DetailRowStyle = .standard
    var showSelectionBar: Bool = true

    @State private var isHovering = false

    init(
        isSelected: Bool,
        isMultiSelectMode: Bool = false,
        isFocused: Bool = false,
        isAlternate: Bool = false,
        style: DetailRowStyle = .standard,
        showSelectionBar: Bool = true,
        onSelect: @escaping (NSEvent?) -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.isSelected = isSelected
        self.isMultiSelectMode = isMultiSelectMode
        self.isFocused = isFocused
        self.isAlternate = isAlternate
        self.style = style
        self.showSelectionBar = showSelectionBar
        self.onSelect = onSelect
        self.leading = leading()
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        Button {
            onSelect(NSApp.currentEvent)
        } label: {
            HStack(spacing: 0) {
                // Selection bar (left edge)
                if showSelectionBar {
                    Rectangle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 3)
                        .animation(.easeOut(duration: 0.05), value: isSelected)
                }

                // Multi-select checkbox
                if isMultiSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accentColor : Theme.current.foregroundMuted)
                        .frame(width: 32, height: 28)
                        .transition(.scale.combined(with: .opacity))
                }

                // Leading content
                leading
                    .padding(.trailing, style.leadingTrailingSpacing)

                // Main content
                content
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing content
                trailing
                    .padding(.leading, style.leadingTrailingSpacing)
            }
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .background(backgroundView)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(alignment: .bottom) {
            if style.showDivider {
                Divider()
                    .opacity(0.3)
            }
        }
        // Focus ring — subtle glow instead of hard border
        .overlay {
            if isFocused && !isSelected {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    .padding(1)
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        ZStack {
            // Base background
            if style.useGlassBackground {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
            } else if isAlternate {
                Rectangle()
                    .fill(Theme.current.foreground.opacity(0.02))
            }

            // Selection/hover overlay
            if isSelected {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Color.accentColor.opacity(0.15))
            } else if isHovering {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Theme.current.foreground.opacity(0.05))
            }
        }
    }
}

/// DetailRow without leading slot
extension DetailRow where Leading == EmptyView {
    init(
        isSelected: Bool,
        isMultiSelectMode: Bool = false,
        isFocused: Bool = false,
        isAlternate: Bool = false,
        style: DetailRowStyle = .standard,
        showSelectionBar: Bool = true,
        onSelect: @escaping (NSEvent?) -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.isSelected = isSelected
        self.isMultiSelectMode = isMultiSelectMode
        self.isFocused = isFocused
        self.isAlternate = isAlternate
        self.style = style
        self.showSelectionBar = showSelectionBar
        self.onSelect = onSelect
        self.leading = EmptyView()
        self.content = content()
        self.trailing = trailing()
    }
}

/// DetailRow without trailing slot
extension DetailRow where Trailing == EmptyView {
    init(
        isSelected: Bool,
        isMultiSelectMode: Bool = false,
        isFocused: Bool = false,
        isAlternate: Bool = false,
        style: DetailRowStyle = .standard,
        showSelectionBar: Bool = true,
        onSelect: @escaping (NSEvent?) -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isMultiSelectMode = isMultiSelectMode
        self.isFocused = isFocused
        self.isAlternate = isAlternate
        self.style = style
        self.showSelectionBar = showSelectionBar
        self.onSelect = onSelect
        self.leading = leading()
        self.content = content()
        self.trailing = EmptyView()
    }
}

/// DetailRow with just content
extension DetailRow where Leading == EmptyView, Trailing == EmptyView {
    init(
        isSelected: Bool,
        isMultiSelectMode: Bool = false,
        isFocused: Bool = false,
        isAlternate: Bool = false,
        style: DetailRowStyle = .standard,
        showSelectionBar: Bool = true,
        onSelect: @escaping (NSEvent?) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isMultiSelectMode = isMultiSelectMode
        self.isFocused = isFocused
        self.isAlternate = isAlternate
        self.style = style
        self.showSelectionBar = showSelectionBar
        self.onSelect = onSelect
        self.leading = EmptyView()
        self.content = content()
        self.trailing = EmptyView()
    }
}

/// Row styling options
enum DetailRowStyle {
    /// Standard table row (compact, no glass)
    case standard
    /// Card-like row with glass background
    case card
    /// Compact row for dense lists
    case compact

    var horizontalPadding: CGFloat {
        #if DEBUG
        if DesignModeManager.shared.listTuningEnabled {
            return DesignModeManager.shared.listHorizontalPadding
        }
        #endif
        switch self {
        case .standard: return Spacing.sm
        case .card: return Spacing.md
        case .compact: return Spacing.sm
        }
    }

    var verticalPadding: CGFloat {
        #if DEBUG
        if DesignModeManager.shared.listTuningEnabled {
            return DesignModeManager.shared.listVerticalPadding
        }
        #endif
        switch self {
        case .standard: return Spacing.sm
        case .card: return Spacing.md
        case .compact: return 7
        }
    }

    var leadingTrailingSpacing: CGFloat {
        #if DEBUG
        if DesignModeManager.shared.listTuningEnabled {
            return DesignModeManager.shared.listLeadingSpacing
        }
        #endif
        switch self {
        case .standard: return Spacing.md
        case .card: return Spacing.md
        case .compact: return Spacing.sm
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .standard: return 0
        case .card: return CornerRadius.sm
        case .compact: return 0
        }
    }

    var useGlassBackground: Bool {
        switch self {
        case .standard, .compact: return false
        case .card: return true
        }
    }

    var showDivider: Bool {
        switch self {
        case .standard, .compact: return true
        case .card: return false
        }
    }
}

// MARK: - Previews

#Preview("Duration Badges") {
    VStack(spacing: Spacing.sm) {
        DurationBadge(seconds: 65)
        DurationBadge(seconds: 125)
        DurationBadge(seconds: 3725)
    }
    .padding()
    .background(Color.black)
}

#Preview("Detail Rows - Standard") {
    VStack(spacing: 0) {
        ForEach(0..<5) { index in
            DetailRow(
                isSelected: index == 1,
                isAlternate: index % 2 == 1,
                onSelect: { _ in }
            ) {
                Image(systemName: "doc.fill")
                    .foregroundColor(Theme.current.foregroundSecondary)
            } content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Item \(index + 1)")
                        .font(.system(size: 13, weight: .medium))
                    Text("Secondary text here")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            } trailing: {
                DurationBadge(seconds: 125 + index * 30)
            }
        }
    }
    .frame(width: 400)
    .background(Color.black)
}

#Preview("Detail Rows - Card Style") {
    VStack(spacing: Spacing.sm) {
        ForEach(0..<3) { index in
            DetailRow(
                isSelected: index == 0,
                style: .card,
                showSelectionBar: false,
                onSelect: { _ in }
            ) {
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voice Memo \(index + 1)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("This is a preview of the transcript content that might be quite long...")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                }
            } trailing: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("2:35")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("Today")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
        }
    }
    .padding()
    .frame(width: 450)
    .background(Color.black)
}

#Preview("Detail Rows - Multi-Select") {
    VStack(spacing: 0) {
        ForEach(0..<4) { index in
            DetailRow(
                isSelected: index == 1 || index == 2,
                isMultiSelectMode: true,
                onSelect: { _ in }
            ) {
                Text("Item \(index + 1)")
                    .font(.system(size: 13, weight: .medium))
            } trailing: {
                Text("10:30 AM")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
    }
    .frame(width: 350)
    .background(Color.black)
}

// MARK: - Search Filter Bar

/// Unified search and filter bar for list views.
/// Provides search field, filter chips, and action buttons.
///
/// Usage:
/// ```swift
/// SearchFilterBar(
///     searchText: $searchText,
///     placeholder: "Search memos..."
/// ) {
///     // Filter chips
///     FilterChip("Short", icon: "clock", isActive: shortFilter) { toggleShort() }
///     FilterChip("iPhone", icon: "iphone", isActive: iphoneFilter) { toggleiPhone() }
/// } trailing: {
///     // Trailing actions
///     RefreshButton(isLoading: isLoading) { await refresh() }
/// }
/// ```
struct SearchFilterBar<Filters: View, Trailing: View>: View {
    @Binding var searchText: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)? = nil
    var searchFocused: FocusState<Bool>.Binding?
    let filters: Filters
    let trailing: Trailing

    @FocusState private var internalSearchFocused: Bool

    init(
        searchText: Binding<String>,
        placeholder: String = "Search...",
        onSubmit: (() -> Void)? = nil,
        searchFocused: FocusState<Bool>.Binding? = nil,
        @ViewBuilder filters: () -> Filters,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.searchFocused = searchFocused
        self.filters = filters()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Search field
            searchField

            // Filter chips
            filters

            Spacer()

            // Trailing actions
            trailing
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(TalkieTheme.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(TalkieTheme.textMuted)
                .font(.system(size: 11))

            textFieldView

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(TalkieTheme.textMuted)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(TalkieTheme.hover)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var textFieldView: some View {
        let field = TextField(placeholder, text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .frame(minWidth: 80, maxWidth: 140)
            .onSubmit {
                onSubmit?()
            }

        if let externalFocus = searchFocused {
            field.focused(externalFocus)
        } else {
            field.focused($internalSearchFocused)
        }
    }
}

// Convenience inits
extension SearchFilterBar where Filters == EmptyView {
    init(
        searchText: Binding<String>,
        placeholder: String = "Search...",
        onSubmit: (() -> Void)? = nil,
        searchFocused: FocusState<Bool>.Binding? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.searchFocused = searchFocused
        self.filters = EmptyView()
        self.trailing = trailing()
    }
}

extension SearchFilterBar where Trailing == EmptyView {
    init(
        searchText: Binding<String>,
        placeholder: String = "Search...",
        onSubmit: (() -> Void)? = nil,
        searchFocused: FocusState<Bool>.Binding? = nil,
        @ViewBuilder filters: () -> Filters
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.searchFocused = searchFocused
        self.filters = filters()
        self.trailing = EmptyView()
    }
}

extension SearchFilterBar where Filters == EmptyView, Trailing == EmptyView {
    init(
        searchText: Binding<String>,
        placeholder: String = "Search...",
        onSubmit: (() -> Void)? = nil,
        searchFocused: FocusState<Bool>.Binding? = nil
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.searchFocused = searchFocused
        self.filters = EmptyView()
        self.trailing = EmptyView()
    }
}

// MARK: - Filter Chip

/// Individual filter chip for use in SearchFilterBar.
///
/// Usage:
/// ```swift
/// FilterChip("Short", icon: "clock", isActive: isShortActive, color: .blue) {
///     toggleShortFilter()
/// }
/// ```
struct FilterChip: View {
    let label: String
    let icon: String?
    let isActive: Bool
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ label: String,
        icon: String? = nil,
        isActive: Bool,
        color: Color = .accentColor,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.isActive = isActive
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundColor(isActive ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isActive ? color : color.opacity(isHovering ? 0.2 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(color.opacity(isActive ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Async Filter Chip

/// Filter chip with async action support for use with async view models.
///
/// Usage:
/// ```swift
/// AsyncFilterChip("Short", icon: "clock", isActive: isShortActive, color: .orange) {
///     await viewModel.toggleFilter(.short)
/// }
/// ```
struct AsyncFilterChip: View {
    let label: String
    let icon: String?
    let isActive: Bool
    let color: Color
    let action: () async -> Void

    @State private var isHovering = false

    init(
        _ label: String,
        icon: String? = nil,
        isActive: Bool,
        color: Color = .accentColor,
        action: @escaping () async -> Void
    ) {
        self.label = label
        self.icon = icon
        self.isActive = isActive
        self.color = color
        self.action = action
    }

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundColor(isActive ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isActive ? color : color.opacity(isHovering ? 0.2 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(color.opacity(isActive ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Refresh Button

/// Animated refresh button with loading state.
///
/// Usage:
/// ```swift
/// RefreshButton(isLoading: viewModel.isLoading) {
///     await viewModel.refresh()
/// }
/// ```
struct RefreshButton: View {
    let isLoading: Bool
    let action: () async -> Void

    @State private var isHovering = false

    init(isLoading: Bool, action: @escaping () async -> Void) {
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11))
                .foregroundColor(isHovering ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
                .rotationEffect(.degrees(isLoading ? 360 : 0))
                .animation(
                    isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isLoading
                )
        }
        .buttonStyle(.plain)
        .help("Refresh")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - View Mode Toggle

/// Toggle between view modes (e.g., list vs cards).
///
/// Usage:
/// ```swift
/// ViewModeToggle(
///     modes: [.list, .cards],
///     selected: $viewMode
/// )
/// ```
struct ViewModeToggle<Mode: Hashable & CaseIterable>: View where Mode: RawRepresentable, Mode.RawValue == String {
    @Binding var selected: Mode
    var showLabels: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Mode.allCases), id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selected = mode
                    }
                } label: {
                    Group {
                        if showLabels {
                            Text(mode.rawValue.capitalized)
                                .font(.system(size: 10, weight: .medium))
                        } else {
                            Image(systemName: iconForMode(mode))
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundColor(selected == mode ? TalkieTheme.textPrimary : TalkieTheme.textMuted)
                    .frame(width: 24, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selected == mode ? TalkieTheme.surfaceCard : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(mode.rawValue.capitalized)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(TalkieTheme.hover)
        )
    }

    private func iconForMode(_ mode: Mode) -> String {
        switch mode.rawValue.lowercased() {
        case "list", "condensed", "table": return "list.bullet"
        case "cards", "grid": return "square.grid.2x2"
        case "expanded": return "rectangle.grid.1x2"
        case "auto": return "sparkles"
        default: return "circle"
        }
    }
}

// MARK: - Count Badge

/// Shows item count in header.
///
/// Usage:
/// ```swift
/// CountBadge(count: 42, label: "memos")
/// ```
struct CountBadge: View {
    let count: Int
    var label: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))

            if let label = label {
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
            }
        }
        .foregroundColor(TalkieTheme.textMuted)
    }
}

// MARK: - List Footer

/// Consistent footer for list views with count, selection info, and actions.
///
/// Usage:
/// ```swift
/// ListFooter(
///     displayedCount: 25,
///     totalCount: 100,
///     selectedCount: 3
/// ) {
///     Button("Load More") { }
/// }
/// ```
struct ListFooter<Trailing: View>: View {
    let displayedCount: Int
    var totalCount: Int? = nil
    var selectedCount: Int = 0
    var onClearSelection: (() -> Void)? = nil
    let trailing: Trailing

    init(
        displayedCount: Int,
        totalCount: Int? = nil,
        selectedCount: Int = 0,
        onClearSelection: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.displayedCount = displayedCount
        self.totalCount = totalCount
        self.selectedCount = selectedCount
        self.onClearSelection = onClearSelection
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Count info
            HStack(spacing: 4) {
                if selectedCount > 1 {
                    Text("\(selectedCount) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)

                    Text("·")
                        .foregroundColor(TalkieTheme.textMuted)
                }

                if let total = totalCount {
                    CountBadge(count: displayedCount, label: "of \(total)")
                } else {
                    CountBadge(count: displayedCount)
                }
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(TalkieTheme.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TalkieTheme.border)
                .frame(height: 1)
        }
    }
}

extension ListFooter where Trailing == EmptyView {
    init(
        displayedCount: Int,
        totalCount: Int? = nil,
        selectedCount: Int = 0,
        onClearSelection: (() -> Void)? = nil
    ) {
        self.displayedCount = displayedCount
        self.totalCount = totalCount
        self.selectedCount = selectedCount
        self.onClearSelection = onClearSelection
        self.trailing = EmptyView()
    }
}

// MARK: - Loading State

/// Loading indicator with optional message.
///
/// Usage:
/// ```swift
/// LoadingState()
/// LoadingState("Loading memos...")
/// LoadingState("Transcribing...", style: .prominent)
/// ```
struct LoadingState: View {
    let message: String?
    let style: LoadingStyle

    enum LoadingStyle {
        case subtle      // Small spinner
        case standard    // Medium spinner with message
        case prominent   // Large spinner with message

        var spinnerSize: CGFloat {
            switch self {
            case .subtle: return 12
            case .standard: return 14
            case .prominent: return 18
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .subtle: return 11
            case .standard: return 13
            case .prominent: return 15
            }
        }

        var spacing: CGFloat {
            switch self {
            case .subtle: return Spacing.xs
            case .standard: return Spacing.sm
            case .prominent: return Spacing.md
            }
        }
    }

    init(_ message: String? = nil, style: LoadingStyle = .standard) {
        self.message = message
        self.style = style
    }

    var body: some View {
        VStack(spacing: style.spacing) {
            BrailleSpinner(size: style.spinnerSize)

            if let message = message {
                Text(message)
                    .font(.system(size: style.fontSize))
                    .foregroundColor(TalkieTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Multi-Select Inspector

/// Inspector view shown when multiple items are selected.
///
/// Usage:
/// ```swift
/// MultiSelectInspector(
///     count: 5,
///     itemName: "memos",
///     onClearSelection: { selection.removeAll() }
/// ) {
///     Button("Export") { }
///     Button("Delete", role: .destructive) { }
/// }
/// ```
struct MultiSelectInspector<Actions: View>: View {
    let count: Int
    var itemName: String = "items"
    var icon: String = "square.stack.3d.up"
    let onClearSelection: () -> Void
    let actions: Actions

    init(
        count: Int,
        itemName: String = "items",
        icon: String = "square.stack.3d.up",
        onClearSelection: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.count = count
        self.itemName = itemName
        self.icon = icon
        self.onClearSelection = onClearSelection
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))

            VStack(spacing: Spacing.xs) {
                Text("\(count) \(itemName.capitalized) Selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TalkieTheme.textSecondary)

                Text("⌘-click to toggle, ⇧-click for range")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    onClearSelection()
                } label: {
                    Label("Clear Selection", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                actions
            }
            .padding(.top, Spacing.xs)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension MultiSelectInspector where Actions == EmptyView {
    init(
        count: Int,
        itemName: String = "items",
        icon: String = "square.stack.3d.up",
        onClearSelection: @escaping () -> Void
    ) {
        self.count = count
        self.itemName = itemName
        self.icon = icon
        self.onClearSelection = onClearSelection
        self.actions = EmptyView()
    }
}

// MARK: - List Detail Layout

/// Responsive layout that shows list + detail in wide mode, list only in compact mode.
/// In compact mode, detail is shown as a sheet when an item is selected.
///
/// Usage:
/// ```swift
/// ListDetailLayout(
///     compactThreshold: 900,
///     showDetailSheet: $showSheet,
///     hasSelection: selectedID != nil
/// ) {
///     // List content
///     MemosList(selection: $selectedID)
/// } detail: {
///     // Detail content
///     if let id = selectedID {
///         MemoDetail(id: id)
///     }
/// }
/// ```
struct ListDetailLayout<ListContent: View, DetailContent: View>: View {
    let compactThreshold: CGFloat
    @Binding var showDetailSheet: Bool
    let hasSelection: Bool
    let listContent: ListContent
    let detailContent: DetailContent

    @State private var isCompactMode = false

    init(
        compactThreshold: CGFloat = 900,
        showDetailSheet: Binding<Bool>,
        hasSelection: Bool,
        @ViewBuilder list: () -> ListContent,
        @ViewBuilder detail: () -> DetailContent
    ) {
        self.compactThreshold = compactThreshold
        self._showDetailSheet = showDetailSheet
        self.hasSelection = hasSelection
        self.listContent = list()
        self.detailContent = detail()
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < compactThreshold

            Group {
                if compact {
                    listContent
                } else {
                    HSplitView {
                        listContent
                            .frame(minWidth: 300, idealWidth: 450)

                        detailContent
                            .frame(minWidth: 280, idealWidth: 380, maxWidth: 500)
                            .background(TalkieTheme.surface)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(TalkieTheme.borderSubtle)
                                    .frame(width: 1)
                                    .ignoresSafeArea(.container, edges: .top)
                            }
                    }
                }
            }
            .onChange(of: compact) { _, newValue in
                isCompactMode = newValue
                if !newValue { showDetailSheet = false }
            }
            .onAppear { isCompactMode = compact }
        }
        .sheet(isPresented: $showDetailSheet) {
            NavigationStack {
                detailContent
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showDetailSheet = false }
                        }
                    }
            }
            .frame(minWidth: 400, idealWidth: 500, minHeight: 500, idealHeight: 600)
        }
    }

    /// Whether the layout is currently in compact mode
    var isCompact: Bool { isCompactMode }
}

// MARK: - Relative Time Formatter

/// Formats dates as relative time strings (e.g., "5m ago", "Mon", "Jan 14")
enum RelativeTimeFormatter {
    static func format(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let interval = now.timeIntervalSince(date)

        // Today: show relative time
        if calendar.isDateInToday(date) {
            if interval < 3600 {
                let minutes = max(1, Int(interval / 60))
                return "\(minutes)m ago"
            } else {
                let hours = Int(interval / 3600)
                return "\(hours)h ago"
            }
        }

        // This week: show short day name
        if interval < 604800 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"  // Mon, Tue, Wed
            return formatter.string(from: date)
        }

        // This year
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }

        // Different year
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Search Filter Bar Previews

#Preview("Search Filter Bar - Full") {
    struct PreviewWrapper: View {
        @State private var searchText = ""
        @State private var shortFilter = false
        @State private var iphoneFilter = true
        @State private var isLoading = false

        var body: some View {
            VStack(spacing: 0) {
                SearchFilterBar(
                    searchText: $searchText,
                    placeholder: "Search memos..."
                ) {
                    FilterChip("Short", icon: "clock", isActive: shortFilter, color: .orange) {
                        shortFilter.toggle()
                    }
                    FilterChip("iPhone", icon: "iphone", isActive: iphoneFilter, color: .blue) {
                        iphoneFilter.toggle()
                    }
                    FilterChip("Mac", icon: "desktopcomputer", isActive: false, color: .purple) {}
                } trailing: {
                    CountBadge(count: 42, label: "memos")
                    RefreshButton(isLoading: isLoading) {
                        isLoading = true
                        try? await Task.sleep(for: .seconds(2))
                        isLoading = false
                    }
                }

                Spacer()
            }
            .frame(width: 600, height: 200)
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}

#Preview("Search Filter Bar - Minimal") {
    struct PreviewWrapper: View {
        @State private var searchText = ""

        var body: some View {
            VStack(spacing: 0) {
                SearchFilterBar(
                    searchText: $searchText,
                    placeholder: "Search..."
                )

                Spacer()
            }
            .frame(width: 400, height: 150)
            .background(Color.black)
        }
    }
    return PreviewWrapper()
}

#Preview("Filter Chips") {
    HStack(spacing: Spacing.sm) {
        FilterChip("Active", icon: "checkmark", isActive: true, color: .green) {}
        FilterChip("Inactive", icon: "xmark", isActive: false, color: .red) {}
        FilterChip("Default", isActive: false) {}
    }
    .padding()
    .background(Color.black)
}
