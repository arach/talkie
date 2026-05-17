# Complications → SwiftUI port spec

**Status:** drafted while Codex scaffolds Phase 0
**Target files** (Codex creates the empty stubs; this doc fills the bodies):

- `apps/ios/Talkie iOS/Views/Next/AppShellNext.swift`
- `apps/ios/Talkie iOS/Views/Next/VoicePivotButton.swift`
- `apps/ios/Talkie iOS/Views/Next/ChromeOverlay.swift`
- `apps/ios/Talkie iOS/Views/Next/ListeningBubble.swift`

**Visual reference:** `http://localhost:3000/complications` (3 states:
resting / expanded / listening).

**Design rationale:** see `design/studio/app/complications/NOTES.md`.
The state model is locked: one ambient bottom-left voice button, tap
to summon chrome, long-press the lit button to enter walkie-talkie
listening, release to send.

---

## State model

```swift
// Lives on AppShellNext as @State; passed down to children via env.
enum ShellChromeState: Equatable {
    case resting        // content full-bleed, only voice button visible
    case expanded       // chrome (corners + tray) fading in
    case listening      // voice button pulsing, listening bubble above
}
```

Transitions:
- Quick tap on voice button while `.resting` → `.expanded` (300ms easeOut)
- Quick tap on voice button while `.expanded` → `.resting` (200ms easeIn — tap-away closes)
- Long-press start (≥350ms) on voice button while `.expanded` → `.listening`
- Long-press end while `.listening` → `.expanded` (and the captured audio fires whatever command-handler is wired in M2)
- Tap on any chrome action (Done / Settings / Camera / Mic / Compose / Keyboard / Share) → handler fires; chrome stays open

A `@StateObject` `ShellChrome` ObservableObject holds the state +
exposes mutators. Lives in AppShellNext, injected via
`.environmentObject` so VoicePivotButton + ChromeOverlay both read it.

---

## AppShellNext.swift

```swift
import SwiftUI

/// Root container for every "Next" screen. Provides the universal
/// voice-pivot button + summon-on-demand chrome over arbitrary content.
struct AppShellNext<Content: View>: View {
    @StateObject private var chrome = ShellChrome()
    @Environment(\.scopeTheme) private var theme   // existing theme env or wherever ThemeManager publishes

    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            // Page content — fills the screen at all times.
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Chrome overlay (corners + tray) — fades in when expanded.
            ChromeOverlay()
                .opacity(chrome.state == .resting ? 0 : 1)
                .allowsHitTesting(chrome.state != .resting)
                .animation(.easeOut(duration: 0.28), value: chrome.state)

            // Listening bubble — only in .listening.
            if chrome.state == .listening {
                ListeningBubble()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // The ambient voice button — always visible.
            VoicePivotButton()
        }
        .environmentObject(chrome)
        .background(theme.colors.background.ignoresSafeArea())
    }
}

/// Observable state for the shell's chrome system. Exposes a small
/// API; view code never mutates `state` directly.
final class ShellChrome: ObservableObject {
    @Published private(set) var state: ShellChromeState = .resting

    func tapVoiceButton() {
        switch state {
        case .resting:   withAnimation(.easeOut(duration: 0.28)) { state = .expanded }
        case .expanded:  withAnimation(.easeIn(duration: 0.20))  { state = .resting }
        case .listening: break  // long-press end handles return
        }
    }

    func longPressBegan() {
        guard state == .expanded else { return }
        withAnimation(.easeOut(duration: 0.18)) { state = .listening }
    }

    func longPressEnded() {
        guard state == .listening else { return }
        // TODO M2: fire captured-audio handler here.
        withAnimation(.easeIn(duration: 0.18)) { state = .expanded }
    }

    func dismissChrome() {
        withAnimation(.easeIn(duration: 0.20)) { state = .resting }
    }
}
```

---

## VoicePivotButton.swift

```swift
import SwiftUI

/// Bottom-left ambient button. Three visual states tied to ShellChrome.
struct VoicePivotButton: View {
    @EnvironmentObject private var chrome: ShellChrome
    @Environment(\.scopeTheme) private var theme

    // Long-press detection — 0.35s threshold matches iOS context-menu feel
    // without being so short that a slow tap accidentally triggers it.
    private let longPressThreshold: Double = 0.35
    @State private var pressing = false

    var body: some View {
        Button(action: { chrome.tapVoiceButton() }) {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .overlay(
                        Circle()
                            .strokeBorder(buttonBorder, lineWidth: buttonBorderWidth)
                    )
                    .overlay(
                        // Brass ring halo when expanded
                        Circle()
                            .strokeBorder(theme.chrome.accentSoft, lineWidth: 3)
                            .blur(radius: 0.5)
                            .opacity(chrome.state == .expanded ? 1 : 0)
                            .scaleEffect(chrome.state == .expanded ? 1.18 : 1.0)
                            .animation(.easeOut(duration: 0.25), value: chrome.state)
                    )
                    .shadow(
                        color: shadowColor,
                        radius: shadowRadius,
                        x: 0, y: shadowYOffset
                    )

                VoiceCmdGlyph()
                    .foregroundStyle(glyphColor)
            }
            .frame(width: 48, height: 48)
            .scaleEffect(chrome.state == .listening ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressThreshold)
                .onEnded { _ in chrome.longPressBegan() }
        )
        // While pressing & in listening state, we need release-to-end.
        // SwiftUI's LongPressGesture doesn't expose release directly;
        // pair it with a DragGesture(minimumDistance: 0) sentinel:
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressing { pressing = true } }
                .onEnded { _ in
                    pressing = false
                    if chrome.state == .listening { chrome.longPressEnded() }
                }
        )
        .position(buttonPosition)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to summon controls. Long-press to talk.")
    }

    // MARK: - Visual state derivation

    private var buttonFill: Color {
        // Listening = filled brass, else = paper.
        chrome.state == .listening
            ? theme.chrome.accent
            : theme.colors.cardBackground
    }

    private var buttonBorder: Color {
        switch chrome.state {
        case .resting:   return theme.chrome.edgeFaint
        case .expanded:  return theme.chrome.accentSoft
        case .listening: return theme.chrome.accentSoft
        }
    }

    private var buttonBorderWidth: CGFloat {
        chrome.state == .resting ? 0.5 : 1.0
    }

    private var glyphColor: Color {
        switch chrome.state {
        case .resting:   return theme.colors.textSecondary
        case .expanded:  return theme.chrome.accent
        case .listening: return theme.colors.cardBackground  // inverse on filled
        }
    }

    private var shadowColor: Color {
        switch chrome.state {
        case .resting:   return Color.black.opacity(0.10)
        case .expanded:  return theme.chrome.accentGlow
        case .listening: return theme.chrome.accentGlow
        }
    }

    private var shadowRadius: CGFloat {
        switch chrome.state {
        case .resting:   return 4
        case .expanded:  return 8
        case .listening: return 14
        }
    }

    private var shadowYOffset: CGFloat { 2 }

    private var buttonPosition: CGPoint {
        // 20pt from left, 22pt from bottom of safe area.
        // Resolved per-screen via GeometryReader inside the parent ZStack;
        // simpler: use a leading-bottom alignment guide. Refactor if needed.
        CGPoint(x: 20 + 24, y: UIScreen.main.bounds.height - 22 - 24)
    }

    private var accessibilityLabel: String {
        switch chrome.state {
        case .resting:   return "Summon Talkie controls"
        case .expanded:  return "Hold to talk"
        case .listening: return "Listening — release to send"
        }
    }
}

/// Voice-command glyph — bracket waves with center dot. Matches the
/// studio's VoiceCmdGlyph SVG.
private struct VoiceCmdGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 16   // 16pt design grid
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineWidth: CGFloat = 1.1 * s

            // Outer brackets — left arc + right arc
            var outerLeft = Path()
            outerLeft.addArc(
                center: CGPoint(x: center.x - 4 * s, y: center.y),
                radius: 5 * s,
                startAngle: .degrees(135), endAngle: .degrees(-135),
                clockwise: false
            )
            ctx.stroke(outerLeft, with: .foreground, lineWidth: lineWidth)

            var outerRight = Path()
            outerRight.addArc(
                center: CGPoint(x: center.x + 4 * s, y: center.y),
                radius: 5 * s,
                startAngle: .degrees(45), endAngle: .degrees(-45),
                clockwise: true
            )
            ctx.stroke(outerRight, with: .foreground, lineWidth: lineWidth)

            // Inner brackets
            var innerLeft = Path()
            innerLeft.addArc(
                center: CGPoint(x: center.x - 2 * s, y: center.y),
                radius: 2.5 * s,
                startAngle: .degrees(135), endAngle: .degrees(-135),
                clockwise: false
            )
            ctx.stroke(innerLeft, with: .foreground, lineWidth: lineWidth)

            var innerRight = Path()
            innerRight.addArc(
                center: CGPoint(x: center.x + 2 * s, y: center.y),
                radius: 2.5 * s,
                startAngle: .degrees(45), endAngle: .degrees(-45),
                clockwise: true
            )
            ctx.stroke(innerRight, with: .foreground, lineWidth: lineWidth)

            // Center dot
            let dot = Path(ellipseIn: CGRect(
                x: center.x - 1.3 * s, y: center.y - 1.3 * s,
                width: 2.6 * s, height: 2.6 * s
            ))
            ctx.fill(dot, with: .foreground)
        }
        .frame(width: 16, height: 16)
    }
}
```

---

## ChromeOverlay.swift

```swift
import SwiftUI

/// The summoned chrome layer. Four corner slots (Done · Settings ·
/// Keyboard · Share) + a bottom liquid-glass tray (Camera · Mic FAB ·
/// Compose). Voice button lives separately in AppShellNext; this
/// layer leaves space for it (bottom-left is omitted from the corner
/// slots since that's the voice button's home).
struct ChromeOverlay: View {
    @EnvironmentObject private var chrome: ShellChrome
    @Environment(\.scopeTheme) private var theme

    var body: some View {
        ZStack {
            cornerSlot(.topLeading,    glyph: AnyView(DoneGlyph()),    label: "Done")    { dismiss() }
            cornerSlot(.topTrailing,   glyph: AnyView(SettingsGlyph()), label: "Settings") { }
            cornerSlot(.bottomTrailing, glyph: AnyView(KeyboardGlyph()), label: "Keyboard") { }
            // bottom-left intentionally empty — voice button lives there

            liquidGlassTray
        }
    }

    private func cornerSlot(
        _ alignment: Alignment,
        glyph: AnyView,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground)
                    .overlay(Circle().strokeBorder(theme.chrome.edgeFaint, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                glyph.foregroundStyle(theme.colors.textSecondary)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(.horizontal, 20)
        .padding(.top, 50)        // below the status bar
        .padding(.bottom, 28)
    }

    private var liquidGlassTray: some View {
        HStack(spacing: 18) {
            TraySlot(glyph: AnyView(CameraGlyph()), label: "Camera")  { }
            TrayFAB()
            TraySlot(glyph: AnyView(ComposeGlyph()), label: "Compose") { }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Liquid-glass: tinted translucent + backdrop blur
                Capsule()
                    .fill(theme.colors.cardBackground.opacity(0.70))
                    .background(.ultraThinMaterial, in: Capsule())
                Capsule()
                    .strokeBorder(theme.chrome.edgeFaint, lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 22)
    }

    private func dismiss() {
        chrome.dismissChrome()
    }
}

private struct TraySlot: View {
    let glyph: AnyView
    let label: String
    let action: () -> Void
    @Environment(\.scopeTheme) private var theme

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct TrayFAB: View {
    @Environment(\.scopeTheme) private var theme

    var body: some View {
        Button(action: {}) {
            ZStack {
                Circle().fill(theme.chrome.accent)
                MicGlyph()
                    .foregroundStyle(theme.colors.cardBackground)
            }
            .frame(width: 48, height: 48)
            .shadow(color: theme.chrome.accentGlow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record memo")
    }
}

// Corner glyphs — sized to ~16pt. Match the studio's stroke weights.
private struct DoneGlyph: View {
    var body: some View {
        Image(systemName: "chevron.left")
            .font(.system(size: 15, weight: .medium))
    }
}
private struct SettingsGlyph: View {
    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 15, weight: .regular))
    }
}
private struct KeyboardGlyph: View {
    var body: some View {
        Image(systemName: "keyboard")
            .font(.system(size: 13, weight: .regular))
    }
}
private struct CameraGlyph: View {
    var body: some View {
        Image(systemName: "camera")
            .font(.system(size: 15, weight: .regular))
    }
}
private struct ComposeGlyph: View {
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 13, weight: .regular))
    }
}
private struct MicGlyph: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 22, weight: .medium))
    }
}
```

---

## ListeningBubble.swift

```swift
import SwiftUI

/// The "HOLD · LISTENING" bubble that floats above the voice button
/// during the listening state. Live waveform on the left, smallcap
/// label, captured-command snippet (placeholder for now; M2 wires the
/// real transcription).
struct ListeningBubble: View {
    @Environment(\.scopeTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            WaveformBars()
                .frame(width: 16, height: 16)
            Text("Hold · Listening")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.8)        // ~0.20em at 9pt
                .foregroundStyle(theme.chrome.accent)
            Text("\"tighten the second paragraph…\"")
                .font(.system(size: 13, design: .default))
                .italic()
                .foregroundStyle(theme.colors.textPrimary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground.opacity(0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.chrome.accentSoft, lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 84)   // above the voice button (button bottom 22 + height 48 + gap 14)
    }
}

/// Four pulsing waveform bars. The cadence matches the studio:
/// staggered ease-in-out, ~1.2s cycle.
private struct WaveformBars: View {
    @State private var phase: Double = 0

    private let bars: [CGFloat] = [6, 10, 8, 14]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(bars.indices, id: \.self) { i in
                    let phase = sin(t * 2 * .pi / 1.2 + Double(i) * 0.6)
                    let scale = 0.55 + (phase + 1) / 2 * 0.45
                    Capsule()
                        .frame(width: 2, height: bars[i] * scale)
                }
            }
            .frame(width: 16, height: 16, alignment: .center)
            .foregroundStyle(.tint)
        }
        .tint(Color(red: 0.769, green: 0.490, blue: 0.110))   // brass; pull from theme.chrome.accent at the call site if needed
    }
}
```

---

## HomeNextStub.swift

```swift
import SwiftUI

/// Placeholder Home content for Phase 0 — replaced by HomeNextView
/// in M1 (see design/studio/app/home/SWIFT_PORT.md).
struct HomeNextStub: View {
    @Environment(\.scopeTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text("TALKIE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(3.5)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.7))

            Text("Home · soon")
                .font(.system(size: 14, design: .default))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

---

## Wiring notes for Codex's scaffolding pass

These are things the scaffolding needs to handle so the view code
above compiles:

1. **`@Environment(\.scopeTheme)`** — there's probably an existing
   `EnvironmentKey` for the active theme. If not, Codex should add
   one that exposes the resolved `ThemeColors` + `ChromeTokens` for
   the currently-selected theme. (Names in the spec are placeholders;
   match whatever ThemeManager exposes.)

2. **`ChromeTokens.accentSoft`** — referenced above; if the field
   doesn't exist on `ChromeTokens`, alias it to `accent.opacity(0.32)`
   in the bridge layer.

3. **`Color` extensions** — if Talkie uses hex strings, make sure
   `Color(hex:)` is available in the Next/ context.

4. **AppShellNext init** — `@ViewBuilder` content closure is
   parameter-less (`() -> Content`). The scaffolding signature must
   match the call in `talkieApp.swift:75`:
   `AppShellNext { HomeNextStub() }`.

5. **Position math** — `VoicePivotButton`'s position currently uses
   `UIScreen.main.bounds.height` for simplicity. A GeometryReader-
   based positioning is cleaner; refactor if Codex finds the screen
   bounds approach fragile across device sizes / safe areas.

## Cut criteria

Phase 0 is done when the build succeeds AND the manual gesture flow
works end-to-end on the simulator:

- App launches → ambient voice button visible bottom-left
- Tap button → chrome fades in (corners + tray); button gets brass ring
- Long-press the lit button → listening bubble fades in with animated waveform
- Release → bubble fades out; chrome stays
- Tap "Done" (top-left chevron) → chrome dismisses; back to resting

All 5 themes (Scope · Midnight · Tactical · Ghost · Lift) repaint
the shell correctly with their accent + paper tokens.
