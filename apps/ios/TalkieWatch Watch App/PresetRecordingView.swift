//
//  PresetRecordingView.swift
//  TalkieWatch
//
//  Capture-in-motion. Same instrument vocabulary as the idle picker —
//  channel header on top, rectangular scope slot, big ultra-light
//  monospaced timer, clean round button at the bottom — but the slot
//  goes live with audio level, the button becomes STOP, and after the
//  user stops we walk through a visible confirmation sequence so the
//  recording feels safely landed instead of "did anything happen?"
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
    let preset: WatchPreset
    @Binding var isRecording: Bool
    var onComplete: () -> Void

    @StateObject private var recorder = AudioRecorder()
    @State private var phase: Phase = .recording
    @State private var routeResult: RouteResult = .pending
    @State private var lastSentDuration: TimeInterval = 0
    @State private var currentMemoId: UUID?
    @State private var phaseDeadline: Task<Void, Never>?

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
            PaperBackground()

            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    InstrumentHeader(elapsed: displayedDuration, isLive: phase == .recording)

                    BracketedScopeSlot {
                        scopeContent
                    }
                    .frame(height: 78)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if phase == .recording { stopAndSend() }
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 18)
                .padding(.top, 16)

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    buttonSlot

                    statusLine
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .onAppear { recorder.startRecording() }
        .onChange(of: sessionManager.lastSentStatus) { _, newStatus in
            handleSendStatusChange(newStatus)
        }
        .onChange(of: latestMemoStatus) { _, status in
            handleMemoStatusChange(status)
        }
        .onDisappear { phaseDeadline?.cancel() }
    }

    // MARK: - Scope slot content (phase-aware)

    @ViewBuilder
    private var scopeContent: some View {
        switch phase {
        case .recording:
            ScopeWaveform(audioLevel: recorder.currentLevel, isLive: true, treatment: .line)

        case .captured, .sending, .received, .transcribing:
            // Frozen low trace; status line carries the active info.
            ScopeWaveform(audioLevel: 0.20, isLive: false, treatment: .line)

        case .routed, .queued, .failed:
            EmptyView()
        }
    }

    // MARK: - Button slot (record / stop / outcome glyph)

    @ViewBuilder
    private var buttonSlot: some View {
        switch phase {
        case .recording:
            RecordButton(kind: .stop, action: stopAndSend)
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

    // MARK: - Status line (under the button)

    private var statusLine: some View {
        let chrome = WatchTheme.current
        return HStack(spacing: 5) {
            // Phase glyph
            Circle()
                .fill(statusColor)
                .frame(width: 4, height: 4)
                .shadow(color: statusColor.opacity(0.55), radius: 2)

            Text(statusLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(chrome.panelInkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLabel: String {
        switch phase {
        case .recording:                       return forcesAI ? "REC · ASK AI" : "REC · AUTO-ROUTE"
        case .captured:                        return "CAPTURED"
        case .sending:                         return "SENDING…"
        case .received:                        return "PHONE RECEIVED"
        case .transcribing:                    return "TRANSCRIBING…"
        case .routed:                          return routeResult == .askAI ? "ASKED AI" : "SAVED TO PHONE"
        case .queued:                          return "QUEUED · WILL SEND"
        case .failed(let msg):                 return "FAILED · \(msg.uppercased())"
        }
    }

    private var statusColor: Color {
        let chrome = WatchTheme.current
        switch phase {
        case .recording:                       return .red
        case .captured, .received, .routed:    return .green
        case .sending, .transcribing:          return chrome.accent
        case .queued:                          return .orange
        case .failed:                          return .red
        }
    }

    private var timerColor: Color {
        let chrome = WatchTheme.current
        return phase == .recording ? chrome.panelInk : chrome.panelInkFaint
    }

    private var displayedDuration: TimeInterval {
        phase == .recording ? recorder.recordingDuration : lastSentDuration
    }

    // MARK: - Memo status observation

    private var latestMemoStatus: WatchMemo.MemoStatus? {
        guard let id = currentMemoId else { return nil }
        return sessionManager.recentMemos.first(where: { $0.id == id })?.status
    }

    private func handleMemoStatusChange(_ status: WatchMemo.MemoStatus?) {
        guard let status else { return }
        switch status {
        case .received:
            if phase == .sending || phase == .captured {
                transition(to: .received)
                schedulePhaseTimeout(seconds: 6, fallback: .routed)
            }
        case .thinking:
            if phase != .routed {
                transition(to: .transcribing)
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
        switch status {
        case .sending:
            if phase == .captured {
                transition(to: .sending)
            }
        case .sent:
            // .sent here means watch-side handed off the file. If the
            // phone is reachable we expect a memo-status update soon
            // (received → transcribed/answered). Show received as a
            // best-guess, give it a few seconds, then fall through.
            if phase == .sending || phase == .captured {
                transition(to: .received)
                schedulePhaseTimeout(seconds: 4, fallback: .routed)
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
        withAnimation(.easeOut(duration: 0.20)) { phase = next }
    }

    /// Schedule a fallback if we don't hear back from the phone within
    /// `seconds`. Used so the sequence keeps moving even if a status
    /// update gets dropped or the phone is slow to respond.
    private func schedulePhaseTimeout(seconds: Double, fallback: Phase) {
        phaseDeadline?.cancel()
        phaseDeadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            // Only fall through if we haven't progressed past the
            // current phase already.
            let alreadyTerminal: Bool = {
                switch phase {
                case .routed, .failed: return true
                default:               return false
                }
            }()
            if !alreadyTerminal {
                if case .routed = fallback {
                    routeResult = forcesAI ? .askAI : .unknown
                }
                transition(to: fallback)
                scheduleDismiss(after: 1.4)
            }
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
        guard let audioURL = recorder.stopRecording() else {
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

        // Phone not reachable? Jump straight to QUEUED and dismiss — no
        // hanging. The audio is already queued for background transfer
        // by sendAudio() in this case.
        if !sessionManager.isReachable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                transition(to: .queued)
                scheduleDismiss(after: 1.4)
            }
            return
        }

        // Reachable — proceed through sending after a beat so CAPTURED
        // has a moment to register.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if phase == .captured {
                transition(to: .sending)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.green)
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
        let (glyph, color): (String, Color) = {
            switch result {
            case .askAI:    return ("sparkles", chrome.accent)
            case .memo:     return ("waveform", .green)
            case .unknown:  return ("checkmark", chrome.panelInk)
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
