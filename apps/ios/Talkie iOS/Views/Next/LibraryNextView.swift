//
//  LibraryNextView.swift
//  Talkie iOS
//
//  Phase 3 paint — Library / all-docs surface. Soft brass underline
//  tabs (Memos · Dictations · Items), 2-line iOS-Notes rows, search
//  bar flush as footer. The shell voice button floats above.
//
//  Spec: design/studio/app/library/SWIFT_PORT.md
//  Visual reference: design/studio/app/library/page.tsx
//

import SwiftUI

enum LibraryTab: CaseIterable, Equatable {
    case memos, dictations, items

    var label: String {
        switch self {
        case .memos:      return "Memos"
        case .dictations: return "Dictations"
        case .items:      return "Items"
        }
    }
}

struct LibraryNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var router = AppShellRouter.shared
    @StateObject private var library: LibraryFeed
    @State private var activeTab: LibraryTab = .memos
    @State private var query: String = ""

    init(feed: LibraryFeed? = nil) {
        _library = StateObject(wrappedValue: feed ?? LibraryFeed())
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(
                count: library.items(for: activeTab, matching: query).count,
                total: library.totalCount(for: activeTab, matching: query),
                onBack: { AppShellRouter.shared.openHome() }
            )
            TabRow(active: $activeTab)
                // Push the tabs down off the header so the titles breathe.
                .padding(.top, 14)
            ScrollView {
                VStack(spacing: 12) {
                    LibraryListCard(
                        items: library.items(for: activeTab, matching: query),
                        earlierCount: library.earlierCount(for: activeTab, matching: query),
                        activeTab: activeTab,
                        isLoading: library.isLoading,
                        errorMessage: library.errorMessage,
                        isSearching: !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) { item in
                        library.delete(item, in: activeTab)
                    } onPromote: { item in
                        library.promoteToMemo(item)
                    } onLoadMore: {
                        library.loadMore(for: activeTab)
                    }
                    .padding(.horizontal, 12)

                    if activeTab == .dictations {
                        FullHistoryLink {
                            AppShellRouter.shared.openDictationHistory()
                        }
                        .padding(.horizontal, 12)
                    }

                    SearchBar(placeholder: searchPlaceholder, query: $query)
                        .padding(.horizontal, 12)

                    Spacer(minLength: 80)
                }
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
        // Contextual primary action — a round CTA appropriate to the
        // active tab: mic to record a memo, keyboard to type a dictation,
        // viewfinder to grab a capture. Floats bottom-center, clear of the
        // shell's bottom-left summon.
        .overlay(alignment: .bottom) {
            // Bottom inset puts the CTA's center of gravity on the same
            // line as the bottom-left summon: summon is 16 + 48/2 = 40pt
            // up; a 62pt CTA at 9 + 62/2 = 40pt matches it.
            LibraryCTA(tab: activeTab)
                .padding(.bottom, 9)
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemosDidChange)) { _ in library.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in library.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .composeNotesDidChange)) { _ in library.reload() }
        .onAppear {
            consumePendingLibraryTab()
        }
        .onChange(of: router.pendingLibraryTab) { _, _ in
            consumePendingLibraryTab()
        }
    }

    private var searchPlaceholder: String {
        switch activeTab {
        case .memos:      return "Search memos"
        case .dictations: return "Search dictations"
        case .items:      return "Search items"
        }
    }

    private func consumePendingLibraryTab() {
        guard let tab = router.pendingLibraryTab else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            activeTab = tab
        }
        router.pendingLibraryTab = nil
    }
}

// MARK: - Header

private struct LibraryHeader: View {
    let count: Int
    let total: Int
    let onBack: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Home")
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Library")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Text("\(count) / \(total)")
                .talkieType(.channelLabelSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(theme.colors.cardBackground)
                        .overlay(Capsule().strokeBorder(
                            theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        ))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // No bottom hairline — the gap below the header (TabRow's top
        // padding) separates the zones by space, not a line.
    }
}

// MARK: - Tab row (soft underline)

private struct TabRow: View {
    @Binding var active: LibraryTab
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func tabButton(_ tab: LibraryTab) -> some View {
        let isActive = (active == tab)
        return Button(action: {
            guard active != tab else { return }
            Haptics.toggle.fire()  // selection tick — switching the Library filter tab
            withAnimation(.easeOut(duration: 0.18)) { active = tab }
        }) {
            VStack(spacing: 4) {
                Text(tab.label)
                    .talkieType(.preview)
                    .foregroundStyle(isActive
                        ? theme.currentTheme.chrome.accent
                        : theme.colors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                Rectangle()
                    .fill(isActive ? theme.currentTheme.chrome.accent : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contextual CTA

/// A swappable MATERIAL skin for the CTA. Themes can diverge across these
/// over time to increasingly stand out; today they share one default.
enum LibraryCTAMaterial: String {
    case accent   // filled + two-layer lift — the highlighted button
    case glass    // dark translucent + accent ring — matches the summon
    case ring     // ghost outline — quietest
}

/// The CTA's resolved permutation. The seam where a theme picks its own
/// material / size / label later; for now everything resolves to `.standard`.
struct LibraryCTAStyle {
    var material: LibraryCTAMaterial
    var diameter: CGFloat
    var showLabel: Bool
    static let standard = LibraryCTAStyle(material: .accent, diameter: 62, showLabel: false)
}

/// The round primary action that swaps with the active tab — record a
/// memo (mic), type a dictation (keyboard), grab a capture (viewfinder).
/// Carries the deck keycaps' two-layer lift so it reads as the one
/// tappable thing on a quiet surface. Shares the summon's vertical center
/// of gravity, and steps aside when the summon chrome is up.
private struct LibraryCTA: View {
    let tab: LibraryTab
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var chrome: ShellChrome

    // Theme-overridable permutation — resolve from the theme as themes
    // diverge; one shared default for now.
    private var style: LibraryCTAStyle { .standard }

    // One highlighted button on screen at a time: when the summon chrome
    // is up, the center CTA steps aside rather than compete with it.
    private var isVisible: Bool { chrome.state == .resting }

    var body: some View {
        VStack(spacing: 7) {
            Button(action: act) { fab }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)

            if style.showLabel {
                Text(caption)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(labelColor)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeOut(duration: 0.2), value: isVisible)
    }

    private var fab: some View {
        let d = style.diameter
        return ZStack {
            Circle()
                .fill(fillColor)
                // Top sheen → catches light from above, like a real cap.
                .overlay(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(sheen), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                )
                .overlay(Circle().strokeBorder(ringColor, lineWidth: ringWidth))

            Image(systemName: icon)
                .font(.system(size: d * 0.34, weight: .semibold))
                .foregroundStyle(glyphColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: d, height: d)
        .compositingGroup()
        .shadow(color: shadow1.color, radius: shadow1.radius, y: shadow1.y)
        .shadow(color: shadow2.color, radius: shadow2.radius, y: shadow2.y)
    }

    // MARK: material-driven appearance

    private var accent: Color { theme.currentTheme.chrome.accent }

    private var fillColor: Color {
        switch style.material {
        case .accent: return accent
        case .glass:  return theme.colors.cardBackground
        case .ring:   return Color.white.opacity(0.02)
        }
    }
    private var sheen: Double {
        switch style.material {
        case .accent: return 0.22
        case .glass:  return 0.07
        case .ring:   return 0
        }
    }
    private var ringColor: Color {
        switch style.material {
        case .accent: return Color.white.opacity(0.16)
        case .glass:  return accent.opacity(0.5)
        case .ring:   return accent
        }
    }
    private var ringWidth: CGFloat {
        switch style.material {
        case .accent: return 0.5
        case .glass:  return 1
        case .ring:   return 1.5
        }
    }
    private var glyphColor: Color {
        switch style.material {
        case .accent:        return Color.black.opacity(0.82)
        case .glass, .ring:  return accent
        }
    }
    private var labelColor: Color {
        switch style.material {
        case .accent:        return theme.colors.textTertiary
        case .glass, .ring:  return accent
        }
    }
    // Lift: a wide glow/ambient + a tight contact. Ring is flat.
    private var shadow1: (color: Color, radius: CGFloat, y: CGFloat) {
        switch style.material {
        case .accent: return (accent.opacity(0.45), 16, 7)
        case .glass:  return (Color.black.opacity(0.45), 12, 6)
        case .ring:   return (Color.clear, 0, 0)
        }
    }
    private var shadow2: (color: Color, radius: CGFloat, y: CGFloat) {
        switch style.material {
        case .accent: return (Color.black.opacity(0.32), 3, 1)
        case .glass:  return (Color.black.opacity(0.40), 2, 1)
        case .ring:   return (Color.clear, 0, 0)
        }
    }

    // MARK: per-tab content

    private var icon: String {
        switch tab {
        case .memos:      return "mic.fill"
        case .dictations: return "keyboard"
        case .items:      return "viewfinder"
        }
    }
    private var caption: String {
        switch tab {
        case .memos:      return "Record"
        case .dictations: return "Dictate"
        case .items:      return "Capture"
        }
    }
    private var accessibilityLabel: String {
        switch tab {
        case .memos:      return "Record a memo"
        case .dictations: return "Type a dictation"
        case .items:      return "Grab a capture"
        }
    }

    private func act() {
        switch tab {
        case .memos:      RecordingSheetController.shared.isPresented = true
        case .dictations: AppShellRouter.shared.openComposeWithKeyboard()
        case .items:      AppShellRouter.shared.openCaptureCompose()
        }
    }
}

// MARK: - List card

private struct LibraryListCard: View {
    let items: [LibraryFeed.Item]
    let earlierCount: Int
    let activeTab: LibraryTab
    let isLoading: Bool
    let errorMessage: String?
    let isSearching: Bool
    let onDelete: (LibraryFeed.Item) -> Void
    let onPromote: (LibraryFeed.Item) -> Void
    let onLoadMore: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else if let errorMessage {
                LibraryMessageState(
                    icon: "exclamationmark.triangle",
                    headline: "Couldn’t load library",
                    hint: errorMessage
                )
            } else if items.isEmpty {
                EmptyTabState(tab: activeTab, isSearching: isSearching)
            } else {
                List {
                    ForEach(items.enumerated(), id: \.element.id) { idx, item in
                        LibraryRow(item: item, showDivider: idx > 0)
                            .contentShape(Rectangle())
                            .onTapGesture { open(item) }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if item.canPromoteToMemo {
                                    Button {
                                        Haptics.success.fire()  // earned: a keyboard dictation becomes a kept memo
                                        onPromote(item)
                                    } label: {
                                        Label("Save as Memo", systemImage: "square.and.arrow.down.fill")
                                    }
                                    .tint(theme.currentTheme.chrome.accent)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Haptics.transition.fire()  // firm thud — a row is gone
                                    onDelete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(items.count) * 56)

                if earlierCount > 0 {
                    Button {
                        Haptics.confirm.fire()  // light "got it" as the next page reveals
                        withAnimation { onLoadMore() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text("LOAD \(min(10, earlierCount)) MORE")
                                .talkieType(.channelLabelTiny)
                            Spacer()
                            Text("\(earlierCount) EARLIER")
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Load \(min(10, earlierCount)) more, \(earlierCount) earlier items")
                    .overlay(
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeSubtle)
                            .frame(height: theme.currentTheme.chrome.hairlineWidth)
                            .padding(.leading, 36),
                        alignment: .top
                    )
                } else {
                    HStack(spacing: 6) {
                        Text("· EARLIER")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .overlay(
                        Rectangle()
                            .fill(theme.currentTheme.chrome.edgeSubtle)
                            .frame(height: theme.currentTheme.chrome.hairlineWidth)
                            .padding(.leading, 36),
                        alignment: .top
                    )
                }

                Color.clear.frame(height: 12)
            }
        }
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
        )
    }

    private func open(_ item: LibraryFeed.Item) {
        switch item.source {
        case .dictation:        AppShellRouter.shared.openMemoDetail(memoID: item.id)
        case .typed:            AppShellRouter.shared.openCompose(documentID: item.id)
        case .link, .scan:      AppShellRouter.shared.openCaptureDetail(captureID: item.id)
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryFeed.Item
    let showDivider: Bool

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
                    .padding(.leading, 36)
            }

            HStack(alignment: .center, spacing: 8) {
                sourceGlyph
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16, height: 16)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    if item.isTranscribing {
                        TranscribingBadge()
                    }
                    Spacer(minLength: 8)
                    Text(item.relativeTime)
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                    if let syncStatus = item.syncStatus {
                        Image(systemName: syncIcon(for: syncStatus))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(syncColor(for: syncStatus))
                            .accessibilityLabel(syncAccessibilityLabel(for: syncStatus))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private func syncIcon(for status: LibraryFeed.SyncStatus) -> String {
        switch status {
        case .synced: return "checkmark.circle.fill"
        case .pending: return "circle.dotted"
        }
    }

    private func syncColor(for status: LibraryFeed.SyncStatus) -> Color {
        switch status {
        case .synced: return theme.currentTheme.chrome.accent
        case .pending: return theme.colors.textTertiary
        }
    }

    private func syncAccessibilityLabel(for status: LibraryFeed.SyncStatus) -> String {
        switch status {
        case .synced: return "Synced to Mac"
        case .pending: return "Not synced to Mac"
        }
    }

    @ViewBuilder
    private var sourceGlyph: some View {
        switch item.source {
        case .dictation:
            Image(systemName: "waveform").font(.system(size: 13))
        case .typed:
            Image(systemName: "keyboard").font(.system(size: 12))
        case .link:
            Image(systemName: "link").font(.system(size: 12))
        case .scan:
            Image(systemName: "viewfinder").font(.system(size: 12))
        }
    }
}

// MARK: - Transcribing badge

/// Tiny in-row marker shown only while a memo's background transcription pass
/// is running (VoiceMemo.isTranscribing). A pulsing accent pip + smallcap
/// label; the pip holds steady when Reduce Motion is on. Retry / empty-state
/// affordances live in the memo detail view, not here — an idle empty
/// transcript shows nothing.
private struct TranscribingBadge: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(theme.currentTheme.chrome.accent)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 0.4 : 1)
            Text("TRANSCRIBING")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
        .onAppear {
            guard !TalkieMotion.isReduced else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct EmptyTabState: View {
    let tab: LibraryTab
    let isSearching: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.currentTheme.chrome.accent.opacity(0.10))
                    .frame(width: 56, height: 56)
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }

            VStack(spacing: 6) {
                Text(headline)
                    .talkieType(.headlineSecondary)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(hint)
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)

            if let cta {
                Button(action: cta.action) {
                    HStack(spacing: 6) {
                        Image(systemName: cta.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(cta.label)
                            .talkieType(.chipLabel)
                    }
                    .foregroundStyle(theme.colors.cardBackground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 14)
    }

    private var iconName: String {
        if isSearching { return "magnifyingglass" }
        switch tab {
        case .memos:      return "waveform"
        case .dictations: return "text.cursor"
        case .items:      return "tray"
        }
    }

    private var headline: String {
        if isSearching { return "No matches" }
        switch tab {
        case .memos:      return "No memos yet"
        case .dictations: return "No dictations yet"
        case .items:      return "Nothing in the tray"
        }
    }

    private var hint: String {
        if isSearching { return "Try a different search term." }
        switch tab {
        case .memos:      return "Tap the mic anywhere in Talkie to start a recording."
        case .dictations: return "Use the Talkie keyboard or Compose to capture text by voice."
        case .items:      return "Share links from Safari, or run a camera scan to add items here."
        }
    }

    private struct CTA {
        let label: String
        let icon: String
        let action: () -> Void
    }

    private var cta: CTA? {
        if isSearching { return nil }
        switch tab {
        case .memos:
            return CTA(label: "RECORD", icon: "mic.fill") {
                RecordingSheetController.shared.isPresented = true
            }
        case .dictations:
            return CTA(label: "ENABLE KEYBOARD", icon: "keyboard") {
                AppShellRouter.shared.openKeyboardActivation()
            }
        case .items:
            return CTA(label: "OPEN CAMERA", icon: "camera") {
                AppShellRouter.shared.openCameraCapture()
            }
        }
    }
}

private struct LibraryMessageState: View {
    let icon: String
    let headline: String
    let hint: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text(headline)
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)
            Text(hint)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 14)
    }
}

// MARK: - Full history link (Dictations tab only)

/// Bridges Library's in-place Dictations filter to the dedicated
/// DictationHistoryNext surface — keyboard-dictation entries with
/// pagination, swipe actions, and richer detail than the filtered
/// memo list.
private struct FullHistoryLink: View {
    let action: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.textTertiary)
                Text("View full dictation history")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                  lineWidth: theme.currentTheme.chrome.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search

private struct SearchBar: View {
    let placeholder: String
    @Binding var query: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textTertiary)
            TextField(placeholder, text: $query)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(theme.colors.cardBackground)
                .overlay(Capsule().strokeBorder(
                    theme.currentTheme.chrome.edgeFaint,
                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                ))
        )
    }
}
