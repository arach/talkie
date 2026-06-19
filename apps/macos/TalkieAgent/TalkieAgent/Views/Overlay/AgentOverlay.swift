//
//  AgentOverlay.swift
//  TalkieAgent
//
//  Shared presentation shell for agent-owned top overlays.
//

import SwiftUI
import TalkieKit

struct AgentOverlay: View {
    enum AnimationStyle {
        case none
        case particles(calm: Bool, speedMultiplier: Double)
        case waveform(sensitive: Bool)
        case island
    }

    enum AnimationDirection {
        case inbound
        case outbound
    }

    enum ControlVisibility {
        case hidden
        case onHover
        case always
    }

    let animationStyle: AnimationStyle
    let animationDirection: AnimationDirection
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let backgroundFill: Color
    let borderColor: Color
    let audioLevel: Float?
    let controlVisibility: ControlVisibility
    let content: AnyView?
    let leadingControl: AnyView?
    let trailingControl: AnyView?
    /// When non-nil, the particle stream coasts to a halt starting at this
    /// reference-date timestamp (used for the recording-stop transition).
    var settleStartReference: TimeInterval? = nil

    @State private var isHovered = false

    var body: some View {
        ZStack {
            animationLayer

            if let content {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showsControls {
                HStack {
                    if let leadingControl {
                        leadingControl
                            .padding(.leading, 14)
                    }

                    Spacer()

                    if let trailingControl {
                        trailingControl
                            .padding(.trailing, 14)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: width, height: height)
        .recordingIndicatorSurface(
            backgroundFill: backgroundFill,
            borderColor: borderColor,
            cornerRadius: cornerRadius
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var animationLayer: some View {
        switch animationStyle {
        case .none:
            EmptyView()
        case .particles(let calm, let speedMultiplier):
            WavyParticlesView(
                calm: calm,
                direction: animationDirection,
                levelOverride: audioLevel,
                speedMultiplier: speedMultiplier,
                settleStartReference: settleStartReference
            )
        case .waveform(let sensitive):
            WaveformBarsView(sensitive: sensitive, direction: animationDirection, levelOverride: audioLevel)
        case .island:
            IslandPillShapesView(direction: animationDirection, levelOverride: audioLevel)
        }
    }

    private var showsControls: Bool {
        switch controlVisibility {
        case .hidden:
            return false
        case .onHover:
            return isHovered
        case .always:
            return true
        }
    }
}
