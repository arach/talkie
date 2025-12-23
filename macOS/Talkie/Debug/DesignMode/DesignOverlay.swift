//
//  DesignOverlay.swift
//  Talkie macOS
//
//  Global design overlay - Grid and visual decorators
//  Appears when Design God Mode is enabled (⌘⇧D)
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI
import DebugKit

#if DEBUG

struct DesignOverlay: View {
    @State private var designMode = DesignModeManager.shared
    @State private var isExpanded = false
    @State private var overlayPosition: DesignOverlayPosition = .bottomTrailing

    var body: some View {
        if designMode.isEnabled {
            ZStack {
                // Grid overlay (when enabled)
                if designMode.showGrid {
                    Color.clear
                        .layoutGrid(
                            showGrid: true,
                            gridSpacing: 8,
                            opacity: 0.2
                        )
                        .allowsHitTesting(false)
                }

                // Floating toolbar button
                VStack {
                    if overlayPosition.isTop {
                        Spacer()
                    }

                    HStack {
                        if overlayPosition.isTrailing {
                            Spacer()
                        }

                        toolbarContent

                        if !overlayPosition.isTrailing {
                            Spacer()
                        }
                    }

                    if !overlayPosition.isTop {
                        Spacer()
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        VStack(alignment: overlayPosition.horizontalAlignment, spacing: 8) {
            if isExpanded {
                controlsPanel
                    .transition(.scale(scale: 0.8, anchor: overlayPosition.scaleAnchor).combined(with: .opacity))
            }

            // Floating button
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "xmark.circle.fill" : "paintbrush.fill")
                        .font(.system(size: 14, weight: .semibold))

                    if !isExpanded {
                        Text("Design")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)
            .onTapGesture(count: 2) {
                // Double-click to cycle position
                withAnimation(.spring(response: 0.3)) {
                    overlayPosition = overlayPosition.next
                }
            }
        }
    }

    @ViewBuilder
    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Visual Decorators")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Position indicator
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        overlayPosition = overlayPosition.next
                    }
                }) {
                    Image(systemName: overlayPosition.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Toggle controls
            toggleRow(
                icon: "grid",
                label: "8pt Grid",
                isOn: $designMode.showGrid
            )

            toggleRow(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                label: "Spacing",
                isOn: $designMode.showSpacing
            )

            toggleRow(
                icon: "textformat.size",
                label: "Typography",
                isOn: $designMode.showTypography
            )

            toggleRow(
                icon: "paintpalette",
                label: "Colors",
                isOn: $designMode.showColors
            )

            toggleRow(
                icon: "square.dashed",
                label: "Borders",
                isOn: $designMode.showBorders
            )

            Divider()
                .background(Color.white.opacity(0.2))

            // Quick actions
            HStack(spacing: 6) {
                Button(action: { designMode.toggleAllDecorators() }) {
                    Text(designMode.hasActiveDecorators ? "All Off" : "All On")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { designMode.resetDecorators() }) {
                    Text("Reset")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .frame(width: 200)
    }

    @ViewBuilder
    private func toggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? .cyan : .white.opacity(0.5))
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                // Toggle indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn.wrappedValue ? Color.cyan : Color.white.opacity(0.2))
                        .frame(width: 32, height: 18)

                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .offset(x: isOn.wrappedValue ? 7 : -7)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overlay Position

enum DesignOverlayPosition {
    case bottomTrailing
    case bottomLeading
    case topTrailing
    case topLeading

    var isTop: Bool {
        self == .topTrailing || self == .topLeading
    }

    var isTrailing: Bool {
        self == .bottomTrailing || self == .topTrailing
    }

    var horizontalAlignment: HorizontalAlignment {
        isTrailing ? .trailing : .leading
    }

    var scaleAnchor: UnitPoint {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }

    var icon: String {
        switch self {
        case .bottomTrailing: return "arrow.down.right"
        case .bottomLeading: return "arrow.down.left"
        case .topTrailing: return "arrow.up.right"
        case .topLeading: return "arrow.up.left"
        }
    }

    var next: DesignOverlayPosition {
        switch self {
        case .bottomTrailing: return .bottomLeading
        case .bottomLeading: return .topLeading
        case .topLeading: return .topTrailing
        case .topTrailing: return .bottomTrailing
        }
    }
}

#Preview("Design Overlay") {
    ZStack {
        Color.gray.opacity(0.1)

        DesignOverlay()
    }
    .frame(width: 800, height: 600)
    .onAppear {
        DesignModeManager.shared.isEnabled = true
    }
}

#endif
