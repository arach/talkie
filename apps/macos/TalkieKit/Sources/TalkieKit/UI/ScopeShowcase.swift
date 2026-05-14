//
//  ScopeShowcase.swift
//  TalkieKit
//
//  Visual exercise of the Scope tokens + components. Not shipped — its
//  only consumer is the Xcode preview / DesignMode harness. Edit and
//  re-preview to dial values.
//

import SwiftUI

/// Standalone preview surface that exercises every Scope primitive on
/// a single panel. Open this file in Xcode to see live rendering.
public struct ScopeShowcase: View {
    public init() {}

    public var body: some View {
        ZStack {
            ScopeCanvas.canvas.ignoresSafeArea()
            GraticuleBackground(pitch: 48, color: ScopeTrace.faint, opacity: 0.40)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    headerSection
                    cardsSection
                    panelSection
                    inkSection
                    edgeSection
                    typeSection
                }
                .padding(40)
            }
        }
        .frame(minWidth: 720, minHeight: 800)
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Scope · Cream Phosphor")
            Text("Lab instrument vocabulary.")
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(ScopeInk.primary)
            Text("Tokens and primitives ported from the usetalkie.com homepage. Layered on top of the existing TalkieTheme — not a replacement.")
                .font(.system(size: 14))
                .foregroundStyle(ScopeInk.muted)
                .frame(maxWidth: 520, alignment: .leading)
            ScopeDivider()
                .padding(.top, 12)
        }
    }

    // MARK: Cards

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("Capture Modes")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                spacing: 16
            ) {
                CaptureCard(
                    eyebrow: "Capture",
                    channel: "CH-01",
                    title: "Catch it before it changes.",
                    copy: "Record on iPhone, Watch, or Mac. Transcript stays in one place."
                )
                CaptureCard(
                    eyebrow: "Dictation",
                    channel: "CH-02",
                    title: "Speak straight into the work.",
                    copy: "Hotkey on Mac. Dictate into whatever app you’re already in."
                )
            }
        }
    }

    // MARK: Dark panel embedded in cream page

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Agent Handoff")
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ScopePanel.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ScopePanel.Edge.normal, lineWidth: 1)
                    )
                GraticuleBackground(pitch: 24, color: ScopePanel.traceFaint, opacity: 0.55)
                    .mask(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 0) {
                    panelHeader
                    Spacer()
                    panelFooter
                }
                .padding(.vertical, 10)
            }
            .frame(height: 180)
            .shadow(color: .black.opacity(0.18), radius: 30, y: 18)
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            PhosphorDot(color: ScopePanel.trace, size: 6)
            Text("RUNNING · AG-01 / VOICE.IN")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text("SPEC · ON  10.23AM · MONO")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
        }
    }

    private var panelFooter: some View {
        HStack {
            Text("· TRIG · LIVE · SIGNAL PATH · LOCAL ONLY")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkFaint)
            Spacer()
            Text("SCOUT · CODEX · HANDOFF ·")
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopePanel.inkSubtle)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(ScopePanel.Edge.faint).frame(height: 1)
        }
    }

    // MARK: Ink ramp

    private var inkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Ink Ramp")
            VStack(alignment: .leading, spacing: 4) {
                Text("Primary — headline / highest contrast").foregroundStyle(ScopeInk.primary)
                Text("Dim — subhead / body lead").foregroundStyle(ScopeInk.dim)
                Text("Muted — paragraph body").foregroundStyle(ScopeInk.muted)
                Text("Faint — captions / secondary").foregroundStyle(ScopeInk.faint)
                Text("Subtle — metadata / chrome").foregroundStyle(ScopeInk.subtle)
            }
            .font(.system(size: 13))
        }
    }

    // MARK: Edge ramp

    private var edgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Edge Ramp")
            HStack(spacing: 12) {
                edgeSwatch("strong", color: ScopeEdge.strong)
                edgeSwatch("normal", color: ScopeEdge.normal)
                edgeSwatch("faint",  color: ScopeEdge.faint)
                edgeSwatch("subtle", color: ScopeEdge.subtle)
            }
        }
    }

    private func edgeSwatch(_ label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(color, lineWidth: 1)
                .frame(width: 110, height: 60)
            ChannelLabel(label)
        }
    }

    // MARK: Type specimens

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Type Specimens")
            VStack(alignment: .leading, spacing: 8) {
                Text("· EYEBROW 10pt mono semibold")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow()
                HStack(spacing: 10) {
                    ChannelLabel("CH-01")
                    ChannelLabel("AG-01")
                    ChannelLabel("U1")
                    ChannelLabel("RUN", color: ScopeAmber.solid)
                }
                Text("CHROME · 8pt mono · TECHNICAL METADATA")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.faint)
            }
        }
    }
}

// MARK: - Capture card (homepage parity)

private struct CaptureCard: View {
    let eyebrow: String
    let channel: String
    let title: String
    let copy: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(ScopeCanvas.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ScopeEdge.normal, lineWidth: 1)
                )
            GraticuleBackground(pitch: 24, color: ScopeTrace.faint, opacity: 0.50)
                .mask(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 10) {
                        amberSquare
                        Text(eyebrow.uppercased())
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(ScopeInk.faint)
                    }
                    Spacer()
                    Text(channel.uppercased())
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.subtle)
                }

                Rectangle().fill(ScopeEdge.subtle).frame(height: 1)

                Text(title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(ScopeInk.primary)
                    .lineLimit(2)

                Text(copy)
                    .font(.system(size: 13))
                    .foregroundStyle(ScopeInk.muted)
                    .lineLimit(3)

                HStack(spacing: 4) {
                    Text("EXPLORE")
                        .font(ScopeType.channel)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeInk.faint)
                    Text("→")
                        .font(.system(size: 11))
                        .foregroundStyle(ScopeInk.faint)
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .frame(minHeight: 200)
    }

    private var amberSquare: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ScopeAmber.tintSubtle)
            .frame(width: 30, height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(ScopeEdge.normal, lineWidth: 1)
            )
            .overlay(
                Image(systemName: "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(ScopeAmber.solid)
                    .phosphorGlow(radius: 3, opacity: 0.32)
            )
    }
}

#Preview("Scope Showcase") {
    ScopeShowcase()
}
