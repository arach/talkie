//
//  OnboardingView.swift
//  Talkie macOS
//
//  Main onboarding flow coordinator view
//

import SwiftUI

struct OnboardingView: View {
    @Bindable private var manager = OnboardingManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDebugToolbar = false
    @State private var keyMonitor: Any? = nil
    @FocusState private var isFocused: Bool

    private var colors: OnboardingColors {
        OnboardingColors.forScheme(colorScheme)
    }

    var body: some View {
        ZStack {
            // Background
            colors.background
                .ignoresSafeArea()

            // Grid pattern
            GridPatternView(lineColor: colors.gridLine)
                .opacity(Opacity.half)

            VStack(spacing: 0) {
                // Top bar - fixed height for consistent layout
                HStack {
                    #if DEBUG
                    // Debug hint (subtle but clickable)
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(Theme.current.fontXS)
                        Text("⌘D")
                            .font(.monoXSmall)
                    }
                    .foregroundColor(colors.textTertiary.opacity(showDebugToolbar ? Opacity.prominent : Opacity.strong))
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(showDebugToolbar ? colors.accent.opacity(Opacity.light) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("Debug button tapped!") // Debug log
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDebugToolbar.toggle()
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .help("Toggle debug navigation (⌘D)")
                    #endif

                    Spacer()

                    Button(action: {
                        manager.completeOnboarding()
                        dismiss()
                    }) {
                        Text("SKIP ONBOARDING")
                            .font(.techLabel)
                            .tracking(Tracking.normal)
                            .foregroundColor(colors.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }
                .frame(height: 44)
                .padding(.horizontal, Spacing.lg)

                // Step content - flexible to fill available space
                // Order: Welcome → LLM Config → Live Mode → Permissions → Model Install → Status Check → Complete
                Group {
                    switch manager.currentStep {
                    case .welcome:
                        WelcomeView(onNext: {
                            manager.currentStep = .llmConfig
                        })
                    case .llmConfig:
                        LLMConfigView(onNext: {
                            manager.currentStep = .liveModePitch
                        })
                    case .liveModePitch:
                        LiveModePitchView(onNext: {
                            manager.currentStep = .permissions
                        })
                    case .permissions:
                        PermissionsSetupView(onNext: {
                            manager.currentStep = .modelInstall
                        })
                    case .modelInstall:
                        ModelInstallView(onNext: {
                            manager.currentStep = .statusCheck
                        })
                    case .statusCheck:
                        StatusCheckView(onNext: {
                            manager.currentStep = .complete
                        })
                    case .complete:
                        CompleteView(onComplete: {
                            manager.completeOnboarding()
                            dismiss()
                        })
                    }
                }
                .frame(maxHeight: .infinity)

                // Navigation - always present for consistent layout
                HStack(spacing: Spacing.lg) {
                    // Back button
                    Button(action: {
                        if let previous = OnboardingStep(rawValue: manager.currentStep.rawValue - 1) {
                            manager.currentStep = previous
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(Theme.current.fontBody)
                            .foregroundColor(colors.textTertiary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .opacity(manager.currentStep != .welcome ? 1 : 0)
                    .disabled(manager.currentStep == .welcome)

                    Spacer()

                    // Page dots with pulsation on current step
                    HStack(spacing: Spacing.xs) {
                        ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                            Circle()
                                .fill(step.rawValue <= manager.currentStep.rawValue ? colors.accent : colors.border)
                                .frame(width: step == manager.currentStep ? 8 : 6, height: step == manager.currentStep ? 8 : 6)
                                .scaleEffect(step == manager.currentStep ? 1.0 : 1.0)
                                .animation(.spring(response: 0.3), value: manager.currentStep)
                        }
                    }
                    .opacity(manager.currentStep != .welcome ? 1 : 0)

                    Spacer()

                    // Empty spacer to maintain layout (debug button removed)
                    Color.clear
                        .frame(width: 40, height: 40)
                }
                .frame(height: 40)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.sm)
            }
        }
        .background(WindowAccessor())
        .onAppear {
            #if DEBUG
            // Set up keyboard shortcut listener
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "d" {
                    print("Cmd+D pressed!") // Debug log
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDebugToolbar.toggle()
                    }
                    return nil // Consume the event
                }
                return event
            }
            #endif
        }
        .onDisappear {
            #if DEBUG
            // Clean up keyboard monitor
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            #endif
        }
        .frame(width: 680, height: 560)
        #if DEBUG
        .overlay(alignment: .bottom) {
            // Debug shelf - overlays the bottom of the window
            if showDebugToolbar {
                DebugShelf(
                    colors: colors,
                    currentStep: $manager.currentStep,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDebugToolbar = false
                        }
                    }
                )
                .frame(width: 680, height: 100)
                .shadow(color: .black.opacity(Opacity.half), radius: Spacing.lg, y: -5)
                .transition(.move(edge: .bottom))
            }
        }
        #endif
    }
}

// MARK: - Debug Shelf

#if DEBUG
private struct DebugShelf: View {
    let colors: OnboardingColors
    @Binding var currentStep: OnboardingStep
    let onClose: () -> Void

    @State private var isGeneratingStoryboard = false
    @State private var storyboardProgress: String = ""

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Header
            HStack {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.techLabelSmall)
                    Text("DEBUG NAVIGATION")
                        .font(Theme.current.fontXSBold)
                        .tracking(Tracking.normal)
                }
                .foregroundColor(colors.textTertiary.opacity(Opacity.half))

                Spacer()

                Text("⌘D to toggle • Jump to any step")
                    .font(Theme.current.fontXS)
                    .foregroundColor(colors.textTertiary.opacity(Opacity.strong))

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.current.fontBody)
                        .foregroundColor(colors.textTertiary.opacity(Opacity.half))
                }
                .buttonStyle(.plain)
                .help("Close (⌘D)")
            }

            // Step buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                        DebugStepButton(
                            colors: colors,
                            step: step,
                            isActive: currentStep == step,
                            action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentStep = step
                                }
                            }
                        )
                    }

                    // Storyboard generator button
                    Divider()
                        .frame(height: 30)
                        .padding(.horizontal, Spacing.xxs)

                    Menu {
                        Button("Generate Now") {
                            Task {
                                await generateStoryboard()
                            }
                        }
                        .disabled(isGeneratingStoryboard)

                        Divider()

                        Button("Copy CLI Command") {
                            let command = "Talkie.app/Contents/MacOS/Talkie --debug=onboarding-storyboard"
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }

                        Button("Show CLI Help") {
                            showCLIHelp()
                        }
                    } label: {
                        VStack(spacing: Spacing.xxs) {
                            if isGeneratingStoryboard {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(Theme.current.fontXSBold)
                            }

                            Text(isGeneratingStoryboard ? "..." : "Storyboard")
                                .font(Theme.current.fontXS)
                        }
                        .foregroundColor(isGeneratingStoryboard ? colors.textTertiary : colors.accent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(colors.surfaceCard)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(isGeneratingStoryboard)
                    .help("Generate storyboard (click for options)")
                }
                .padding(.horizontal, Spacing.xxs)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(
            Rectangle()
                .fill(colors.background)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.border.opacity(Opacity.strong))
                .frame(height: 1)
        }
    }

    private func generateStoryboard() async {
        isGeneratingStoryboard = true
        storyboardProgress = "Preparing..."

        let originalStep = currentStep
        var screenshots: [NSImage] = []

        // Capture each step
        for step in OnboardingStep.allCases {
            storyboardProgress = "Capturing \(step.rawValue + 1)/\(OnboardingStep.allCases.count)..."

            // Switch to the step
            await MainActor.run {
                currentStep = step
            }

            // Wait for view to update
            try? await Task.sleep(for: .milliseconds(300))

            // Capture screenshot
            if let screenshot = await captureOnboardingWindow() {
                screenshots.append(screenshot)
            }
        }

        // Restore original step
        await MainActor.run {
            currentStep = originalStep
        }

        // Composite screenshots with arrows
        if let composite = createStoryboardComposite(screenshots: screenshots) {
            saveStoryboard(composite)
        }

        isGeneratingStoryboard = false
        storyboardProgress = ""
    }

    private func captureOnboardingWindow() async -> NSImage? {
        await MainActor.run {
            // Find the onboarding sheet window
            guard let window = NSApp.windows.first(where: { $0.title == "" && $0.isSheet }) else {
                return nil
            }

            guard let contentView = window.contentView else { return nil }

            let bounds = contentView.bounds
            guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
                return nil
            }

            contentView.cacheDisplay(in: bounds, to: bitmapRep)

            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmapRep)
            return image
        }
    }

    private func createStoryboardComposite(screenshots: [NSImage]) -> NSImage? {
        guard !screenshots.isEmpty else { return nil }

        let arrowWidth: CGFloat = 60
        let spacing: CGFloat = 20
        let imageWidth: CGFloat = 680
        let imageHeight: CGFloat = 560

        let totalWidth = CGFloat(screenshots.count) * imageWidth + CGFloat(screenshots.count - 1) * (arrowWidth + spacing * 2)
        let totalHeight = imageHeight

        let composite = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        composite.lockFocus()

        var xOffset: CGFloat = 0

        for (index, screenshot) in screenshots.enumerated() {
            // Draw screenshot
            screenshot.draw(in: NSRect(x: xOffset, y: 0, width: imageWidth, height: imageHeight))
            xOffset += imageWidth

            // Draw arrow (except after last screenshot)
            if index < screenshots.count - 1 {
                xOffset += spacing
                drawArrow(at: NSRect(x: xOffset, y: imageHeight / 2 - 20, width: arrowWidth, height: 40))
                xOffset += arrowWidth + spacing
            }
        }

        composite.unlockFocus()
        return composite
    }

    private func drawArrow(at rect: NSRect) {
        let path = NSBezierPath()
        let midY = rect.midY

        // Arrow shaft
        path.move(to: NSPoint(x: rect.minX, y: midY))
        path.line(to: NSPoint(x: rect.maxX - 15, y: midY))

        // Arrow head
        path.move(to: NSPoint(x: rect.maxX - 15, y: midY - 10))
        path.line(to: NSPoint(x: rect.maxX, y: midY))
        path.line(to: NSPoint(x: rect.maxX - 15, y: midY + 10))

        NSColor.white.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    private func saveStoryboard(_ image: NSImage) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "onboarding-storyboard-\(timestamp).png"

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileURL = desktopURL.appendingPathComponent(filename)

        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
            print("Storyboard saved to: \(fileURL.path)")

            // Show in Finder
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private func showCLIHelp() {
        let alert = NSAlert()
        alert.messageText = "Debug Commands"
        alert.informativeText = """
        Talkie supports headless debug commands:

        Basic usage:
        Talkie.app/Contents/MacOS/Talkie --debug=<command>

        Generate storyboard:
        --debug=onboarding-storyboard [path]

        Show all commands:
        --debug=help

        Perfect for CI/CD, scripts, and automation!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            let command = "Talkie.app/Contents/MacOS/Talkie --debug=onboarding-storyboard"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}

private struct DebugStepButton: View {
    let colors: OnboardingColors
    let step: OnboardingStep
    let isActive: Bool
    let action: () -> Void

    private var stepName: String {
        switch step {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .modelInstall: return "Models"
        case .llmConfig: return "LLM"
        case .liveModePitch: return "Live"
        case .statusCheck: return "Status"
        case .complete: return "Complete"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {
                Text("\(step.rawValue + 1)")
                    .font(.techLabelSmall)
                    .foregroundColor(isActive ? .white : colors.textSecondary)

                Text(stepName)
                    .font(Theme.current.fontXS)
                    .foregroundColor(isActive ? .white : colors.textTertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isActive ? colors.accent : colors.surfaceCard)
            )
        }
        .buttonStyle(.plain)
    }
}
#endif

#Preview("Light") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
