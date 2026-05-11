import SwiftUI

struct NotchLabView: View {
    @State private var parameters = NotchParameters()
    @State private var curveMode: InnerCurveMode = .canonicalDownward
    @State private var showGuides = true
    @State private var showOutline = true
    @State private var compareAllModes = true
    @State private var liveSyncToTalkie = true

    private var shapeWidth: CGFloat {
        parameters.pokeOut * 2 + parameters.notchWidth
    }

    private var shapeHeight: CGFloat {
        max(parameters.height, parameters.notchHeight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            previewPane
            controlsPane
        }
        .padding(20)
        .frame(minWidth: 1000, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            pushLiveValues()
        }
        .onChange(of: parameters) { _, _ in
            pushLiveValues()
        }
        .onChange(of: curveMode) { _, _ in
            pushLiveValues()
        }
        .onChange(of: liveSyncToTalkie) { _, _ in
            pushLiveValues()
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Canonical Notch Drawing")
                .font(.title2.weight(.semibold))
            Text("Fixed center notch + independent side wings. Tune only the wing join behavior.")
                .foregroundStyle(.secondary)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.96))

                Rectangle()
                    .fill(Color.yellow.opacity(0.7))
                    .frame(height: 1)

                ZStack {
                    CanonicalNotchShape(parameters: parameters, curveMode: curveMode)
                        .fill(Color(white: 0.08))

                    if showOutline {
                        CanonicalNotchShape(parameters: parameters, curveMode: curveMode)
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }

                    if showGuides {
                        NotchGuideOverlay(parameters: parameters, curveMode: curveMode)
                    }

                    PhysicalNotchShape(bottomRadius: min(parameters.bottomRadius, parameters.notchHeight / 2))
                        .fill(Color.black)
                        .frame(width: parameters.notchWidth, height: parameters.notchHeight)
                        .frame(width: shapeWidth, height: shapeHeight, alignment: .top)

                    PhysicalNotchShape(bottomRadius: min(parameters.bottomRadius, parameters.notchHeight / 2))
                        .stroke(Color.cyan.opacity(0.95), style: .init(lineWidth: 1, dash: [5, 4]))
                        .frame(width: parameters.notchWidth, height: parameters.notchHeight)
                        .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
                }
                .frame(width: shapeWidth, height: shapeHeight)
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(curveMode.subtitle)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("Cyan dashed shape = fixed physical notch (not resized).")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)

            if compareAllModes {
                Divider()
                Text("Mode Comparison")
                    .font(.headline)

                HStack(spacing: 10) {
                    ForEach(InnerCurveMode.allCases) { mode in
                        VStack(spacing: 6) {
                            Text(mode.title)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(mode == curveMode ? .primary : .secondary)

                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.96))

                                Rectangle()
                                    .fill(Color.yellow.opacity(0.7))
                                    .frame(height: 1)

                                ZStack {
                                    CanonicalNotchShape(parameters: parameters, curveMode: mode)
                                        .fill(Color(white: 0.08))

                                    CanonicalNotchShape(parameters: parameters, curveMode: mode)
                                        .stroke(Color.white.opacity(0.9), lineWidth: 1)

                                    PhysicalNotchShape(bottomRadius: min(parameters.bottomRadius, parameters.notchHeight / 2))
                                        .fill(Color.black)
                                        .frame(
                                            width: parameters.notchWidth * 0.62,
                                            height: parameters.notchHeight * 0.9
                                        )
                                        .frame(
                                            width: shapeWidth * 0.62,
                                            height: shapeHeight * 0.9,
                                            alignment: .top
                                        )

                                    PhysicalNotchShape(bottomRadius: min(parameters.bottomRadius, parameters.notchHeight / 2))
                                        .stroke(Color.cyan.opacity(0.95), style: .init(lineWidth: 1, dash: [4, 3]))
                                        .frame(
                                            width: parameters.notchWidth * 0.62,
                                            height: parameters.notchHeight * 0.9
                                        )
                                        .frame(
                                            width: shapeWidth * 0.62,
                                            height: shapeHeight * 0.9,
                                            alignment: .top
                                        )
                                }
                                .frame(width: shapeWidth * 0.62, height: shapeHeight * 0.9)
                                .padding(.top, 1)
                            }
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(.headline)

            Picker("Inner Curve", selection: $curveMode) {
                ForEach(InnerCurveMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Compare All Modes", isOn: $compareAllModes)
            Toggle("Live Sync To Talkie", isOn: $liveSyncToTalkie)
            Toggle("Show Guides", isOn: $showGuides)
            Toggle("Show Outline", isOn: $showOutline)

            Divider()

            sliderRow("Wing Width", value: $parameters.pokeOut, range: 0...90, step: 1)
            sliderRow("Notch Width", value: $parameters.notchWidth, range: 120...280, step: 1)
            sliderRow("Notch Height", value: $parameters.notchHeight, range: 24...64, step: 1)
            sliderRow("Wing Height", value: $parameters.height, range: 22...64, step: 1)
            sliderRow("Top Outer Radius (+out / -in)", value: $parameters.topOuterRadius, range: -24...24, step: 1)
            sliderRow("Top Inner Radius (t)", value: $parameters.topInnerRadius, range: 0...28, step: 1)
            sliderRow("Bottom Radius", value: $parameters.bottomRadius, range: 0...28, step: 1)
            sliderRow("Notch Overlap", value: $parameters.notchOverlap, range: 0...24, step: 1)

            Divider()

            Group {
                Text("Canonical left inner curve:")
                Text("p.addQuadCurve(to: CGPoint(x: t, y: t),")
                Text("               control: CGPoint(x: t, y: 0))")
                Text("If this still looks straight, raise t and keep wing width >= t + outerRadius.")
                Text("Live sync suite: \(NotchLiveBridge.suiteName)")
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(width: 360, alignment: .topLeading)
    }

    private func sliderRow(
        _ title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func pushLiveValues() {
        guard liveSyncToTalkie else { return }
        guard let defaults = UserDefaults(suiteName: NotchLiveBridge.suiteName) else { return }

        defaults.set(Double(parameters.pokeOut), forKey: NotchLiveBridge.hoverPokeOutKey)
        defaults.set(Double(parameters.pokeOut), forKey: NotchLiveBridge.activePokeOutKey)
        defaults.set(Double(parameters.topOuterRadius), forKey: NotchLiveBridge.topOuterRadiusKey)
        defaults.set(Double(parameters.topOuterRadius), forKey: NotchLiveBridge.leftTopOuterRadiusKey)
        defaults.set(Double(parameters.topOuterRadius), forKey: NotchLiveBridge.rightTopOuterRadiusKey)
        defaults.set(Double(parameters.topInnerRadius), forKey: NotchLiveBridge.topInnerRadiusKey)
        defaults.set(Double(parameters.bottomRadius), forKey: NotchLiveBridge.bottomRadiusKey)
        defaults.set(Double(parameters.notchOverlap), forKey: NotchLiveBridge.notchOverlapKey)
        defaults.set(curveMode.rawValue, forKey: NotchLiveBridge.innerCurveModeKey)
    }
}
