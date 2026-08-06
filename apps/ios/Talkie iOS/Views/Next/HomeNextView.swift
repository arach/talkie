//
//  HomeNextView.swift
//  Talkie iOS
//
//  M1 — Talkie's canonical iPhone home, painted to match the
//  studio mock at http://localhost:3000/home.
//
//  Composition: TALKIE wordmark · communication cockpit · frequent-action strip ·
//  command/search bar · Recent list (2-line iOS-Notes style) ·
//  contextual suggestions strip.
//  The ambient voice button lives in AppShellNext, not here.
//
//  Spec: design/studio/app/home/SWIFT_PORT.md
//  Visual reference: design/studio/app/home/page.tsx
//
//  Type system: TalkieTypeStyle tokens (see TalkieType.swift).
//  No raw .font(.system(...)) calls here — channel labels, body
//  serif, and instrument readouts all flow through .talkieType(...).
//

import SwiftUI
import Observation
import TalkieMobileKit
import UIKit

struct HomeNextView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @ObservedObject private var iCloudStatus = iCloudStatusManager.shared
    @ObservedObject private var recordingSheet = RecordingSheetController.shared
    @ObservedObject private var masthead = HomeMastheadExperiment.shared
    @StateObject private var feed: HomeFeed
    @State private var isCommandFocused = false
    @State private var commandKeyboard = HomeCommandKeyboardController()
    @State private var commandMode: HomeCommandMode = .ask
    @State private var askPrompt = ""

    init(feed: HomeFeed? = nil) {
        _feed = StateObject(wrappedValue: feed ?? HomeFeed())
    }

    var body: some View {
        ZStack {
            // Behind the scroll, not inside it: the deck is the thing the
            // content travels across, so it must not travel with it.
            if masthead.isOn, MastheadMaterial.current == .inverted {
                MastheadDeck()
            }

            homeScroll
        }
    }

    private var homeScroll: some View {
        ScrollView {
            // 12 was the gap between three objects that each had a frame of
            // their own to sit in. Once the top became one surface the page
            // below stopped being a stack of cards and started being a set of
            // sections, and sections are told apart by the space around them —
            // at 12 the divider, the action row, the ask bar and the lists all
            // ran together into one column of chrome.
            VStack(spacing: HomeSectionMetrics.gap) {
                if masthead.isOn {
                    // One object where there were three. The stack's 12pt gap
                    // still applies below it, which is what keeps this an
                    // experiment about the top of the page rather than a
                    // rewrite of the page.
                    HomeMasthead(cockpit: feed.cockpit)
                        .padding(
                            .bottom,
                            HomeSectionMetrics.mastheadGap - HomeSectionMetrics.gap
                        )
                } else {
                    HomeHeader()

                    HomeCockpit(model: feed.cockpit)
                        .padding(.horizontal, 12)
                }

                HomeFrequentActionsStrip(onSearch: focusSearch)
                    .padding(.horizontal, 12)

                HomeCommandBar(
                    prompt: $askPrompt,
                    searchText: $feed.searchText,
                    mode: $commandMode,
                    isFocused: $isCommandFocused,
                    keyboardController: commandKeyboard
                )
                    .padding(.horizontal, 12)

                RecentSection(
                    items: feed.recentItems,
                    totalCount: feed.totalRecentCount,
                    isLoading: feed.isLoading,
                    errorMessage: feed.errorMessage,
                    isSearching: feed.isSearching,
                    hasMore: feed.hasMoreRecentItems,
                    remainingCount: feed.remainingRecentItems,
                    contentFilter: $feed.contentFilter,
                    sortOption: $feed.sortOption,
                    showsSyncPrompt: iCloudStatus.status == .noAccount && !iCloudStatus.isDismissed,
                    onLoadMore: { feed.loadMoreRecentItems() },
                    onPromote: { feed.promoteToMemo($0) },
                    onDelete: { feed.delete($0) },
                    onOpenICloudSettings: openICloudSettings,
                    onDismissSyncPrompt: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            iCloudStatus.dismissBanner()
                        }
                    }
                )
                .padding(.horizontal, 12)

                // Back on the page's margin.
                //
                // Running it to the glass did fix the chop, but it bought that
                // by making one row disobey the column every other section
                // keeps — which reads as a mistake rather than as an
                // affordance. The chop is solved where it actually lives
                // instead: at the cut, which now fades.
                HomeSuggestionsStrip()
                    .padding(.horizontal, HomeSectionMetrics.gutter)

                Spacer(minLength: 80)   // breathing room for the shell voice button
            }
            // Puts the content back exactly where the safe area had it, so the
            // only thing that actually moved is the band's background.
            .padding(.top, masthead.isOn ? MastheadSurface.statusBarInset : 0)
        }
        .scrollIndicators(.hidden)
        // The band pads its own surface up by the status bar height to run
        // under the clock — and it was being clipped away every time, because a
        // scroll view clips to its bounds and its bounds began below the status
        // bar. The negative padding was drawing into a strip the scroll view
        // did not own. It owns it now.
        //
        // Scoped to the experiment: the control has no band to bleed, and the
        // point of a control is that it is untouched.
        .ignoresSafeArea(edges: masthead.isOn ? .top : [])
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isCommandFocused {
                HomeTalkieKeyboardHost(
                    controller: commandKeyboard,
                    visualStyle: theme.currentTheme == .mineral ? .mineralInstrument : .automatic
                )
                .frame(maxWidth: .infinity)
                .frame(height: commandKeyboard.preferredHeight)
                // The slab runs to the screen edge; the keys should not. The
                // shared `CompactKeyboardView` lays out edge to edge because
                // that is correct for the system keyboard extension, so the
                // breathing room is added here, on the app's side of the seam,
                // rather than in a constant both hosts read.
                .padding(.horizontal, HomeKeyboardSlabMetrics.sideInset)
                .padding(.top, HomeKeyboardSlabMetrics.topInset)
                // The keyboard view paints no background of its own — as a real
                // `inputView` the system supplies the backdrop. Home hands it to
                // a `safeAreaInset` instead, so without this the recents list
                // scrolls visibly between the keys.
                .background {
                    // Extended past the home indicator so the strip below the
                    // last key is chrome too, not a window onto the feed.
                    theme.colors.background
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.currentTheme.chrome.edgeFaint)
                        .frame(height: theme.currentTheme.chrome.hairlineWidth)
                }
                // The way out rides above the slab on an offset, which draws
                // but does not measure. Carried as a row in the stack it billed
                // the feed a full 30pt of visible height for one glyph, and a
                // `safeAreaInset` charges that to every screenful; as a lifted
                // chip it costs nothing and shades one trailing corner instead.
                .overlay(alignment: .topTrailing) {
                    HomeKeyboardDismissChip { commandKeyboard.onCollapse?() }
                        .padding(.trailing, HomeKeyboardSlabMetrics.sideInset)
                        .offset(y: HomeKeyboardSlabMetrics.dismissLift)
                }
                // Move only. Fading it in as it travels makes the slab
                // translucent for the whole flight — the feed shows through the
                // keys and it reads as materializing rather than arriving from
                // the bottom edge. A keyboard is a solid object; it slides.
                .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .voiceMemosDidChange)) { _ in feed.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .capturesDidChange)) { _ in feed.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .composeNotesDidChange)) { _ in feed.reload() }
        .onChange(of: recordingSheet.isPresented) { wasPresented, isPresented in
            guard wasPresented && !isPresented else { return }
            feed.reload()
        }
        .onChange(of: isCommandFocused) { _, isFocused in
            AppShellRouter.shared.isEditorKeyboardUp = isFocused
        }
        .onChange(of: deepLinkManager.pendingAction) { _, action in
            handleDeepLinkAction(action)
        }
        .onAppear {
            feed.reload()
            handleDeepLinkAction(deepLinkManager.pendingAction)
        }
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--screenshotHomeAskReady") else { return }
            commandMode = .ask
            askPrompt = "Help me outline the launch plan"
            try? await Task.sleep(for: .milliseconds(450))
            isCommandFocused = true
        }
        .animation(.easeOut(duration: 0.22), value: isCommandFocused)
        .onDisappear {
            AppShellRouter.shared.isEditorKeyboardUp = false
        }
    }

    private func handleDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .search(let query):
            commandMode = .search
            feed.searchText = query
            isCommandFocused = true
            deepLinkManager.clearAction()
        case .openSearch:
            focusSearch()
            deepLinkManager.clearAction()
        default:
            break
        }
    }

    private func focusSearch() {
        commandMode = .search
        isCommandFocused = true
    }

    private func openICloudSettings() {
        if let url = URL(string: "App-Prefs:root=APPLE_ACCOUNT") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

enum SharedCaptureIngress {
    static func importURLContent(
        from url: URL,
        suggestedTitle: String? = nil,
        ingestionMethod: String,
        onCapture: @escaping @MainActor @Sendable (Capture) -> Void
    ) {
        Task {
            let result = await URLBookmarkMetadataService.buildCapture(
                from: url,
                suggestedTitle: suggestedTitle,
                sourceDevice: "iPhone",
                ingestionMethod: ingestionMethod
            )

            var capture = result.capture
            if let imageData = result.imageData {
                let filename = CaptureStore.shared.saveImage(imageData, id: capture.id)
                capture = capture.copyWithImage(filename: filename)
            }

            let importedCapture = capture
            await MainActor.run {
                onCapture(importedCapture)
            }
        }
    }

    static func processQueuedShare(
        id: String,
        onCapture: @escaping @MainActor @Sendable (Capture) -> Void
    ) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TalkieMobileRuntimeIdentifiers.appGroupIdentifier
        ) else {
            AppLogger.app.warning("Share queue: app group unavailable")
            return
        }

        let fileURL = containerURL
            .appending(path: "Library/Application Support/Talkie/share-queue")
            .appending(path: "\(id).json")

        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.app.warning("Share queue: file not found for \(id)")
            return
        }

        let payload: QueuedSharePayload
        do {
            payload = try JSONDecoder().decode(QueuedSharePayload.self, from: data)
        } catch {
            AppLogger.app.error("Share queue: failed to decode \(id): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        try? FileManager.default.removeItem(at: fileURL)

        switch payload.sourceType {
        case "url":
            guard let urlString = payload.sourceURL, let url = URL(string: urlString) else { return }
            importURLContent(
                from: url,
                suggestedTitle: payload.title,
                ingestionMethod: "share-extension",
                onCapture: onCapture
            )
        case "photo":
            Task {
                await processSharedPhoto(imageBase64: payload.imageBase64, onCapture: onCapture)
            }
        case "text":
            let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Task { @MainActor in
                onCapture(Capture(sourceType: "text", text: text, title: payload.title))
            }
        default:
            AppLogger.app.warning("Share queue: unknown source type \(payload.sourceType)")
        }
    }

    private static func processSharedPhoto(
        imageBase64: String?,
        onCapture: @escaping @MainActor @Sendable (Capture) -> Void
    ) async {
        guard let imageBase64,
              let imageData = Data(base64Encoded: imageBase64),
              let image = UIImage(data: imageData) else {
            AppLogger.app.warning("Share queue: could not decode image payload")
            return
        }

        let ocrText: String
        do {
            let result = try await ScreenshotOCRService.extractText(from: image)
            ocrText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.ai.info("Share OCR extracted \(ocrText.count) characters")
        } catch {
            ocrText = ""
            AppLogger.ai.info("Share OCR found no text in image")
        }

        let captureID = UUID()
        let imageFilename = CaptureStore.shared.saveImage(imageData, id: captureID)
        let capture = Capture(
            id: captureID,
            sourceType: "photo",
            text: ocrText.isEmpty ? "Image shared from iPhone" : ocrText,
            title: "Image · \(Date().formatted(.dateTime.month().day().hour().minute()))",
            imageFilename: imageFilename
        )

        await MainActor.run {
            onCapture(capture)
        }
    }
}

private struct QueuedSharePayload: Codable {
    let sourceType: String
    let text: String
    let title: String?
    let sourceURL: String?
    let imageBase64: String?
}

private extension Capture {
    func copyWithImage(filename: String?) -> Capture {
        Capture(
            id: id,
            sourceType: sourceType,
            text: text,
            title: title,
            sourceURL: sourceURL,
            bookmark: bookmark,
            imageFilename: filename,
            deferredPageFilenames: deferredPageFilenames,
            totalPageCount: totalPageCount,
            timestamp: timestamp,
            syncedToMac: syncedToMac
        )
    }
}

// MARK: - Masthead (experiment)

/// Home's top region as one full-bleed band — see `HomeMastheadExperiment`.
///
/// Everything here is subtraction. The header keeps its glyphs and loses its
/// lozenges; the cockpit keeps its message line and its Roll and loses the
/// bezel, the screen, and the well. What replaces all of it is a single
/// surface, three hairlines, and a highlight at the top.
///
/// The highlight is *painted*, not laid on: it is a gradient between two opaque
/// colours, the crest resolved once against the band's own fill. A translucent
/// white wash would have been one line shorter and would have made this the
/// only film on a theme whose entire argument is that there are none — and on
/// Press, where nothing is allowed to be see-through, it would have been a
/// contradiction rather than a shortcut.
private struct HomeMasthead: View {
    let cockpit: HomeFeed.CockpitModel
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader(chromeless: true)

            MastheadRule(color: theme.currentTheme.chrome.edgeFaint)

            // No horizontal inset here on purpose. The rows inside carry their
            // own, so the rule between them can run the full width like the one
            // under the header — a division that stops short of both edges is a
            // fourth box outline, which is the thing this is trying to remove.
            HomeCockpit(model: cockpit, flush: true)
                .padding(.bottom, 10)
        }
        .background(alignment: .top) { MastheadSurface() }
        // The one division that has to carry weight. Every rule inside the band
        // separates two rows of the same thing; this one separates the masthead
        // from the page, so it is the full `edge` token rather than the faint
        // one — the same reasoning that made a flat theme's rules heavier in the
        // first place.
        //
        // The step hangs below the band rather than inside it — negative
        // padding takes it out of the overlay's own height, so the rule still
        // lands exactly on the bottom edge and only the shade overhangs.
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                MastheadCoatEdge(material: MastheadMaterial.current)

                // The drawn rule is for the painted band only.
                //
                // A painted plane that stops needs a line to say it stopped —
                // there is nothing else there. A finished one does not: it has
                // a lit cut above and its own shade below, which is an edge
                // with a thickness rather than a mark. Drawing the rule as well
                // put a third horizontal thing in a band of two, and read as a
                // divider laid across the seam instead of as the seam.
                if MastheadMaterial.current == .painted {
                    MastheadRule(color: theme.currentTheme.chrome.edge)
                }

                MastheadStep()
            }
            .padding(.bottom, -MastheadStep.drop)
        }
    }
}

// MARK: - Header

private struct HomeHeader: View {
    /// Masthead experiment: drop the two lozenges around the glyphs.
    ///
    /// A filled, bordered, shadowed 40pt circle is how a button announces
    /// itself when it is floating on an open page with nothing else nearby. In
    /// a band that is already a surface, the circle is a third object drawn on
    /// a plane that has one — and its drop shadow is the one film left on a
    /// theme that argues against films. The glyph alone is still a target;
    /// `contentShape` keeps it the same 40pt target it was.
    var chromeless: Bool = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            DeckComplication(chromeless: chromeless)
            Spacer()
            Text("TALKIE")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Button(action: { AppShellRouter.shared.openSettings() }) {
                HomeHeaderButtonGlyph(systemName: "gearshape", chromeless: chromeless, hug: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("dock.settings")
        }
        .padding(.horizontal, HomeCockpitMetrics.mastheadInset)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

// MARK: - Deck complication

private struct HomeHeaderButtonGlyph: View {
    let systemName: String
    var isEnabled: Bool = true
    var chromeless: Bool = false
    /// Which edge a bare glyph sits on, if any.
    ///
    /// A lozenge is its own left edge: centre the glyph in the circle and the
    /// circle sits on the margin, so the margin is the thing you see. Take the
    /// lozenge away and the glyph is still centred in the 40pt target the
    /// lozenge used to fill — which parks its ink about ten points inboard of
    /// where the band's own type starts, and leaves the top-left of the page
    /// agreeing with nothing below it.
    ///
    /// So bare glyphs hug their edge. The target keeps its 40pt; it simply
    /// grows inward, which is the direction with room.
    var hug: HorizontalEdge? = nil
    @ObservedObject private var theme = ThemeManager.shared

    private var alignment: Alignment {
        guard chromeless, let hug else { return .center }
        return hug == .leading ? .leading : .trailing
    }

    var body: some View {
        ZStack(alignment: alignment) {
            if !chromeless {
                Circle().fill(theme.colors.cardBackground)
                Circle().strokeBorder(
                    theme.currentTheme.chrome.edgeFaint,
                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                )
            }
            Image(systemName: systemName)
                // Bare, the glyph has no lozenge behind it to separate it from
                // the band, so it carries a little more weight itself — the
                // same trade the type tokens make under a flat finish.
                .font(.system(size: chromeless ? 17 : 15, weight: chromeless ? .medium : .regular))
                .foregroundStyle(isEnabled ? theme.colors.textSecondary : theme.colors.textTertiary)
        }
        .frame(width: 40, height: 40, alignment: alignment)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(chromeless ? 0 : 0.10), radius: 4, y: 2)
    }
}

/// Resting Command Deck complication at the top-left of Home. It shares the
/// settings button treatment; bridge state is exposed through accessibility and
/// the Deck surface itself instead of a separate status bead.
private struct DeckComplication: View {
    var chromeless: Bool = false
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var deck = DeckMirrorStore.shared

    var body: some View {
        Button(action: openDeck) {
            HomeHeaderButtonGlyph(systemName: "square.grid.3x3", chromeless: chromeless, hug: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Deck remote")
    }

    // MARK: - State derivation

    private var hasDeckBoard: Bool {
        guard let board = deck.board else { return false }
        return !board.spaces.isEmpty
    }

    private func openDeck() {
        AppShellRouter.shared.openDeck()
    }

    private var accessibilityLabel: String {
        let mac = bridgeManager.pairedMacDisplayName ?? "Mac"
        if !bridgeManager.isPaired {
            return "Command Deck, not paired"
        }
        if bridgeManager.awaitingPairingApproval {
            return "Command Deck, \(mac) pending approval"
        }
        switch bridgeManager.status {
        case .connected:
            return hasDeckBoard ? "Command Deck on \(mac)" : "Command Deck, waiting for \(mac)"
        case .connecting: return "Command Deck, \(mac) connecting"
        case .disconnected: return "Command Deck, \(mac) offline"
        case .error: return "Command Deck, \(mac) error"
        }
    }
}

// MARK: - Home cockpit palette

// The cockpit used to carry a tactical orange palette regardless of the user's
// theme. Derive its fabricated chassis, screen, ink, and signal colors from the
// active chrome vocabulary so Mineral reads as copper on blue-gray alloy while
// Tactical, Scope, and the monochrome themes retain their own identities.
private enum HomeCockpitPalette {
    private static var activeTheme: AppTheme { ActiveTheme.current }

    private static var chrome: ChromeTokens { activeTheme.chrome }

    /// Whether the cockpit is currently drawn with its screen removed — the
    /// masthead experiment. Every `panel*` token below describes ink for a dark
    /// recessed plate: on the themes whose plates stay dark in both modes those
    /// are near-whites by design. With the plate gone they land on the page, so
    /// the four ink tokens re-read off the page vocabulary instead. The three
    /// plate colours are left alone — nothing draws them in this mode.
    private static var flush: Bool { HomeMastheadExperiment.isFlush }

    private static var colors: ThemeColors { activeTheme.colors }

    static var accent: Color { chrome.accent }
    static var accentSoft: Color { chrome.accentTint }
    static var accentEdge: Color { flush ? chrome.edge : chrome.panelEdge }
    static var matte: Color { chrome.panelAlt }
    static var matteLow: Color { chrome.panel }
    static var screen: Color { chrome.panel }
    static var screenAlt: Color { chrome.panelAlt }
    static var screenInk: Color { flush ? colors.textPrimary : chrome.panelInk }
    static var screenInkFaint: Color { flush ? colors.textSecondary : chrome.panelInkFaint }
    static var phosphor: Color { flush ? chrome.accent : chrome.panelAccent }

    /// How far a lit readout is allowed to bleed. Themes that declare no halo
    /// (`glowRadius: 0`) get none here either — a glow is a film over the word,
    /// and a theme that has argued against films shouldn't sprout one in the
    /// cockpit.
    static var glowRadius: CGFloat { flush ? 0 : chrome.glowRadius }

    /// Gloss, lift and letterform — the same finish the Codex deck reads. The
    /// cockpit is the densest small type in the app, so it is where the films
    /// cost the most. See `DeckFinish`.
    static var finish: DeckFinish { activeTheme.finish }

    /// An ink tint on the cockpit screen. The plate is always the same one
    /// here, so unlike the deck the call sites don't have to name it — they
    /// just stop deciding for themselves whether the result is composited.
    static func tint(_ ink: Color, _ alpha: Double) -> Color {
        finish.tint(ink, alpha, over: flush ? colors.cardBackground : screen)
    }

    /// The glow a lit readout gets. A flush cockpit has no screen to be lit, so
    /// it gets none — the same trade the flush strip makes with its scanlines.
    static var lift: Double { flush ? 0 : finish.lift }

    /// The recessed track behind a small control. On a screen that is the
    /// screen's own two-stop gradient; on the page there is nothing to recess
    /// into, so it becomes a whisper of the page's own ink. Getting this wrong
    /// is the same failure the bay selector already carries a note about — ink
    /// from one family on a plate from another — so plate and ink move together.
    static var track: Color { flush ? tint(screenInk, 0.07) : screen }
    static var trackAlt: Color { flush ? tint(screenInk, 0.04) : screenAlt }
}

// MARK: - Command center

private enum HomeCommandMode: String {
    case ask
    case search

    var label: String {
        switch self {
        case .ask: "ASK"
        case .search: "FIND"
        }
    }

    var icon: String {
        switch self {
        case .ask: "sparkles"
        case .search: "magnifyingglass"
        }
    }

    var placeholder: String {
        switch self {
        case .ask: "Ask Talkie anything"
        case .search: "Search your captures"
        }
    }
}

private struct HomeAskShortcut: Identifiable {
    let label: String
    let prompt: String

    var id: String { label }

    static let all = [
        HomeAskShortcut(label: "PLAN", prompt: "Help me turn this into a practical plan: "),
        HomeAskShortcut(label: "DRAFT", prompt: "Draft a clear message about: "),
        HomeAskShortcut(label: "THINK", prompt: "Help me think through: "),
    ]
}

@MainActor
@Observable
private final class HomeCommandKeyboardController {
    var preferredHeight: CGFloat = 230

    @ObservationIgnored weak var inputHost: KeyboardInputHost?
    @ObservationIgnored weak var keyboard: HostedTalkieKeyboardView?
    @ObservationIgnored var onDictationToggle: (() -> Void)?
    @ObservationIgnored var onCollapse: (() -> Void)?
}

/// Geometry for the keyboard slab as Home hosts it — the app-side inset around
/// the shared keys, and the lifted dismiss chip.
private enum HomeKeyboardSlabMetrics {
    /// Rides on top of `CompactKeyboardView`'s own 3pt gutter, which stays
    /// small because the system extension it also serves is full-bleed.
    static let sideInset: CGFloat = 7
    static let topInset: CGFloat = 6

    /// A 30pt capsule inside a 44pt tap target — the chip is small, the touch
    /// area is not.
    static let dismissCapsuleWidth: CGFloat = 52
    static let dismissCapsuleHeight: CGFloat = 30
    static let dismissPadV: CGFloat = 7
    static let dismissTapHeight: CGFloat = dismissCapsuleHeight + dismissPadV * 2
    /// Clearance between the capsule and the slab's top hairline.
    static let dismissGap: CGFloat = 6
    /// Negative — the chip is lifted clear of the slab so it draws over the
    /// feed rather than pushing it. Derived so the capsule (not its tap
    /// padding) is what sits `dismissGap` above the edge.
    static let dismissLift: CGFloat = dismissPadV - dismissTapHeight - dismissGap
}

/// The visible way out of the keyboard.
///
/// Deliberately routed through the same `onCollapse` the swipe-down gesture
/// fires rather than flipping the focus binding directly: collapsing means
/// resigning first responder, and having two paths that do it differently is
/// how the field and the slab end up disagreeing about whether input is live.
private struct HomeKeyboardDismissChip: View {
    let onDismiss: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        let capsule = Capsule(style: .continuous)

        Button(action: onDismiss) {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(
                    width: HomeKeyboardSlabMetrics.dismissCapsuleWidth,
                    height: HomeKeyboardSlabMetrics.dismissCapsuleHeight
                )
                // Opaque, and laid over the page ground first: the chip floats
                // above whatever recents row happens to be under it, so it has
                // to carry its own backdrop rather than borrow one.
                .background {
                    ZStack {
                        capsule.fill(theme.colors.background)
                        capsule.fill(theme.colors.cardBackground)
                    }
                }
                .overlay(
                    capsule.strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    )
                )
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                // Outside the capsule, so the tap target clears 44pt without
                // the chip growing to match.
                .padding(.vertical, HomeKeyboardSlabMetrics.dismissPadV)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide keyboard")
        .accessibilityIdentifier("home.keyboard-dismiss")
    }
}

/// Home presents the Talkie keyboard as app-owned chrome, just like Compose.
/// This keeps it visible on iPad even when a hardware keyboard is connected;
/// UIKit's custom `inputView` presentation is intentionally bypassed.
private struct HomeTalkieKeyboardHost: UIViewRepresentable {
    let controller: HomeCommandKeyboardController
    let visualStyle: KeyboardVisualStyle

    func makeUIView(context: Context) -> HostedTalkieKeyboardView {
        let keyboard = HostedTalkieKeyboardView()
        keyboard.accessibilityIdentifier = "home.talkie-keyboard"
        keyboard.allowsMinimalLayout = false
        keyboard.preferredInitialLayout = .compact
        keyboard.preferredInitialModeId = KeyboardMode.abc.id
        keyboard.visualStyle = visualStyle
        keyboard.overrideUserInterfaceStyle = visualStyle == .mineralInstrument ? .light : .unspecified
        keyboard.inputHost = controller.inputHost
        keyboard.onDictationToggle = { [weak controller] in
            controller?.onDictationToggle?()
        }
        keyboard.onRequestCollapse = { [weak controller] in
            controller?.onCollapse?()
        }
        keyboard.onLayoutHeightChange = { [weak controller, weak keyboard] in
            guard let controller, let keyboard else { return }
            controller.preferredHeight = keyboard.intrinsicContentSize.height
        }
        keyboard.resetToPreferredInitialLayout()
        controller.keyboard = keyboard
        controller.preferredHeight = keyboard.intrinsicContentSize.height
        return keyboard
    }

    // A keyboard has no opinion about its own width; it takes the one it is
    // offered. Without this, the representable falls back to Auto Layout's
    // intrinsic measurement, which is derived from the key pitch rather than the
    // slot. Saying so here is also the seam that leaves `CompactKeyboardView`
    // alone — the same view is the system extension's full-bleed layout, where
    // running edge to edge is correct.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: HostedTalkieKeyboardView,
        context: Context
    ) -> CGSize? {
        let fallbackWidth = uiView.window?.bounds.width ?? uiView.bounds.width
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(
            width: proposed ?? fallbackWidth,
            height: uiView.intrinsicContentSize.height
        )
    }

    func updateUIView(_ keyboard: HostedTalkieKeyboardView, context: Context) {
        keyboard.inputHost = controller.inputHost
        keyboard.visualStyle = visualStyle
        keyboard.overrideUserInterfaceStyle = visualStyle == .mineralInstrument ? .light : .unspecified
        controller.keyboard = keyboard
        controller.preferredHeight = keyboard.intrinsicContentSize.height
    }

    static func dismantleUIView(
        _ keyboard: HostedTalkieKeyboardView,
        coordinator: Void
    ) {
        keyboard.inputHost = nil
        keyboard.onDictationToggle = nil
        keyboard.onRequestCollapse = nil
        keyboard.onLayoutHeightChange = nil
    }
}

private struct HomeCommandBar: View {
    @Binding var prompt: String
    @Binding var searchText: String
    @Binding var mode: HomeCommandMode
    @Binding var isFocused: Bool
    let keyboardController: HomeCommandKeyboardController
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggleMode) {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.label)
                            .talkieType(.channelLabelTiny)
                    }
                    // The capsule carries the ASK state, not the ink. Accent-on-
                    // accent-tint is the same hue at two lightnesses and never
                    // clears 4.5:1 (measured 2.15:1 in tactical/light), so the
                    // label stays at full page ink and the fill does the signalling.
                    .foregroundStyle(mode == .ask ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background {
                        Capsule()
                            .fill(mode == .ask ? HomeCockpitPalette.accentSoft : theme.currentTheme.chrome.edgeFaint)
                            .overlay {
                                Capsule().strokeBorder(
                                    mode == .ask ? HomeCockpitPalette.accentEdge : theme.currentTheme.chrome.edgeFaint,
                                    lineWidth: theme.currentTheme.chrome.hairlineWidth
                                )
                            }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode == .ask ? "Switch to search" : "Switch to Ask AI")
                .accessibilityIdentifier("home.command-mode")

                HomeCommandTextField(
                    text: activeText,
                    placeholder: mode.placeholder,
                    isFocused: $isFocused,
                    keyboardController: keyboardController,
                    textColor: UIColor(theme.colors.textPrimary),
                    placeholderColor: UIColor(theme.colors.textTertiary),
                    tintColor: UIColor(HomeCockpitPalette.accent),
                    onSubmit: submit
                )
                // Ask and Search own independent values. Recreate the UIKit
                // coordinator when the mode changes so its keystroke replay
                // guard cannot preserve text from the previous field.
                .id(mode)
                .frame(height: 30)

                Button(action: submit) {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(trailingForeground)
                        .frame(width: 32, height: 32)
                        .background {
                            Circle()
                                .fill(trailingBackground)
                                .overlay {
                                    Circle().strokeBorder(
                                        trailingBorder,
                                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                                    )
                                }
                        }
                }
                .buttonStyle(.plain)
                .disabled(mode == .ask && trimmedActiveText.isEmpty)
                .accessibilityLabel(mode == .ask ? "Send to Ask AI" : "Finish searching")
                .accessibilityIdentifier("home.command-send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)

            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth)

            commandRail
                .frame(height: 34)
                .padding(.horizontal, 11)
        }
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground.opacity(0.9))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(HomeCockpitPalette.accentSoft.opacity(mode == .ask ? (isFocused ? 0.7 : 0.28) : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isFocused && mode == .ask ? HomeCockpitPalette.accentEdge : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: isFocused ? 1 : theme.currentTheme.chrome.hairlineWidth
                        )
                }
        }
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .animation(.easeOut(duration: 0.18), value: mode)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    @ViewBuilder
    private var commandRail: some View {
        if mode == .ask {
            HStack(spacing: 6) {
                Text("START WITH")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                ForEach(HomeAskShortcut.all) { shortcut in
                    Button(shortcut.label) {
                        prompt = shortcut.prompt
                        isFocused = true
                    }
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textSecondary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start with \(shortcut.label.capitalized)")
                }

                Spacer(minLength: 4)

                Button(action: switchToSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                    Text("RECENTS")
                        .talkieType(.channelLabelTiny)
                }
                .foregroundStyle(theme.colors.textTertiary)
                .buttonStyle(.plain)
                .accessibilityLabel("Search Recents")
            }
        } else {
            HStack(spacing: 8) {
                Text(searchText.isEmpty ? "RECENTS FILTER LIVE" : "FILTERING RECENTS")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)

                Spacer()

                if !searchText.isEmpty {
                    Button("CLEAR") { searchText = "" }
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.action)
                        .buttonStyle(.plain)
                }

                Button("ASK AI", action: switchToAsk)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeCockpitPalette.accent)
                    .buttonStyle(.plain)
            }
        }
    }

    private var activeText: Binding<String> {
        mode == .ask ? $prompt : $searchText
    }

    private var trimmedActiveText: String {
        activeText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trailingIcon: String {
        if mode == .ask { return "arrow.up" }
        return isFocused ? "keyboard.chevron.compact.down" : "magnifyingglass"
    }

    private var trailingForeground: Color {
        if mode == .ask {
            return trimmedActiveText.isEmpty ? theme.colors.textTertiary : theme.colors.cardBackground
        }
        return theme.colors.textSecondary
    }

    private var trailingBackground: Color {
        if mode == .ask, !trimmedActiveText.isEmpty { return HomeCockpitPalette.accent }
        return theme.currentTheme.chrome.edgeFaint
    }

    private var trailingBorder: Color {
        mode == .ask && !trimmedActiveText.isEmpty
            ? HomeCockpitPalette.accentEdge
            : theme.currentTheme.chrome.edgeFaint
    }

    private func submit() {
        guard mode == .ask else {
            isFocused = false
            return
        }

        let command = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        prompt = ""
        isFocused = false
        let isReadyToSend = InferenceService.shared.readiness.isReady
        AppShellRouter.shared.openAskAISeeded(
            prompt: command,
            autoSend: isReadyToSend,
            startsNewSession: true
        )
    }

    private func toggleMode() {
        if mode == .ask {
            switchToSearch()
        } else {
            switchToAsk()
        }
    }

    private func switchToSearch() {
        mode = .search
        isFocused = true
    }

    private func switchToAsk() {
        mode = .ask
        isFocused = true
    }
}

/// Single-line command input backed by `UITextField` so Home can present the
/// same reusable Talkie keyboard as Compose and SSH. UIKit still owns focus,
/// selection, and hardware input; the visible key surface is app-hosted below.
private struct HomeCommandTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let keyboardController: HomeCommandKeyboardController
    let textColor: UIColor
    let placeholderColor: UIColor
    let tintColor: UIColor
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSubmit: onSubmit,
            keyboardController: keyboardController
        )
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        // The Talkie keyboard is an ordinary bottom-anchored view. Suppress
        // the system keyboard while retaining a real first responder/caret.
        textField.inputView = UIView()
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        textField.backgroundColor = .clear
        textField.borderStyle = .none
        textField.clearButtonMode = .never
        textField.autocapitalizationType = .sentences
        textField.autocorrectionType = .yes
        textField.spellCheckingType = .yes
        textField.smartDashesType = .yes
        textField.smartQuotesType = .yes
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.returnKeyType = .send
        textField.accessibilityIdentifier = "home.command-field"
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []

        context.coordinator.textField = textField
        keyboardController.inputHost = context.coordinator
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.setFocused = { focused in
            isFocused = focused
        }

        if textField.text != text,
           context.coordinator.shouldApplyBoundText(text, to: textField) {
            textField.text = text
            context.coordinator.recordFieldValue(text)
        }

        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: textField.font ?? UIFont.preferredFont(forTextStyle: .body),
            ]
        )

        keyboardController.inputHost = context.coordinator

        if isFocused {
            if !textField.isFirstResponder {
                textField.becomeFirstResponder()
            }
        } else if textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ textField: UITextField, coordinator: Coordinator) {
        coordinator.teardown()
        textField.delegate = nil
        textField.inputView = nil
        if textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate, KeyboardInputHost {
        var text: Binding<String>
        var onSubmit: () -> Void
        var setFocused: ((Bool) -> Void)?
        weak var textField: UITextField?
        let keyboardController: HomeCommandKeyboardController

        private let dictationController = InlineDictationController()
        private var recentFieldValues: [String]

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            keyboardController: HomeCommandKeyboardController
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.keyboardController = keyboardController
            recentFieldValues = [text.wrappedValue]
            super.init()

            keyboardController.inputHost = self
            keyboardController.onDictationToggle = { [weak self] in
                self?.toggleDictation()
            }
            keyboardController.onCollapse = { [weak self] in
                self?.textField?.resignFirstResponder()
            }

            dictationController.onStateChange = { [weak self] state in
                self?.applyDictationState(state)
            }
            dictationController.onTranscript = { [weak self] transcript in
                guard let self else { return }
                replaceSelection(with: transcript)
                keyboardController.keyboard?.showDictationSuccessFeedback()
            }
            dictationController.onError = { [weak self] _ in
                self?.keyboardController.keyboard?.setDictationState(.idle)
            }
        }

        @objc func textDidChange(_ textField: UITextField) {
            commitFieldValue(textField.text ?? "")
        }

        func shouldApplyBoundText(_ value: String, to textField: UITextField) -> Bool {
            guard textField.isFirstResponder else { return true }

            // UIKit can deliver several hardware/XCTest keystrokes before
            // SwiftUI finishes replaying every intermediate Binding value.
            // Never push one of those older prefixes back into the live field.
            return !recentFieldValues.contains(value)
        }

        func recordFieldValue(_ value: String) {
            recentFieldValues.append(value)
            if recentFieldValues.count > 64 {
                recentFieldValues.removeFirst(recentFieldValues.count - 64)
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            keyboardController.keyboard?.resetToPreferredInitialLayout()
            setFocused?(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            setFocused?(false)
            dictationController.cancel()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            submit()
            return false
        }

        func performKeyboardAction(_ action: KeyboardAction) {
            guard let textField else { return }

            switch action {
            case .insert(let insertedText):
                replaceSelection(with: insertedText)
            case .deleteBackward:
                textField.deleteBackward()
                commitFieldValue(textField.text ?? "")
            case .copy:
                copySelection(from: textField)
            case .paste:
                guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else { return }
                replaceSelection(with: clipboardText)
            case .selectAll:
                textField.selectAll(nil)
            case .tab:
                replaceSelection(with: " ")
            case .enter:
                submit()
            case .escape, .dismissKeyboard:
                textField.resignFirstResponder()
            case .moveCursor(let movement):
                moveCursor(movement, in: textField)
            case .toggleShift, .toggleControl, .interrupt:
                break
            }
        }

        func toggleDictation() {
            switch dictationController.currentState {
            case .idle:
                Task { @MainActor [weak self] in
                    await self?.dictationController.start()
                }
            case .recording:
                dictationController.stop(insertTranscript: true)
            case .transcribing:
                break
            }
        }

        func teardown() {
            dictationController.cancel()
            if keyboardController.inputHost === self {
                keyboardController.inputHost = nil
            }
            keyboardController.onDictationToggle = nil
            keyboardController.onCollapse = nil
            textField = nil
        }

        private func submit() {
            textField?.resignFirstResponder()
            onSubmit()
        }

        private func replaceSelection(with insertedText: String) {
            guard let textField else { return }
            if let selection = textField.selectedTextRange {
                textField.replace(selection, withText: insertedText)
            } else {
                textField.text = (textField.text ?? "") + insertedText
            }
            commitFieldValue(textField.text ?? "")
        }

        private func commitFieldValue(_ value: String) {
            recordFieldValue(value)
            text.wrappedValue = value
        }

        private func copySelection(from textField: UITextField) {
            guard let selection = textField.selectedTextRange else {
                UIPasteboard.general.string = textField.text
                return
            }
            let selected = textField.text(in: selection) ?? ""
            UIPasteboard.general.string = selected.isEmpty ? textField.text : selected
        }

        private func moveCursor(_ movement: KeyboardCursorMovement, in textField: UITextField) {
            guard let selection = textField.selectedTextRange else { return }
            let offset: Int
            switch movement {
            case .left, .up: offset = -1
            case .right, .down: offset = 1
            case .wordLeft: offset = -5
            case .wordRight: offset = 5
            }
            guard let position = textField.position(from: selection.start, offset: offset),
                  let collapsed = textField.textRange(from: position, to: position) else {
                return
            }
            textField.selectedTextRange = collapsed
        }

        private func applyDictationState(_ state: InlineDictationController.State) {
            switch state {
            case .idle:
                keyboardController.keyboard?.setDictationState(.idle)
            case .recording:
                keyboardController.keyboard?.setDictationState(.recording)
            case .transcribing:
                keyboardController.keyboard?.setDictationState(.processing)
            }
        }
    }
}

// MARK: - Communication cockpit (the Console)
//
// The converged "Cockpit Two-Row Console" (design/studio/components/studies/
// CockpitTwoRow.tsx). A raised metal Bezel (bezelChassis) around a dark-glass
// Screen — the Message Line straight on top (NO header row) over a fixed-height
// Bay that toggles between two pages via a user-controlled Bay Selector:
//
//   1. Message Line — a slim amber-CRT terminal readout of ONE derived fact,
//      carrying an optional right-docked Docked Readout (STRK n / take count).
//   2. The Bay      — one recessed 144pt well holding both pages so the Selector
//      swaps content with no reflow: THE ROLL (18×7 contribution calendar) ⁄
//      GAUGES (TAKES count + Meter · TIME m:ss + Meter · STRK Life-in-Dots).
//      The list-replay Take Log is retired; GAUGES read as instruments only.
//
// Nominal tap opens the Library (the tape it summarizes); first-run standby taps
// open the recorder. Screen ink only — always dark. The Bay Selector's 0.4s
// crossfade is the only animation.
//
// Vocabulary: design/studio/app/cockpit-two-row/page.tsx (NamesMarginalia —
// Console · Bezel · Message Line · Docked Readout · Toggle · Bay · Roll Bay ·
// Gauge Bay · Meter · Life-in-Dots). Data: HomeFeed.makeCockpit (one pass).

/// Studio-mirrored Console geometry. Named so studio · Swift · chat share one
/// vocabulary; values track CockpitTwoRow.tsx exactly. The Roll grid geometry
/// lives on HomeFeed (the data owner); these are the visual + message knobs.
/// How the page below the masthead is spaced.
private enum HomeSectionMetrics {
    /// Between one section and the next.
    static let gap: CGFloat = 20

    /// The page's side margin.
    static let gutter: CGFloat = 12

    /// Between the masthead and the first section.
    ///
    /// Wider, because the band overhangs: its shade falls 14pt onto the page,
    /// and a section starting inside that shade reads as being under the
    /// console rather than beside it. This is the shade's depth plus a normal
    /// gap after it, which is what the gap would be if the step were an object.
    static let mastheadGap: CGFloat = 30
}

private enum HomeCockpitMetrics {
    // Bezel + Screen (BEZEL_PAD 7 · SCREEN_PAD 10 · STACK_GAP 8 → CONSOLE_H 220)
    static let bezelPad: CGFloat = 7
    static let bezelCorner: CGFloat = 14
    static let screenPad: CGFloat = 10
    static let screenCorner: CGFloat = 12
    static let stackGap: CGFloat = 8

    // Message Line
    static let messageHeight: CGFloat = 32      // MSG_H

    // Masthead experiment. The strip stands taller once it has no plate: a
    // bordered 32pt box reads as a deliberate object at that height, but the
    // same 32pt with the box removed reads as a cramped row, because the border
    // was doing the work of saying "this much space is mine". Height has to
    // take that job over.
    static let flushMessageHeight: CGFloat = 40
    /// Side inset for everything in the masthead. Matches the header's own, so
    /// the wordmark, the message line and the Roll all start on one margin.
    static let mastheadInset: CGFloat = 20

    // The Roll (CELL 12 · CGAP 3 → grid 102pt tall)
    static let rollCell: CGFloat = 12           // CELL
    static let rollGap: CGFloat = 3             // CGAP
    /// How far the flush Roll takes to dissolve at its leading edge. Sized in
    /// points rather than columns so the ramp reads the same on every phone —
    /// roughly five columns, long enough that no single cell looks half-erased.
    static let rollFadeWidth: CGFloat = 84

    // The Bay (BAY_PAD 10 · BAY_LABEL_H 14 · BAY_LABEL_GAP 8 · BAY_CONTENT_H 102 → BAY_H 144)
    static let bayPad: CGFloat = 10
    static let bayCorner: CGFloat = 8
    static let bayLabelHeight: CGFloat = 14
    static let bayLabelGap: CGFloat = 8
    static let bayContentHeight: CGFloat = 102
    static let bayHeight: CGFloat = 144

    // Gauge lanes (G_TAKES_H 28 · G_TIME_H 28 · G_STRK_H 38 · G_GAP 4 → 102)
    static let gaugeTakesHeight: CGFloat = 28
    static let gaugeTimeHeight: CGFloat = 28
    static let gaugeStrkHeight: CGFloat = 38
    static let gaugeGap: CGFloat = 4
    static let gaugeCorner: CGFloat = 6

    // Life-in-Dots (DOT 7 · DOT_GAP 4 · last 12 days, 6×2)
    static let dot: CGFloat = 7
    static let dotGap: CGFloat = 4

    // Meter full-bar scales (a full 12-seg bar = a strong day)
    static let scaleTakes: Double = 4           // SCALE_TAKES — 4 takes fills the bar
    static let scaleTimeSeconds: Double = 360   // SCALE_TIME — 6:00 fills the bar

    // Bay Selector crossfade (user-initiated)
    static let baySelectorCrossfade: Double = 0.4

    // Message-line derivation
    static let milestoneWindow = 5              // "just crossed" a 100 boundary
    static let recencyDays = 7                  // recency inside a week, else station ident

    /// Clamp a level to the meter's [0, 1] fill range.
    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// The single derived fact on the Message Line, priority-ordered. Pure so both
/// the terminal render and the accessibility label read the same string.
private enum CockpitMessage {
    static func line(model: HomeFeed.CockpitModel, parakeetDownloading: Bool, now: Date) -> String {
        if model.isEmpty { return "STANDING BY — ROLL TAPE TO BEGIN" }
        if parakeetDownloading { return "PARAKEET DOWNLOADING" }
        if model.totalTakes >= 100, model.totalTakes % 100 < HomeCockpitMetrics.milestoneWindow {
            return "TAKE #\(model.totalTakes) ON TAPE"
        }
        if let last = model.lastTakeDate {
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: last),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            if days < HomeCockpitMetrics.recencyDays {
                return "LAST TAKE \(HomeFeed.compactAge(from: last, now: now)) AGO"
            }
        }
        return stationIdent(now: now)
    }

    private static func stationIdent(now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 9 { return "TALKIE · EARLY SHIFT" }
        if hour >= 22 { return "NIGHT DESK" }
        return "TALKIE · ON AIR"
    }
}

private struct HomeActivityEvent: Identifiable {
    let time: String
    let title: String
    let kind: String

    var id: String { "\(time)-\(title)" }
}

private struct HomeCockpit: View {
    let model: HomeFeed.CockpitModel
    /// Masthead experiment: no bezel, no screen, laid straight onto the band.
    var flush: Bool = false
    @ObservedObject private var parakeet = ParakeetModelManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        if isScreenshotMode {
            VStack(alignment: .leading, spacing: 8) {
                Text("· TODAY")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.leading, 4)

                Button(action: open) {
                    VStack(spacing: 8) {
                        HomeActivityScreen(events: screenshotEvents)

                        Text("3 COMPLETED TODAY · LATEST 5 MIN AGO")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .softCard(
                        padding: 10,
                        corner: 14,
                        emphasis: .edge,
                        fill: HomeCockpitPalette.matte
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Today's Talkie activity: roadmap memo recorded, product brief summarized, follow-up added to Reminders")
                .accessibilityHint("Shows today's completed Talkie activity")
            }
        } else {
            // The production cockpit retains master's latest Roll/Gauges bay.
            Button(action: open) {
                if flush {
                    CockpitScreen(model: model, parakeetDownloading: parakeetDownloading, flush: true)
                        .frame(maxWidth: .infinity)
                } else {
                    CockpitScreen(model: model, parakeetDownloading: parakeetDownloading)
                        .frame(maxWidth: .infinity)
                        .bezelChassis(
                            padding: HomeCockpitMetrics.bezelPad,
                            corner: HomeCockpitMetrics.bezelCorner,
                            metal: true,
                            fill: HomeCockpitPalette.matte
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(model.isEmpty ? "Opens the recorder to capture your first take" : "Opens your library")
        }
    }

    private var parakeetDownloading: Bool {
        if case .downloading = parakeet.state { return true }
        return false
    }

    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
    }

    // Routing: nominal → the Library (the tape this instrument summarizes);
    // first-run standby → the recorder, since there is nothing to browse yet.
    private func open() {
        if model.isEmpty {
            RecordingSheetController.shared.isPresented = true
        } else {
            AppShellRouter.shared.openLibrary()
        }
    }

    private var screenshotEvents: [HomeActivityEvent] {
        [
            HomeActivityEvent(time: "9:36", title: "Roadmap memo recorded", kind: "VOICE"),
            HomeActivityEvent(time: "9:18", title: "Product brief summarized", kind: "AI"),
            HomeActivityEvent(time: "8:54", title: "Follow-up added to Reminders", kind: "ACTION"),
        ]
    }

    // Describes both bay pages regardless of which is up: the message line, the
    // Roll streak, and today's take count. Standby leads with the recorder cue.
    private var accessibilitySummary: String {
        let message = CockpitMessage.line(model: model, parakeetDownloading: parakeetDownloading, now: Date())
        if model.isEmpty {
            return "Cockpit, standing by. \(message). Tap to record your first take."
        }
        let streakPart = model.streak == 1 ? "the Roll, 1 day streak" : "the Roll, \(model.streak) day streak"
        let todayPart = model.todayTakes == 1 ? "1 take today" : "\(model.todayTakes) takes today"
        let totalPart = model.totalTakes == 1 ? "1 take on tape" : "\(model.totalTakes) takes on tape"
        return "Cockpit. \(message). \(totalPart). \(streakPart). \(todayPart)."
    }

}

/// Screenshot-mode event log. Unlike the production communication cockpit,
/// this shows discrete outcomes in time order—no synthetic levels or telemetry.
private struct HomeActivityScreen: View {
    let events: [HomeActivityEvent]
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let hairline = max(theme.currentTheme.chrome.hairlineWidth, 0.8)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(spacing: 8) {
            HStack {
                Text("TALKIE")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeCockpitPalette.screenInkFaint)
                Spacer()
                Text("ACTIVITY")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeCockpitPalette.phosphor)
                Spacer()
                Text("9:41")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(HomeCockpitPalette.screenInkFaint)
            }

            VStack(spacing: 0) {
                ForEach(events.enumerated(), id: \.element.id) { index, event in
                    HomeActivityRow(event: event, showsDivider: index < events.count - 1)
                }
            }
            .background(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.14), lineWidth: 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                HomeCockpitPalette.screen
                if HomeCockpitPalette.finish.isGlossy {
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.black.opacity(0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    RadialGradient(
                        colors: [HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.18), .clear],
                        center: UnitPoint(x: 0.72, y: 0.36),
                        startRadius: 0,
                        endRadius: 140
                    )
                }
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(HomeCockpitPalette.accentEdge, lineWidth: hairline)
        }
    }
}

private struct HomeActivityRow: View {
    let event: HomeActivityEvent
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: 9) {
            Text(event.time)
                .talkieType(.timestamp)
                .foregroundStyle(HomeCockpitPalette.screenInkFaint)
                .frame(width: 34, alignment: .leading)

            Circle()
                .fill(HomeCockpitPalette.phosphor)
                .frame(width: 5, height: 5)
                .shadow(color: HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.65), radius: 3)

            Text(event.title)
                .talkieType(.preview)
                .foregroundStyle(HomeCockpitPalette.screenInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(event.kind)
                .talkieType(.channelLabelTiny)
                .foregroundStyle(HomeCockpitPalette.phosphor)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.08))
                    .frame(height: 0.5)
                    .padding(.leading, 52)
            }
        }
    }
}

/// The always-dark instrument screen inside the cockpit chassis: the Message Line
/// on top (now the sole status carrier — no more TALKIE/status/clock header row)
/// over the shared slot where the Take Log and the Roll alternate. Panel ink only
/// — the screen ignores light/dark so it reads as lit glass everywhere. The
/// 60-second timeline keeps the message-line age and the time-of-day station ident
/// fresh without any per-frame animation.
private struct CockpitScreen: View {
    let model: HomeFeed.CockpitModel
    let parakeetDownloading: Bool
    /// Give up the screen — its colour, its corners, its border — and lay the
    /// message line and the bay directly onto the masthead's surface, divided
    /// by a hairline instead of by a gap.
    ///
    /// This is the part of the experiment with something real at stake. The
    /// dark screen is what makes the cockpit read as an instrument rather than
    /// as a card, and giving it up is not free. What it buys is that the top of
    /// Home becomes one plane instead of three, and a hairline between two rows
    /// of a single surface is a quieter division than a rounded dark rectangle
    /// inset inside a metal bezel — which is the question being asked.
    var flush: Bool = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let hairline = max(theme.currentTheme.chrome.hairlineWidth, 0.8)
        let shape = RoundedRectangle(cornerRadius: HomeCockpitMetrics.screenCorner, style: .continuous)

        VStack(spacing: flush ? 0 : HomeCockpitMetrics.stackGap) {
            // Message Line — straight on top (no header). Its own 60s timeline
            // keeps the age / station-ident fresh with no per-frame animation.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                TerminalMessageStrip(
                    text: CockpitMessage.line(
                        model: model,
                        parakeetDownloading: parakeetDownloading,
                        now: context.date
                    ),
                    height: flush ? HomeCockpitMetrics.flushMessageHeight : HomeCockpitMetrics.messageHeight,
                    dock: dockReadout,
                    flush: flush
                )
            }
            // Top up each row's own inset to the masthead margin, rather than
            // insetting the stack, so the divider below stays full width.
            .padding(.horizontal, flush ? HomeCockpitMetrics.mastheadInset - TerminalStripMetrics.padH : 0)

            if flush {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeFaint)
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
            }

            // The Bay — the toggled 144pt well (Roll ⁄ Gauges).
            // The cells below read the palette off a static table, which is
            // invisible to SwiftUI's dependency tracking — their inputs are ints
            // and bools that a theme change doesn't touch, so their bodies stay
            // cached and they keep drawing the outgoing theme's phosphor. Keying
            // the bay on the theme rebuilds the subtree instead.
            CockpitBay(model: model, flush: flush)
                .id(theme.currentTheme)
                .padding(.horizontal, flush ? HomeCockpitMetrics.mastheadInset - HomeCockpitMetrics.bayPad : 0)
        }
        .padding(flush ? 0 : HomeCockpitMetrics.screenPad)
        .frame(maxWidth: .infinity)
        // Three films stack here — a top-to-bottom gloss, a phosphor bloom, and a
        // left-to-right wash — and the whole cockpit's type is read through all
        // of them. That is what makes the screen read as lit glass, and it is
        // also why the 8pt legends look hazy. A flat theme keeps the screen
        // colour and drops the stack.
        .background {
            ZStack {
                if !flush {
                    HomeCockpitPalette.screen
                    if HomeCockpitPalette.finish.isGlossy {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.08), location: 0),
                                .init(color: Color.white.opacity(0.02), location: 0.45),
                                .init(color: Color.black.opacity(0.24), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        RadialGradient(
                            colors: [HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.22), .clear],
                            center: UnitPoint(x: 0.5, y: 0.44),
                            startRadius: 0,
                            endRadius: 110
                        )
                        LinearGradient(
                            colors: [
                                HomeCockpitPalette.screenAlt.opacity(0.00),
                                HomeCockpitPalette.screenAlt.opacity(0.45),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            }
        }
        .clipShape(flush ? AnyShape(Rectangle()) : AnyShape(shape))
        .overlay {
            if !flush {
                shape.strokeBorder(HomeCockpitPalette.accentEdge, lineWidth: hairline)
            }
        }
    }

    /// The Docked Readout for the Message Line, resolved from the dial. Hidden in
    /// first-run standby (DAY 1 semantics haven't started yet).
    private var dockReadout: TerminalDockReadout? {
        guard !model.isEmpty else { return nil }
        switch CockpitDockDial.current {
        case .none:
            return nil
        case .streak:
            return TerminalDockReadout(label: "STRK", value: "\(model.streak)", hot: model.streak > 0)
        case .takesToday:
            return TerminalDockReadout(label: "TAKES", value: "\(model.todayTakes)", hot: model.todayTakes > 0)
        }
    }
}

/// The Docked Readout dial — the single knob picking which useful fact the
/// Message Line's right-docked lane carries (studio "Docked Readout"). Defaults
/// to `.streak`; `.none` bares the strip and `.takesToday` shows the day's count.
/// The lane is hidden entirely in first-run standby (see `dockReadout`).
private enum CockpitDockDial {
    case none, streak, takesToday
    static let current: CockpitDockDial = .streak
}

// MARK: - The Bay (Roll ⁄ Gauges)

/// Which page the Bay is showing. Persisted via @AppStorage so the chosen bay
/// survives relaunch.
private enum CockpitBayPage: String {
    case roll, gauges
    var toggled: CockpitBayPage { self == .roll ? .gauges : .roll }
}

/// The toggled big section under the Message Line — one recessed 144pt well that
/// both pages fill (ZStack, opacity), so the Bay Selector swaps content with no
/// reflow. Its label row carries the Selector on the left and a contextual
/// readout on the right (STRK n on ROLL · TODAY · 7-DAY AVG on GAUGES).
private struct CockpitBay: View {
    let model: HomeFeed.CockpitModel
    /// Drop the well. The bay is normally recessed into the screen by a tinted
    /// fill and a border; flush, the masthead is already the surface and the
    /// row above is already divided from it by a hairline, so a second frame
    /// only says the same thing twice.
    var flush: Bool = false
    @AppStorage("home.cockpit.bayPage") private var bayPageRaw = CockpitBayPage.roll.rawValue

    private var page: CockpitBayPage { CockpitBayPage(rawValue: bayPageRaw) ?? .roll }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeCockpitMetrics.bayCorner, style: .continuous)

        let content = VStack(spacing: HomeCockpitMetrics.bayLabelGap) {
            // Label row — the Bay Selector + a contextual readout.
            HStack(spacing: 8) {
                BaySelector(page: page, onToggle: toggle)
                Spacer(minLength: 0)
                Text(readout)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.8) // 0.1em at 8pt
                    .foregroundStyle(readoutHot ? HomeCockpitPalette.phosphor : HomeCockpitPalette.screenInkFaint)
                    .accessibilityHidden(true)
            }
            .frame(height: HomeCockpitMetrics.bayLabelHeight)

            // Content — both pages laid out; the chosen one lit. Fixed 102pt.
            ZStack {
                CockpitRollPage(model: model, flush: flush)
                    .opacity(page == .roll ? 1 : 0)
                CockpitGaugePage(model: model)
                    .opacity(page == .gauges ? 1 : 0)
            }
            .frame(height: HomeCockpitMetrics.bayContentHeight)
        }
        .padding(HomeCockpitMetrics.bayPad)
        .frame(height: HomeCockpitMetrics.bayHeight)
        .frame(maxWidth: .infinity)
        // White-on-dark was safe while every plate was dark. Tinting with the
        // plate's own ink instead keeps the well recessed either way.
        .background { if !flush { HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.035) } }

        // Flush there is no well to clip to, and clipping anyway would cut the
        // Roll back to the margin it is deliberately crossing on its way to the
        // glass. Bounded, the frame and the border are the whole point.
        if flush {
            content
        } else {
            content
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.08), lineWidth: 1)
                }
        }
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: HomeCockpitMetrics.baySelectorCrossfade)) {
            bayPageRaw = page.toggled.rawValue
        }
    }

    private var readout: String {
        if model.isEmpty { return page == .roll ? "DAY 1" : "DAY 1 · STANDBY" }
        return page == .roll ? "STRK \(model.streak)" : "TODAY · 7-DAY AVG"
    }

    private var readoutHot: Bool {
        page == .roll && (model.isEmpty || model.streak > 0)
    }
}

// MARK: - Bay Selector (the two-position Toggle)

/// The tiny hardware two-position Bay Selector on the Bay's label row — a
/// recessed dark track with ROLL ⁄ GAUGES segments, the active bay lit amber
/// phosphor. A nested Button: tapping it toggles the bay (0.4s crossfade) and,
/// because SwiftUI gives the innermost button the tap, never fires the outer
/// whole-Console tap.
private struct BaySelector: View {
    let page: CockpitBayPage
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 1) {
                segment(.roll, "ROLL")
                segment(.gauges, "GAUGES")
            }
            .padding(1)
            .frame(height: HomeCockpitMetrics.bayLabelHeight)
            // The track was two literal near-blacks, which was fine for as long
            // as every theme's plates were dark. It draws `screenInk` and
            // `phosphor` on itself, and those come from the panel family — so a
            // theme with a light panel put dark ink on a black track and the
            // unselected segment measured 1.04:1. Ink and plate now come from
            // the same place and cannot disagree.
            .background(
                LinearGradient(
                    colors: [HomeCockpitPalette.track, HomeCockpitPalette.trackAlt],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bay selector")
        .accessibilityValue(page == .roll ? "The Roll" : "Gauges")
        .accessibilityHint("Toggles the cockpit bay between the Roll and the Gauges")
    }

    @ViewBuilder
    private func segment(_ key: CockpitBayPage, _ label: String) -> some View {
        let on = key == page
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.96) // 0.12em at 8pt
            // The unselected segment is still a live control, so it carries the
            // plate's neutral ink at full strength — dimming the phosphor with
            // alpha walks it into the near-black track (measured 2.1–3.5:1).
            // Selected reads as *coloured*, not merely brighter.
            .foregroundStyle(on ? HomeCockpitPalette.phosphor : HomeCockpitPalette.screenInk)
            // Capped at 3 because that is all an 8pt glyph in a 28px chip can
            // carry before the halo starts reading as the letter.
            .shadow(
                color: on ? HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.55) : .clear,
                radius: on ? min(HomeCockpitPalette.glowRadius, 3) : 0
            )
            .padding(.horizontal, 7)
            .frame(maxHeight: .infinity)
            // No wash under the lit segment. A phosphor tint behind phosphor ink
            // walks the plate toward the word — at 0.16 it cost the selected
            // segment ~2 points of contrast (scope/light measured 3.93:1 with it,
            // 5.9:1 without) for an affordance the colour, the bezel and the halo
            // already carry three times over.
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.55), lineWidth: 0.5)
                }
            }
    }
}

// MARK: - The Roll page (Roll Bay)

/// THE ROLL page — the contribution calendar reseated into the Bay's well (the
/// label + STRK readout now live on the Bay's shared label row). Cell intensity
/// = captures that day; the trailing Streak Run lights amber and ends on the
/// Today Marker. Standby ⇒ Ghost Cells + the amber Today Seed.
///
/// Two readings of the same data. In the well it is a chart: a fixed 18-week
/// window, centred, ending where its frame ends. Flush it is a tape — today
/// pinned to the trailing margin, history running left past the margin and
/// dissolving into the glass. Nothing cuts it off, it just stops being visible,
/// which is the honest shape for a record that keeps going backwards.
private struct CockpitRollPage: View {
    let model: HomeFeed.CockpitModel
    /// Run the map off the leading edge instead of ending it on the margin.
    var flush: Bool = false

    private var days: [Int] { model.rollDays }
    private var todayIndex: Int { model.todayIndex }
    private var streak: Int { model.streak }
    private var ghost: Bool { model.isEmpty }

    private func intensity(_ index: Int) -> Int {
        index >= 0 && index < days.count ? days[index] : 0
    }

    private var runEnd: Int {
        guard streak > 0 else { return -1 }
        return intensity(todayIndex) > 0 ? todayIndex : todayIndex - 1
    }

    var body: some View {
        if flush {
            // Reclaim the masthead's leading margin so the oldest columns can
            // reach the glass. The trailing edge stays on the margin the
            // wordmark and the message line share — the map is anchored to
            // today, and only its tail is allowed to leave.
            GeometryReader { geo in
                let columns = columnsFitting(geo.size.width)
                grid(columns: columns)
                    .mask(leadingFade(columns: columns))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            .padding(.leading, -HomeCockpitMetrics.mastheadInset)
            .accessibilityHidden(true)
        } else {
            grid(columns: HomeFeed.rollWeeksBounded)
                .frame(maxWidth: .infinity, maxHeight: .infinity) // center the grid in the well
                .accessibilityHidden(true)
        }
    }

    /// The trailing `columns` weeks of the Roll, oldest→newest left→right.
    /// Always counted back from the end so today stays in the last column
    /// whatever the width allows.
    private func grid(columns: Int) -> some View {
        let end = runEnd
        let runStart = end - streak + 1
        let firstColumn = max(0, HomeFeed.rollWeeks - columns)

        return VStack(spacing: HomeCockpitMetrics.rollGap) {
            ForEach(0..<HomeFeed.rollDaysPerWeek, id: \.self) { row in
                HStack(spacing: HomeCockpitMetrics.rollGap) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = (firstColumn + col) * HomeFeed.rollDaysPerWeek + row
                        RollCell(
                            intensity: intensity(index),
                            isToday: index == todayIndex,
                            inRun: streak > 0 && index >= runStart && index <= end,
                            isFuture: index > todayIndex,
                            ghost: ghost
                        )
                    }
                }
            }
        }
    }

    /// How many week columns this width can hold. Derived rather than fixed so
    /// the map is as long as the phone allows — a bigger screen shows more
    /// history instead of the same window with more air around it.
    private func columnsFitting(_ width: CGFloat) -> Int {
        let pitch = HomeCockpitMetrics.rollCell + HomeCockpitMetrics.rollGap
        // Rounded up on purpose: the leading column should be cut by the glass
        // rather than stop politely one gap short of it. The fade has already
        // taken that column to nothing, so what this really buys is the
        // guarantee that there is never a sliver of margin on the left.
        let fits = Int(((width + HomeCockpitMetrics.rollGap) / pitch).rounded(.up))
        return max(1, min(HomeFeed.rollWeeks, fits))
    }

    /// The dissolve, measured against the grid's own width rather than the
    /// frame's, so the ramp always lands on real cells even when the data runs
    /// out before the screen does.
    private func leadingFade(columns: Int) -> LinearGradient {
        let pitch = HomeCockpitMetrics.rollCell + HomeCockpitMetrics.rollGap
        let gridWidth = CGFloat(columns) * pitch - HomeCockpitMetrics.rollGap
        let stop = gridWidth > 0
            ? min(1, HomeCockpitMetrics.rollFadeWidth / gridWidth)
            : 0
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: stop),
                .init(color: .black, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - The Gauge page (Gauge Bay)

/// GAUGES page — three instrument lanes filling the well (NOT a Take Log replay):
/// TAKES (today's count + 12-seg Meter vs 7-day avg + pace) · TIME (today's m:ss
/// + Meter) · STRK (Life-in-Dots + run count). Lane heights sum to 102pt.
private struct CockpitGaugePage: View {
    let model: HomeFeed.CockpitModel

    private var standby: Bool { model.isEmpty }

    var body: some View {
        VStack(spacing: HomeCockpitMetrics.gaugeGap) {
            MeterLane(
                caption: "TAKES",
                readout: standby ? "0" : "\(model.todayTakes)",
                todayLevel: HomeCockpitMetrics.clamp01(Double(model.todayTakes) / HomeCockpitMetrics.scaleTakes),
                avgLevel: HomeCockpitMetrics.clamp01(model.avgTakes / HomeCockpitMetrics.scaleTakes),
                standby: standby,
                height: HomeCockpitMetrics.gaugeTakesHeight
            )
            MeterLane(
                caption: "TIME",
                readout: standby ? "0:00" : HomeFeed.compactDuration(model.todayDurationSeconds),
                todayLevel: HomeCockpitMetrics.clamp01(model.todayDurationSeconds / HomeCockpitMetrics.scaleTimeSeconds),
                avgLevel: HomeCockpitMetrics.clamp01(model.avgDurationSeconds / HomeCockpitMetrics.scaleTimeSeconds),
                standby: standby,
                height: HomeCockpitMetrics.gaugeTimeHeight
            )
            StrkLane(model: model, height: HomeCockpitMetrics.gaugeStrkHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Meter lane (TAKES · TIME)

/// One meter gauge lane — CAPTION · big phosphor readout · 12-segment Meter ·
/// pace label. Reused by the TAKES + TIME gauges.
private struct MeterLane: View {
    let caption: String
    let readout: String
    let todayLevel: Double
    let avgLevel: Double
    let standby: Bool
    let height: CGFloat

    var body: some View {
        let pace = MeterLane.pace(todayLevel: todayLevel, avgLevel: avgLevel, standby: standby)
        HStack(spacing: 9) {
            // Quiet on the plate is a token choice, never an alpha one: dimming
            // the phosphor composites it toward the near-black plate (measured
            // 2.0–3.5:1). The faint plate ink is authored to stay legible there.
            Text(caption)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8) // 0.1em at 8pt
                .foregroundStyle(HomeCockpitPalette.screenInkFaint)
                .frame(width: 42, alignment: .leading)

            Text(readout)
                .font(.system(size: 15, weight: .bold, design: .monospaced).monospacedDigit())
                .tracking(0.3) // 0.02em at 15pt
                .foregroundStyle(standby ? HomeCockpitPalette.screenInk : HomeCockpitPalette.phosphor)
                .shadow(color: standby ? .clear : HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.55), radius: standby ? 0 : 4)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)

            SegMeter(todayLevel: todayLevel, avgLevel: avgLevel, standby: standby)
                .frame(maxWidth: .infinity)

            Text(pace.text)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.48) // 0.06em at 8pt
                .foregroundStyle(pace.hot ? HomeCockpitPalette.phosphor : HomeCockpitPalette.screenInk)
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.035))
        .clipShape(RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous)
                .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.08), lineWidth: 1)
        )
    }

    /// Pace from the today-vs-average delta (studio `paceOf`).
    static func pace(todayLevel: Double, avgLevel: Double, standby: Bool) -> (text: String, hot: Bool) {
        if standby { return ("—", false) }
        let d = todayLevel - avgLevel
        if d > 0.02 { return ("▲ ABOVE AVG", true) }
        if d < -0.02 { return ("▼ BELOW AVG", false) }
        return ("= AT AVG", false)
    }
}

// MARK: - Segment Meter

/// The slim 12-segment Meter — fill = today, a brighter amber tick marks where
/// the trailing 7-day average sits, so today reads against its own baseline.
/// Standby ⇒ 12 outlined Ghost segments.
private struct SegMeter: View {
    let todayLevel: Double
    let avgLevel: Double
    let standby: Bool

    var body: some View {
        let filled = standby ? 0 : Int((HomeCockpitMetrics.clamp01(todayLevel) * 12).rounded())
        let avgIndex = standby ? 0 : Int((HomeCockpitMetrics.clamp01(avgLevel) * 12).rounded())

        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                let lit = i < filled
                let isAvg = !standby && avgIndex > 0 && i == avgIndex - 1
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fill(lit: lit, isAvg: isAvg))
                    .overlay {
                        if standby {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.10), lineWidth: 1)
                        }
                    }
                    .shadow(
                        color: glow(i: i, filled: filled, lit: lit, isAvg: isAvg),
                        radius: (isAvg || (lit && i == filled - 1)) ? 3 : 0
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 6)
    }

    private func fill(lit: Bool, isAvg: Bool) -> Color {
        if standby { return .clear }
        if isAvg && !lit { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.5) }
        if lit { return HomeCockpitPalette.phosphor }
        return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.12)
    }

    private func glow(i: Int, filled: Int, lit: Bool, isAvg: Bool) -> Color {
        if standby { return .clear }
        if isAvg { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.7) }
        if lit && i == filled - 1 { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.55) }
        return .clear
    }
}

// MARK: - STRK lane (Life-in-Dots)

/// The STRK gauge — the run count + the Life-in-Dots module (last 12 days, 6×2).
private struct StrkLane: View {
    let model: HomeFeed.CockpitModel
    let height: CGFloat

    private var standby: Bool { model.isEmpty }
    private var streak: Int { model.streak }

    var body: some View {
        HStack(spacing: 9) {
            Text("STRK")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8) // 0.1em at 8pt
                .foregroundStyle(HomeCockpitPalette.screenInkFaint)
                .frame(width: 42, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(standby ? "0" : "\(streak)")
                    .font(.system(size: 17, weight: .bold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(standby || streak > 0 ? HomeCockpitPalette.phosphor : HomeCockpitPalette.screenInk)
                    .shadow(
                        color: (!standby && streak > 0) ? HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.5) : .clear,
                        radius: (!standby && streak > 0) ? 3 : 0
                    )
                Text(standby ? "DAY 1" : "DAY RUN")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(0.56) // 0.08em at 7pt
                    .foregroundStyle(HomeCockpitPalette.screenInkFaint)
            }
            .frame(width: 66, alignment: .leading)

            Spacer(minLength: 0)

            LifeInDots(days: model.last12Days, standby: standby)
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.035))
        .clipShape(RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HomeCockpitMetrics.gaugeCorner, style: .continuous)
                .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.08), lineWidth: 1)
        )
    }
}

/// The Life-in-Dots module — the last 12 days as a 6×2 dot grid (row-major,
/// oldest→newest; today = bottom-right). Filled = captured · amber = today ·
/// outlined = empty. Standby ⇒ Ghost dots + the amber Today Seed.
private struct LifeInDots: View {
    let days: [Bool] // oldest→newest, length 12
    let standby: Bool

    var body: some View {
        VStack(spacing: HomeCockpitMetrics.dotGap) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: HomeCockpitMetrics.dotGap) {
                    ForEach(0..<6, id: \.self) { col in
                        let i = row * 6 + col
                        Dot(filled: filled(i), isToday: i == 11, standby: standby)
                    }
                }
            }
        }
    }

    private func filled(_ i: Int) -> Bool { i >= 0 && i < days.count ? days[i] : false }
}

private struct Dot: View {
    let filled: Bool
    let isToday: Bool
    let standby: Bool

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: HomeCockpitMetrics.dot, height: HomeCockpitMetrics.dot)
            .overlay { stroke }
            .shadow(color: glowColor, radius: glowRadius)
    }

    private var fill: Color {
        if standby { return .clear }
        if isToday { return HomeCockpitPalette.phosphor }
        if filled { return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.9) }
        return .clear
    }

    @ViewBuilder
    private var stroke: some View {
        if standby && isToday {
            Circle().strokeBorder(HomeCockpitPalette.phosphor, lineWidth: 1.5) // amber Today Seed
        } else if standby {
            Circle().strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.11), lineWidth: 1) // Ghost dot
        } else if !filled && !isToday {
            Circle().strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.16), lineWidth: 1) // empty day
        }
    }

    private var glowColor: Color {
        if standby && isToday { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.7) }
        if !standby && isToday { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.8) }
        return .clear
    }

    private var glowRadius: CGFloat {
        if isToday { return standby ? 3 : 4 }
        return 0
    }
}

// MARK: - Roll cell

/// One Roll cell. Precedence (matching studio RollCell): ghost (standby) → future
/// → today → in-run → active intensity → empty past day.
private struct RollCell: View {
    let intensity: Int
    let isToday: Bool
    let inRun: Bool
    let isFuture: Bool
    /// Standby / first-run — draw an outlined Ghost Cell, today as the amber Seed.
    var ghost: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fill)
            .frame(width: HomeCockpitMetrics.rollCell, height: HomeCockpitMetrics.rollCell)
            .overlay { strokeOverlay }
            .shadow(color: glowColor, radius: glowRadius)
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        if ghost && isToday {
            // The amber Today Seed — the "you are here" the streak grows from.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(HomeCockpitPalette.phosphor, lineWidth: 1.5)
        } else if ghost {
            // A Ghost Cell — a faint outline sketching the grid that will fill in.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.11), lineWidth: 1)
        } else if isToday && intensity == 0 {
            // Today, no capture yet — an unlit amber ring marker.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(HomeCockpitPalette.phosphor, lineWidth: 1)
        }
    }

    private var fill: Color {
        if ghost { return .clear }  // ghost cells are outlined only
        if isFuture { return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.03) }
        if isToday && intensity > 0 { return HomeCockpitPalette.phosphor }
        if isToday { return .clear }  // ring drawn in the overlay
        if inRun { return HomeCockpitPalette.phosphor.opacity(0.7 + Double(intensity) * 0.1) }
        if intensity > 0 { return activeInk }
        return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.05)   // empty past day
    }

    // Cell ink is the plate's own ink, not a literal white — a light plate
    // needs dark cells for the same reason a dark one needs light ones.
    private var activeInk: Color {
        if intensity >= 3 { return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.85) }
        if intensity == 2 { return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.55) }
        return HomeCockpitPalette.tint(HomeCockpitPalette.screenInk, 0.30)
    }

    private var glowColor: Color {
        if ghost && isToday { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.7) }
        if ghost { return .clear }
        if isToday && intensity > 0 { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.85) }
        if inRun { return HomeCockpitPalette.tint(HomeCockpitPalette.phosphor, 0.4) }
        return .clear
    }

    private var glowRadius: CGFloat {
        if ghost && isToday { return 4 }
        if ghost { return 0 }
        if isToday && intensity > 0 { return 4 }
        if inRun { return 2 }
        return 0
    }
}

// MARK: - Frequent actions (above recents)

private struct HomeFrequentActionsStrip: View {
    let onSearch: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        // No label.
        //
        // `RECENT` and `EXPLORE` name things that would otherwise be
        // ambiguous — a list of items, a row of destinations. Four cells that
        // say RECORD, COMPOSE, SCAN and SEARCH are not ambiguous, and a
        // heading over them only says "these are the quick ones", which is a
        // claim about the row's rank rather than its contents. It also cost a
        // whole type register at the top of the page's most-used control.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                actionCell(label: "RECORD", icon: "waveform", accessibilityID: "dock.record") {
                    RecordingSheetController.shared.isPresented = true
                }
                divider
                actionCell(label: "COMPOSE", icon: "square.and.pencil") {
                    AppShellRouter.shared.openCompose(
                        documentID: "blank-\(UUID().uuidString.prefix(8))"
                    )
                }
                divider
                actionCell(label: "SCAN", icon: "camera") {
                    AppShellRouter.shared.openCameraCapture()
                }
                divider
                actionCell(label: "SEARCH", icon: "magnifyingglass", action: onSearch)
            }
            .frame(height: 56)
            // A clean framed control rail. The hairline gives it enough
            // structure without repeating the cockpit's heavy depth cues.
            // No `hairlineEmphasis` here, and it is worth saying why, because
            // the design system recommends applying it liberally.
            //
            // On a card floating in open space a lit top edge reads as the
            // fabricated edge of a raised thing. On a full-width rail sitting
            // directly under a full-width band, it reads as a second rule — the
            // eye has just been given one horizontal division and this hands it
            // another, twelve points below. Measured, it doubled the top edge
            // from 54 to 93 against a page at 6. That is a divider, whatever it
            // was drawn as.
            .softCard(padding: 0, corner: 12, emphasis: .faint)
        }
    }

    private func actionCell(
        label: String,
        icon: String,
        accessibilityID: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(iconColor(label: label))
                Text(label)
                    .talkieType(.channelLabelTiny)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.capitalized)
        .accessibilityIdentifier(accessibilityID ?? "home.quick.\(label.lowercased().replacing(" ", with: "-"))")
    }

    private func iconColor(label: String) -> Color {
        switch label {
        case "RECORD", "SEARCH":
            return HomeCockpitPalette.accent
        default:
            return theme.currentTheme.chrome.action
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(width: theme.currentTheme.chrome.hairlineWidth)
            .padding(.vertical, 10)
    }
}

// MARK: - Suggestions (below recents)

private struct HomeSuggestionsStrip: View {
    @State private var bridgeManager = BridgeManager.shared
    @ObservedObject private var theme = ThemeManager.shared

    private var suggestions: [HomeSuggestion] {
        var items: [HomeSuggestion] = []

        if !bridgeManager.isPaired {
            items.append(HomeSuggestion(
                title: "Pair Mac",
                icon: "qrcode.viewfinder",
                action: { AppShellRouter.shared.openBridgeDetail() }
            ))
        } else if bridgeManager.status != .connected {
            items.append(HomeSuggestion(
                title: "Connections",
                icon: "link",
                action: { AppShellRouter.shared.openConnectionCenter() }
            ))
        } else {
            items.append(HomeSuggestion(
                title: "Deck",
                icon: "square.grid.3x3",
                action: { AppShellRouter.shared.openDeck() }
            ))
        }

        items.append(HomeSuggestion(
            title: "Workflows",
            icon: "point.3.connected.trianglepath.dotted",
            action: { AppShellRouter.shared.openWorkflows() }
        ))
        items.append(HomeSuggestion(
            title: "Terminal",
            icon: "terminal",
            action: { AppShellRouter.shared.openTerminal() }
        ))
        items.append(HomeSuggestion(
            title: "Keyboard",
            icon: "keyboard",
            action: { AppShellRouter.shared.openKeyboardActivation() }
        ))

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· EXPLORE")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button(action: suggestion.action) {
                            HStack(spacing: 6) {
                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(HomeCockpitPalette.accent)
                                Text(suggestion.title)
                                    .talkieType(.fieldLabel)
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(theme.colors.cardBackground)
                                    .overlay(
                                        Capsule()
                                            .fill(HomeCockpitPalette.tint(HomeCockpitPalette.accent, 0.035))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                theme.currentTheme.chrome.edgeFaint,
                                                lineWidth: theme.currentTheme.chrome.hairlineWidth
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(suggestion.accessibilityIdentifier)
                    }
                }
            }
            // The cut, softened.
            //
            // A row of chips that ends on a hard vertical edge reads as
            // damaged — the last chip looks broken rather than continued. The
            // honest fix is not to hide the cut but to stop it being an edge:
            // the last few points dissolve, which says "there is more" in the
            // one vocabulary that cannot be mistaken for a border.
            //
            // Trailing only. A leading fade would dim the first chip while the
            // row is at rest, which is most of the time, to solve a problem
            // that only exists once it has been scrolled.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.90),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

private struct HomeSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: () -> Void

    var accessibilityIdentifier: String {
        title == "Keyboard" ? "dock.keyboard" : "home.suggestion.\(title.lowercased().replacing(" ", with: "-"))"
    }
}

// MARK: - RECENT

private enum HomeRecentMetrics {
    static let rowHeight: CGFloat = 38
}

private struct RecentSection: View {
    let items: [HomeFeed.RecentItem]
    let totalCount: Int
    let isLoading: Bool
    let errorMessage: String?
    let isSearching: Bool
    let hasMore: Bool
    let remainingCount: Int
    @Binding var contentFilter: HomeFeed.ContentFilter
    @Binding var sortOption: HomeFeed.SortOption
    let showsSyncPrompt: Bool
    let onLoadMore: () -> Void
    let onPromote: (HomeFeed.RecentItem) -> Void
    let onDelete: (HomeFeed.RecentItem) -> Void
    let onOpenICloudSettings: () -> Void
    let onDismissSyncPrompt: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("· RECENT")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(totalCountLabel)
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recent, \(totalCountLabel)")

                Spacer()

                filterMenu
                sortMenu

                Button(action: { AppShellRouter.shared.openLibrary(tab: libraryTabForCurrentFilter) }) {
                    Text("ALL ›")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let errorMessage {
                    FeedMessageState(
                        icon: "exclamationmark.triangle",
                        title: "Couldn’t load recents",
                        message: errorMessage
                    )
                } else if items.isEmpty {
                    EmptyHomeRecentState(
                        isSearching: isSearching,
                        showsSyncPrompt: showsSyncPrompt,
                        onOpenICloudSettings: onOpenICloudSettings,
                        onDismissSyncPrompt: onDismissSyncPrompt
                    )
                } else {
                    List {
                        ForEach(items.enumerated(), id: \.element.id) { idx, item in
                            Button(action: { open(item) }) {
                                RecentRow(item: item, showDivider: idx > 0)
                                    .contentShape(Rectangle())
                            }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("memo.row")
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
                    .listRowSpacing(0)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, HomeRecentMetrics.rowHeight)
                    .frame(height: CGFloat(items.count) * HomeRecentMetrics.rowHeight)

                    if hasMore {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(theme.currentTheme.chrome.edgeSubtle.opacity(0.75))
                                .frame(height: theme.currentTheme.chrome.hairlineWidth)

                            Button(action: {
                                Haptics.confirm.fire()  // light "got it" as the next page reveals
                                withAnimation { onLoadMore() }
                            }) {
                                HStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Load \(min(10, remainingCount)) more")
                                        .talkieType(.preview)
                                    Spacer()
                                }
                                .foregroundStyle(theme.colors.textSecondary)
                                .frame(height: HomeRecentMetrics.rowHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            // Recents are a quiet reading surface, not another instrument
            // screen. A flat fill and hairline frame preserve grouping without
            // casting a gray falloff over the first row.
            .softCard(
                padding: 0,
                corner: 10,
                emphasis: .faint,
                fill: theme.colors.cardBackground.opacity(0.72)
            )
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(HomeFeed.ContentFilter.allCases, id: \.self) { filter in
                Button {
                    contentFilter = filter
                } label: {
                    Label(filter.label, systemImage: filter.icon)
                }
            }
        } label: {
            Label(contentFilter.label, systemImage: contentFilter.icon)
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .accessibilityLabel("Content filter")
        .accessibilityValue(contentFilter.label)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(HomeFeed.SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    Label(option.label, systemImage: option.menuIcon)
                }
            }
        } label: {
            Image(systemName: sortOption.menuIcon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.colors.textTertiary)
        }
        .accessibilityLabel("Sort recent items")
        .accessibilityValue(sortOption.label)
    }

    private var totalCountLabel: String {
        totalCount == 1 ? "1 item" : "\(totalCount) items"
    }

    private var libraryTabForCurrentFilter: LibraryTab? {
        switch contentFilter {
        case .all: return nil
        case .memos: return .memos
        case .dictations: return .dictations
        case .captures: return .items
        }
    }

    private func open(_ item: HomeFeed.RecentItem) {
        switch item.source {
        case .dictation:        AppShellRouter.shared.openMemoDetail(memoID: item.id)
        case .typed:            AppShellRouter.shared.openCompose(documentID: item.id)
        case .link, .scan:      AppShellRouter.shared.openCaptureDetail(captureID: item.id)
        }
    }
}

private struct RecentRow: View {
    let item: HomeFeed.RecentItem
    let showDivider: Bool
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 8) {
                sourceGlyph
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16, height: 16)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .talkieType(.preview)
                        .foregroundStyle(isContentPreview ? theme.colors.textSecondary : theme.colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    if item.isTranscribing {
                        RecentTranscribingBadge()
                    }

                    Spacer(minLength: 8)

                    Text(item.relativeTime)
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let syncStatus = item.syncStatus {
                        Image(systemName: syncIcon(for: syncStatus))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(syncColor(for: syncStatus))
                            .accessibilityLabel(syncAccessibilityLabel(for: syncStatus))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: HomeRecentMetrics.rowHeight)

            if showDivider {
                Rectangle()
                    .fill(theme.currentTheme.chrome.edgeSubtle.opacity(0.75))
                    .frame(height: theme.currentTheme.chrome.hairlineWidth)
            }
        }
        .frame(height: HomeRecentMetrics.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private var isContentPreview: Bool {
        if case .typed = item.source { return true }
        return false
    }

    private func syncIcon(for status: HomeFeed.SyncStatus) -> String {
        switch status {
        case .synced: return "checkmark.icloud.fill"
        case .pending: return "icloud.and.arrow.up"
        }
    }

    private func syncColor(for status: HomeFeed.SyncStatus) -> Color {
        switch status {
        case .synced: return theme.currentTheme.chrome.accent
        case .pending: return theme.colors.textTertiary
        }
    }

    private func syncAccessibilityLabel(for status: HomeFeed.SyncStatus) -> String {
        switch status {
        case .synced: return "Synced"
        case .pending: return "Sync pending"
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
/// affordances live in the memo detail view, not here.
private struct RecentTranscribingBadge: View {
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

private struct FeedMessageState: View {
    let icon: String
    let title: String
    let message: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text(title)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textSecondary)
            Text(message)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }
}

private struct EmptyHomeRecentState: View {
    let isSearching: Bool
    let showsSyncPrompt: Bool
    let onOpenICloudSettings: () -> Void
    let onDismissSyncPrompt: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 12) {
            FeedMessageState(
                icon: isSearching ? "magnifyingglass" : "tray",
                title: isSearching ? "· NO MATCHES" : "· NOTHING RECENT",
                message: isSearching ? "Try a different search term" : "Record, dictate, compose, or scan to start your feed."
            )

            if showsSyncPrompt {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud is not signed in")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("Sign in to sync memos with your Mac.")
                            .talkieType(.hint)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    Spacer()
                    Button("Open") {
                        onOpenICloudSettings()
                    }
                    .talkieType(.chipLabel)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    Button(action: onDismissSyncPrompt) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(12)
                .background(theme.currentTheme.chrome.accentTint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}
