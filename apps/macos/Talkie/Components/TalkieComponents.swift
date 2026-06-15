//
//  TalkieComponents.swift
//  Talkie
//
//  UI components with built-in performance instrumentation
//  Uses os_signpost for zero-overhead native instrumentation
//  Convention-based automatic naming via environment propagation
//

import SwiftUI
import OSLog
import TalkieKit

// MARK: - Instrumentation Environment

/// Environment key for current instrumentation section context
private struct InstrumentationSectionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Current instrumentation section (e.g., "AllMemos")
    /// Automatically propagated down the view hierarchy
    var instrumentationSection: String? {
        get { self[InstrumentationSectionKey.self] }
        set { self[InstrumentationSectionKey.self] = newValue }
    }
}

// MARK: - Naming Conventions

/// Automatic naming helper
private func instrumentationName(section: String?, component: String?) -> String {
    switch (section, component) {
    case (let s?, let c?):
        return "\(s).\(c)"
    case (let s?, nil):
        return s
    case (nil, let c?):
        return c
    default:
        return "Unknown"
    }
}

// MARK: - Section Layout

/// Layout style for TalkieSection
enum SectionLayout {
    /// No layout applied - content renders as-is
    case none
    /// Standard page layout with ScrollView, padding, and background
    case page
    /// Page layout without ScrollView (for split views, etc.)
    case pageFixed
}

// MARK: - Universal Page Header

/// Unified header that appears at the top of every page
/// Contains: page title (left), optional title accessory, record button (optional), universal search (right)
struct UniversalPageHeader: View {
    let pageTitle: String
    let showRecordButton: Bool
    var onRecordTap: (() -> Void)?
    /// Optional view rendered between the page title and the spacer (e.g. a type filter control)
    var titleAccessory: AnyView?

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    var body: some View {
        PageHeaderBar {
            if isScope {
                CompactScopePageHeader(title: pageTitle, subtitle: nil)
            } else {
                TalkieText(pageTitle, style: .pageTitle)
            }

            if let titleAccessory {
                titleAccessory
            }

            if showRecordButton {
                Button(action: { onRecordTap?() }) {
                    Image(systemName: "plus")
                        .font(Theme.current.fontXSMedium)
                        .foregroundColor(isScope ? ScopeAmber.solid : Theme.current.foregroundSecondary)
                        .frame(width: 22, height: 22)
                        .background(isScope ? ScopeAmber.tintSubtle : Theme.current.foreground.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Record new memo")
            }

            Spacer()

            // Universal search (searches across all content)
            InlineSearchField(
                text: $searchText,
                placeholder: "Search...",
                onSubmit: {},
                isFocused: $isSearchFocused
            )
        }
        .background(isScope ? ScopeCanvas.canvas : Theme.current.background)
    }
}

// MARK: - Talkie Section

/// A section of UI with optional layout and automatic performance tracking.
///
/// Layout options:
/// - `.none` - No layout, content renders as-is (default)
/// - `.page` - ScrollView + standard padding + background
/// - `.pageFixed` - Standard padding + background, no scroll
///
/// Usage:
/// ```
/// // With page layout (most screens)
/// TalkieSection("Home", layout: .page) {
///     statsRow
///     activitySection
/// }
///
/// // Without layout (nested content, split panes)
/// TalkieSection("Recordings") {
///     recordingsList
/// }
/// ```
///
/// Automatically sets instrumentation section in environment for child components.
/// Events emitted to os_signpost for performance tracking.
struct TalkieSection<Content: View>: View {
    let name: String
    let layout: SectionLayout
    let content: Content
    let onLoad: (() async -> Void)?
    let showUniversalHeader: Bool
    let showRecordButton: Bool
    let onRecordTap: (() -> Void)?
    /// Optional view rendered in the header between the title and the spacer
    let titleAccessory: AnyView?

    @State private var hasAppeared = false
    @State private var isLoading = false
    @State private var signpostState: OSSignpostIntervalState?

    init(
        _ name: String,
        layout: SectionLayout = .none,
        showUniversalHeader: Bool = true,
        showRecordButton: Bool = false,
        onRecordTap: (() -> Void)? = nil,
        titleAccessory: AnyView? = nil,
        @ViewBuilder content: () -> Content,
        onLoad: (() async -> Void)? = nil
    ) {
        self.name = name
        self.layout = layout
        self.content = content()
        self.onLoad = onLoad
        self.showUniversalHeader = showUniversalHeader
        self.showRecordButton = showRecordButton
        self.onRecordTap = onRecordTap
        self.titleAccessory = titleAccessory
    }

    @ViewBuilder
    private var layoutWrapper: some View {
        switch layout {
        case .none:
            content
        case .page:
            ScrollView {
                pageContent
            }
            .background(Theme.current.background)
        case .pageFixed:
            pageContent
                .background(Theme.current.background)
        }
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: PageLayout.sectionSpacing) {
            content
            Spacer(minLength: Spacing.xxl)
        }
        .padding(.horizontal, PageLayout.horizontalPadding)
        .padding(.top, PageLayout.topPadding)
        .padding(.bottom, PageLayout.bottomPadding)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showUniversalHeader {
                UniversalPageHeader(
                    pageTitle: name,
                    showRecordButton: showRecordButton,
                    onRecordTap: onRecordTap,
                    titleAccessory: titleAccessory
                )
            }

            layoutWrapper
                .environment(\.instrumentationSection, name)
        }
        .stageContainer()
        .background(Theme.current.background)
        .designBounds("Section: \(name)", color: .yellow, showDimensions: true)
        .onAppear {
                if !hasAppeared {
                    hasAppeared = true

                    // Do ALL instrumentation work asynchronously to keep UI snappy
                    Task { @MainActor in
                        let id = talkieSignposter.makeSignpostID()

                        // Begin section lifecycle interval (for Instruments)
                        let state = talkieSignposter.beginInterval("SectionLifecycle", id: id)
                        signpostState = state

                        // If there's an onLoad closure, execute it (DB operations will be tracked
                        // and added to the active Navigate action from the sidebar click)
                        if let onLoad = onLoad {
                            isLoading = true
                            await onLoad()
                            isLoading = false
                        }

                        // Complete the Navigate action (captures view creation + DB operations)
                        PerformanceMonitor.shared.completeAction()

                        // Mark as rendered on next runloop (after SwiftUI layout/paint)
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1))
                            PerformanceMonitor.shared.markActionAsRendered(actionName: name)
                        }
                    }
                }
            }
            .onDisappear {
                // End signpost interval for Instruments
                if let state = signpostState {
                    talkieSignposter.endInterval("SectionLifecycle", state, "\(name)")
                    signpostState = nil
                }
            }
    }
}

// MARK: - TalkieButton Variant & Size

/// Visual style variants for TalkieButton
enum TalkieButtonVariant {
    case primary          // Solid accent - main CTAs
    case secondary        // Subtle bg - secondary actions
    case ghost            // Border only - tertiary
    case destructive      // Red accent - dangerous
    case icon             // Icon-only circular hover
    case chip             // Pill-shaped toggle
}

/// Size presets for TalkieButton
@MainActor
enum TalkieButtonSize {
    case small   // 24pt
    case medium  // 32pt (default)
    case large   // 40pt

    var height: CGFloat {
        switch self {
        case .small: return ComponentSize.tiny
        case .medium: return ComponentSize.medium
        case .large: return ComponentSize.large
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return Spacing.sm
        case .medium: return Spacing.md
        case .large: return Spacing.lg
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .small: return Spacing.xs
        case .medium: return Spacing.sm
        case .large: return Spacing.md
        }
    }

    var font: Font {
        switch self {
        case .small: return Theme.current.fontXSMedium
        case .medium: return Theme.current.fontSMMedium
        case .large: return Theme.current.fontBodyMedium
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 14
        case .large: return 16
        }
    }

    var iconButtonSize: CGFloat {
        switch self {
        case .small: return 20
        case .medium: return 24
        case .large: return 32
        }
    }
}

// MARK: - Talkie Button

/// Unified button with consistent styling AND built-in instrumentation.
///
/// Features:
/// - Visual variants: primary, secondary, ghost, destructive, icon, chip
/// - Automatic performance tracking via os_signpost
/// - Convention-based naming from parent TalkieSection
/// - Loading states, hover/press animations
///
/// Usage:
/// ```
/// TalkieButton("Save", icon: "checkmark") { await save() }
/// TalkieButton("Delete", variant: .destructive) { delete() }
/// TalkieButton(icon: "xmark") { dismiss() }
/// ```
///
/// With instrumentation:
/// ```
/// TalkieSection("MemoDetail") {
///     TalkieButton("Save") { ... }  // Auto-instrumented as "MemoDetail.Save"
/// }
/// ```
struct TalkieButton: View {

    // MARK: - Properties

    let name: String
    let label: String?
    let icon: String?
    let variant: TalkieButtonVariant
    let size: TalkieButtonSize
    let isActive: Bool
    let isLoading: Bool
    let tint: Color?
    let explicitSection: String?
    let skipInstrumentation: Bool
    let action: () async -> Void

    @Environment(\.instrumentationSection) private var environmentSection
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var isExecuting = false

    // MARK: - Initializers

    /// Standard button with label and optional icon
    init(
        _ label: String,
        icon: String? = nil,
        variant: TalkieButtonVariant = .primary,
        size: TalkieButtonSize = .medium,
        tint: Color? = nil,
        isLoading: Bool = false,
        section: String? = nil,
        skipInstrumentation: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.name = label
        self.label = label
        self.icon = icon
        self.variant = variant
        self.size = size
        self.tint = tint
        self.isActive = false
        self.isLoading = isLoading
        self.explicitSection = section
        self.skipInstrumentation = skipInstrumentation
        self.action = action
    }

    /// Sync action convenience
    init(
        _ label: String,
        icon: String? = nil,
        variant: TalkieButtonVariant = .primary,
        size: TalkieButtonSize = .medium,
        tint: Color? = nil,
        isLoading: Bool = false,
        section: String? = nil,
        skipInstrumentation: Bool = false,
        action: @escaping () -> Void
    ) {
        self.name = label
        self.label = label
        self.icon = icon
        self.variant = variant
        self.size = size
        self.tint = tint
        self.isActive = false
        self.isLoading = isLoading
        self.explicitSection = section
        self.skipInstrumentation = skipInstrumentation
        self.action = { action() }
    }

    /// Icon-only button
    init(
        icon: String,
        name: String? = nil,
        variant: TalkieButtonVariant = .icon,
        size: TalkieButtonSize = .medium,
        tint: Color? = nil,
        section: String? = nil,
        skipInstrumentation: Bool = false,
        action: @escaping () -> Void
    ) {
        self.name = name ?? icon
        self.label = nil
        self.icon = icon
        self.variant = variant
        self.size = size
        self.tint = tint
        self.isActive = false
        self.isLoading = false
        self.explicitSection = section
        self.skipInstrumentation = skipInstrumentation
        self.action = { action() }
    }

    /// Chip/toggle with active state
    init(
        _ label: String,
        icon: String? = nil,
        isActive: Bool,
        tint: Color? = nil,
        size: TalkieButtonSize = .medium,
        section: String? = nil,
        skipInstrumentation: Bool = false,
        action: @escaping () -> Void
    ) {
        self.name = label
        self.label = label
        self.icon = icon
        self.variant = .chip
        self.size = size
        self.tint = tint
        self.isActive = isActive
        self.isLoading = false
        self.explicitSection = section
        self.skipInstrumentation = skipInstrumentation
        self.action = { action() }
    }

    // MARK: - Computed

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    // MARK: - Body

    var body: some View {
        Button {
            guard !isLoading && !isExecuting else { return }
            Task {
                isExecuting = true

                // Instrumentation (unless skipped)
                if !skipInstrumentation {
                    await MainActor.run {
                        PerformanceMonitor.shared.startAction(
                            type: "Click",
                            name: fullName,
                            context: explicitSection ?? environmentSection
                        )
                    }
                }

                let id = talkieSignposter.makeSignpostID()
                let state = skipInstrumentation ? nil : talkieSignposter.beginInterval("ButtonAction", id: id)

                await action()

                if let state = state {
                    talkieSignposter.endInterval("ButtonAction", state, "\(fullName)")
                }

                if !skipInstrumentation {
                    await MainActor.run {
                        PerformanceMonitor.shared.completeAction()
                    }
                }

                await MainActor.run {
                    isExecuting = false
                }
            }
        } label: {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isExecuting)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .designBounds("Button: \(name)", color: .blue)
    }

    // MARK: - Content

    @ViewBuilder
    private var buttonContent: some View {
        switch variant {
        case .icon:
            iconContent
        case .chip:
            chipContent
        default:
            standardContent
        }
    }

    // MARK: - Standard Button

    private var standardContent: some View {
        HStack(spacing: Spacing.xs) {
            if isLoading || isExecuting {
                BrailleSpinner(size: 12)
            } else if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize, weight: .medium))
            }

            if let label = label {
                Text(label)
                    .font(size.font)
            }
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .frame(minHeight: size.height)
        .background(background)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(TalkieAnimation.fast, value: isPressed)
        .animation(TalkieAnimation.fast, value: isHovered)
    }

    @ViewBuilder
    private var background: some View {
        let radius = TechnicalStyle.isActive ? CornerRadius.cardSmall : cornerRadius
        let borderWidth = SettingsManager.shared.currentBorderWidth

        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(backgroundColor)

            // Technical theme: always show subtle border + matte highlight
            if TechnicalStyle.isActive {
                RoundedRectangle(cornerRadius: radius)
                    .fill(TechnicalStyle.matteHighlight(surfaceLevel: 1))
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(
                        isHovered ? TechnicalStyle.borderHover(baseLevel: 1) : TechnicalStyle.borderLevel1,
                        lineWidth: borderWidth
                    )
            } else if variant == .ghost {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
    }

    // MARK: - Icon Button

    private var iconContent: some View {
        Group {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize, weight: .medium))
                    .foregroundColor(iconForeground)
            }
        }
        .frame(width: size.iconButtonSize, height: size.iconButtonSize)
        .background(Circle().fill(isHovered ? iconHoverBg : Color.clear))
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(TalkieAnimation.fast, value: isPressed)
        .animation(TalkieAnimation.fast, value: isHovered)
    }

    // MARK: - Chip Button

    private var chipContent: some View {
        HStack(spacing: Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize - 2, weight: .medium))
            }
            if let label = label {
                Text(label)
                    .font(size.font)
            }
        }
        .foregroundColor(chipForeground)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Capsule().fill(chipBackground))
        .overlay(Capsule().strokeBorder(chipBorder, lineWidth: 1))
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(TalkieAnimation.fast, value: isPressed)
        .animation(TalkieAnimation.fast, value: isHovered)
    }

    // MARK: - Colors (Central customization point)

    private var effectiveTint: Color { tint ?? .accentColor }
    private var cornerRadius: CGFloat { variant == .ghost ? CornerRadius.xs : CornerRadius.sm }

    private var foregroundColor: Color {
        // Technical theme: neutral grays, no color tints
        if TechnicalStyle.isActive {
            switch variant {
            case .primary:
                return isHovered ? TechnicalStyle.textPrimary : TechnicalStyle.textSecondary
            case .secondary, .ghost:
                return isHovered ? TechnicalStyle.textPrimary : TechnicalStyle.textSecondary
            case .destructive:
                return SemanticColor.error
            default:
                return TechnicalStyle.textSecondary
            }
        }

        // Default styling
        switch variant {
        case .primary: return .white
        case .secondary: return effectiveTint
        case .ghost: return isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary
        case .destructive: return isHovered ? .white : SemanticColor.error
        default: return Theme.current.foreground
        }
    }

    private var backgroundColor: Color {
        // Technical theme: flat surfaces, no tinted backgrounds
        if TechnicalStyle.isActive {
            switch variant {
            case .primary:
                return isHovered ? TechnicalStyle.surface3 : TechnicalStyle.surface2
            case .secondary, .ghost:
                return isHovered ? TechnicalStyle.surfaceHover(level: 1) : TechnicalStyle.surface1
            case .destructive:
                return isHovered ? SemanticColor.error.opacity(0.2) : SemanticColor.error.opacity(0.1)
            default:
                return TechnicalStyle.surface1
            }
        }

        // Default styling
        switch variant {
        case .primary: return isHovered ? effectiveTint.opacity(0.85) : effectiveTint
        case .secondary: return isHovered ? effectiveTint.opacity(Opacity.light) : effectiveTint.opacity(Opacity.subtle)
        case .ghost: return isHovered ? Theme.current.foreground.opacity(Opacity.subtle) : .clear
        case .destructive: return isHovered ? SemanticColor.error : SemanticColor.error.opacity(Opacity.light)
        default: return .clear
        }
    }

    private var borderColor: Color {
        isHovered ? Theme.current.foreground.opacity(Opacity.medium) : Theme.current.divider
    }

    private var iconForeground: Color {
        if let tint = tint {
            return isHovered ? tint : Theme.current.foregroundSecondary
        }
        return isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary
    }

    private var iconHoverBg: Color {
        if tint == SemanticColor.error {
            return SemanticColor.error.opacity(Opacity.medium)
        }
        return Color.primary.opacity(Opacity.light)
    }

    private var chipForeground: Color {
        isActive ? effectiveTint : (isHovered ? Theme.current.foreground : Theme.current.foregroundSecondary)
    }

    private var chipBackground: Color {
        isActive ? effectiveTint.opacity(Opacity.medium) : (isHovered ? Theme.current.foreground.opacity(Opacity.subtle) : .clear)
    }

    private var chipBorder: Color {
        isActive ? effectiveTint.opacity(Opacity.strong) : (isHovered ? Theme.current.divider : Theme.current.divider.opacity(Opacity.half))
    }
}

// MARK: - TalkieAction (Generic Action Wrapper)

/// Generic action wrapper with instrumentation. Use for custom-styled buttons.
///
/// This is the foundation - TalkieButton uses this internally.
/// Use TalkieAction directly when you need 100% custom visuals.
///
/// Usage:
/// ```
/// TalkieAction("VoicePrompt") {
///     await startRecording()
/// } label: {
///     // Completely custom label - pulsing mic, whatever
///     CustomVoiceButton(isRecording: isRecording)
/// }
/// ```
struct TalkieAction<Label: View>: View {
    let name: String
    let explicitSection: String?
    let action: () async -> Void
    let label: Label

    @Environment(\.instrumentationSection) private var environmentSection
    @State private var isExecuting = false

    init(
        _ name: String,
        section: String? = nil,
        action: @escaping () async -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = section
        self.action = action
        self.label = label()
    }

    /// Sync action convenience
    init(
        _ name: String,
        section: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = section
        self.action = { action() }
        self.label = label()
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        Button {
            guard !isExecuting else { return }
            Task {
                isExecuting = true

                // Instrumentation
                await MainActor.run {
                    PerformanceMonitor.shared.startAction(
                        type: "Click",
                        name: fullName,
                        context: explicitSection ?? environmentSection
                    )
                }

                let id = talkieSignposter.makeSignpostID()
                let state = talkieSignposter.beginInterval("Action", id: id)

                await action()

                talkieSignposter.endInterval("Action", state, "\(fullName)")

                await MainActor.run {
                    PerformanceMonitor.shared.completeAction()
                    isExecuting = false
                }
            }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .designBounds("Action: \(name)", color: .orange)
    }
}

// MARK: - Talkie Button Sync (Legacy)

/// Legacy sync button - prefer using TalkieButton with sync action instead.
/// Kept for backward compatibility with existing code.
@available(*, deprecated, message: "Use TalkieButton with sync action instead")
struct TalkieButtonSync<Label: View>: View {
    let name: String
    let explicitSection: String?
    let action: () -> Void
    let label: Label

    @Environment(\.instrumentationSection) private var environmentSection

    init(
        _ name: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = nil
        self.action = action
        self.label = label()
    }

    init(
        _ name: String,
        section: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.name = name
        self.explicitSection = section
        self.action = action
        self.label = label()
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        Button {
            let id = talkieSignposter.makeSignpostID()
            talkieSignposter.emitEvent("Click", id: id, "\(fullName)")
            action()
        } label: {
            label
        }
        .designBounds("Button: \(name)", color: .blue)
    }
}

// MARK: - Talkie Row

/// A row component that tracks clicks via os_signpost
///
/// Automatically inherits section name from parent TalkieSection.
///
/// Convention-based naming:
/// ```
/// TalkieSection("AllMemos") {
///     TalkieList("Memos", items: memos) { memo in
///         TalkieRow("MemoRow", id: memo.id) { ... }  // Auto-named: AllMemos.MemoRow
///     }
/// }
/// ```
struct TalkieRow<Content: View>: View {
    let name: String
    let explicitSection: String?
    let id: String
    let onTap: () -> Void
    let content: Content

    @Environment(\.instrumentationSection) private var environmentSection

    /// Create row with automatic section inheritance
    init(
        _ name: String,
        id: String,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.explicitSection = nil
        self.id = id
        self.onTap = onTap
        self.content = content()
    }

    /// Create row with explicit section override
    init(
        _ name: String,
        section: String,
        id: String,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.explicitSection = section
        self.id = id
        self.onTap = onTap
        self.content = content()
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                let id = talkieSignposter.makeSignpostID()
                talkieSignposter.emitEvent("RowClick", id: id, "\(fullName)")
                onTap()
            }
            .designBounds("Row: \(name)", color: .cyan)
    }
}

// MARK: - Talkie List

/// A list that tracks loading and scrolling performance via os_signpost
///
/// Automatically inherits section name from parent TalkieSection.
///
/// Convention-based naming:
/// ```
/// TalkieSection("AllMemos") {
///     TalkieList("Memos", items: memos) { ... }  // Auto-named: AllMemos.Memos
/// }
/// ```
struct TalkieList<Item: Identifiable, RowContent: View>: View {
    let name: String
    let explicitSection: String?
    let items: [Item]
    let rowContent: (Item) -> RowContent
    let onLoadMore: (() async -> Void)?

    @Environment(\.instrumentationSection) private var environmentSection
    @State private var hasAppeared = false
    @State private var signpostState: OSSignpostIntervalState?

    /// Create list with automatic section inheritance
    init(
        _ name: String,
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.name = name
        self.explicitSection = nil
        self.items = items
        self.rowContent = rowContent
        self.onLoadMore = onLoadMore
    }

    /// Create list with explicit section override
    init(
        _ name: String,
        section: String,
        items: [Item],
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        onLoadMore: (() async -> Void)? = nil
    ) {
        self.name = name
        self.explicitSection = section
        self.items = items
        self.rowContent = rowContent
        self.onLoadMore = onLoadMore
    }

    private var fullName: String {
        let section = explicitSection ?? environmentSection
        return instrumentationName(section: section, component: name)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    rowContent(item)
                        .onAppear {
                            // Trigger load more when approaching end
                            if let lastItem = items.last, item.id == lastItem.id {
                                if let onLoadMore = onLoadMore {
                                    Task {
                                        let id = talkieSignposter.makeSignpostID()
                                        talkieSignposter.emitEvent("LoadMore", id: id, "\(fullName)")
                                        await onLoadMore()
                                    }
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                let id = talkieSignposter.makeSignpostID()

                // Begin list lifecycle
                let state = talkieSignposter.beginInterval("ListLifecycle", id: id)
                signpostState = state
            }
        }
        .onDisappear {
            if let state = signpostState {
                talkieSignposter.endInterval("ListLifecycle", state, "\(fullName)")
                signpostState = nil
            }
        }
        .designBounds("List: \(name)", color: .green)
    }
}

// MARK: - Preview Examples

#Preview("TalkieButton Variants") {
    VStack(alignment: .leading, spacing: Spacing.xl) {
        // Primary
        Group {
            Text("PRIMARY").font(.techLabel).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                TalkieButton("Get Started", icon: "arrow.right", skipInstrumentation: true) { }
                TalkieButton("Save", skipInstrumentation: true) { }
                TalkieButton("Loading", isLoading: true, skipInstrumentation: true) { }
            }
        }

        // Secondary
        Group {
            Text("SECONDARY").font(.techLabel).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                TalkieButton("Cancel", variant: .secondary, skipInstrumentation: true) { }
                TalkieButton("Learn More", icon: "questionmark.circle", variant: .secondary, skipInstrumentation: true) { }
            }
        }

        // Ghost
        Group {
            Text("GHOST").font(.techLabel).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                TalkieButton("Export", icon: "square.and.arrow.up", variant: .ghost, skipInstrumentation: true) { }
                TalkieButton("View Details", variant: .ghost, skipInstrumentation: true) { }
            }
        }

        // Destructive
        Group {
            Text("DESTRUCTIVE").font(.techLabel).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                TalkieButton("Delete", icon: "trash", variant: .destructive, skipInstrumentation: true) { }
                TalkieButton("Disconnect", variant: .destructive, skipInstrumentation: true) { }
            }
        }

        // Icon
        Group {
            Text("ICON").font(.techLabel).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                TalkieButton(icon: "xmark", skipInstrumentation: true) { }
                TalkieButton(icon: "gear", skipInstrumentation: true) { }
                TalkieButton(icon: "trash", tint: SemanticColor.error, skipInstrumentation: true) { }
            }
        }

        // Chip
        Group {
            Text("CHIP").font(.techLabel).foregroundStyle(.secondary)
            HStack(spacing: Spacing.sm) {
                TalkieButton("All", isActive: true, skipInstrumentation: true) { }
                TalkieButton("Errors", icon: "exclamationmark.triangle", isActive: false, tint: .red, skipInstrumentation: true) { }
                TalkieButton("Warnings", isActive: false, tint: .orange, skipInstrumentation: true) { }
            }
        }

        // Sizes
        Group {
            Text("SIZES").font(.techLabel).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: Spacing.md) {
                TalkieButton("Small", size: .small, skipInstrumentation: true) { }
                TalkieButton("Medium", size: .medium, skipInstrumentation: true) { }
                TalkieButton("Large", size: .large, skipInstrumentation: true) { }
            }
        }
    }
    .padding(Spacing.xl)
    .frame(width: 500)
    .background(Theme.current.background)
}

#Preview("TalkieButton with Instrumentation") {
    TalkieSection("Settings") {
        VStack(spacing: Spacing.lg) {
            // Auto-instrumented: Settings.Save
            TalkieButton("Save", icon: "checkmark") {
                try? await Task.sleep(for: .milliseconds(100))
            }

            // Auto-instrumented: Settings.Cancel
            TalkieButton("Cancel", variant: .secondary) { }

            // Auto-instrumented: Settings.Delete
            TalkieButton("Delete", icon: "trash", variant: .destructive) { }

            Text("All buttons auto-inherit 'Settings' section for instrumentation")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview("List Example") {
    struct Memo: Identifiable {
        let id = UUID()
        let title: String
    }

    let memos = (1...20).map { Memo(title: "Memo \($0)") }

    return TalkieSection("AllMemos") {
        VStack {
            TalkieList("MemoList", items: memos) { memo in
                TalkieRow("MemoRow", id: memo.id.uuidString) {
                    TalkieConsole.info("Tapped: \(memo.title)")
                } content: {
                    Text(memo.title)
                        .padding()
                }
            }
        }
    }
}
