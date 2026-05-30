//
//  ScopeLearnScreen.swift
//  Talkie macOS
//
//  Agent-powered "Learn" interstitial — Scope theme replacement for
//  the data-listing ScopeStatsScreen. Not a dashboard of "things
//  you've done"; a discovery surface that puts Talkie's surface area
//  in front of you, with an agent box at the top to ask about it.
//
//  Ported from `design/studio/app/mac-learn/` (2026-05-17). See that
//  study's NOTES.md for the design rationale.
//
//  Composition (top → bottom):
//    1. TopBand        — universal "Learn" identity rail
//    2. Hero           — "Learn" page title
//    3. AskTalkie box  — input + suggested chips + stubbed example
//                        responses. Placeholder "Ask Talkie about
//                        Talkie…" carries the cute self-reference.
//    4. Did you know?  — 3-card recap of existing features users may
//                        not have discovered
//    5. Features       — 6-card illustrated atlas of surfaces
//    6. Integrations   — LLM provider tiles + services
//    7. What's new     — recently shipped strip
//

import SwiftUI
import TalkieKit

private let learnLog = Log(.ui)

// MARK: - Display font (mirrors ScopeHomeView's ScopeFont)
private enum LearnFont {
    private static let regular  = ["CormorantGaramond-Regular", "Cormorant Garamond", "CormorantGaramond"]
    private static let mediumNm = ["CormorantGaramond-Medium", "Cormorant Garamond Medium"]

    static func display(size: CGFloat, medium: Bool = false) -> Font {
        for name in (medium ? mediumNm : regular) {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: medium ? .medium : .regular, design: .serif)
    }
}

// MARK: - Screen

struct ScopeLearnScreen: View {
    let onNavigate: (NavigationSection) -> Void
    let onOpenSettings: (SettingsSection) -> Void

    init(
        onNavigate: @escaping (NavigationSection) -> Void = { _ in },
        onOpenSettings: @escaping (SettingsSection) -> Void = { _ in }
    ) {
        self.onNavigate = onNavigate
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            ScopeTopBand(title: "Learn", chrome: "AGENT · INTERSTITIAL")

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    hero
                    knowledgeBaseBlock
                    didYouKnowBlock
                    featureAtlasBlock
                    integrationsBlock
                    whatsNewBlock
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopeCanvas.canvas)
    }

    private func open(_ destination: LearnDestination) {
        switch destination {
        case .section(let section):
            onNavigate(section)
        case .settings(let section):
            onOpenSettings(section)
        }
    }

    private func handleLearnBridgeURL(_ url: URL) {
        let host = url.host?.localizedLowercase ?? ""
        let path = url.pathComponents.dropFirst().first?.localizedLowercase ?? ""

        switch host {
        case "open":
            if !openBridgeSection(path) {
                learnLog.warning("Unhandled Learn open bridge: \(url.absoluteString)")
            }
        case "settings":
            guard !path.isEmpty else {
                open(.section(.settings))
                return
            }
            if let section = SettingsSection.from(path: path) {
                open(.settings(section.canonicalSection))
            } else {
                learnLog.warning("Unhandled Learn settings bridge: \(url.absoluteString)")
            }
        case "tray":
            if path == "shelf" {
                TrayShelf.shared.toggle()
            } else {
                TrayViewer.shared.show()
            }
        case "home":
            open(.section(.home))
        case "compose":
            open(.section(.drafts))
        case "library":
            open(.section(.recordings))
        default:
            if !openBridgeSection(host) {
                learnLog.warning("Unhandled Learn bridge URL: \(url.absoluteString)")
            }
        }
    }

    @discardableResult
    private func openBridgeSection(_ rawTarget: String) -> Bool {
        let target = rawTarget
            .replacing("_", with: "-")
            .localizedLowercase

        switch target {
        case "home", "today":
            open(.section(.home))
        case "compose", "drafts":
            open(.section(.drafts))
        case "notes":
            open(.section(.notes))
        case "memos", "recordings", "library":
            open(.section(.recordings))
        case "dictations":
            open(.section(.dictations))
        case "workflows", "workflow":
            open(.section(.workflows))
        case "context", "context-rules", "rules":
            open(.section(.contextRules))
        case "console", "system-console", "agents":
            open(.section(.systemConsole))
        case "screenshots", "captures":
            open(.section(.screenshots))
        case "models":
            open(.section(.models))
        case "settings":
            open(.section(.settings))
        default:
            return false
        }
        return true
    }

    // MARK: - Hero

    // The ScopeTopBand already owns the "Learn" identity (top rail). The hero
    // no longer repeats a 44px "Learn" title — that was the doubled-up header.
    // It keeps only the eyebrow as a lead-in to the Ask surface below.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ASK · EXPLORE · REVISIT FEATURES")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.faint)
        }
    }

    // MARK: - Ask Talkie

    private var askTalkieBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Ask Talkie")
                Spacer()
                Text("APPLE INTELLIGENCE · ANTHROPIC · OPENAI · LOCAL")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            AskTalkieBox(onOpen: open)
        }
    }

    private var knowledgeBaseBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Knowledge")
                Spacer()
                Text("LOCAL HTML · NATIVE BRIDGE")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }

            LearnKnowledgeBaseView(onBridgeAction: handleLearnBridgeURL)
        }
    }

    // MARK: - Did you know

    private var didYouKnowBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Did you know?")
                Spacer()
                Text("EXISTING FEATURES · WORTH A REVISIT")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ],
                spacing: 16
            ) {
                RecapCard(
                    glyph: .diff,
                    hook: "You can diff Compose edits",
                    detail: "Voice instructions revise existing text; the changes show as inline diffs before you accept.",
                    action: "OPEN COMPOSE",
                    onOpen: { open(.section(.drafts)) }
                )
                RecapCard(
                    glyph: .screenshot,
                    hook: "Hyper+S captures with audio",
                    detail: "The screen grab joins the current recording — pinned alongside the words, not separately.",
                    action: "SHORTCUTS",
                    onOpen: { open(.settings(.surface)) }
                )
                RecapCard(
                    glyph: .context,
                    hook: "Context rules scope to apps",
                    detail: "Bind a rule to iTerm only, or to anywhere except Slack. The matcher reads the foreground app at trigger time.",
                    action: "MANAGE RULES",
                    onOpen: { open(.section(.contextRules)) }
                )
            }
        }
    }

    // MARK: - Feature atlas

    private var featureAtlasBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Features")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ],
                spacing: 16
            ) {
                FeatureCard(glyph: .workflows, name: "Workflows",     state: "3 ran today",       action: "OPEN") {
                    open(.section(.workflows))
                }
                FeatureCard(glyph: .context,   name: "Context rules", state: "12 active",          action: "OPEN") {
                    open(.section(.contextRules))
                }
                FeatureCard(glyph: .console,   name: "Console",       state: "2 tabs open",        action: "OPEN") {
                    open(.section(.systemConsole))
                }
                FeatureCard(glyph: .compose,   name: "Compose",       state: "Last · 9:34 AM",     action: "OPEN") {
                    open(.section(.drafts))
                }
                FeatureCard(glyph: .keys,      name: "Hyper keys",    state: "5 bindings",         action: "MANAGE") {
                    open(.settings(.surface))
                }
                FeatureCard(glyph: .memos,     name: "Memos",         state: "436 in last 7 days", action: "OPEN") {
                    open(.section(.recordings))
                }
            }
        }
    }

    // MARK: - Integrations

    private var integrationsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Integrations")
                Spacer()
                Text("LLMS · SERVICES · YOUR KEYS")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ProviderTile(name: "Apple Intelligence", category: "LLM",     status: .available,  detail: "on-device · macOS 15.1+") {
                    open(.settings(.aiProviders))
                }
                ProviderTile(name: "Anthropic",          category: "LLM",     status: .configured, detail: "claude-opus-4-7") {
                    open(.settings(.aiProviders))
                }
                ProviderTile(name: "OpenAI",             category: "LLM",     status: .configured, detail: "gpt-4o") {
                    open(.settings(.aiProviders))
                }
                ProviderTile(name: "Local",              category: "LLM",     status: .available,  detail: "ollama · mistral 7b") {
                    open(.settings(.aiProviders))
                }
                ProviderTile(name: "Gemini",             category: "LLM",     status: .available,  detail: "your API key") {
                    open(.settings(.aiProviders))
                }
                ProviderTile(name: "Hugging Face",       category: "LLM",     status: .soon,       detail: "inference endpoints") {
                    open(.settings(.aiProviders))
                }
                ProviderTile(name: "iCloud",             category: "Service", status: .configured, detail: "private sync") {
                    open(.settings(.sync))
                }
                ProviderTile(name: "Bridge API",         category: "Service", status: .available,  detail: "local HTTP · port 7745") {
                    open(.settings(.helpers))
                }
            }
        }
    }

    // MARK: - What's new

    private var whatsNewBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("What's new")
            VStack(spacing: 0) {
                ForEach(WhatsNewEntry.recent) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(entry.date)
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(ScopeInk.faint)
                            .frame(width: 96, alignment: .leading)
                        Text(entry.title)
                            .font(.system(size: 12))
                            .foregroundStyle(ScopeInk.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) {
                        if entry.id != WhatsNewEntry.recent.first?.id {
                            Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ScopeEdge.faint, lineWidth: 0.5)
            )
        }
    }
}

private enum LearnDestination {
    case section(NavigationSection)
    case settings(SettingsSection)
}

// MARK: - Ask Talkie box

private struct AskTalkieBox: View {
    let onOpen: (LearnDestination) -> Void

    @State private var prompt: String = ""

    var body: some View {
        VStack(spacing: 14) {
            // Input
            HStack(spacing: 10) {
                Text("»")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
                TextField("Ask Talkie about Talkie…", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(ScopeInk.primary)
                Text("↵")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ScopeInk.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ScopeEdge.faint, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Suggested chips
            FlowChips(suggestions: SUGGESTED, onPick: { prompt = $0 })

            // Stubbed response area
            responseArea
        }
        .padding(20)
        .background(Color.white.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(ScopeEdge.faint, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private static let SUGGESTED: [String] = [
        "How do workflows trigger?",
        "Can a context rule scope to one app?",
        "What's bound to Hyper+S?",
        "Which LLM providers can I plug in?",
        "How do diffs work in Compose?",
    ]
    private var SUGGESTED: [String] { Self.SUGGESTED }

    @ViewBuilder
    private var responseArea: some View {
        let stub = stubAnswer(for: prompt)
        VStack(alignment: .leading, spacing: 10) {
            if let stub {
                HStack(alignment: .top, spacing: 10) {
                    Text("TALKIE")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                        .padding(.top, 2)
                    Text(stub.body)
                        .font(.system(size: 12))
                        .foregroundStyle(ScopeInk.primary)
                        .lineSpacing(2)
                }
                Button(action: { onOpen(stub.destination) }) {
                    HStack(spacing: 4) {
                        Text(stub.link.uppercased())
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                        Text("→")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.hex("9A6A22"))
                }
                .buttonStyle(.plain)
            } else {
                Text("The agent's answer lands here — grounded in Talkie's capabilities, with quick links to the surfaces it touches.")
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.faint)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .foregroundStyle(ScopeEdge.faint)
        )
    }

    private struct StubAnswer {
        let body: String
        let link: String
        let destination: LearnDestination
    }

    private func stubAnswer(for q: String) -> StubAnswer? {
        switch q.trimmingCharacters(in: .whitespaces) {
        case "How do workflows trigger?":
            return .init(
                body: "Three triggers — recording finished, context rule matched, manual run. Each step pipes its output to the next.",
                link: "Open Workflows",
                destination: .section(.workflows)
            )
        case "Can a context rule scope to one app?":
            return .init(
                body: "Yes. The matcher reads the foreground app at trigger time. You can scope to one app, a list, or an everywhere-except set.",
                link: "Manage Context Rules",
                destination: .section(.contextRules)
            )
        case "What's bound to Hyper+S?":
            return .init(
                body: "Hyper+S triggers the screenshot chord. Pick A (region), S (fullscreen), or D (window). The grab attaches to the current recording if one's running.",
                link: "Open Shortcuts",
                destination: .settings(.surface)
            )
        case "Which LLM providers can I plug in?":
            return .init(
                body: "Anthropic and OpenAI by API key, local via Ollama, Apple Intelligence on-device on 15.1+. Provider chosen per-feature in Settings.",
                link: "Open Integrations",
                destination: .settings(.aiProviders)
            )
        case "How do diffs work in Compose?":
            return .init(
                body: "Voice instructions revise existing text. The change shows as an inline diff — accept the whole thing, accept span-by-span, or reject.",
                link: "Open Compose",
                destination: .section(.drafts)
            )
        default:
            return nil
        }
    }
}

private struct FlowChips: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(suggestions, id: \.self) { s in
                Button(action: { onPick(s) }) {
                    Text(s)
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeInk.faint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(ScopeEdge.faint, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Recap card (Did you know)

private struct RecapCard: View {
    enum Glyph { case diff, screenshot, context }

    let glyph: Glyph
    let hook: String
    let detail: String
    let action: String
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    glyphTile
                    Text(hook)
                        .font(LearnFont.display(size: 15, medium: true))
                        .foregroundStyle(ScopeInk.primary)
                        .tracking(-0.2)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ScopeInk.muted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Divider().overlay(ScopeEdge.subtle)
                HStack(spacing: 4) {
                    Text(action)
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                    Text("→")
                        .font(.system(size: 11))
                }
                .foregroundStyle(isHovered ? ScopeAmber.solid : Color.hex("9A6A22"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(Color.white.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? ScopeEdge.normal : ScopeEdge.faint, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }

    private var glyphTile: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.hex("FAF6E8"))
            .frame(width: 36, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.faint, lineWidth: 0.5)
            )
            .overlay(RecapGlyphShape(kind: glyph))
    }
}

private struct RecapGlyphShape: View {
    let kind: RecapCard.Glyph

    var body: some View {
        switch kind {
        case .diff:
            VStack(spacing: 3) {
                Rectangle()
                    .fill(Color.hex("9A6A22").opacity(0.4))
                    .frame(width: 11, height: 2)
                Rectangle()
                    .fill(Color.hex("9A6A22"))
                    .frame(width: 16, height: 2)
            }
        case .screenshot:
            ZStack {
                CrosshairMark()
                    .stroke(Color.hex("9A6A22"), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.hex("9A6A22"))
                    .frame(width: 5, height: 5)
            }
        case .context:
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.hex("9A6A22"), lineWidth: 1)
                    .frame(width: 18, height: 10)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.hex("9A6A22"))
                        .frame(width: 2.4, height: 2.4)
                    Rectangle()
                        .fill(Color.hex("9A6A22"))
                        .frame(width: 8, height: 1)
                }
            }
        }
    }
}

// L-shaped corner brackets — viewfinder cue for the screenshot recap.
private struct CrosshairMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len: CGFloat = 5
        let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        p.move(to: CGPoint(x: minX, y: minY + len))
        p.addLine(to: CGPoint(x: minX, y: minY))
        p.addLine(to: CGPoint(x: minX + len, y: minY))
        p.move(to: CGPoint(x: maxX - len, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY + len))
        p.move(to: CGPoint(x: minX, y: maxY - len))
        p.addLine(to: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX + len, y: maxY))
        p.move(to: CGPoint(x: maxX - len, y: maxY))
        p.addLine(to: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: maxX, y: maxY - len))
        return p
    }
}

// MARK: - Feature card (Atlas)

private struct FeatureCard: View {
    enum Glyph { case workflows, context, console, compose, keys, memos }

    let glyph: Glyph
    let name: String
    let state: String
    let action: String
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                // Illustration band
                ZStack {
                    LinearGradient(
                        colors: [Color.hex("FAF6E8"), Color.hex("F4EFE0")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    FeatureGlyphShape(kind: glyph)
                        .frame(width: 56, height: 40)
                }
                .frame(height: 88)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ScopeEdge.subtle).frame(height: 0.5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(LearnFont.display(size: 14, medium: true))
                        .foregroundStyle(ScopeInk.primary)
                        .tracking(-0.2)
                    Text(state.uppercased())
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider().overlay(ScopeEdge.subtle)

                HStack(spacing: 4) {
                    Text(action)
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                    Text("→")
                        .font(.system(size: 11))
                }
                .foregroundStyle(isHovered ? ScopeAmber.solid : Color.hex("9A6A22"))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? ScopeEdge.normal : ScopeEdge.faint, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

// Feature glyphs — tiny illustrations per surface, drawn with Shapes.
private struct FeatureGlyphShape: View {
    let kind: FeatureCard.Glyph

    var body: some View {
        let amber = Color.hex("9A6A22")
        switch kind {
        case .workflows:
            // Node graph: dot · ring · dot
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 12, y: 20)); p.addLine(to: CGPoint(x: 28, y: 10))
                    p.move(to: CGPoint(x: 12, y: 20)); p.addLine(to: CGPoint(x: 28, y: 30))
                    p.move(to: CGPoint(x: 28, y: 10)); p.addLine(to: CGPoint(x: 44, y: 20))
                    p.move(to: CGPoint(x: 28, y: 30)); p.addLine(to: CGPoint(x: 44, y: 20))
                }
                .stroke(amber.opacity(0.6), lineWidth: 1)
                Circle().fill(amber).frame(width: 7, height: 7).offset(x: -16)
                Circle().stroke(amber, lineWidth: 1).frame(width: 6, height: 6).offset(x: 0, y: -10)
                Circle().stroke(amber, lineWidth: 1).frame(width: 6, height: 6).offset(x: 0, y: 10)
                Circle().fill(amber).frame(width: 7, height: 7).offset(x: 16)
            }
        case .context:
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(amber, lineWidth: 1)
                    .frame(width: 36, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(amber.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(amber, lineWidth: 1))
                    .frame(width: 32, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .stroke(amber, lineWidth: 1)
                    .frame(width: 28, height: 8)
            }
        case .console:
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(amber, lineWidth: 1)
                    .frame(width: 44, height: 28)
                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(amber)
                    Rectangle().fill(amber.opacity(0.6)).frame(width: 14, height: 2)
                    Rectangle().fill(amber).frame(width: 6, height: 6)
                }
            }
        case .compose:
            VStack(alignment: .leading, spacing: 4) {
                Rectangle().fill(amber.opacity(0.6)).frame(width: 40, height: 2)
                HStack(spacing: 2) {
                    Rectangle().fill(amber).frame(width: 32, height: 2)
                    Rectangle().fill(amber).frame(width: 2, height: 2)
                }
                Rectangle().fill(amber.opacity(0.4)).frame(width: 20, height: 2)
                Rectangle().fill(amber.opacity(0.6)).frame(width: 36, height: 2)
            }
            .frame(width: 40, height: 28, alignment: .leading)
        case .keys:
            HStack(spacing: 3) {
                ForEach(["⌃", "⇧", "⌘", "S"], id: \.self) { k in
                    Text(k)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(amber)
                        .frame(width: 11, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(amber, lineWidth: 1)
                        )
                }
            }
        case .memos:
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<14, id: \.self) { i in
                    let heights: [CGFloat] = [8, 14, 6, 18, 10, 22, 12, 16, 8, 20, 14, 6, 18, 10]
                    Rectangle()
                        .fill(amber.opacity(0.5 + Double(i % 3) * 0.15))
                        .frame(width: 2, height: heights[i])
                }
            }
        }
    }
}

// MARK: - Provider tile (Integrations)

private struct ProviderTile: View {
    enum Status { case configured, available, soon }

    let name: String
    let category: String
    let status: Status
    let detail: String
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: dotColor.opacity(0.45), radius: 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ScopeInk.primary)
                        Text(category.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    Text("\(statusLabel) · \(detail.uppercased())")
                        .font(ScopeType.chrome)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? ScopeEdge.normal : ScopeEdge.faint, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var dotColor: Color {
        switch status {
        case .configured: return Color.hex("54A06A")
        case .available:  return Color.hex("9A6A22")
        case .soon:       return Color.hex("A8A29E")
        }
    }
    private var statusLabel: String {
        switch status {
        case .configured: return "CONFIGURED"
        case .available:  return "AVAILABLE"
        case .soon:       return "SOON"
        }
    }
}

// MARK: - What's new entries

private struct WhatsNewEntry: Identifiable {
    let id = UUID()
    let date: String
    let title: String

    static let recent: [WhatsNewEntry] = [
        .init(date: "2026-05-17", title: "Bay scheme picker · 4 light-mode schemes (Pearl, Porcelain, Chiffon, Vellum)"),
        .init(date: "2026-05-17", title: "Design Studio · in-repo HTML lab for native app treatments"),
        .init(date: "2026-05-17", title: "Scope Home · reintegrated Routines, Discovery, scheme-aware System Status"),
        .init(date: "2026-05-14", title: "Library readout body system · 3 readout variants"),
    ]
}
