//
//  CodexCommandDeckSurface.swift
//  Talkie iOS
//
//  THESIS: This is an exact-task instrument, not a generic remote-control grid.
//  OWN WORLD: Paper chassis, recessed graphite console, amber signal traces,
//  raised cream keycaps, amber lane signals, and red closed failures.
//  STORY: Pick one known task in the console lid, speak, see where the turn went,
//  then read or hear the answer without returning to the Mac.
//  FIRST VIEWPORT: Live console above a 4×4 command keybed. The lid owns lane
//  selection, delivery mode, and host activity; the stable keybed owns talk.
//  FORM: Extends Talkie's established Scope instrument language and existing
//  bridge behavior. A lane is a direct destination, not a separate claim.
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
                .frame(height: store.activeLaneIsInFlight ? 318 : 274)
                .animation(.easeInOut(duration: 0.22), value: store.activeLaneIsInFlight)

            keybed
                .layoutPriority(60)
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
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                outputDial(index: 1)
                actionKey(index: 2, label: "Mapper", icon: "rectangle.3.group", action: openMapper)
                actionKey(index: 3, label: "Status", icon: "rectangle.inset.filled", action: { showingStatus = true })
                actionKey(
                    index: 4,
                    label: "Refresh",
                    icon: "arrow.clockwise",
                    isEnabled: !store.isLoadingCatalog,
                    action: { Task { await store.refreshCatalog() } }
                )
            }

            GridRow {
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

            GridRow {
                openSocket(index: 9)
                openSocket(index: 10)
                actionKey(
                    index: 11,
                    label: "Stop",
                    icon: "stop.fill",
                    isEnabled: store.phase == .speaking || store.phase == .preparingSpeech,
                    action: store.interruptNarration
                )
                openSocket(index: 12)
            }

            GridRow {
                openSocket(index: 13)
                captureKey
                    .gridCellColumns(2)
                openSocket(index: 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private func actionKey(
        index: Int,
        label: String,
        icon: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
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
            .background(keycapSurface(active: isActive, isEmpty: false))
            .overlay(alignment: .topLeading) { keyIndexLabel(index: index) }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureKey: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.colors.accent.opacity(store.phase.isCapturing ? 0.24 : 0.10))
                    Circle()
                        .stroke(theme.colors.accent.opacity(0.68), lineWidth: 1)
                    Image(systemName: captureIcon)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(captureTitle)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(captureSubtitle)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.45)
                        .foregroundStyle(utilityInkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(keycapSurface(active: store.phase.isCapturing, isEmpty: false))
            .overlay(alignment: .topLeading) { keyIndexLabel(index: 14) }
            .overlay(alignment: .topTrailing) { trailingKeyIndexLabel(index: 15) }
        }
        .buttonStyle(
            CodexPressAndHoldButtonStyle { isPressed in
                if isPressed {
                    store.beginPushToTalk()
                } else {
                    store.endPushToTalk()
                }
            }
        )
        .disabled(!canCapture)
        .opacity(store.activeLaneNumber == nil ? 0.48 : 1)
        .accessibilityLabel(captureTitle)
        .accessibilityHint(captureAccessibilityHint)
        .accessibilityAction { store.handleCaptureControl() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            return store.activeLaneIsInFlight
                ? "RELEASE TO \(store.activeLaneMessageMode.label.uppercased())"
                : "RELEASE TO SEND"
        case .speaking: return "INTERRUPT + TALK"
        case .submitting where store.activeLaneIsInFlight:
            return "HOLD TO \(store.activeLaneMessageMode.label.uppercased())"
        default: return "HOLD TO TALK"
        }
    }

    private var captureSubtitle: String {
        switch store.phase {
        case .listening: return "KEEP HOLDING WHILE YOU SPEAK"
        case .speaking: return "STOPS NARRATION, THEN LISTENS"
        case .submitting where store.activeLaneIsInFlight:
            if store.activeLaneMessageMode == .queue {
                let queued = store.activeLaneNumber.map(store.queuedMessageCount(for:)) ?? 0
                let suffix = queued > 0
                    ? " · \(queued) WAITING"
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
        case .submitting where store.activeLaneIsInFlight: return "mic"
        case .transcribing, .submitting, .preparingSpeech: return "ellipsis"
        case .idle, .failed: return "mic"
        }
    }

    private var captureAccessibilityHint: String {
        guard store.activeLaneIsInFlight else {
            return "Sends speech to the active Codex task"
        }
        switch store.activeLaneMessageMode {
        case .queue:
            return "Queues the message to run after the current Codex turn"
        case .steer:
            return "Steers the current Codex turn immediately"
        case .auto:
            return "Sends speech to the active Codex task"
        }
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

    private func trailingKeyIndexLabel(index: Int) -> some View {
        Text("\(index)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(utilityInkFaint.opacity(0.56))
            .padding(.top, 7)
            .padding(.trailing, 8)
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
            ? Color(red: 0.30, green: 0.285, blue: 0.265)
            : Color(red: 0.86, green: 0.825, blue: 0.76)
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
        let isEnabled = !store.phase.isCapturing

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

                Text(laneModeMark(lane))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(laneStatusColor(lane: lane, isActive: isActive))
            }
            .foregroundStyle(isActive ? theme.chrome.panelInk : theme.chrome.panelInkFaint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(laneKeySurface(isActive: isActive))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isActive ? 1 : 0.56)
        .accessibilityLabel(lanePickerAccessibilityLabel(number: number, lane: lane, isActive: isActive))
        .accessibilityHint(lane == nil ? "Opens the task mapper" : "Selects this exact Codex task")
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

    private func laneStatusColor(lane: CodexLane?, isActive: Bool) -> Color {
        guard lane != nil else { return theme.chrome.panelInkFaint.opacity(0.30) }
        return theme.chrome.panelAccent.opacity(isActive ? 1 : 0.62)
    }

    private func laneModeMark(_ lane: CodexLane?) -> String {
        guard let lane else { return "––" }
        let mode = lane.preferredMessageMode == .queue ? "Q" : "S"
        guard store.isTurnInFlight(on: lane.number) else { return mode }
        return "\(mode)•"
    }

    private func lanePickerAccessibilityLabel(
        number: Int,
        lane: CodexLane?,
        isActive: Bool
    ) -> String {
        guard let lane else { return "Lane \(number), empty" }
        return "Lane \(number), \(lane.task.title), \(isActive ? "selected" : "mapped")"
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
                Text(consoleStatusLabel)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let lane = store.activeLane {
                    Text(lane.number < 10 ? "LANE 0\(lane.number)" : "LANE \(lane.number)")
                        .foregroundStyle(theme.chrome.panelAccent)

                    Text(lane.task.activityLabel().uppercased())
                        .foregroundStyle(theme.chrome.panelInkFaint)

                    Spacer(minLength: 6)

                    laneModeSelector(lane)
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

            if let task = store.activeLane?.task {
                HStack(spacing: 6) {
                    Label(task.projectName, systemImage: "folder")
                    if let branch = task.branchName {
                        Text("/")
                            .foregroundStyle(theme.chrome.panelInkFaint.opacity(0.55))
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(1)

                if !store.activeLaneIsInFlight {
                    Text(task.compactPath)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(theme.chrome.panelInkFaint.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Tap an empty lane above to map an exact Codex task.")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.chrome.panelInkFaint)
                    .lineLimit(2)
            }

            conversationPreview
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: store.activeLaneIsInFlight ? 189 : 145,
            alignment: .topLeading
        )
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
    private var conversationPreview: some View {
        if let number = store.activeLaneNumber,
           let activity = store.activity(for: number) {
            liveActivity(activity, laneNumber: number)
        } else if let failure = store.failure {
            Label(failure.combined, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(red: 0.92, green: 0.42, blue: 0.30))
                .lineLimit(2)
        } else if let number = store.activeLaneNumber,
                  let turn = store.latestTurn(for: number) {
            VStack(alignment: .leading, spacing: 4) {
                conversationLine(label: "YOU", text: turn.instruction, lineLimit: 1)
                conversationLine(label: "CODEX", text: turn.response, lineLimit: 2)
            }
            .padding(.top, 2)
        } else if store.activeLane != nil {
            Text("Hold the 14–15 key to talk directly to this task.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        } else {
            Text("Pick a lane above, or open Mapper to choose an exact task.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInkFaint)
                .lineLimit(2)
        }
    }

    private func laneModeSelector(_ lane: CodexLane) -> some View {
        HStack(spacing: 2) {
            laneModeButton(.steer, lane: lane)
            laneModeButton(.queue, lane: lane)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.chrome.panelInk.opacity(0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(theme.chrome.panelInk.opacity(0.13), lineWidth: theme.chrome.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lane \(lane.number) delivery mode")
    }

    private func laneModeButton(_ mode: CodexMessageMode, lane: CodexLane) -> some View {
        let isActive = lane.preferredMessageMode == mode
        return Button {
            store.setMessageMode(mode, for: lane.number)
        } label: {
            Text(mode.label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(isActive ? theme.chrome.panel : theme.chrome.panelInkFaint)
                .frame(minWidth: 43, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? theme.chrome.panelAccent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func liveActivity(_ activity: CodexLaneActivity, laneNumber: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            conversationLine(label: "TX", text: activity.instruction, lineLimit: 1)

            switch activity.state {
            case .working(let mode):
                if !activity.updates.isEmpty {
                    ForEach(Array(activity.updates.suffix(2))) { update in
                        progressLine(
                            update,
                            isLatest: update.id == activity.updates.last?.id
                        )
                    }
                }
                CodexWorkingSignal(
                    mode: mode,
                    queuedCount: store.queuedMessageCount(for: laneNumber),
                    color: theme.chrome.panelAccent,
                    secondaryColor: theme.chrome.panelInkFaint
                )
            case .accepted:
                technicalLine("HOST> STEER ACCEPTED // TURN CONTINUES")
            case .receiving:
                if let response = activity.response {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("RX")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(theme.chrome.panelAccent)
                            .frame(width: 38, alignment: .leading)

                        CodexPipedText(
                            text: response,
                            color: theme.chrome.panelInk.opacity(0.88)
                        )
                    }
                }
            case .failed(let message):
                technicalLine("ERR> \(message)", isFailure: true)
            }
        }
        .padding(.top, 2)
    }

    private func progressLine(_ update: CodexProgressUpdate, isLatest: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(update.kind == "tool" ? "SYS" : "LIVE")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(
                    update.kind == "tool"
                        ? theme.chrome.panelInkFaint
                        : theme.chrome.panelAccent
                )
                .frame(width: 38, alignment: .leading)

            Text(update.text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInk.opacity(isLatest ? 0.90 : 0.62))
                .lineLimit(isLatest && update.kind != "tool" ? 3 : 1)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .accessibilityElement(children: .combine)
    }

    private func technicalLine(_ text: String, isFailure: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.25)
            .foregroundStyle(
                isFailure
                    ? Color(red: 0.92, green: 0.42, blue: 0.30)
                    : theme.chrome.panelInkFaint
            )
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func conversationLine(label: String, text: String, lineLimit: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(theme.chrome.panelAccent)
                .frame(width: 38, alignment: .leading)

            Text(text)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.chrome.panelInk.opacity(0.82))
                .lineLimit(lineLimit)
        }
    }

    private var consoleStatusLabel: String {
        switch store.phase {
        case .listening, .transcribing, .preparingSpeech, .speaking:
            return store.phase.label.uppercased()
        case .failed:
            return "ERROR"
        case .idle, .submitting:
            break
        }

        guard let number = store.activeLaneNumber,
              let activity = store.activity(for: number) else {
            return store.activeLaneNumber == nil ? "NO LANE" : "READY"
        }
        switch activity.state {
        case .working(let mode):
            return mode == .queue ? "QUEUED" : "WORKING"
        case .accepted:
            return "STEERED"
        case .receiving:
            return "RESPONSE"
        case .failed:
            return "ERROR"
        }
    }

    private var phaseColor: Color {
        if let number = store.activeLaneNumber,
           case .failed = store.activity(for: number)?.state {
            return Color(red: 0.92, green: 0.42, blue: 0.30)
        }
        switch store.phase {
        case .failed: return Color(red: 0.92, green: 0.42, blue: 0.30)
        case .idle: return store.activeLaneNumber == nil
            ? theme.chrome.panelInkFaint
            : theme.chrome.panelAccent
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

            Text(store.activeLaneIsInFlight ? "Turn active. Delivery mode is set with the lane control above." : "Hold key 14–15 to talk directly to this task.")
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
        return "Lane \(lane.number), \(lane.task.projectName), \(lane.task.title)"
    }
}

private struct CodexWorkingSignal: View {
    let mode: CodexMessageMode
    let queuedCount: Int
    let color: Color
    let secondaryColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                signal(frame: 0)
            } else {
                TimelineView(.animation(minimumInterval: 0.14)) { timeline in
                    let frame = Int(timeline.date.timeIntervalSinceReferenceDate * 7) % 7
                    signal(frame: frame)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func signal(frame: Int) -> some View {
        let cells = (0..<7)
            .map { $0 == frame ? "◆" : "·" }
            .joined()
        return HStack(spacing: 7) {
            Text("HOST>")
                .foregroundStyle(color)
            Text("[\(cells)]")
                .foregroundStyle(color)
            Text(statusText)
                .foregroundStyle(secondaryColor)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(0.25)
        .lineLimit(1)
    }

    private var statusText: String {
        switch mode {
        case .queue:
            return queuedCount > 0 ? "QUEUE \(queuedCount) // WAIT" : "QUEUE // WAIT"
        case .steer:
            return "STEER // WORK"
        case .auto:
            return "TURN // WORK"
        }
    }

    private var accessibilityLabel: String {
        switch mode {
        case .queue: return "Message queued. Codex is working."
        case .steer: return "Steering message sent. Codex is working."
        case .auto: return "Message sent. Codex is working."
        }
    }
}

private struct CodexPipedText: View {
    let text: String
    let color: Color

    @State private var visibleCharacterCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(displayedText)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(color)
            .lineLimit(2)
            .task(id: text) {
                await revealText()
            }
            .accessibilityLabel(text)
    }

    private var displayedText: String {
        let visible = String(text.prefix(visibleCharacterCount))
        return visibleCharacterCount < text.count ? "\(visible)▌" : visible
    }

    private func revealText() async {
        guard !reduceMotion else {
            visibleCharacterCount = text.count
            return
        }

        visibleCharacterCount = 0
        while visibleCharacterCount < text.count, !Task.isCancelled {
            visibleCharacterCount = min(text.count, visibleCharacterCount + 4)
            try? await Task.sleep(for: .milliseconds(24))
        }
    }
}

private struct CodexPressAndHoldButtonStyle: ButtonStyle {
    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressingChanged(isPressed)
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
