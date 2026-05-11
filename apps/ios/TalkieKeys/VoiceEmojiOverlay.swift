//
//  VoiceEmojiOverlay.swift
//  TalkieKeys
//
//  Voice emoji search: Tap to record, tap to stop, tap emoji to insert.
//

import UIKit
import TalkieMobileKit

private let log = Log(.ui)

// MARK: - Particle

private struct Particle {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: CGFloat
    var velocity: CGPoint
    var brightness: CGFloat
}

// MARK: - Particle Layer

private class ParticleLayer: CALayer {
    var particles: [Particle] = []

    override func draw(in ctx: CGContext) {
        for particle in particles {
            let color = UIColor(white: particle.brightness, alpha: particle.opacity)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(
                x: particle.x - particle.size / 2,
                y: particle.y - particle.size / 2,
                width: particle.size,
                height: particle.size
            ))
        }
    }
}

// MARK: - Emoji Button

private class EmojiButton: UIButton {
    var emoji: String = ""
}

// MARK: - Voice Emoji Overlay View

class VoiceEmojiOverlayView: UIView, UIScrollViewDelegate {

    // MARK: - Callbacks

    var onDismiss: (() -> Void)?
    var onEmojiSelected: ((String) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onClearTranscript: (() -> Void)?
    var onTimeout: (() -> Void)?
    var onBrowse: (() -> Void)?
    var onShowRecent: (() -> Void)?

    // MARK: - State

    enum State {
        case idle       // Waiting to start
        case recording  // Recording voice
        case processing // Transcribing
        case results    // Showing emoji options
    }

    private(set) var state: State = .idle
    var audioLevel: Float = 0

    // MARK: - UI Elements

    // Left panel (30%): controls
    private let leftPanel = UIView()
    private let tapButton = UIButton(type: .custom)
    private let tapButtonLabel = UILabel()
    private let particleLayer = ParticleLayer()

    // Full-screen particle layer for recording mode
    private let expandedParticleLayer = ParticleLayer()
    private var expandedParticles: [Particle] = []
    private let expandedParticleCount = 80

    // Top bar: exit button and instruction
    private let exitButton = UIButton(type: .system)
    private let instructionLabel = UILabel()

    // Browse button (bottom of left panel)
    private let browseButton = UIButton(type: .system)

    // Recent button (for showing recent emojis)
    private let recentButton = UIButton(type: .system)

    // Right panel (70%): emoji grid
    private let rightPanel = UIView()
    private let statusBar = UIView()
    private let statusLabel = UILabel()
    private let statusTapButton = UIButton(type: .system)
    private let categoryScrollView = UIScrollView()
    private let categoryStack = UIStackView()
    private let emojiScrollView = UIScrollView()
    private let emojiContentView = UIView()
    private var emojiButtons: [EmojiButton] = []
    private var skeletonViews: [UIView] = []

    // Track the transcript separately so it doesn't get overwritten
    private var currentTranscript: String = ""

    // Browse mode state
    private var isBrowseMode = false
    private var isBrowseSearchMode = false
    private var browseEntries: [(title: String, emojis: [String])] = []
    private var browseAllIndex = 0
    private var browseCategoryButtons: [UIButton] = []
    private var browseAllEmojis: [String] = []
    private var browseDisplayedCount = 0
    private let browsePageSize = 120
    private var selectedBrowseCategoryIndex = 0
    private var applyingBrowseSuggestions = false

    private var displayLink: CADisplayLink?
    private var particles: [Particle] = []
    private let particleCount = 35

    private let bridge = KeyboardBridge.shared

    // Pre-prepared haptic generators for responsive feedback
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    // Layout constants
    private let tapButtonSize: CGFloat = 90
    private let browseTapButtonSize: CGFloat = 64
    private let browseTapButtonPadding: CGFloat = 12
    private let gridColumns = 4
    private let maxVisibleRows = 2  // Visible rows without scrolling
    private let initialSlotCount = 16
    private let emojiButtonPoolBuffer = 24

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Setup

    private func setupUI() {
        lightImpact.prepare()
        mediumImpact.prepare()

        backgroundColor = UIColor(white: 0.03, alpha: 1.0)

        // Expanded particle layer (covers right panel during recording)
        expandedParticleLayer.contentsScale = traitCollection.displayScale
        expandedParticleLayer.backgroundColor = UIColor.clear.cgColor
        expandedParticleLayer.opacity = 0
        layer.addSublayer(expandedParticleLayer)

        // Left panel
        leftPanel.backgroundColor = .clear
        addSubview(leftPanel)

        // Right panel
        rightPanel.backgroundColor = .clear
        addSubview(rightPanel)

        // Exit button (top-level so it's always visible)
        exitButton.setTitle("✕", for: .normal)
        exitButton.setTitleColor(UIColor(white: 0.4, alpha: 1.0), for: .normal)
        exitButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        addSubview(exitButton)

        // Instruction label (below exit button)
        instructionLabel.text = "Voice Emoji"
        instructionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        instructionLabel.textColor = UIColor(white: 0.35, alpha: 1.0)
        instructionLabel.textAlignment = .center
        leftPanel.addSubview(instructionLabel)

        // Recent button (shows recent emojis)
        recentButton.setTitle("Recent", for: .normal)
        recentButton.setTitleColor(UIColor(white: 0.5, alpha: 1.0), for: .normal)
        recentButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        recentButton.addTarget(self, action: #selector(recentTapped), for: .touchUpInside)
        leftPanel.addSubview(recentButton)

        // Browse button (bottom of left panel)
        browseButton.setTitle("Browse", for: .normal)
        browseButton.setTitleColor(UIColor(white: 0.5, alpha: 1.0), for: .normal)
        browseButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        browseButton.addTarget(self, action: #selector(browseTapped), for: .touchUpInside)
        leftPanel.addSubview(browseButton)

        // --- Left Panel Contents ---

        // Tap button (circular with text inside)
        tapButton.backgroundColor = UIColor(red: 0.15, green: 0.5, blue: 0.85, alpha: 1.0)
        tapButton.layer.cornerRadius = tapButtonSize / 2
        tapButton.layer.borderWidth = 3
        tapButton.layer.borderColor = UIColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 0.6).cgColor
        tapButton.addTarget(self, action: #selector(tapButtonPressed), for: .touchUpInside)

        // Add subtle shadow for depth
        tapButton.layer.shadowColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0).cgColor
        tapButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        tapButton.layer.shadowRadius = 8
        tapButton.layer.shadowOpacity = 0.4
        leftPanel.addSubview(tapButton)

        // Particle layer (inside tap button)
        particleLayer.contentsScale = traitCollection.displayScale
        particleLayer.backgroundColor = UIColor.clear.cgColor
        tapButton.layer.insertSublayer(particleLayer, at: 0)

        // Label inside tap button
        tapButtonLabel.text = "Tap &\nSpeak"
        tapButtonLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        tapButtonLabel.textColor = .white
        tapButtonLabel.textAlignment = .center
        tapButtonLabel.numberOfLines = 2
        tapButton.addSubview(tapButtonLabel)

        // --- Right Panel Contents ---

        // Status bar at top (shows transcript)
        statusBar.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        statusBar.layer.cornerRadius = 6
        rightPanel.addSubview(statusBar)

        statusLabel.text = "Say an emoji name..."
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor(white: 0.4, alpha: 1.0)
        statusLabel.textAlignment = .center
        statusBar.addSubview(statusLabel)

        statusTapButton.backgroundColor = .clear
        statusTapButton.addTarget(self, action: #selector(statusBarTapped), for: .touchUpInside)
        statusBar.addSubview(statusTapButton)

        // Category scroll view (horizontal, hidden until browse mode)
        categoryScrollView.showsHorizontalScrollIndicator = false
        categoryScrollView.showsVerticalScrollIndicator = false
        categoryScrollView.alwaysBounceHorizontal = true
        categoryScrollView.backgroundColor = .clear
        categoryScrollView.isHidden = true
        rightPanel.addSubview(categoryScrollView)

        categoryStack.axis = .horizontal
        categoryStack.alignment = .fill
        categoryStack.spacing = 6
        categoryScrollView.addSubview(categoryStack)

        // Scroll view for emoji grid (allows scrolling for more results)
        emojiScrollView.showsVerticalScrollIndicator = true
        emojiScrollView.showsHorizontalScrollIndicator = false
        emojiScrollView.alwaysBounceVertical = true
        emojiScrollView.indicatorStyle = .white
        emojiScrollView.delegate = self
        rightPanel.addSubview(emojiScrollView)

        emojiContentView.backgroundColor = .clear
        emojiScrollView.addSubview(emojiContentView)

        // Create skeleton placeholders (initial 16 slots: 4x4 grid, scrollable)
        for i in 0..<initialSlotCount {
            let skeleton = UIView()
            skeleton.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
            skeleton.layer.cornerRadius = 12
            skeleton.layer.borderWidth = 1
            skeleton.layer.borderColor = UIColor(white: 0.12, alpha: 1.0).cgColor

            // Add faint placeholder emoji to first two cells
            if i < 2 {
                let placeholder = UILabel()
                placeholder.text = i == 0 ? "😊" : "❤️"
                placeholder.font = .systemFont(ofSize: 28)
                placeholder.textAlignment = .center
                placeholder.alpha = 0.15
                placeholder.tag = 100
                skeleton.addSubview(placeholder)
            }

            skeletonViews.append(skeleton)
            emojiContentView.addSubview(skeleton)
        }

        ensureEmojiButtonCapacity(initialSlotCount)

        // Initialize particles
        initializeParticles()

        // Start animation
        displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink?.add(to: .main, forMode: .common)

        // Swipe down to dismiss
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDismiss))
        swipeDown.direction = .down
        addGestureRecognizer(swipeDown)

        // Swipe left to dismiss (like going back)
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDismiss))
        swipeLeft.direction = .left
        addGestureRecognizer(swipeLeft)
    }

    @objc private func handleSwipeDismiss() {
        if state == .recording {
            onRecordingStopped?()
        }
        dismiss()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let safeTop = safeAreaInsets.top
        let safeBottom = safeAreaInsets.bottom
        let contentHeight = bounds.height - safeTop - safeBottom

        // Full width in browse mode, 30/70 split in voice mode
        let isFullWidthBrowse = isBrowseMode
        let leftWidth = isFullWidthBrowse ? 0 : bounds.width * 0.32
        let rightWidth = bounds.width - leftWidth

        leftPanel.frame = CGRect(x: 0, y: safeTop, width: leftWidth, height: contentHeight)
        rightPanel.frame = CGRect(x: leftWidth, y: safeTop, width: rightWidth, height: contentHeight)
        leftPanel.isHidden = isFullWidthBrowse

        // Expanded particle layer covers the right panel area
        expandedParticleLayer.frame = CGRect(x: leftWidth, y: safeTop, width: rightWidth, height: contentHeight)

        // --- Right Panel Layout ---
        let gridPadding: CGFloat = 12
        let gridTop: CGFloat = 16

        // Status bar at top
        statusBar.frame = CGRect(x: gridPadding, y: gridTop, width: rightPanel.bounds.width - gridPadding * 2, height: 32)
        statusLabel.frame = statusBar.bounds
        statusTapButton.frame = statusBar.bounds
        statusTapButton.isHidden = !isBrowseMode

        // Optional category strip for browse mode
        let categoryHeight: CGFloat = isBrowseMode ? 28 : 0
        if isBrowseMode {
            categoryScrollView.isHidden = false
            categoryScrollView.frame = CGRect(
                x: gridPadding,
                y: statusBar.frame.maxY + 8,
                width: rightPanel.bounds.width - gridPadding * 2,
                height: categoryHeight
            )
            categoryStack.frame = CGRect(
                x: 0,
                y: 0,
                width: categoryStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width,
                height: categoryHeight
            )
            categoryScrollView.contentSize = CGSize(width: categoryStack.frame.width, height: categoryHeight)
        } else {
            categoryScrollView.isHidden = true
        }

        // Scroll view below status bar / category strip
        let scrollStartY = statusBar.frame.maxY + 12 + categoryHeight
        let scrollHeight = rightPanel.bounds.height - scrollStartY - 8
        emojiScrollView.frame = CGRect(
            x: gridPadding,
            y: scrollStartY,
            width: rightPanel.bounds.width - gridPadding * 2,
            height: scrollHeight
        )

        // Exit button: in browse mode align with grid padding, else center in left panel
        let exitX = isFullWidthBrowse ? gridPadding : (leftPanel.frame.midX - 16)
        exitButton.frame = CGRect(x: exitX, y: safeTop + gridTop, width: 32, height: 32)
        bringSubviewToFront(exitButton)

        let cellHeight: CGFloat = 62
        if isFullWidthBrowse {
            // Floating voice button in bottom-right corner
            if tapButton.superview !== self {
                tapButton.removeFromSuperview()
                addSubview(tapButton)
            }

            let buttonSize = browseTapButtonSize
            tapButton.frame = CGRect(
                x: bounds.width - buttonSize - browseTapButtonPadding,
                y: bounds.height - safeBottom - buttonSize - browseTapButtonPadding,
                width: buttonSize,
                height: buttonSize
            )
            tapButton.layer.cornerRadius = buttonSize / 2
            particleLayer.frame = tapButton.bounds
            tapButtonLabel.frame = tapButton.bounds

            let bottomInset = buttonSize + browseTapButtonPadding + 8
            emojiScrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            emojiScrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
            bringSubviewToFront(tapButton)
        } else {
            emojiScrollView.contentInset = .zero
            emojiScrollView.verticalScrollIndicatorInsets = .zero

            // Return tap button to left panel if needed
            if tapButton.superview !== leftPanel {
                tapButton.removeFromSuperview()
                leftPanel.addSubview(tapButton)
            }

            // --- Left Panel Layout ---
            let leftCenterX = leftPanel.bounds.width / 2

            // Calculate the vertical center of the visible emoji area (2 rows)
            let visibleGridHeight = CGFloat(maxVisibleRows) * cellHeight
            let emojiAreaTop = scrollStartY
            let emojiAreaCenterY = emojiAreaTop + visibleGridHeight / 2

            // Size the tap button to roughly fit the height of 2 emoji rows
            let adjustedButtonSize = min(tapButtonSize, visibleGridHeight - 16)

            // Tap button centered with emoji rows
            tapButton.frame = CGRect(
                x: leftCenterX - adjustedButtonSize / 2,
                y: emojiAreaCenterY - adjustedButtonSize / 2,
                width: adjustedButtonSize,
                height: adjustedButtonSize
            )
            tapButton.layer.cornerRadius = adjustedButtonSize / 2
            particleLayer.frame = tapButton.bounds
            tapButtonLabel.frame = tapButton.bounds

            // Instruction label below exit button
            instructionLabel.frame = CGRect(x: 4, y: exitButton.frame.maxY + 4, width: leftPanel.bounds.width - 8, height: 16)

            // Recent and Browse buttons at the bottom
            let buttonWidth = (leftPanel.bounds.width - 12) / 2
            recentButton.frame = CGRect(x: 4, y: leftPanel.bounds.height - 36, width: buttonWidth, height: 28)
            browseButton.frame = CGRect(x: buttonWidth + 8, y: leftPanel.bounds.height - 36, width: buttonWidth, height: 28)
        }

        // Grid layout inside scroll view
        let availableWidth = emojiScrollView.bounds.width
        let cellWidth = availableWidth / CGFloat(gridColumns)
        let cellSize = min(cellWidth, cellHeight) - 8

        let totalCells = max(initialSlotCount, emojiButtons.count)
        let totalRows = (totalCells + gridColumns - 1) / gridColumns
        let gridContentHeight = CGFloat(totalRows) * cellHeight

        emojiContentView.frame = CGRect(x: 0, y: 0, width: availableWidth, height: gridContentHeight)
        emojiScrollView.contentSize = CGSize(width: availableWidth, height: gridContentHeight)

        for index in skeletonViews.indices {
            let row = index / gridColumns
            let col = index % gridColumns
            let x = CGFloat(col) * cellWidth + (cellWidth - cellSize) / 2
            let y = CGFloat(row) * cellHeight + (cellHeight - cellSize) / 2
            let frame = CGRect(x: x, y: y, width: cellSize, height: cellSize)
            skeletonViews[index].frame = frame
            if let placeholder = skeletonViews[index].viewWithTag(100) {
                placeholder.frame = skeletonViews[index].bounds
            }
        }

        for index in emojiButtons.indices {
            let row = index / gridColumns
            let col = index % gridColumns
            let x = CGFloat(col) * cellWidth + (cellWidth - cellSize) / 2
            let y = CGFloat(row) * cellHeight + (cellHeight - cellSize) / 2
            emojiButtons[index].frame = CGRect(x: x, y: y, width: cellSize, height: cellSize)
        }
    }

    // MARK: - Particles

    private func initializeParticles() {
        let buttonSize = tapButton.bounds.width > 0 ? tapButton.bounds.width : tapButtonSize
        let cx = buttonSize / 2
        let cy = buttonSize / 2

        particles = (0..<particleCount).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 5...18)
            return Particle(
                x: cx + cos(angle) * radius,
                y: cy + sin(angle) * radius,
                size: CGFloat.random(in: 1.5...3),
                opacity: CGFloat.random(in: 0.15...0.35),
                velocity: CGPoint(
                    x: CGFloat.random(in: -0.15...0.15),
                    y: CGFloat.random(in: -0.15...0.15)
                ),
                brightness: CGFloat.random(in: 0.6...0.9)
            )
        }
        particleLayer.particles = particles

        initializeExpandedParticles()
    }

    private func initializeExpandedParticles() {
        let width = expandedParticleLayer.bounds.width > 0 ? expandedParticleLayer.bounds.width : 250
        let height = expandedParticleLayer.bounds.height > 0 ? expandedParticleLayer.bounds.height : 200
        let cx = width / 2
        let cy = height / 2

        expandedParticles = (0..<expandedParticleCount).map { _ in
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 20...80)
            return Particle(
                x: cx + cos(angle) * radius,
                y: cy + sin(angle) * radius,
                size: CGFloat.random(in: 2...4),
                opacity: CGFloat.random(in: 0.1...0.3),
                velocity: CGPoint(
                    x: CGFloat.random(in: -0.3...0.3),
                    y: CGFloat.random(in: -0.3...0.3)
                ),
                brightness: CGFloat.random(in: 0.5...0.85)
            )
        }
        expandedParticleLayer.particles = expandedParticles
    }

    @objc private func updateAnimation() {
        if state == .recording {
            audioLevel = bridge.getAudioLevel()
        } else {
            audioLevel = 0.03
        }

        let level = CGFloat(audioLevel)
        let isActive = state == .recording

        updateTapButtonParticles(level: level, isActive: isActive)

        if isActive {
            updateExpandedParticles(level: level)
        }
    }

    private func updateTapButtonParticles(level: CGFloat, isActive: Bool) {
        let buttonSize = tapButton.bounds.width > 0 ? tapButton.bounds.width : tapButtonSize
        let cx = buttonSize / 2
        let cy = buttonSize / 2
        let maxRadius = buttonSize / 2 - 8

        for i in particles.indices {
            var p = particles[i]

            let angle = atan2(p.y - cy, p.x - cx)
            let distance = hypot(p.x - cx, p.y - cy)

            if isActive {
                let baseRadius: CGFloat = 10 + level * 22
                let radiusDiff = baseRadius - distance

                p.velocity.x += CGFloat.random(in: -0.4...0.4) * level
                p.velocity.y += CGFloat.random(in: -0.4...0.4) * level
                p.velocity.x *= 0.88
                p.velocity.y *= 0.88

                p.x += cos(angle) * radiusDiff * 0.08 + p.velocity.x
                p.y += sin(angle) * radiusDiff * 0.08 + p.velocity.y

                let orbitSpeed: CGFloat = 0.012 + level * 0.018
                let newAngle = angle + orbitSpeed
                let newDist = min(distance, maxRadius)
                p.x = cx + cos(newAngle) * newDist
                p.y = cy + sin(newAngle) * newDist

                p.size = 2 + level * 2.5
                p.opacity = 0.25 + level * 0.5
                p.brightness = 0.7 + level * 0.3
            } else {
                let targetRadius: CGFloat = 12
                let radiusDiff = targetRadius - distance
                p.x += cos(angle) * radiusDiff * 0.015
                p.y += sin(angle) * radiusDiff * 0.015

                let orbitSpeed: CGFloat = 0.002
                let newAngle = angle + orbitSpeed
                p.x = cx + cos(newAngle) * distance
                p.y = cy + sin(newAngle) * distance

                p.size = 1.5
                p.opacity = 0.12
                p.brightness = 0.5
            }

            particles[i] = p
        }

        particleLayer.particles = particles
        particleLayer.setNeedsDisplay()
    }

    private func updateExpandedParticles(level: CGFloat) {
        let width = expandedParticleLayer.bounds.width
        let height = expandedParticleLayer.bounds.height
        guard width > 0, height > 0 else { return }

        let cx = width / 2
        let cy = height / 2
        let maxRadius = min(width, height) / 2 - 20

        for i in expandedParticles.indices {
            var p = expandedParticles[i]

            let angle = atan2(p.y - cy, p.x - cx)
            let distance = hypot(p.x - cx, p.y - cy)

            let baseRadius: CGFloat = 30 + level * 60
            let radiusDiff = baseRadius - distance

            p.velocity.x += CGFloat.random(in: -0.6...0.6) * level
            p.velocity.y += CGFloat.random(in: -0.6...0.6) * level
            p.velocity.x *= 0.92
            p.velocity.y *= 0.92

            p.x += cos(angle) * radiusDiff * 0.05 + p.velocity.x
            p.y += sin(angle) * radiusDiff * 0.05 + p.velocity.y

            let orbitSpeed: CGFloat = 0.008 + level * 0.012
            let newAngle = angle + orbitSpeed
            let newDist = min(distance, maxRadius)
            p.x = cx + cos(newAngle) * newDist
            p.y = cy + sin(newAngle) * newDist

            p.size = 2.5 + level * 3
            p.opacity = 0.15 + level * 0.4
            p.brightness = 0.6 + level * 0.35

            expandedParticles[i] = p
        }

        expandedParticleLayer.particles = expandedParticles
        expandedParticleLayer.setNeedsDisplay()
    }

    // MARK: - State Management

    private func setState(_ newState: State) {
        state = newState

        // Animate expanded particles visibility
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        expandedParticleLayer.opacity = (newState == .recording) ? 1.0 : 0.0
        CATransaction.commit()

        // Re-initialize expanded particles when starting recording
        if newState == .recording {
            initializeExpandedParticles()
        }

        UIView.animate(withDuration: 0.2) {
            switch newState {
            case .idle:
                self.tapButtonLabel.text = self.isBrowseMode ? "Voice" : "Tap &\nSpeak"
                self.tapButton.backgroundColor = UIColor(red: 0.15, green: 0.5, blue: 0.85, alpha: 1.0)
                self.tapButton.layer.borderColor = UIColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 0.6).cgColor
                self.tapButton.layer.shadowColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0).cgColor
                if !self.isBrowseMode {
                    self.statusLabel.text = "Say an emoji name..."
                }
                self.statusLabel.textColor = UIColor(white: 0.4, alpha: 1.0)
                self.statusBar.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
                self.rightPanel.alpha = 1.0

            case .recording:
                self.tapButtonLabel.text = "Tap to\nStop"
                self.tapButton.backgroundColor = UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1.0)
                self.tapButton.layer.borderColor = UIColor(red: 0.95, green: 0.4, blue: 0.4, alpha: 0.6).cgColor
                self.tapButton.layer.shadowColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0).cgColor
                self.statusLabel.text = "Listening..."
                self.statusLabel.textColor = UIColor(white: 0.5, alpha: 1.0)
                self.statusBar.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
                self.rightPanel.alpha = 0.15

            case .processing:
                self.tapButtonLabel.text = "..."
                self.tapButton.backgroundColor = UIColor(white: 0.25, alpha: 1.0)
                self.tapButton.layer.borderColor = UIColor(white: 0.35, alpha: 0.6).cgColor
                self.tapButton.layer.shadowColor = UIColor(white: 0.3, alpha: 1.0).cgColor
                self.statusLabel.text = "Processing..."
                self.statusLabel.textColor = UIColor(white: 0.5, alpha: 1.0)
                self.rightPanel.alpha = 0.5

            case .results:
                if self.isBrowseMode {
                    self.tapButtonLabel.text = "Voice"
                    self.tapButton.backgroundColor = UIColor(red: 0.15, green: 0.5, blue: 0.85, alpha: 1.0)
                    self.tapButton.layer.borderColor = UIColor(red: 0.3, green: 0.6, blue: 0.95, alpha: 0.6).cgColor
                    self.tapButton.layer.shadowColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0).cgColor
                } else {
                    self.tapButtonLabel.text = "Try\nAgain"
                    self.tapButton.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
                    self.tapButton.layer.borderColor = UIColor(white: 0.3, alpha: 0.6).cgColor
                    self.tapButton.layer.shadowColor = UIColor(white: 0.25, alpha: 1.0).cgColor
                }
                self.statusLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
                self.statusBar.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
                self.rightPanel.alpha = 1.0
            }
        }
    }

    // MARK: - Public API

    func show(in view: UIView) {
        frame = view.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        view.addSubview(self)

        setNeedsLayout()
        layoutIfNeeded()
        initializeParticles()

        setState(.idle)
        setSkeletonPlaceholderVisible(true)

        // Reset emoji buttons
        emojiButtons.forEach { $0.alpha = 0 }

        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }
    }

    func updateTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            currentTranscript = trimmed
            statusLabel.text = "\"\(trimmed)\""
        }
    }

    func updateSuggestions(_ suggestions: [(emoji: String, confidence: Float)], preserveScrollOffset: Bool = false) {
        if isBrowseMode && !applyingBrowseSuggestions {
            isBrowseSearchMode = true
            setNeedsLayout()
            layoutIfNeeded()
        }
        let desiredCapacity = max(initialSlotCount, suggestions.count + emojiButtonPoolBuffer)
        trimEmojiButtonCapacity(
            to: desiredCapacity,
            allowInBrowseMode: isBrowseSearchMode
        )
        ensureEmojiButtonCapacity(suggestions.count)

        // Hide all emoji buttons first
        emojiButtons.forEach { $0.alpha = 0 }

        if !preserveScrollOffset {
            emojiScrollView.setContentOffset(.zero, animated: false)
        }

        if suggestions.isEmpty {
            setSkeletonPlaceholderVisible(true)
            setState(.idle)
            if !currentTranscript.isEmpty {
                statusLabel.text = "No matches for \"\(currentTranscript)\""
            } else {
                statusLabel.text = "No matches found"
            }
            return
        }

        if !currentTranscript.isEmpty, (!isBrowseMode || isBrowseSearchMode) {
            statusLabel.text = "\"\(currentTranscript)\""
        }

        setSkeletonPlaceholderVisible(false)

        // Populate with suggestions
        for (index, suggestion) in suggestions.enumerated() {
            let btn = emojiButtons[index]
            btn.emoji = suggestion.emoji
            btn.setTitle(suggestion.emoji, for: .normal)
        }

        setState(.results)

        // Animate emojis appearing
        if suggestions.count > 80 {
            // Skip per-item animation for large sets
            for (index, _) in suggestions.enumerated() {
                emojiButtons[index].alpha = 1
            }
        } else {
            for (index, _) in suggestions.enumerated() {
                let delay = Double(min(index, 24)) * 0.01
                UIView.animate(withDuration: 0.12, delay: delay, options: .curveEaseOut) {
                    self.emojiButtons[index].alpha = 1
                }
            }
        }
    }

    func showEmojiBrowser(
        allEmojis: [String],
        categories: [(title: String, emojis: [String])],
        featured: [(title: String, emojis: [String])] = []
    ) {
        currentTranscript = "Browse"
        statusLabel.text = "Browse"
        isBrowseMode = true
        isBrowseSearchMode = false
        browseAllEmojis = allEmojis
        browseDisplayedCount = min(browsePageSize, allEmojis.count)

        var entries: [(title: String, emojis: [String])] = []
        entries.append(contentsOf: featured.filter { !$0.emojis.isEmpty })
        entries.append(("All", allEmojis))
        entries.append(contentsOf: categories.filter { !$0.emojis.isEmpty })
        browseEntries = entries
        browseAllIndex = entries.firstIndex(where: { $0.title == "All" }) ?? 0
        rebuildBrowseCategoryButtons()
        let defaultIndex = entries.firstIndex(where: { $0.title == "Popular" }) ?? browseAllIndex
        selectBrowseCategory(at: defaultIndex)
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Called when transcription results arrive
    func didReceiveTranscription() {
        if state == .processing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.state == .processing else { return }
                self.setState(.idle)
                self.statusLabel.text = "Try again"
                self.onTimeout?()
            }
        }
    }

    // For compatibility - not used in tap flow
    func startListening() {}
    func stopListening() {}

    // MARK: - Actions

    @objc private func tapButtonPressed() {
        switch state {
        case .idle, .results:
            setState(.recording)
            emojiButtons.forEach { $0.alpha = 0 }
            currentTranscript = ""
            setSkeletonPlaceholderVisible(true)
            mediumImpact.impactOccurred()
            onRecordingStarted?()

        case .recording:
            setState(.processing)
            lightImpact.impactOccurred()
            onRecordingStopped?()

            // Safety timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self, self.state == .processing else { return }
                self.setState(.idle)
                self.statusLabel.text = "Timeout - try again"
                self.onTimeout?()
            }

        case .processing:
            break
        }
    }

    @objc private func statusBarTapped() {
        guard isBrowseMode else { return }
        isBrowseSearchMode = true
        statusLabel.text = "Search emoji"
        setNeedsLayout()
        layoutIfNeeded()
        tapButtonPressed()
    }

    @objc private func emojiTapped(_ sender: EmojiButton) {
        guard !sender.emoji.isEmpty else { return }

        onEmojiSelected?(sender.emoji)

        mediumImpact.impactOccurred()

        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = .identity
            }
        }
    }

    @objc private func exitTapped() {
        if state == .recording {
            onRecordingStopped?()
        }
        dismiss()
    }

    @objc private func browseTapped() {
        lightImpact.impactOccurred()
        onBrowse?()
    }

    @objc private func recentTapped() {
        lightImpact.impactOccurred()

        let recents = RecentEmojis.shared.recentMatches(limit: initialSlotCount)
        if recents.isEmpty {
            statusLabel.text = "No recent emojis"
            setState(.idle)
        } else {
            currentTranscript = "Recent"
            statusLabel.text = "Recent"
            updateSuggestions(recents)
        }
    }

    private func dismiss() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }

    // MARK: - Browse Mode Helpers

    private func setSkeletonPlaceholderVisible(_ visible: Bool) {
        for skeleton in skeletonViews {
            skeleton.viewWithTag(100)?.alpha = visible ? 0.15 : 0.0
        }
    }

    private func rebuildBrowseCategoryButtons() {
        for button in browseCategoryButtons {
            categoryStack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        browseCategoryButtons.removeAll()

        for (index, entry) in browseEntries.enumerated() {
            let button = UIButton(type: .custom)
            var configuration = button.configuration ?? UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            button.configuration = configuration
            button.setTitle(entry.title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
            button.layer.cornerRadius = 10
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor(white: 0.18, alpha: 1.0).cgColor
            button.setTitleColor(UIColor(white: 0.7, alpha: 1.0), for: .normal)
            button.backgroundColor = UIColor(white: 0.10, alpha: 1.0)
            button.tag = index
            button.addTarget(self, action: #selector(browseCategoryTapped(_:)), for: .touchUpInside)
            categoryStack.addArrangedSubview(button)
            browseCategoryButtons.append(button)
        }
    }

    @objc private func browseCategoryTapped(_ sender: UIButton) {
        selectBrowseCategory(at: sender.tag)
    }

    private func selectBrowseCategory(at index: Int) {
        guard browseEntries.indices.contains(index) else { return }
        selectedBrowseCategoryIndex = index
        let entry = browseEntries[index]
        isBrowseSearchMode = false

        for (i, button) in browseCategoryButtons.enumerated() {
            let selected = (i == index)
            button.backgroundColor = selected ? UIColor(white: 0.22, alpha: 1.0) : UIColor(white: 0.10, alpha: 1.0)
            button.layer.borderColor = selected ? UIColor(white: 0.35, alpha: 1.0).cgColor : UIColor(white: 0.18, alpha: 1.0).cgColor
            button.setTitleColor(selected ? UIColor.white : UIColor(white: 0.7, alpha: 1.0), for: .normal)
        }

        statusLabel.text = entry.title == "All" ? "Browse" : "Browse \u{2022} \(entry.title)"

        let emojisToShow: [String]
        if index == browseAllIndex {
            emojisToShow = Array(browseAllEmojis.prefix(browseDisplayedCount))
        } else {
            emojisToShow = entry.emojis
        }

        applyingBrowseSuggestions = true
        updateSuggestions(emojisToShow.map { ($0, Float(1.0)) })
        applyingBrowseSuggestions = false
        isBrowseMode = true
        categoryScrollView.isHidden = false
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === emojiScrollView else { return }
        guard isBrowseMode, selectedBrowseCategoryIndex == browseAllIndex else { return }
        guard browseDisplayedCount < browseAllEmojis.count else { return }

        let threshold: CGFloat = 180
        let distanceToBottom = scrollView.contentSize.height - (scrollView.contentOffset.y + scrollView.bounds.height)
        guard distanceToBottom < threshold else { return }

        let previousOffset = scrollView.contentOffset
        browseDisplayedCount = min(browseDisplayedCount + browsePageSize, browseAllEmojis.count)

        applyingBrowseSuggestions = true
        let nextSlice = Array(browseAllEmojis.prefix(browseDisplayedCount))
        updateSuggestions(nextSlice.map { ($0, Float(1.0)) }, preserveScrollOffset: true)
        applyingBrowseSuggestions = false

        scrollView.setContentOffset(previousOffset, animated: false)
    }

    // MARK: - Dynamic Capacity

    private func ensureEmojiButtonCapacity(_ count: Int) {
        guard count > emojiButtons.count else { return }

        let missing = count - emojiButtons.count
        for _ in 0..<missing {
            let btn = EmojiButton(type: .system)
            btn.titleLabel?.font = .systemFont(ofSize: 36)
            btn.addTarget(self, action: #selector(emojiTapped(_:)), for: .touchUpInside)
            btn.alpha = 0
            emojiButtons.append(btn)
            emojiContentView.addSubview(btn)
        }

        setNeedsLayout()
    }

    private func trimEmojiButtonCapacity(to target: Int, allowInBrowseMode: Bool = false) {
        guard target >= initialSlotCount else { return }
        guard emojiButtons.count > target else { return }

        if isBrowseMode && !allowInBrowseMode {
            return
        }

        for index in stride(from: emojiButtons.count - 1, through: target, by: -1) {
            let button = emojiButtons.remove(at: index)
            button.removeFromSuperview()
        }
    }
}
