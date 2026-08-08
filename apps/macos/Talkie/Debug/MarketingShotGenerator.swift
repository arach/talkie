//
//  MarketingShotGenerator.swift
//  Talkie macOS
//
//  Captures the core screens across every curated theme, for the website.
//
//  This renders each screen into its own offscreen window rather than driving
//  the live app, so a run is deterministic: no clicking, no coordinates, no
//  dependence on which section the user happened to leave open. The same
//  primitive ConsoleScreenshotGenerator uses, widened to a matrix.
//
//  Usage: Talkie.app/Contents/MacOS/Talkie --debug=marketing-shots [outputDir]
//

import AppKit
import SwiftUI
import TalkieKit

/// One screen in the inventory. `slug` names the file; ordering is the order
/// a visitor would meet these screens on the site, not the sidebar's order.
struct MarketingShot {
    let slug: String
    let title: String
    let section: NavigationSection
    let settingsSection: SettingsSection

    init(
        _ slug: String,
        _ title: String,
        _ section: NavigationSection,
        settingsSection: SettingsSection = .about
    ) {
        self.slug = slug
        self.title = title
        self.section = section
        self.settingsSection = settingsSection
    }
}

@MainActor
final class MarketingShotGenerator {
    static let shared = MarketingShotGenerator()

    private init() {}

    /// The core pages. Deliberately short — these are the screens that explain
    /// what Talkie is, not every surface it has.
    static let shots: [MarketingShot] = [
        MarketingShot("home", "Home", .home),
        MarketingShot("library", "Library", .recordings),
        MarketingShot("editor", "Editor", .markdownStudio),
        MarketingShot("markup", "Markup", .screenshots),
        MarketingShot("workflows", "Workflows", .workflows),
        MarketingShot("console", "Console", .systemConsole),
        MarketingShot("settings", "Settings", .settings, settingsSection: .appearance),
    ]

    /// Every curated theme. `ThemePreset.allCases` is the source of truth —
    /// adding a fourth preset adds a fourth style to the inventory for free.
    static var themes: [ThemePreset] { ThemePreset.allCases }

    static let defaultSize = CGSize(width: 1440, height: 900)

    // MARK: - Run

    /// Captures shots × themes into `outputDir`, then puts the user's own
    /// appearance settings back exactly as they were.
    @discardableResult
    func captureAll(
        to outputDir: URL,
        size: CGSize = MarketingShotGenerator.defaultSize
    ) async -> [URL] {
        let settings = SettingsManager.shared

        // applyTheme() writes through to UserDefaults and the declarative
        // settings file, so a capture run would otherwise leave the user in
        // whichever theme happened to be last. Snapshot every field it touches
        // — not just the preset, since these can be customised away from their
        // preset defaults — and hand them all back at the end.
        let restore = AppearanceSnapshot(
            theme: settings.currentTheme,
            appearanceMode: settings.appearanceMode,
            uiFontStyle: settings.uiFontStyle,
            contentFontStyle: settings.contentFontStyle,
            accentColor: settings.accentColor,
            fontSize: settings.fontSize
        )
        // A crash mid-run can't run the defer, so leave the original on disk
        // where the wrapper script can find it and put it back.
        writeRecoveryFile(restore, near: outputDir)
        defer {
            restore.apply(to: settings)
            Theme.refresh()
            settings.applyThemeConfig()
            removeRecoveryFile(near: outputDir)
        }

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var written: [URL] = []
        var entries: [ManifestEntry] = []

        for theme in Self.themes {
            let styleSlug = Self.slug(for: theme)
            let styleDir = outputDir.appendingPathComponent(styleSlug)
            try? FileManager.default.createDirectory(at: styleDir, withIntermediateDirectories: true)

            settings.applyTheme(theme)
            Theme.refresh()
            // Let the theme land before the first window of the run renders in
            // it; SwiftUI reads these tokens at body evaluation.
            try? await Task.sleep(for: .milliseconds(400))

            for (index, shot) in Self.shots.enumerated() {
                let filename = String(format: "%02d-%@.png", index + 1, shot.slug)
                let url = styleDir.appendingPathComponent(filename)

                TalkieConsole.info("📸 \(styleSlug)/\(filename)")

                guard let saved = await capture(shot, theme: theme, to: url, size: size) else {
                    TalkieConsole.info("❌ failed: \(styleSlug)/\(filename)")
                    continue
                }

                written.append(saved)
                entries.append(
                    ManifestEntry(
                        style: styleSlug,
                        styleName: theme.displayName,
                        appearance: theme.appearanceMode == .dark ? "dark" : "light",
                        page: shot.slug,
                        pageName: shot.title,
                        file: "\(styleSlug)/\(filename)",
                        width: Int(size.width),
                        height: Int(size.height)
                    )
                )
            }
        }

        writeManifest(entries, to: outputDir, size: size)
        return written
    }

    // MARK: - One shot

    private func capture(
        _ shot: MarketingShot,
        theme: ThemePreset,
        to url: URL,
        size: CGSize
    ) async -> URL? {
        let window = renderWindow(size: size)
        window.title = shot.title
        // The window's own appearance has to match the theme, or the titlebar
        // and any AppKit-backed chrome render in the system appearance while
        // the SwiftUI content renders in the theme's.
        window.appearance = NSAppearance(
            named: theme.appearanceMode == .dark ? .darkAqua : .aqua
        )
        window.contentView = NSHostingView(
            rootView: rootView(for: shot)
                .frame(width: size.width, height: size.height)
                .clipped()
        )
        window.styleMask.remove(.resizable)

        // Capture resolution follows the backing scale of whichever display the
        // window is on, so on a 1x external monitor the whole inventory comes
        // out half-resolution and blurs on a retina browser. Prefer a 2x screen.
        if let retina = NSScreen.screens.first(where: { $0.backingScaleFactor >= 2 }) {
            let frame = retina.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2
            ))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        try? await Task.sleep(for: settleDelay)
        defer { window.close() }

        // Some screens (Workflows, Settings) attach a window toolbar, so their
        // window is taller than the others for the same content size and the
        // inventory came out in two different shapes. Derive the trim from the
        // style mask rather than the live window — that's the plain titlebar
        // height every shot should end up with, toolbar or not.
        let chromeHeight = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable]
        ).height - size.height

        guard let image = await captureWindow(window).map({
                  crop($0, toPointHeight: size.height + chromeHeight)
              }),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        do {
            try png.write(to: url)
            return url
        } catch {
            TalkieConsole.info("❌ Failed to write \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func rootView(for shot: MarketingShot) -> some View {
        AppNavigation(
            initialSection: shot.section,
            initialSettingsSection: shot.settingsSection
        )
        .environment(SettingsManager.shared)
        .environment(EngineClient.shared)
        .environment(AgentSettings.shared)
        .environment(CloudKitSyncManager.shared)
        .environment(SystemEventManager.shared)
        .environment(RelativeTimeTicker.shared)
        .tint(SettingsManager.shared.accentColor.color)
    }

    private func renderWindow(size: CGSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func captureWindow(_ window: NSWindow) async -> NSImage? {
        try? await Task.sleep(for: .milliseconds(100))

        if let cgImage = await ScreenshotCaptureService.shared
            .captureWindowImage(windowID: CGWindowID(window.windowNumber)) {
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }

        guard let contentView = window.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        else { return nil }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        let image = NSImage(size: contentView.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// Trims an over-tall capture from the bottom to a fixed height in points,
    /// preserving whatever backing scale the capture came in at.
    private func crop(_ image: NSImage, toPointHeight pointHeight: CGFloat) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let scale = image.size.height > 0 ? CGFloat(cg.height) / image.size.height : 1
        let targetPixels = Int((pointHeight * scale).rounded())
        guard targetPixels > 0, targetPixels < cg.height,
              let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: targetPixels))
        else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    /// Screens that load from the database need longer than a static view.
    /// Overridable so a slow machine can buy more time without a rebuild.
    private var settleDelay: Duration {
        if let raw = ProcessInfo.processInfo.environment["TALKIE_SHOT_DELAY_SECONDS"],
           let seconds = Double(raw), seconds > 0 {
            return .seconds(seconds)
        }
        return .seconds(1.8)
    }

    static func slug(for theme: ThemePreset) -> String {
        theme.displayName.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - Manifest

    private struct ManifestEntry: Encodable {
        let style: String
        let styleName: String
        let appearance: String
        let page: String
        let pageName: String
        let file: String
        let width: Int
        let height: Int
    }

    private struct Manifest: Encodable {
        let generatedAt: String
        let appVersion: String
        let styles: Int
        let pages: Int
        let shots: [ManifestEntry]
    }

    private func writeManifest(_ entries: [ManifestEntry], to dir: URL, size: CGSize) {
        let manifest = Manifest(
            generatedAt: Date().iso8601,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            styles: Set(entries.map(\.style)).count,
            pages: Set(entries.map(\.page)).count,
            shots: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: dir.appendingPathComponent("manifest.json"))
    }

    // MARK: - Appearance restore

    private struct AppearanceSnapshot {
        let theme: ThemePreset?
        let appearanceMode: AppearanceMode
        let uiFontStyle: FontStyleOption
        let contentFontStyle: FontStyleOption
        let accentColor: AccentColorOption
        let fontSize: FontSizeOption

        @MainActor
        func apply(to settings: SettingsManager) {
            settings.currentTheme = theme
            settings.appearanceMode = appearanceMode
            settings.uiFontStyle = uiFontStyle
            settings.contentFontStyle = contentFontStyle
            settings.accentColor = accentColor
            settings.fontSize = fontSize
        }
    }

    private func recoveryFileURL(near dir: URL) -> URL {
        dir.deletingLastPathComponent().appendingPathComponent(".talkie-appearance-restore.json")
    }

    private func writeRecoveryFile(_ snapshot: AppearanceSnapshot, near dir: URL) {
        try? FileManager.default.createDirectory(
            at: dir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = ["theme": snapshot.theme?.rawValue ?? ""]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: recoveryFileURL(near: dir))
    }

    private func removeRecoveryFile(near dir: URL) {
        try? FileManager.default.removeItem(at: recoveryFileURL(near: dir))
    }
}
