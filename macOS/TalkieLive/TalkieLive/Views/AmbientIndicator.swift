//
//  AmbientIndicator.swift
//  TalkieLive
//
//  Menu bar indicator for ambient mode.
//  Shows current state: hidden (disabled), green (listening), orange (command active).
//

import SwiftUI
import AppKit
import Combine
import TalkieKit

private let log = Log(.ui)

// MARK: - Ambient Indicator Controller

@MainActor
final class AmbientIndicatorController: ObservableObject {
    static let shared = AmbientIndicatorController()

    // MARK: - State

    @Published private(set) var isVisible: Bool = false

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Observe ambient controller state
        AmbientController.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateForState(state)
            }
            .store(in: &cancellables)
    }

    // MARK: - Show/Hide

    /// Show the ambient indicator in the menu bar
    func show() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = indicatorImage(for: .listening)
            button.target = self
            button.action = #selector(indicatorClicked)
            button.toolTip = "Ambient Mode - Click to cancel command"
        }

        isVisible = true
        log.debug("Ambient indicator shown")
    }

    /// Hide the ambient indicator from the menu bar
    func hide() {
        guard let item = statusItem else { return }

        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        isVisible = false
        log.debug("Ambient indicator hidden")
    }

    // MARK: - State Updates

    private func updateForState(_ state: AmbientState) {
        switch state {
        case .disabled:
            hide()

        case .listening:
            show()
            updateIndicator(color: .systemGreen, tooltip: "Ambient Mode: Listening for '\(AmbientSettings.shared.wakePhrase)'")

        case .command:
            show()
            updateIndicator(color: .systemOrange, tooltip: "Ambient Mode: Recording command... (click to cancel)")

        case .processing:
            show()
            updateIndicator(color: .systemBlue, tooltip: "Ambient Mode: Processing command...")

        case .cancelled:
            // Brief flash before returning to listening
            updateIndicator(color: .systemGray, tooltip: "Ambient Mode: Command cancelled")
        }
    }

    private func updateIndicator(color: NSColor, tooltip: String) {
        guard let button = statusItem?.button else { return }

        button.image = indicatorImage(color: color)
        button.toolTip = tooltip
    }

    private func indicatorImage(for state: AmbientState) -> NSImage {
        let color: NSColor
        switch state {
        case .disabled: color = .systemGray
        case .listening: color = .systemGreen
        case .command: color = .systemOrange
        case .processing: color = .systemBlue
        case .cancelled: color = .systemGray
        }
        return indicatorImage(color: color)
    }

    private func indicatorImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw a filled circle
            color.setFill()
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            circle.fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Actions

    @objc private func indicatorClicked() {
        let state = AmbientController.shared.state

        switch state {
        case .command:
            // Cancel the current command
            log.info("Ambient indicator clicked - cancelling command")
            AmbientController.shared.cancelCommand()

        case .listening:
            // Could toggle off, but for now just show status
            log.debug("Ambient indicator clicked while listening")

        case .disabled, .processing, .cancelled:
            break
        }
    }
}

// MARK: - Ambient Indicator View (for SwiftUI if needed)

struct AmbientIndicatorView: View {
    @ObservedObject private var controller = AmbientController.shared
    @ObservedObject private var settings = AmbientSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            // State indicator dot
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            // Status text (optional, for expanded views)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.3))
        .cornerRadius(4)
    }

    private var stateColor: Color {
        switch controller.state {
        case .disabled: return .gray
        case .listening: return .green
        case .command: return .orange
        case .processing: return .blue
        case .cancelled: return .gray
        }
    }

    private var statusText: String {
        switch controller.state {
        case .disabled: return "Off"
        case .listening: return "Listening..."
        case .command: return "Recording..."
        case .processing: return "Processing..."
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Preview

#Preview {
    AmbientIndicatorView()
        .padding()
        .background(Color.black)
}
