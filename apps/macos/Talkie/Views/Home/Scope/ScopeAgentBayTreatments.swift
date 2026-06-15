//
//  ScopeAgentBayTreatments.swift
//  Talkie macOS
//

import SwiftUI

// MARK: - More agent bay treatments

/// Inner highlight (top) + inner shadow (bottom) so the bay reads as
/// physically sunk into the cream desk. Drawn as two thin gradient
/// rings inside the rounded rect. Light schemes use a much softer
/// shadow - a heavy black ring on cream paper reads as cheap chrome.
struct BezelOverlay: View {
    let scheme: BayScheme

    var body: some View {
        let highlightTop = scheme.isLight ? 0.45 : 0.10
        let highlightMid = scheme.isLight ? 0.10 : 0.02
        let shadowMid    = scheme.isLight ? 0.06 : 0.20
        let shadowBottom = scheme.isLight ? 0.14 : 0.45

        ZStack {
            // Top inner highlight - catches the light from above.
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlightTop),
                            Color.white.opacity(highlightMid),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)

            // Bottom inner shadow - recess cue.
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(shadowMid),
                            Color.black.opacity(shadowBottom)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(1.5)
        }
        .allowsHitTesting(false)
    }
}

/// 7-day phosphor heatmap. 7 columns x 5 rows of small cells; each
/// cell's opacity is seeded so the grid reads as a recent-activity
/// matrix without real data plumbing.
struct ActivityHeatmap: View {
    let scheme: BayScheme

    var body: some View {
        let cols = 7
        let rows = 5
        let cellSize: CGFloat = 8
        let gap: CGFloat = 2

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("LAST 7d")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(scheme.inkFaint)
                Spacer()
            }
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<cols, id: \.self) { c in
                            let intensity = ActivityHeatmap.intensity(row: r, col: c)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(scheme.cell(intensity: intensity))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .frame(width: CGFloat(cols) * cellSize + CGFloat(cols - 1) * gap, alignment: .leading)
    }

    static func intensity(row: Int, col: Int) -> Double {
        // Deterministic seeded intensity - diagonal-ish ramp w/ noise.
        let base = Double((col &* 23 &+ row &* 41 &+ 7) & 0xFF) / 255.0
        let bias = Double(col) / 7.0 * 0.4
        let v = base * 0.7 + bias
        return min(1.0, max(0.05, v))
    }
}

/// 24h tick ribbon. Each of 48 half-hour columns gets a vertical tick
/// whose height encodes synthetic activity density. Static.
struct TodayTimeline: View {
    let scheme: BayScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("00").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("06").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("12").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("18").chromeLabel(color: scheme.inkSubtle)
                Spacer()
                Text("24").chromeLabel(color: scheme.inkSubtle)
            }
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(0..<48, id: \.self) { i in
                        let intensity = TodayTimeline.intensity(slot: i)
                        Rectangle()
                            .fill(scheme.trace.opacity(0.18 + 0.55 * intensity))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(2, geo.size.height * CGFloat(intensity)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 14)
        }
    }

    static func intensity(slot: Int) -> Double {
        // Bursty pattern: heavier mid-morning + evening, quiet overnight.
        let hour = Double(slot) / 2.0
        let morning = exp(-pow((hour - 10) / 3.0, 2)) * 0.75
        let evening = exp(-pow((hour - 20) / 2.5, 2)) * 0.55
        let jitter = Double((slot &* 53 &+ 11) & 0xFF) / 255.0 * 0.15
        return min(1.0, max(0.04, morning + evening + jitter * 0.4))
    }
}

private extension Text {
    func chromeLabel(color: Color) -> some View {
        self
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Viewfinder-style L-shaped corner crops drawn inside the panel.
/// Inset slightly from the rounded edge so they read as crop marks,
/// not as a second border.
struct BayCornerBrackets: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 8
            let len: CGFloat = 10
            let w = geo.size.width
            let h = geo.size.height

            Path { p in
                // Top-left
                p.move(to: CGPoint(x: inset, y: inset + len))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: inset + len, y: inset))
                // Top-right
                p.move(to: CGPoint(x: w - inset - len, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset + len))
                // Bottom-left
                p.move(to: CGPoint(x: inset, y: h - inset - len))
                p.addLine(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset + len, y: h - inset))
                // Bottom-right
                p.move(to: CGPoint(x: w - inset - len, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset - len))
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
