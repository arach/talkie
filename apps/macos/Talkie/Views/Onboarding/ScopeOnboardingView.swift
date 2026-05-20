//
//  ScopeOnboardingView.swift
//  Talkie
//
//  Editorial first-launch onboarding. Four ceremonial chapters:
//  Frontispiece → Permissions → Models → Ready.
//
//  Studio source of truth:
//    design/studio/app/mac-onboarding/page.tsx
//
//  Visual-first port. Permission grant buttons + model picks call into
//  existing services where wired, otherwise stub to next step so the
//  flow is walkable end-to-end for visual sign-off before the real
//  plumbing lands.
//
//  Activated via the `useScopeOnboarding` defaults flag. Original
//  OnboardingCoordinator + ProOnboardingView remain available as
//  fallbacks until this lands as the canonical flow.
//

import SwiftUI
import AVFoundation
import AppKit

// MARK: - Entry

struct ScopeOnboardingView: View {
    @State private var step: Step = .frontispiece
    @State private var didGrantMic: Bool = false
    @State private var didGrantAccessibility: Bool = false
    @State private var didGrantScreen: Bool = false

    // Polling tasks — started when the user clicks GRANT, stopped when
    // the matching permission flips to granted or 90s elapses.
    // Mirrors the proven PermissionsSettings pattern.
    @State private var accessibilityPollTask: Task<Void, Never>?
    @State private var screenPollTask: Task<Void, Never>?

    var onFinish: () -> Void = {}

    enum Step: Int, CaseIterable {
        case frontispiece, permissions, models, ready

        var label: String {
            switch self {
            case .frontispiece: return "I"
            case .permissions:  return "II"
            case .models:       return "III"
            case .ready:        return "IV"
            }
        }

        var index: Int { rawValue }
    }

    var body: some View {
        ZStack {
            ScopeOnboardingTokens.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                switch step {
                case .frontispiece:
                    Frontispiece(advance: advance)
                case .permissions:
                    Permissions(
                        didGrantMic: $didGrantMic,
                        didGrantAccessibility: $didGrantAccessibility,
                        didGrantScreen: $didGrantScreen,
                        advance: advance,
                        back: back,
                        startAccessibilityPolling: startAccessibilityPolling,
                        startScreenPolling: startScreenPolling
                    )
                case .models:
                    Models(advance: advance, back: back, onFinish: onFinish)
                case .ready:
                    Ready(finish: { onFinish() }, back: back)
                }
            }
            .frame(maxWidth: 880, maxHeight: 600)
        }
        .background(KeyboardEnterMonitor(onEnter: handleEnter))
        .onAppear { refreshGrantedState() }
        .onDisappear {
            accessibilityPollTask?.cancel()
            screenPollTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            refreshGrantedState()
        }
    }

    /// Re-checks system permission state. Called on view appear and
    /// whenever the app regains focus (e.g., user returns from System
    /// Settings after granting through the install assistant).
    private func refreshGrantedState() {
        didGrantMic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        didGrantAccessibility = AXIsProcessTrusted()
        didGrantScreen = CGPreflightScreenCaptureAccess()
    }

    /// Starts a 90-second polling loop that checks accessibility
    /// trust every 0.5s. macOS doesn't always notify the app when the
    /// user toggles trust in System Settings, so we have to ask.
    /// Matches the proven `PermissionsSettings` flow.
    @MainActor
    private func startAccessibilityPolling() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(90)
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                if AXIsProcessTrusted() {
                    didGrantAccessibility = true
                    return
                }
            }
        }
    }

    @MainActor
    private func startScreenPolling() {
        screenPollTask?.cancel()
        screenPollTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(90)
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                if CGPreflightScreenCaptureAccess() {
                    didGrantScreen = true
                    return
                }
            }
        }
    }

    // MARK: Step transitions

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        withAnimation(.easeInOut(duration: 0.28)) { step = next }
    }

    private func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.28)) { step = prev }
    }

    private func handleEnter() {
        switch step {
        case .frontispiece, .ready: advance()
        default: break
        }
    }
}

// MARK: - Step Bar

private struct StepBar: View {
    let active: ScopeOnboardingView.Step

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScopeOnboardingView.Step.allCases, id: \.rawValue) { s in
                let isActive = s == active
                let isPast = s.rawValue < active.rawValue

                Text(s.label)
                    .font(ScopeOnboardingFonts.mono(size: 9))
                    .tracking(2.6)
                    .foregroundColor(
                        isActive ? ScopeOnboardingTokens.ink
                        : isPast ? ScopeOnboardingTokens.amber
                        : ScopeOnboardingTokens.inkFainter
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Rectangle()
                            .fill(isActive
                                  ? ScopeOnboardingTokens.ink
                                  : ScopeOnboardingTokens.inkFainter.opacity(0.4))
                            .frame(height: 2)
                            .padding(.top, 30),
                        alignment: .bottom
                    )
            }
        }
        .padding(.horizontal, 36)
        .overlay(
            Rectangle()
                .fill(ScopeOnboardingTokens.inkRule.opacity(0.55))
                .frame(height: 0.5),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .fill(ScopeOnboardingTokens.inkRule.opacity(0.55))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

// MARK: - Step Footer

private struct StepFooter: View {
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var onContinue: (() -> Void)?
    var continueLabel: String = "CONTINUE"
    var skipLabel: String = "DO LATER"

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Text("← BACK")
                        .font(ScopeOnboardingFonts.mono(size: 10))
                        .tracking(2.2)
                        .foregroundColor(ScopeOnboardingTokens.inkFaint)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 18) {
                if let onSkip {
                    Button(action: onSkip) {
                        Text(skipLabel)
                            .font(ScopeOnboardingFonts.mono(size: 10))
                            .tracking(2.2)
                            .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
                if let onContinue {
                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Text(continueLabel)
                                .font(ScopeOnboardingFonts.mono(size: 10))
                                .tracking(2.2)
                            Text("→")
                        }
                        .foregroundColor(ScopeOnboardingTokens.cream)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ScopeOnboardingTokens.ink)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .overlay(
            Rectangle()
                .fill(ScopeOnboardingTokens.inkRule.opacity(0.55))
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

// MARK: - Step I · Frontispiece

private struct Frontispiece: View {
    let advance: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepBar(active: .frontispiece)

            VStack(spacing: 0) {
                Text("· TALKIE ·")
                    .font(ScopeOnboardingFonts.mono(size: 10))
                    .tracking(4.4)
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)

                Text("Talkie.")
                    .font(ScopeOnboardingFonts.serif(size: 110))
                    .tracking(-4.5)
                    .foregroundColor(ScopeOnboardingTokens.ink)
                    .padding(.top, 36)

                Text("A quiet desk for memos, dictations, and notes. Voice in, editorial out.")
                    .font(ScopeOnboardingFonts.serifItalic(size: 19))
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, 28)
                    .lineSpacing(4)

                HStack(spacing: 12) {
                    Text("PRESS")
                    Text("↵")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ScopeOnboardingTokens.paper)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ScopeOnboardingTokens.edge, lineWidth: 0.5)
                                )
                        )
                        .foregroundColor(ScopeOnboardingTokens.ink)
                    Text("TO BEGIN")
                }
                .font(ScopeOnboardingFonts.mono(size: 10))
                .tracking(2.8)
                .foregroundColor(ScopeOnboardingTokens.inkFainter)
                .padding(.top, 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)

            StepFooter(onContinue: advance, continueLabel: "BEGIN")
        }
    }
}

// MARK: - Step II · Permissions

private struct Permissions: View {
    @Binding var didGrantMic: Bool
    @Binding var didGrantAccessibility: Bool
    @Binding var didGrantScreen: Bool
    let advance: () -> Void
    let back: () -> Void
    let startAccessibilityPolling: () -> Void
    let startScreenPolling: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepBar(active: .permissions)

            VStack(alignment: .leading, spacing: 0) {
                Text("· PERMISSIONS")
                    .font(ScopeOnboardingFonts.mono(size: 10))
                    .tracking(3.6)
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)

                Text("What Talkie needs to work")
                    .font(ScopeOnboardingFonts.serif(size: 32))
                    .tracking(-0.5)
                    .foregroundColor(ScopeOnboardingTokens.ink)
                    .padding(.top, 12)

                Text("Two required, one optional. Grant them now and we're done.")
                    .font(ScopeOnboardingFonts.serifItalic(size: 15))
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    PermissionRow(
                        title: "Microphone",
                        why: "to record your voice for memos and dictations.",
                        kind: .required,
                        granted: didGrantMic,
                        action: {
                            Task {
                                let ok = await AVCaptureDevice.requestAccess(for: .audio)
                                await MainActor.run { didGrantMic = ok }
                            }
                        }
                    )
                    Divider().background(ScopeOnboardingTokens.inkRule.opacity(0.35))
                    PermissionRow(
                        title: "Accessibility",
                        why: "to type dictation into the focused app and listen for global shortcuts.",
                        kind: .required,
                        granted: didGrantAccessibility,
                        action: {
                            AccessibilityInstallAssistant.shared
                                .present(target: .talkie, permission: .accessibility)
                            startAccessibilityPolling()
                        }
                    )
                    Divider().background(ScopeOnboardingTokens.inkRule.opacity(0.35))
                    PermissionRow(
                        title: "Screen Recording",
                        why: "to capture screenshots when you press ⇧⌃⌥⌘ S. Optional — Talkie works without it.",
                        kind: .optional,
                        granted: didGrantScreen,
                        action: {
                            AccessibilityInstallAssistant.shared
                                .present(target: .talkie, permission: .screenRecording)
                            startScreenPolling()
                        }
                    )
                }
                .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StepFooter(onBack: back, onSkip: advance, onContinue: advance)
        }
    }
}

private struct PermissionRow: View {
    enum Kind { case required, optional }
    let title: String
    let why: String
    let kind: Kind
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(ScopeOnboardingFonts.serif(size: 18))
                        .foregroundColor(ScopeOnboardingTokens.ink)
                    if kind == .optional {
                        Text("· OPTIONAL")
                            .font(ScopeOnboardingFonts.mono(size: 9))
                            .tracking(2.2)
                            .foregroundColor(ScopeOnboardingTokens.inkFainter)
                    }
                    if granted {
                        Text("· GRANTED")
                            .font(ScopeOnboardingFonts.mono(size: 9))
                            .tracking(2.2)
                            .foregroundColor(ScopeOnboardingTokens.amber)
                    }
                }
                Text(why)
                    .font(ScopeOnboardingFonts.serifItalic(size: 14))
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    .lineSpacing(3)
            }

            Spacer()

            Button(action: action) {
                Text(granted ? "✓ GRANTED" : "GRANT →")
                    .font(ScopeOnboardingFonts.mono(size: 9.5))
                    .tracking(2.4)
                    .foregroundColor(ScopeOnboardingTokens.amber)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ScopeOnboardingTokens.amberTint)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(ScopeOnboardingTokens.amber, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(granted)
        }
        .padding(.vertical, 18)
    }
}

// MARK: - Step III · Models

private struct Models: View {
    let advance: () -> Void
    let back: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepBar(active: .models)

            VStack(alignment: .leading, spacing: 0) {
                Text("· MODELS")
                    .font(ScopeOnboardingFonts.mono(size: 10))
                    .tracking(3.6)
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)

                Text("Voice in, AI commands optional")
                    .font(ScopeOnboardingFonts.serif(size: 32))
                    .tracking(-0.5)
                    .foregroundColor(ScopeOnboardingTokens.ink)
                    .padding(.top, 12)

                Text("Talkie needs a speech-to-text model to hear you. An LLM is only required for AI commands in Compose.")
                    .font(ScopeOnboardingFonts.serifItalic(size: 15))
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    .padding(.top, 8)
                    .lineSpacing(3)
                    .frame(maxWidth: 620, alignment: .leading)

                VStack(spacing: 18) {
                    ModelBlock(
                        eyebrow: "· VOICE · REQUIRED",
                        title: "Parakeet v3",
                        byline: "0.6 GB · runs locally · no network",
                        status: .ready,
                        action: nil
                    )
                    ModelBlock(
                        eyebrow: "· COMMANDS · OPTIONAL",
                        title: "Connect to ChatGPT",
                        byline: "OpenRouter, Anthropic, Gemini and others supported. Bring your own key — Talkie doesn't proxy.",
                        status: .skipAvailable,
                        action: ModelAction(label: "CONNECT →", onTap: {
                            onFinish()
                            NavigationState.shared.navigate(to: .settings)
                        })
                    )
                }
                .padding(.top, 28)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StepFooter(onBack: back, onContinue: advance)
        }
    }
}

private struct ModelAction {
    let label: String
    let onTap: () -> Void
}

private struct ModelBlock: View {
    enum Status { case ready, downloading(progress: Double), skipAvailable }
    let eyebrow: String
    let title: String
    let byline: String
    let status: Status
    let action: ModelAction?

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(eyebrow)
                        .font(ScopeOnboardingFonts.mono(size: 9))
                        .tracking(2.6)
                        .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    if action == nil {
                        Spacer()
                        statusBadge
                    }
                }
                Text(title)
                    .font(ScopeOnboardingFonts.serif(size: 22))
                    .foregroundColor(ScopeOnboardingTokens.ink)
                Text(byline)
                    .font(ScopeOnboardingFonts.serifItalic(size: 13))
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    .lineSpacing(2)
            }
            if let action {
                Spacer()
                Button(action: action.onTap) {
                    Text(action.label)
                        .font(ScopeOnboardingFonts.mono(size: 9.5))
                        .tracking(2.4)
                        .foregroundColor(ScopeOnboardingTokens.amber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ScopeOnboardingTokens.amberTint)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(ScopeOnboardingTokens.amber, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(ScopeOnboardingTokens.edge, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .ready:
            Text("✓ READY")
                .font(ScopeOnboardingFonts.mono(size: 9))
                .tracking(2.2)
                .foregroundColor(ScopeOnboardingTokens.amber)
        case .downloading(let p):
            Text("DOWNLOADING · \(Int(p * 100))%")
                .font(ScopeOnboardingFonts.mono(size: 9))
                .tracking(2.2)
                .foregroundColor(ScopeOnboardingTokens.brass)
        case .skipAvailable:
            Text("SKIP FOR NOW")
                .font(ScopeOnboardingFonts.mono(size: 9))
                .tracking(2.2)
                .foregroundColor(ScopeOnboardingTokens.inkFaint)
        }
    }
}

// MARK: - Step IV · Ready

private struct Ready: View {
    let finish: () -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepBar(active: .ready)

            VStack(spacing: 0) {
                Text("· READY")
                    .font(ScopeOnboardingFonts.mono(size: 10))
                    .tracking(4.4)
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)

                Text("You're set.")
                    .font(ScopeOnboardingFonts.serif(size: 64))
                    .tracking(-2.5)
                    .foregroundColor(ScopeOnboardingTokens.ink)
                    .padding(.top, 30)

                Text("Tap the TALKIE pill in the window chrome or press ⌘ N to start your first memo.")
                    .font(ScopeOnboardingFonts.serifItalic(size: 17))
                    .foregroundColor(ScopeOnboardingTokens.inkFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .padding(.top, 22)
                    .lineSpacing(4)

                HStack(spacing: 16) {
                    KeyCap("⌘")
                    KeyCap("N")
                    Text("·")
                        .foregroundColor(ScopeOnboardingTokens.inkFainter)
                    Text("NEW MEMO")
                        .font(ScopeOnboardingFonts.mono(size: 10))
                        .tracking(2.8)
                        .foregroundColor(ScopeOnboardingTokens.inkFainter)
                }
                .padding(.top, 50)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)

            StepFooter(onBack: back, onContinue: finish, continueLabel: "OPEN TALKIE")
        }
    }
}

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(ScopeOnboardingFonts.mono(size: 13))
            .foregroundColor(ScopeOnboardingTokens.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(ScopeOnboardingTokens.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(ScopeOnboardingTokens.edge, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Keyboard ↵ monitor

private struct KeyboardEnterMonitor: NSViewRepresentable {
    let onEnter: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onEnter = onEnter
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyView)?.onEnter = onEnter
    }

    private final class KeyView: NSView {
        var onEnter: () -> Void = {}
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            // ↵ = 36
            if event.keyCode == 36 { onEnter() } else { super.keyDown(with: event) }
        }
    }
}

// MARK: - Tokens

private enum ScopeOnboardingTokens {
    static let cream       = Color(red: 0.984, green: 0.984, blue: 0.980)
    static let paper       = Color(red: 0.957, green: 0.945, blue: 0.918)
    static let ink         = Color(red: 0.165, green: 0.149, blue: 0.125)
    static let inkFaint    = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.55)
    static let inkFainter  = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.32)
    static let inkRule     = Color(red: 0.165, green: 0.149, blue: 0.125).opacity(0.18)
    static let amber       = Color(red: 0.769, green: 0.490, blue: 0.110)
    static let amberTint   = Color(red: 0.769, green: 0.490, blue: 0.110).opacity(0.08)
    static let brass       = Color(red: 0.604, green: 0.416, blue: 0.133)
    static let edge        = Color(red: 0.878, green: 0.863, blue: 0.827)
}

// MARK: - Fonts

private enum ScopeOnboardingFonts {
    static func serif(size: CGFloat) -> Font {
        for name in ["Newsreader-Regular", "Newsreader"] {
            if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        }
        return .system(size: size, weight: .regular, design: .serif)
    }
    static func serifItalic(size: CGFloat) -> Font {
        for name in ["Newsreader-Italic", "Newsreader-RegularItalic"] {
            if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        }
        return Font.custom("Newsreader-Regular", size: size).italic()
    }
    static func mono(size: CGFloat) -> Font {
        for name in ["JetBrainsMono-SemiBold", "JetBrainsMono-Medium"] {
            if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }
}
