//
//  PresetRecordingView.swift
//  TalkieWatch
//
//  Capture-in-motion. The quiet branded composition stays fixed while the
//  recording becomes a distinct live composition: REC state, the original
//  particle language, a centered elapsed-time readout, and a balanced
//  pause–stop rail in the lower reach zone. Transfer and outcome return to the
//  quiet branded face.
//
//  Sequence after stop:
//    • CAPTURED         — local capture finalized (brief, ~0.5s)
//    • SENDING…         — pushing audio to phone
//    • PHONE RECEIVED   — phone has the file
//    • TRANSCRIBING…    — phone is working
//    • → ASK AI / MEMO  — routed result (or → SAVED if status unknown)
//  Or, if the phone isn't nearby at stop time, jump straight to:
//    • QUEUED · WILL SEND WHEN PHONE IS NEAR (then return to picker
//      after a beat — never hang).
//

import SwiftUI
import WatchKit

struct PresetRecordingView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @Environment(\.watchThemeName) private var themeName
    let preset: WatchPreset
    @Binding var isRecording: Bool
    var onComplete: () -> Void

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .recording
    @State private var routeResult: RouteResult = .pending
    @State private var lastSentDuration: TimeInterval = 0
    @State private var currentMemoId: UUID?
    @State private var phaseDeadline: Task<Void, Never>?
    /// How far the paused face has been pushed toward the discard, in points
    /// along whichever of the two allowed directions is winning.
    @State private var discardPush: CGSize = .zero
    /// Set once per drag, so crossing the threshold ticks rather than buzzes
    /// continuously while the finger hovers on the line.
    @State private var discardArmed = false

    enum Phase: Equatable {
        case recording
        case captured     // local: audio finalized
        case sending      // transferring to phone
        case received     // phone has the file
        case transcribing // phone is processing
        case routed       // final outcome
        case queued       // phone not nearby — queued for later
        case failed(String)
    }

    enum RouteResult {
        case pending
        case askAI
        case memo
        case unknown
    }

    private var forcesAI: Bool { preset.intent == "ai" }

    var body: some View {
        ZStack {
            TalkieCaptureBackground()

            if phase == .recording {
                liveRecordingFace
            } else {
                TalkieCaptureLayout {
                    crossbarReadout
                } primary: {
                    buttonSlot
                } caption: {
                    EmptyView()
                } secondary: {
                    EmptyView()
                }
            }
        }
        .onAppear {
            WatchConsole.info(
                "[WatchCapture] opened intent=\(preset.intent ?? "auto") reachable=\(sessionManager.isReachable)"
            )
            recorder.startRecording()
        }
        .onChange(of: sessionManager.lastSentStatus) { _, newStatus in
            handleSendStatusChange(newStatus)
        }
        .onChange(of: latestMemoStatus) { _, status in
            handleMemoStatusChange(status)
        }
        .onDisappear { phaseDeadline?.cancel() }
    }

    private var liveRecordingFace: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 190
            let capture = themeName.captureStyle
            let material = capture.material

            ZStack {
                // Uncovered as the face is pushed aside, so the gesture explains
                // itself while it is happening instead of after it has taken
                // the recording.
                discardLegend(material: material)
                    .opacity(discardProgress)
                    .scaleEffect(0.92 + discardProgress * 0.08)

                Group {
                    if forcesAI {
                        aiVoiceMessageFace(
                            isCompact: compact,
                            accent: capture.trace,
                            material: material
                        )
                    } else {
                        memoRecordingFace(
                            isCompact: compact,
                            accent: capture.trace,
                            material: material
                        )
                    }
                }
                .offset(x: discardPush.width, y: discardPush.height)
                .opacity(1 - discardProgress * 0.72)
            }
            .gesture(discardGesture)
        }
    }

    // MARK: - Discard by gesture

    /// The push needed to commit, in points. Short enough to be one flick of a
    /// thumb, long enough that a wrist knocked against a doorway does not clear
    /// a recording — which is also why the whole gesture is gated on paused.
    private static let discardDistance: CGFloat = 56

    private var discardProgress: Double {
        let travelled = max(-discardPush.width, discardPush.height)
        return min(max(Double(travelled / Self.discardDistance), 0), 1)
    }

    private var discardGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // Pause is the consent. While the memo is still running the
                // face does not move at all, so there is nothing to discover
                // by accident mid-sentence.
                guard phase == .recording, recorder.isPaused else { return }

                // Left and down only. A push up or right is not a discard, so
                // it reads as the face refusing to move rather than as a
                // gesture that half-worked.
                let left = min(0, value.translation.width)
                let down = max(0, value.translation.height)
                let push = CGSize(
                    width: rubberBanded(left),
                    height: rubberBanded(down)
                )
                discardPush = abs(left) >= down
                    ? CGSize(width: push.width, height: 0)
                    : CGSize(width: 0, height: push.height)

                let armed = discardProgress >= 1
                if armed != discardArmed {
                    discardArmed = armed
                    WKInterfaceDevice.current().play(.click)
                }
            }
            .onEnded { _ in
                guard phase == .recording, recorder.isPaused, discardArmed else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        discardPush = .zero
                    }
                    discardArmed = false
                    return
                }
                discardCapture()
            }
    }

    /// Past the commit distance the face keeps following the finger, but at a
    /// third of the rate — the drag stops feeling like it can go further, which
    /// is the cue that the threshold has already been met.
    private func rubberBanded(_ travel: CGFloat) -> CGFloat {
        let magnitude = abs(travel)
        guard magnitude > Self.discardDistance else { return travel }
        let excess = magnitude - Self.discardDistance
        let eased = Self.discardDistance + excess / 3
        return travel < 0 ? -eased : eased
    }

    private func discardLegend(material: WatchCaptureMaterial) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "trash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(material.ink.opacity(0.86))

            Text(discardArmed ? "RELEASE TO DISCARD" : "KEEP GOING")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(material.inkFaint)
        }
        .animation(.easeOut(duration: 0.14), value: discardArmed)
        .accessibilityHidden(true)
    }

    private func discardCapture() {
        WatchConsole.info(
            "[WatchCapture] discarded by gesture duration=\(recorder.recordingDuration)"
        )
        WKInterfaceDevice.current().play(.failure)
        recorder.cancelRecording()
        phaseDeadline?.cancel()
        discardArmed = false
        discardPush = .zero
        isRecording = false
        onComplete()
    }

    private func aiVoiceMessageFace(
        isCompact: Bool,
        accent: Color,
        material: WatchCaptureMaterial
    ) -> some View {
        VStack(spacing: isCompact ? 4 : 7) {
            HStack(alignment: .center) {
                Text("talkie")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(material.ink.opacity(0.90))

                Spacer(minLength: 10)

                Label("ASK", systemImage: "sparkles")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(accent.opacity(0.88))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ask, recording voice message")

            RecordingSignalChamber(
                level: recorder.currentLevel,
                duration: formatDuration(recorder.recordingDuration),
                color: accent,
                material: material,
                isPaused: false,
                isCompact: isCompact,
                composition: .signalRail
            )
            .frame(maxHeight: .infinity)

            AIVoiceMessageComposer(
                duration: formatDuration(recorder.recordingDuration),
                accent: accent,
                material: material,
                isCompact: isCompact,
                action: stopAndSend
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, isCompact ? 2 : 5)
        .padding(.bottom, isCompact ? 4 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func memoRecordingFace(
        isCompact: Bool,
        accent: Color,
        material: WatchCaptureMaterial
    ) -> some View {
        let composition = RecordingFaceComposition.active

        return VStack(spacing: isCompact ? 3 : 5) {
            HStack(alignment: .center) {
                Text("talkie")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(material.ink.opacity(0.90))

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    Circle()
                        .fill(recorder.isPaused ? accent : Color.red)
                        .frame(width: 5, height: 5)
                        .shadow(
                            color: (recorder.isPaused ? accent : Color.red).opacity(0.42),
                            radius: 2
                        )

                    Text(recorder.isPaused ? "PAUSED" : "REC")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(material.inkFaint)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(recorder.isPaused ? "Recording paused" : "Recording memo")
            // The swipe is invisible to VoiceOver, so the same escape hatch is
            // published as a rotor action under the same paused-only rule.
            .accessibilityAction(named: "Discard recording") {
                guard recorder.isPaused else { return }
                discardCapture()
            }

            RecordingSignalChamber(
                level: recorder.currentLevel,
                duration: formatDuration(recorder.recordingDuration),
                color: accent,
                material: material,
                isPaused: recorder.isPaused,
                isCompact: isCompact,
                composition: composition
            )
            .frame(
                height: composition == .signalRail
                    ? nil
                    : composition.chamberHeight(isCompact: isCompact)
            )
            .frame(maxHeight: composition == .signalRail ? .infinity : nil)
            .overlay {
                // The field is nearly dead while paused, so this borrows a band
                // that is already quiet rather than adding chrome. A gesture
                // nobody knows about is not a feature, and pause is exactly the
                // moment the question "can I take that back" comes up.
                if recorder.isPaused && discardProgress == 0 {
                    Text("SWIPE AWAY TO DISCARD")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(material.inkFaint.opacity(0.62))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.22), value: recorder.isPaused)

            if composition != .signalRail {
                Spacer(minLength: isCompact ? 0 : 2)
            }

            if composition == .signalRail {
                RecordingElapsedTime(
                    duration: formatDuration(recorder.recordingDuration),
                    color: accent.opacity(0.92),
                    material: material,
                    font: .system(
                        size: isCompact ? 16 : 18,
                        weight: .medium,
                        design: .monospaced
                    ),
                    tracking: 0,
                    revealProgress: 1
                )
                .frame(width: isCompact ? 66 : 72, height: isCompact ? 20 : 23)
                .accessibilityHidden(true)

                HStack(spacing: 0) {
                    PauseResumeButton(
                        isPaused: recorder.isPaused,
                        color: accent,
                        material: material,
                        action: togglePause
                    )
                    .frame(width: 46, height: 46)

                    Spacer(minLength: isCompact ? 16 : 22)

                    RecordButton(
                        kind: .stop,
                        audioLevel: recorder.currentLevel,
                        action: stopAndSend
                    )
                    .scaleEffect(composition.stopScale(isCompact: isCompact))
                    .frame(width: 46, height: 46)
                }
                .padding(.horizontal, 7)
            } else {
                RecordButton(
                    kind: .stop,
                    audioLevel: recorder.currentLevel,
                    action: stopAndSend
                )
                .scaleEffect(composition.stopScale(isCompact: isCompact))
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, isCompact ? 2 : 5)
        .padding(.bottom, isCompact ? 3 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Crossbar readout

    @ViewBuilder
    private var crossbarReadout: some View {
        let material = themeName.captureStyle.material
        if phase == .recording {
            Text(formatDuration(recorder.recordingDuration))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(material.ink)
        } else {
            Text(statusLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(material.inkFaint)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Button slot (record / stop / outcome glyph)

    @ViewBuilder
    private var buttonSlot: some View {
        switch phase {
        case .recording:
            RecordButton(kind: .stop, audioLevel: recorder.currentLevel, action: stopAndSend)
        case .captured, .sending, .received, .transcribing:
            // Replace the button with a small status puck so the layout
            // doesn't jump but the affordance is clearly "in flight".
            ProgressPuck(phase: phase)
        case .routed:
            RoutedPuck(result: routeResult)
        case .queued:
            QueuedPuck()
        case .failed:
            FailedPuck()
        }
    }

    private var statusLabel: String {
        switch phase {
        case .recording:                       return formatDuration(recorder.recordingDuration)
        case .captured:                        return forcesAI ? "Message ready" : "Captured"
        case .sending:                         return forcesAI ? "Sending message" : "Sending"
        case .received:                        return forcesAI ? "Message sent" : "Sent"
        case .transcribing:                    return forcesAI ? "AI is working" : "Working"
        case .routed:                          return routeResult == .askAI ? "Asked AI" : "Saved"
        case .queued:                          return forcesAI ? "Message queued" : "Queued"
        case .failed:                          return "Not sent"
        }
    }

    // MARK: - Memo status observation

    private var latestMemoStatus: WatchMemo.MemoStatus? {
        guard let id = currentMemoId else { return nil }
        return sessionManager.recentMemos.first(where: { $0.id == id })?.status
    }

    private func handleMemoStatusChange(_ status: WatchMemo.MemoStatus?) {
        guard let status else { return }
        WatchConsole.info(
            "[WatchCapture] memo status=\(status.rawValue) memo=\(currentMemoId?.uuidString ?? "none") phase=\(String(describing: phase))"
        )
        switch status {
        case .received:
            if phase == .sending || phase == .captured {
                transition(to: .received)
                scheduleDismiss(after: 1.6)
            }
        case .thinking:
            if phase != .routed {
                transition(to: .transcribing)
                scheduleDismiss(after: 2.2)
            }
        case .transcribed:
            routeResult = .memo
            transition(to: .routed)
            scheduleDismiss(after: 1.6)
        case .answered:
            routeResult = .askAI
            transition(to: .routed)
            scheduleDismiss(after: 1.6)
        case .failed:
            transition(to: .failed("transfer"))
            scheduleDismiss(after: 1.6)
        case .sending, .sent:
            break
        }
    }

    private func handleSendStatusChange(_ status: WatchSessionManager.SendStatus) {
        WatchConsole.info(
            "[WatchCapture] transfer status=\(String(describing: status)) phase=\(String(describing: phase))"
        )
        switch status {
        case .sending:
            if phase == .captured {
                beginSendingPhase()
            }
        case .sent:
            // The WatchConnectivity file handoff completed. Processing may
            // continue on the phone, but the Watch surface can close cleanly.
            if phase == .sending || phase == .captured {
                transition(to: .received)
                scheduleDismiss(after: 1.6)
            }
        case .failed(let msg):
            transition(to: .failed(msg))
            scheduleDismiss(after: 1.6)
        case .idle:
            break
        }
    }

    // MARK: - Transitions

    private func transition(to next: Phase) {
        guard phase != next else { return }
        WatchConsole.info(
            "[WatchCapture] phase \(String(describing: phase)) -> \(String(describing: next))"
        )
        withAnimation(.easeOut(duration: 0.20)) { phase = next }
    }

    private func beginSendingPhase() {
        transition(to: .sending)
        // `transferFile` is durable but its completion callback is not a UI
        // guarantee. Fall back to the honest queued state rather than leaving
        // a permanent spinner when WatchConnectivity suspends either app.
        schedulePhaseTimeout(seconds: 8, fallback: .queued)
    }

    /// Schedule a fallback if we don't hear back from the phone within
    /// `seconds`. Used so the sequence keeps moving even if a status
    /// update gets dropped or the phone is slow to respond.
    private func schedulePhaseTimeout(seconds: Double, fallback: Phase) {
        phaseDeadline?.cancel()
        let expectedPhase = phase
        WatchConsole.info(
            "[WatchCapture] deadline phase=\(String(describing: expectedPhase)) seconds=\(seconds) fallback=\(String(describing: fallback))"
        )
        phaseDeadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            guard phase == expectedPhase else {
                WatchConsole.info(
                    "[WatchCapture] ignored stale deadline expected=\(String(describing: expectedPhase)) actual=\(String(describing: phase))"
                )
                return
            }
            WatchConsole.info(
                "[WatchCapture] deadline fired phase=\(String(describing: phase)) fallback=\(String(describing: fallback))"
            )
            transition(to: fallback)
            scheduleDismiss(after: 1.4)
        }
    }

    private func scheduleDismiss(after seconds: Double) {
        phaseDeadline?.cancel()
        phaseDeadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            isRecording = false
            onComplete()
        }
    }

    // MARK: - Actions

    private func stopAndSend() {
        WKInterfaceDevice.current().play(.stop)
        lastSentDuration = recorder.recordingDuration
        WatchConsole.info(
            "[WatchCapture] stop requested duration=\(lastSentDuration) intent=\(preset.intent ?? "auto")"
        )

        Task { @MainActor in
            guard let audioURL = await recorder.stopRecording() else {
                isRecording = false
                onComplete()
                return
            }

            transition(to: .captured)
            WKInterfaceDevice.current().play(.click)

            sessionManager.sendAudio(
                fileURL: audioURL,
                duration: lastSentDuration,
                preset: forcesAI ? preset : nil,
                autoRoute: !forcesAI
            )

            // Capture the memoId so we can observe the right entry.
            currentMemoId = sessionManager.recentMemos.first?.id
            WatchConsole.info(
                "[WatchCapture] queued memo=\(currentMemoId?.uuidString ?? "none") reachable=\(sessionManager.isReachable)"
            )

            // Phone not reachable? Jump straight to QUEUED and dismiss — no
            // hanging. The audio is already queued for background transfer.
            if !sessionManager.isReachable {
                try? await Task.sleep(for: .milliseconds(450))
                transition(to: .queued)
                scheduleDismiss(after: 1.4)
                return
            }

            // Reachable — proceed through sending after a beat so CAPTURED
            // has a moment to register.
            try? await Task.sleep(for: .milliseconds(450))
            if phase == .captured {
                beginSendingPhase()
            }
        }
    }

    private func togglePause() {
        guard recorder.togglePause() else { return }
        WKInterfaceDevice.current().play(.click)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsText)"
    }
}

/// Three bounded recording studies, all within the same Talkie material world.
/// The release build uses the signal-rail hierarchy. Debug builds can render
/// the alternatives by setting `watch.recordingFaceStudy` in UserDefaults.
private enum RecordingFaceComposition: String {
    case chronograph
    case signalRail
    case constellation

    static var active: RecordingFaceComposition {
        #if DEBUG
        if let rawValue = UserDefaults.standard.string(forKey: "watch.recordingFaceStudy"),
           let composition = RecordingFaceComposition(rawValue: rawValue) {
            return composition
        }
        #endif
        return .signalRail
    }

    func chamberHeight(isCompact: Bool) -> CGFloat {
        switch self {
        case .chronograph:
            isCompact ? 63 : 78
        case .signalRail:
            isCompact ? 78 : 94
        case .constellation:
            isCompact ? 71 : 88
        }
    }

    func stopScale(isCompact: Bool) -> CGFloat {
        switch self {
        case .chronograph:
            isCompact ? 0.80 : 0.86
        case .signalRail:
            isCompact ? 0.62 : 0.68
        case .constellation:
            isCompact ? 0.90 : 0.98
        }
    }

    var particleScale: CGFloat {
        switch self {
        case .chronograph: 1.00
        case .signalRail: 1.38
        case .constellation: 1.82
        }
    }

    var quietZone: CGFloat {
        switch self {
        case .chronograph: 0.18
        case .signalRail: 0.12
        case .constellation: 0.15
        }
    }
}

/// The original Watch recorder felt alive because the particles, elapsed time,
/// and stop control read as one capture state. In the release composition this
/// chamber gives the visual treatment its own band. The timer remains centered
/// and stable while the actions stay together in the lower reach zone.
private struct RecordingSignalChamber: View {
    let level: Float
    let duration: String
    let color: Color
    let material: WatchCaptureMaterial
    let isPaused: Bool
    let isCompact: Bool
    let composition: RecordingFaceComposition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealProgress: CGFloat = 0

    var body: some View {
        Group {
            if composition == .signalRail {
                RecordingParticleField(
                    level: level,
                    color: color,
                    quietZone: 0,
                    particleScale: composition.particleScale,
                    isPaused: isPaused,
                    revealProgress: revealProgress
                )
                .frame(height: isCompact ? 32 : 42)
            } else {
                ZStack {
                    RecordingParticleField(
                        level: level,
                        color: color,
                        quietZone: composition.quietZone,
                        particleScale: composition.particleScale,
                        isPaused: isPaused,
                        revealProgress: revealProgress
                    )

                    RecordingElapsedTime(
                        duration: duration,
                        color: timerColor,
                        material: material,
                        font: timerFont,
                        tracking: timerTracking,
                        revealProgress: revealProgress
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed \(duration)")
        .onAppear(perform: reveal)
    }

    private var timerFont: Font {
        switch composition {
        case .chronograph:
            .system(size: isCompact ? 25 : 31, weight: .medium, design: .rounded)
        case .signalRail:
            .system(size: isCompact ? 19 : 23, weight: .semibold, design: .monospaced)
        case .constellation:
            .system(size: isCompact ? 21 : 25, weight: .regular, design: .rounded)
        }
    }

    private var timerTracking: CGFloat {
        switch composition {
        case .chronograph: -0.7
        case .signalRail: 0.1
        case .constellation: -0.35
        }
    }

    private var timerColor: Color {
        switch composition {
        case .chronograph:
            material.ink
        case .signalRail:
            color.opacity(0.92)
        case .constellation:
            material.ink.opacity(0.74)
        }
    }

    private func reveal() {
        if reduceMotion {
            revealProgress = 1
        } else {
            withAnimation(.easeOut(duration: 0.62)) {
                revealProgress = 1
            }
        }
    }
}

private struct RecordingParticleField: View {
    let level: Float
    let color: Color
    let quietZone: CGFloat
    let particleScale: CGFloat
    let isPaused: Bool
    let revealProgress: CGFloat

    var body: some View {
        ParticlesView(
                level: level,
                color: color,
                centerQuietZone: quietZone,
                particleScale: particleScale,
                isPaused: isPaused
            )
                .scaleEffect(
                    x: 0.92 + revealProgress * 0.08,
                    y: 0.76 + revealProgress * 0.24
                )
                .opacity(
                    (0.20 + Double(revealProgress) * 0.80)
                        * (isPaused ? 0.38 : 1)
                )
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.08),
                            .init(color: .white, location: 0.92),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .animation(.easeOut(duration: 0.22), value: isPaused)
                .accessibilityHidden(true)
    }
}

private struct RecordingElapsedTime: View {
    let duration: String
    let color: Color
    let material: WatchCaptureMaterial
    let font: Font
    let tracking: CGFloat
    let revealProgress: CGFloat

    var body: some View {
        Text(duration)
                .font(font)
                .tracking(tracking)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .minimumScaleFactor(0.78)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .shadow(color: material.field.opacity(0.94), radius: 5)
                .shadow(color: material.fieldShade.opacity(0.44), radius: 1, y: 1)
                .blur(radius: (1 - revealProgress) * 2.5)
                .opacity(0.56 + Double(revealProgress) * 0.44)
    }
}

private struct PauseResumeButton: View {
    let isPaused: Bool
    let color: Color
    let material: WatchCaptureMaterial
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isPaused ? color.opacity(0.10) : material.secondaryFill)
                    .frame(width: 36, height: 36)

                Circle()
                    .stroke(color.opacity(isPaused ? 0.76 : 0.48), lineWidth: 0.9)
                    .frame(width: 36, height: 36)

                Group {
                    if isPaused {
                        Image(systemName: "play.fill")
                    } else {
                        Image(systemName: "pause")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isPaused ? color : material.ink.opacity(0.82))
            }
            .frame(width: 46, height: 46)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Resume recording" : "Pause recording")
    }
}

/// Ask AI is a voice-message composer, not a memo transport. The live signal
/// remains useful feedback, while the only completion action is an explicit
/// message send affordance with a stable, single-line elapsed time.
private struct AIVoiceMessageComposer: View {
    let duration: String
    let accent: Color
    let material: WatchCaptureMaterial
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent.opacity(0.92))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(accent.opacity(0.10))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("VOICE MESSAGE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(material.inkFaint)
                    .lineLimit(1)

                Text(duration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(material.ink.opacity(0.90))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 2)

            Button(action: action) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(material.field)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(accent)
                            .shadow(color: accent.opacity(0.24), radius: 3, y: 2)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send voice message to AI")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: isCompact ? 48 : 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(material.secondaryFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(material.secondaryEdge, lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Status pucks (replace the record button after stop)

private struct ProgressPuck: View {
    let phase: PresetRecordingView.Phase

    var body: some View {
        let chrome = WatchTheme.current
        ZStack {
            Circle()
                .strokeBorder(chrome.accent.opacity(0.55), lineWidth: 1.2)
                .frame(width: 44, height: 44)

            switch phase {
            case .captured:
                // Accent, not green. Capture succeeding is the expected path,
                // not a notable outcome, and the puck's own ring is already
                // accent — a green glyph inside an accent ring read as two
                // unrelated signals.
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chrome.accent)
            case .received:
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(chrome.accent)
            case .sending, .transcribing:
                BrailleSpinner(size: 18, color: chrome.accent)
            default:
                EmptyView()
            }
        }
    }
}

private struct RoutedPuck: View {
    let result: PresetRecordingView.RouteResult

    var body: some View {
        let chrome = WatchTheme.current
        let material = WatchTheme.capture.material
        let (glyph, color): (String, Color) = {
            switch result {
            case .askAI:    return ("sparkles", chrome.accent)
            // The glyph already separates memo from ask; colour does not need
            // to, and the theme accent keeps the outcome inside the app's
            // palette instead of borrowing system green.
            case .memo:     return ("waveform", chrome.accent)
            case .unknown:  return ("checkmark", material.ink)
            case .pending:  return ("ellipsis", chrome.accent)
            }
        }()
        return ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 50, height: 50)
            Circle()
                .strokeBorder(color, lineWidth: 1.8)
                .frame(width: 44, height: 44)
            Image(systemName: glyph)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
        }
        .onAppear { WKInterfaceDevice.current().play(.success) }
    }
}

private struct QueuedPuck: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.orange, lineWidth: 1.8)
                .frame(width: 44, height: 44)
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.orange)
        }
        .onAppear { WKInterfaceDevice.current().play(.click) }
    }
}

private struct FailedPuck: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.red, lineWidth: 1.8)
                .frame(width: 44, height: 44)
            Image(systemName: "exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.red)
        }
        .onAppear { WKInterfaceDevice.current().play(.failure) }
    }
}

// MARK: - Braille spinner (matches TalkieKit)

struct BrailleSpinner: View {
    var size: CGFloat = 14
    var speed: Double = 0.08
    var color: Color = .blue

    @State private var frame = 0
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        Text(frames[frame])
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .onAppear { startAnimation() }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            frame = (frame + 1) % frames.count
        }
    }
}

#Preview {
    PresetRecordingView(
        preset: .go,
        isRecording: .constant(true),
        onComplete: {}
    )
    .environmentObject(WatchSessionManager.shared)
}
