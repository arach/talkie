//
//  CodexCommandDeckSurface.swift
//  Talkie iOS
//
//  THESIS: This is an exact-task instrument, not a generic remote-control grid.
//  OWN WORLD: Paper chassis, recessed graphite console, amber signal traces,
//  raised cream keycaps, green ownership confirmation, and red closed failures.
//  STORY: Pick one known task in the console lid, confirm ownership, speak, see where the turn went,
//  then read or hear the answer without returning to the Mac.
//  FIRST VIEWPORT: Live console above a navigation-only 3×4. The lid owns lane
//  selection while the fixed bottom rail owns push-to-talk and in-turn delivery.
//  FORM: Extends Talkie's established Scope instrument language and existing
//  bridge behavior. Nothing shown as live or locked is inferred locally.
//

import SwiftUI

struct CodexCommandDeckSurface: View {
    let onShowSpaces: () -> Void

    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var appSettings = TalkieAppSettings.shared
    @State private var showingMapper = false
    @State private var showingHistory = false
    @State private var showingResponse = false
    @State private var showingStatus = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            CodexCommandConsole(onShowMapper: openMapper)
                .frame(height: 226)

            keybed
                .layoutPriority(60)

            CodexCaptureRail()
                .frame(height: 76)
                .padding(.horizontal, 12)
                .dynamicTypeSize(.xSmall ... .xxxLarge)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingMapper) {
            CodexLaneMapperView()
        }
        .sheet(isPresented: $showingHistory) {
            CodexTurnHistorySheet()
        }
        .sheet(isPresented: $showingResponse) {
            if let turn = store.lastTurn {
                CodexResponseSheet(turn: turn)
            }
        }
        .sheet(isPresented: $showingStatus) {
            CodexDeckStatusSheet()
        }
    }

    private var keybed: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                outputDial(index: 1)
                actionKey(index: 2, label: "Mapper", icon: "rectangle.3.group", action: openMapper)
                actionKey(index: 3, label: "Status", icon: "rectangle.inset.filled", action: { showingStatus = true })
                actionKey(
                    index: 4,
                    label: "Revalidate",
                    icon: "arrow.clockwise",
                    isEnabled: store.activeLaneNumber != nil,
                    action: store.revalidateActiveLane
                )
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                actionKey(
                    index: 5,
                    label: "History",
                    icon: "clock.arrow.circlepath",
                    isEnabled: !store.history.isEmpty,
                    action: { showingHistory = true }
                )
                actionKey(index: 6, label: "Spaces", icon: "square.grid.2x2", action: onShowSpaces)
                actionKey(
                    index: 7,
                    label: "Replay",
                    icon: "play",
                    isEnabled: store.lastTurn != nil,
                    action: { showingResponse = true }
                )
                actionKey(
                    index: 8,
                    label: "Narrate",
                    icon: "speaker.wave.2",
                    isEnabled: store.lastTurn != nil,
                    action: store.narrateLastResponse
                )
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                openSocket(index: 9)
                openSocket(index: 10)
                openSocket(index: 11)
                openSocket(index: 12)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private func actionKey(
        index: Int,
        label: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .light))
                    .frame(height: 18)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? utilityInk : utilityInkFaint.opacity(0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .background(keycapSurface(active: false, isEmpty: false))
            .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func outputDial(index: Int) -> some View {
        Button(action: cycleOutputRoute) {
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                ZStack {
                    ForEach(0..<9, id: \.self) { tick in
                        Capsule()
                            .fill(utilityInkFaint.opacity(0.40))
                            .frame(width: 1, height: 4)
                            .offset(y: -24)
                            .rotationEffect(.degrees(Double(tick) * 30 - 120))
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [dialFace.opacity(0.88), dialFace],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.20), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.34), radius: 4, y: 3)

                    Capsule()
                        .fill(theme.chrome.panelAccent)
                        .frame(width: 2, height: 12)
                        .offset(y: -12)
                        .rotationEffect(outputDialAngle)
                        .talkieAccentGlow(radius: 3)
                }
                .frame(width: 52, height: 52)

                Text("OUTPUT · \(outputRoute.shortLabel)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(utilityInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .background(keycapSurface(active: false, isEmpty: false))
            .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Response output, \(outputRoute.displayName)")
        .accessibilityHint("Cycles between iPhone, Watch, and silent output")
        .animation(.spring(response: 0.32, dampingFraction: 0.74), value: outputRoute.rawValue)
        .sensoryFeedback(.selection, trigger: outputRoute.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSocket(index: Int) -> some View {
        ZStack {
            keycapSurface(active: false, isEmpty: true)
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .ultraLight))
                .foregroundStyle(utilityInkFaint.opacity(0.45))
        }
        .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open deck slot \(index)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keycapSurface(active: Bool, isEmpty: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let raisedShadow = colorScheme == .dark ? Color.black.opacity(0.42) : Color.black.opacity(0.16)
        return shape
            .fill(
                active
                    ? theme.chrome.accent.opacity(0.18)
                    : (isEmpty ? emptyKeyFace : utilityFace)
            )
            .overlay {
                if !isEmpty {
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.58), .clear, Color.black.opacity(0.045)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                if active {
                    shape.strokeBorder(theme.chrome.accent.opacity(0.72), lineWidth: 1)
                } else if isEmpty {
                    shape.strokeBorder(theme.chrome.edgeFaint, lineWidth: theme.chrome.hairlineWidth)
                }
            }
            .compositingGroup()
            .shadow(
                color: isEmpty ? .clear : raisedShadow,
                radius: isEmpty ? 0 : 8,
                y: isEmpty ? 0 : 5
            )
            .shadow(
                color: isEmpty ? .clear : Color.black.opacity(0.18),
                radius: isEmpty ? 0 : 2,
                y: isEmpty ? 0 : 2
            )
    }

    private func keyIndexLabel(index: Int) -> some View {
        Text(index < 10 ? "0\(index)" : "\(index)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(utilityInkFaint.opacity(0.56))
            .padding(.top, 7)
            .padding(.leading, 8)
            .allowsHitTesting(false)
    }

    private var outputRoute: AIResponseSpeechRoute {
        AIResponseSpeechRoute(rawValue: appSettings.aiVoiceOutputRoute) ?? .phone
    }

    private var utilityFace: Color {
        colorScheme == .dark
            ? theme.colors.cardBackground
            : Color(red: 0.965, green: 0.945, blue: 0.905)
    }

    private var emptyKeyFace: Color {
        colorScheme == .dark
            ? theme.colors.textPrimary.opacity(0.035)
            : Color(red: 0.30, green: 0.25, blue: 0.19).opacity(0.035)
    }

    private var utilityInk: Color {
        colorScheme == .dark
            ? theme.colors.textSecondary
            : Color(red: 0.28, green: 0.24, blue: 0.19)
    }

    private var utilityInkFaint: Color {
        colorScheme == .dark
            ? theme.colors.textTertiary
            : Color(red: 0.42, green: 0.36, blue: 0.28)
    }

    private var dialFace: Color {
        colorScheme == .dark
            ? theme.colors.textPrimary
            : Color(red: 0.995, green: 0.985, blue: 0.955)
    }

    private var outputDialAngle: Angle {
        switch outputRoute {
        case .silent: return .degrees(-80)
        case .phone: return .degrees(0)
        case .watch: return .degrees(80)
        }
    }

    private func cycleOutputRoute() {
        let next: AIResponseSpeechRoute
        switch outputRoute {
        case .phone: next = .watch
        case .watch: next = .silent
        case .silent: next = .phone
        }
        appSettings.aiVoiceOutputRoute = next.rawValue
    }

    private func openMapper() {
        showingMapper = true
    }

}

private struct CodexCommandConsole: View {
    let onShowMapper: () -> Void

    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var bridge = BridgeManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            consoleHeader

            VStack(alignment: .leading, spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityLaneTransport
                    accessibilityTaskIdentity
                } else {
                    lanePicker
                    taskIdentity
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 12)
        }
        .background {
            ZStack {
                consoleChassis
                diagonalTrace
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 0)
                .stroke(consoleInk.opacity(0.16), lineWidth: theme.chrome.hairlineWidth)
        }
        .dynamicTypeSize(.xSmall ... .accessibility1)
    }

    private var lanePicker: some View {
        HStack(spacing: 5) {
            HStack(spacing: 4) {
                ForEach(Array(CodexLane.range), id: \.self) { number in
                    lanePickerButton(number)
                }
            }

            Button(action: onShowMapper) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.chrome.panelInkFaint)
                    .frame(width: 44, height: 44)
                    .background(laneKeySurface(isActive: false))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map Codex task lanes")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.chrome.panelInk.opacity(0.13), lineWidth: theme.chrome.hairlineWidth)
        }
        .frame(height: 56)
        .sensoryFeedback(.selection, trigger: store.activeLaneNumber)
    }

    private func lanePickerButton(_ number: Int) -> some View {
        let lane = store.lane(number)
        let isActive = store.activeLaneNumber == number
        let isLocked = store.isLocked(number)
        let isEnabled = !store.isTurnInFlight && !store.phase.isCapturing

        return Button {
            guard let lane else {
                onShowMapper()
                return
            }
            Task { await store.activate(lane.number) }
        } label: {
            VStack(spacing: 3) {
                Text("\(number)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Circle()
                    .fill(laneStatusColor(lane: lane, isLocked: isLocked))
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isActive ? theme.chrome.panelInk : theme.chrome.panelInkFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(laneKeySurface(isActive: isActive))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.56)
        .accessibilityLabel(lanePickerAccessibilityLabel(number: number, lane: lane, isLocked: isLocked))
        .accessibilityHint(lane == nil ? "Opens the task mapper" : "Selects and validates this exact Codex task")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func laneKeySurface(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(isActive ? theme.colors.accent.opacity(0.20) : theme.chrome.panel)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), .clear, Color.black.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.stroke(
                    isActive ? theme.colors.accent.opacity(0.78) : theme.chrome.panelInk.opacity(0.15),
                    lineWidth: isActive ? 1 : theme.chrome.hairlineWidth
                )
            }
            .shadow(color: Color.black.opacity(0.12), radius: 3, y: 2)
    }

    private func laneStatusColor(lane: CodexLane?, isLocked: Bool) -> Color {
        guard lane != nil else { return theme.chrome.panelInkFaint.opacity(0.30) }
        return isLocked ? theme.colors.success : theme.chrome.panelAccent.opacity(0.78)
    }

    private func lanePickerAccessibilityLabel(
        number: Int,
        lane: CodexLane?,
        isLocked: Bool
    ) -> String {
        guard let lane else { return "Lane \(number), empty" }
        return "Lane \(number), \(lane.task.title), \(isLocked ? "ownership confirmed" : "mapped")"
    }

    private var consoleHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 9, weight: .medium))
            Text((bridge.pairedMacDisplayName ?? "MAC").uppercased())
                .lineLimit(1)
            Text("/")
                .foregroundStyle(consoleInkFaint.opacity(0.60))
            Text("CODEX")

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 5, height: 5)
                Text(store.phase.label.uppercased())
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(phaseColor.opacity(0.13))
            )
            .overlay(
                Capsule().stroke(phaseColor.opacity(0.42), lineWidth: 0.6)
            )
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(1.2)
        .foregroundStyle(consoleInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(consoleInk.opacity(0.16))
                .frame(height: theme.chrome.hairlineWidth)
        }
    }

    private var taskIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if let lane = store.activeLane {
                    Text(lane.number < 10 ? "LANE 0\(lane.number)" : "LANE \(lane.number)")
                        .foregroundStyle(theme.chrome.panelAccent)
                    ownershipBadge(isLocked: store.isLocked(lane.number))
                } else {
                    Text("NO ACTIVE TASK")
                        .foregroundStyle(theme.chrome.panelAccent)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.2)

            Text(store.activeLane?.task.title ?? "Choose a lane")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.chrome.panelInk)
                .lineLimit(2)

            Text(store.activeLane.map { "\($0.task.projectName)  ·  \($0.task.id)" } ?? "Tap an empty lane above to map an exact Codex task.")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(1)

            responseReadout
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 103, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.chrome.panelEdge.opacity(0.78), lineWidth: theme.chrome.hairlineWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskIdentityAccessibilityLabel)
    }

    @ViewBuilder
    private func ownershipBadge(isLocked: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isLocked ? theme.colors.success : theme.chrome.panelAccent)
                .frame(width: 4, height: 4)
            Text(isLocked ? "OWNERSHIP CONFIRMED" : "REVALIDATION REQUIRED")
        }
        .foregroundStyle(isLocked ? theme.colors.success : theme.chrome.panelAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((isLocked ? theme.colors.success : theme.chrome.panelAccent).opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke((isLocked ? theme.colors.success : theme.chrome.panelAccent).opacity(0.35), lineWidth: 0.5)
        )
    }

    private var responseReadout: some View {
        Group {
            if let failure = store.failure {
                Text(failure.combined)
                    .foregroundStyle(Color(red: 0.92, green: 0.42, blue: 0.30))
            } else if let turn = store.lastTurn,
                      turn.laneNumber == store.activeLaneNumber {
                Text(turn.response)
                    .foregroundStyle(theme.chrome.panelInk.opacity(0.82))
            } else if store.activeLane != nil {
                Text("Hold to talk. Talkie will send only to the confirmed task above.")
                    .foregroundStyle(theme.chrome.panelInkFaint)
            } else {
                Text("Pick a lane above to confirm exact task ownership on your Mac.")
                    .foregroundStyle(theme.chrome.panelInkFaint)
            }
        }
        .font(.system(size: 11, weight: .regular))
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
    }

    private var phaseColor: Color {
        switch store.phase {
        case .failed: return Color(red: 0.92, green: 0.42, blue: 0.30)
        case .idle:
            if let number = store.activeLaneNumber, store.isLocked(number) {
                return theme.colors.success
            }
            return theme.chrome.panelInkFaint
        default: return theme.chrome.panelAccent
        }
    }

    private var consoleChassis: Color {
        colorScheme == .dark
            ? theme.colors.cardBackground
            : Color(red: 0.90, green: 0.875, blue: 0.825)
    }

    private var consoleInk: Color {
        colorScheme == .dark
            ? theme.colors.textSecondary
            : Color(red: 0.25, green: 0.21, blue: 0.17)
    }

    private var consoleInkFaint: Color {
        colorScheme == .dark
            ? theme.colors.textTertiary
            : Color(red: 0.40, green: 0.34, blue: 0.27)
    }

    private var diagonalTrace: some View {
        Canvas { context, size in
            var path = Path()
            var offset: CGFloat = -size.height
            while offset < size.width {
                path.move(to: CGPoint(x: offset, y: size.height))
                path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                offset += 18
            }
            context.stroke(path, with: .color(theme.colors.accent.opacity(0.055)), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }

    private var accessibilityLaneTransport: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(CodexLane.range), id: \.self) { number in
                    lanePickerButton(number)
                        .frame(width: 44)
                }

                Button(action: onShowMapper) {
                    Label("Map", systemImage: "rectangle.3.group")
                        .font(.caption.bold())
                        .frame(minWidth: 64, minHeight: 44)
                        .background(laneKeySurface(isActive: false))
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
        )
        .accessibilityLabel("Codex lane transport")
    }

    private var accessibilityTaskIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.activeLane.map { "Lane \($0.number), \($0.task.projectName)" } ?? "No active task")
                .font(.caption.bold())
                .foregroundStyle(theme.chrome.panelAccent)

            Text(store.activeLane?.task.title ?? "Choose a lane")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.chrome.panelInk)
                .lineLimit(2)

            Text(store.isTurnInFlight ? "Turn active. Choose Queue or Steer in the bottom rail." : "The bottom rail sends only to this exact task.")
                .font(.caption)
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.chrome.panel)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskIdentityAccessibilityLabel)
    }

    private var taskIdentityAccessibilityLabel: String {
        guard let lane = store.activeLane else {
            return "No active Codex task. Choose a lane or open the mapper."
        }
        let ownership = store.isLocked(lane.number) ? "ownership confirmed" : "revalidation required"
        return "Lane \(lane.number), \(lane.task.projectName), \(lane.task.title), \(ownership)"
    }
}

private struct CodexCaptureRail: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            captureTarget

            if store.isTurnInFlight {
                duringTurnModeControl
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(7)
        .background(railSurface)
        .animation(.snappy(duration: 0.24), value: store.isTurnInFlight)
    }

    private var captureTarget: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.colors.accent.opacity(store.phase.isCapturing ? 0.24 : 0.12))
                Circle()
                    .stroke(theme.colors.accent.opacity(0.72), lineWidth: 1)
                Image(systemName: captureIcon)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(captureTitle)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(captureSubtitle)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(railInkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            if let number = store.activeLaneNumber, !store.isTurnInFlight {
                Text("L\(number)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(railInkFaint)
            }
        }
        .foregroundStyle(theme.colors.accent)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(theme.colors.accent.opacity(store.phase.isCapturing ? 0.13 : 0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: 44,
            pressing: { isPressed in
                if isPressed {
                    store.beginPushToTalk()
                } else {
                    store.endPushToTalk()
                }
            },
            perform: {}
        )
        .allowsHitTesting(canCapture)
        .opacity(store.activeLaneNumber == nil ? 0.48 : 1)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(captureTitle)
        .accessibilityHint(captureAccessibilityHint)
        .accessibilityAction { store.handleCaptureControl() }
    }

    private var duringTurnModeControl: some View {
        HStack(spacing: 4) {
            duringTurnModeButton(.queue, icon: "tray.and.arrow.down")
            duringTurnModeButton(.steer, icon: "arrow.triangle.turn.up.right.diamond")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("During-turn delivery")
    }

    private func duringTurnModeButton(_ mode: CodexMessageMode, icon: String) -> some View {
        let isSelected = store.duringTurnMessageMode == mode

        return Button {
            store.setDuringTurnMessageMode(mode)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(mode.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.3)
            }
            .foregroundStyle(isSelected ? railInk : railInkFaint)
            .frame(width: 49, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.colors.accent.opacity(0.20) : railFace)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? theme.colors.accent.opacity(0.76) : railInk.opacity(0.14),
                        lineWidth: isSelected ? 1 : theme.chrome.hairlineWidth
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.label) the next message")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var railSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return shape
            .fill(railFace)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.09 : 0.54), .clear, Color.black.opacity(0.045)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                shape.stroke(theme.colors.accent.opacity(0.64), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.16), radius: 9, y: 5)
    }

    private var railFace: Color {
        colorScheme == .dark
            ? theme.colors.cardBackground
            : Color(red: 0.97, green: 0.945, blue: 0.90)
    }

    private var railInk: Color {
        colorScheme == .dark
            ? theme.colors.textPrimary
            : Color(red: 0.25, green: 0.21, blue: 0.17)
    }

    private var railInkFaint: Color {
        colorScheme == .dark
            ? theme.colors.textSecondary
            : Color(red: 0.40, green: 0.34, blue: 0.27)
    }

    private var canCapture: Bool {
        store.activeLaneNumber != nil
            && (!store.phase.isBusy
                || store.phase.isCapturing
                || store.phase == .speaking
                || store.isTurnInFlight)
    }

    private var captureTitle: String {
        switch store.phase {
        case .listening:
            return store.isTurnInFlight
                ? "RELEASE TO \(store.duringTurnMessageMode.label.uppercased())"
                : "RELEASE TO SEND"
        case .speaking: return "INTERRUPT + TALK"
        case .submitting where store.isTurnInFlight:
            return "HOLD TO \(store.duringTurnMessageMode.label.uppercased())"
        default: return "HOLD TO TALK"
        }
    }

    private var captureSubtitle: String {
        switch store.phase {
        case .listening: return "KEEP HOLDING WHILE YOU SPEAK"
        case .speaking: return "STOPS NARRATION, THEN LISTENS"
        case .submitting where store.isTurnInFlight:
            if store.duringTurnMessageMode == .queue {
                let suffix = store.queuedMessageCount > 0
                    ? " · \(store.queuedMessageCount) WAITING"
                    : ""
                return "AFTER THIS TURN\(suffix)"
            }
            return "ADDS TO THE ACTIVE TURN NOW"
        default: return "EXACT TASK ROUTING"
        }
    }

    private var captureIcon: String {
        switch store.phase {
        case .listening: return "arrow.up"
        case .speaking: return "waveform"
        case .submitting where store.isTurnInFlight: return "mic"
        case .validating, .transcribing, .submitting, .preparingSpeech: return "ellipsis"
        case .idle, .failed: return "mic"
        }
    }

    private var captureAccessibilityHint: String {
        guard store.isTurnInFlight else {
            return "Sends speech only to the selected exact Codex task"
        }
        switch store.duringTurnMessageMode {
        case .queue:
            return "Queues the message to run after the current Codex turn"
        case .steer:
            return "Steers the current Codex turn immediately"
        case .auto:
            return "Sends speech to the selected exact Codex task"
        }
    }
}

private struct CodexDeckStatusSheet: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                List {
                    Section("Active task") {
                        if let lane = store.activeLane {
                            LabeledContent("Lane", value: "\(lane.number)")
                            LabeledContent("Task", value: lane.task.title)
                            LabeledContent("Project", value: lane.task.projectName)
                            LabeledContent("Ownership", value: store.isLocked(lane.number) ? "Confirmed" : "Revalidation required")
                        } else {
                            Text("No lane is active.")
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                    }

                    Section("Voice loop") {
                        LabeledContent("Phase", value: store.phase.label)
                        if let failure = store.failure {
                            Text(failure.combined)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let turn = store.lastTurn {
                        Section("Last delivery") {
                            LabeledContent("Result", value: turn.delivery.label)
                            LabeledContent("Task", value: turn.taskTitle)
                            Text(turn.response)
                                .lineLimit(4)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Codex Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CodexTurnHistorySheet: View {
    @ObservedObject private var store = CodexLaneStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                List(store.history) { turn in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("LANE \(turn.laneNumber)")
                            Spacer()
                            Text(turn.delivery.label.uppercased())
                        }
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)

                        Text(turn.taskTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)

                        Text(turn.instruction)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(2)

                        Text(turn.response)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(theme.colors.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Codex History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension AIResponseSpeechRoute {
    var shortLabel: String {
        switch self {
        case .phone: return "PHONE"
        case .watch: return "WATCH"
        case .silent: return "MUTE"
        }
    }
}
