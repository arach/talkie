#if os(macOS)
import AppKit
import QuartzCore

@MainActor
final class ScrollingCaptureProgressOverlay {
    private let panel: NSPanel
    private let progressView: ScrollingCaptureProgressView

    var excludedWindowIDs: [CGWindowID] {
        let windowNumber = panel.windowNumber
        return windowNumber > 0 ? [CGWindowID(windowNumber)] : []
    }

    init(screenRect: CGRect) {
        progressView = ScrollingCaptureProgressView(frame: NSRect(origin: .zero, size: screenRect.size))
        panel = NSPanel(
            contentRect: screenRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = progressView
    }

    func show() {
        panel.orderFrontRegardless()
        progressView.startAnimating()
    }

    func markViewportCaptured(_ viewport: Int) {
        progressView.setViewport(viewport)
    }

    func dismiss() {
        progressView.stopAnimating()
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

@MainActor
private final class ScrollingCaptureProgressView: NSView {
    private let accentColor = NSColor(calibratedRed: 0.96, green: 0.66, blue: 0.34, alpha: 1)
    private let borderLayer = CAShapeLayer()
    private let scanLineLayer = CAGradientLayer()
    private let statusBackdropLayer = CALayer()
    private let statusTextLayer = CATextLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = accentColor.withAlphaComponent(0.9).cgColor
        borderLayer.lineWidth = 2
        borderLayer.shadowColor = accentColor.cgColor
        borderLayer.shadowOpacity = 0.38
        borderLayer.shadowRadius = 5
        borderLayer.shadowOffset = .zero
        layer?.addSublayer(borderLayer)

        scanLineLayer.colors = [
            accentColor.withAlphaComponent(0).cgColor,
            accentColor.withAlphaComponent(0.52).cgColor,
            NSColor.white.withAlphaComponent(0.95).cgColor,
            accentColor.withAlphaComponent(0.52).cgColor,
            accentColor.withAlphaComponent(0).cgColor,
        ]
        scanLineLayer.locations = [0, 0.18, 0.5, 0.82, 1]
        scanLineLayer.startPoint = CGPoint(x: 0, y: 0.5)
        scanLineLayer.endPoint = CGPoint(x: 1, y: 0.5)
        scanLineLayer.shadowColor = accentColor.cgColor
        scanLineLayer.shadowOpacity = 0.75
        scanLineLayer.shadowRadius = 8
        scanLineLayer.shadowOffset = .zero
        layer?.addSublayer(scanLineLayer)

        statusBackdropLayer.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.86).cgColor
        statusBackdropLayer.cornerRadius = 8
        statusBackdropLayer.borderColor = accentColor.withAlphaComponent(0.38).cgColor
        statusBackdropLayer.borderWidth = 1
        layer?.addSublayer(statusBackdropLayer)

        statusTextLayer.alignmentMode = .center
        statusTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        statusTextLayer.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        statusTextLayer.fontSize = 10
        statusTextLayer.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        statusTextLayer.string = "SCANNING · 1"
        layer?.addSublayer(statusTextLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let borderRect = bounds.insetBy(dx: 2, dy: 2)
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: borderRect, cornerWidth: 7, cornerHeight: 7, transform: nil)

        scanLineLayer.bounds = CGRect(x: 0, y: 0, width: max(bounds.width - 10, 1), height: 2)
        scanLineLayer.position.x = bounds.midX

        let statusWidth = min(max(bounds.width - 20, 104), 122)
        let statusFrame = CGRect(x: 10, y: max(bounds.height - 32, 8), width: statusWidth, height: 22)
        statusBackdropLayer.frame = statusFrame
        statusTextLayer.frame = statusFrame.insetBy(dx: 6, dy: 5)
    }

    func startAnimating() {
        layoutSubtreeIfNeeded()
        scanLineLayer.removeAnimation(forKey: "scan")

        let scan = CABasicAnimation(keyPath: "position.y")
        scan.fromValue = max(bounds.height - 5, 5)
        scan.toValue = min(5, bounds.height / 2)
        scan.duration = 0.82
        scan.repeatCount = .infinity
        scan.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLineLayer.add(scan, forKey: "scan")

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.62
        pulse.toValue = 1
        pulse.duration = 0.48
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        borderLayer.add(pulse, forKey: "pulse")
    }

    func setViewport(_ viewport: Int) {
        statusTextLayer.string = "SCANNING · \(viewport)"

        let flash = CABasicAnimation(keyPath: "opacity")
        flash.fromValue = 1
        flash.toValue = 0.45
        flash.duration = 0.16
        flash.autoreverses = true
        scanLineLayer.add(flash, forKey: "capture-flash")
    }

    func stopAnimating() {
        layer?.removeAllAnimations()
        borderLayer.removeAllAnimations()
        scanLineLayer.removeAllAnimations()
    }
}
#endif
