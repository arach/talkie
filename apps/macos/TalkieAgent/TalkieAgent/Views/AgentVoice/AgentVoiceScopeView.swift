//
//  AgentVoiceScopeView.swift
//  TalkieAgent
//
//  The floating instrument that blooms in the center of the screen
//  when Hyper+T is held. Oscilloscope dominates; status strip above,
//  response section + footer below.
//
//  Unit 3 — closed loop. Phase progression drives layout:
//
//    .ready / .transmitting / .over  → scope only (panel ~280pt)
//    .thinking                       → scope + "thinking…" line
//    .receiving                      → scope + transcript + reply + actions
//    .error                          → scope + error message
//
//  The response section is an "extension" of the instrument — it
//  expands the panel downward via NSHostingController.sizingOptions.
//

import SwiftUI

enum AgentVoiceScopePhase {
    case ready
    case arming
    case transmitting
    case over
    case thinking
    case receiving
    case followUpRecording
    case followUpOver
    case error
}

struct AgentVoiceScopeView: View {
    @ObservedObject var session: AgentVoiceSession
    let onDismiss: () -> Void

    @State private var followUpText = ""

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            display
            if showsResponseSection {
                responseSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(amberBody)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(amberEdge, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 24)
        .shadow(color: .black.opacity(0.35), radius: 9, x: 0, y: 6)
        .animation(.easeOut(duration: 0.22), value: session.phase)
    }

    private var showsResponseSection: Bool {
        switch session.phase {
        case .ready, .arming, .transmitting, .over: return false
        case .thinking, .receiving, .followUpRecording, .followUpOver, .error: return true
        }
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack {
            HStack(spacing: 12) {
                channelPill
                Text("T01")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(inkSubtle)
            }

            Spacer()
            phaseBadge
            Spacer()

            HStack(spacing: 12) {
                Text(timecode)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(inkSubtle)
                    .monospacedDigit()
                signalDot
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(amberEdgeFaint)
                .frame(height: 0.5)
        }
    }

    private var channelPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(channelDotColor)
                .frame(width: 6, height: 6)
                .shadow(color: liveDot ? amberTrace.opacity(0.8) : .clear, radius: 4)
            Text("CH-01 · NIGHTOPS")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(amberEdgeFaint, lineWidth: 0.5)
        )
    }

    private var phaseBadge: some View {
        Text(phaseLabel)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(3.2)
            .foregroundStyle(badgeIsHot ? amberTrace : ink)
            .shadow(color: badgeIsHot ? amberTrace.opacity(0.6) : .clear, radius: 6)
    }

    private var signalDot: some View {
        Circle()
            .fill(isMicLive ? Color(red: 0.85, green: 0.29, blue: 0.17) : inkSubtle)
            .frame(width: 6, height: 6)
            .shadow(
                color: isMicLive ? Color(red: 0.85, green: 0.29, blue: 0.17).opacity(0.65) : .clear,
                radius: 4
            )
    }

    private var isMicLive: Bool {
        session.phase == .transmitting || session.phase == .followUpRecording
    }

    // MARK: - Display

    private var display: some View {
        ZStack {
            Color(red: 0.031, green: 0.035, blue: 0.039)
            graticule
            scanlines
            scopeTrace
            cornerLabel("AGENT", alignment: .topLeading)
            cornerLabel(session.phase == .receiving ? "REPLY" : "VOICE", alignment: .topTrailing)
            cornerLabel("listening", alignment: .bottomLeading)
            cornerLabel("live", alignment: .bottomTrailing)
        }
        .frame(height: 200)
    }

    private var graticule: some View {
        Canvas { context, size in
            let grid = amberGrid.opacity(0.85)
            let axis = Color(red: 0.91, green: 0.60, blue: 0.24).opacity(0.18)

            for i in 1..<8 {
                let y = size.height * CGFloat(i) / 8.0
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(grid), lineWidth: 0.5)
            }
            for i in 1..<16 {
                let x = size.width * CGFloat(i) / 16.0
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(grid), lineWidth: 0.5)
            }
            var hAxis = Path()
            hAxis.move(to: CGPoint(x: 0, y: size.height / 2))
            hAxis.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(hAxis, with: .color(axis), lineWidth: 0.5)
            var vAxis = Path()
            vAxis.move(to: CGPoint(x: size.width / 2, y: 0))
            vAxis.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(vAxis, with: .color(axis), lineWidth: 0.5)
        }
    }

    private var scanlines: some View {
        Canvas { context, size in
            for y in stride(from: 0, to: size.height, by: 3) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.018)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var scopeTrace: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = session.phase
                let level = CGFloat(session.level)
                let points = tracePoints(for: phase, t: t, level: level, count: 120)
                guard points.count >= 2 else { return }
                var path = Path()
                path.move(to: scaled(points[0], to: size))
                for p in points.dropFirst() {
                    path.addLine(to: scaled(p, to: size))
                }
                let hot = phase == .transmitting || phase == .followUpRecording || phase == .receiving
                let color = hot ? amberTrace : amberTraceDim
                context.stroke(path, with: .color(color), lineWidth: 1.4)
            }
            .shadow(color: amberTrace.opacity(0.55), radius: 6)
        }
    }

    private func scaled(_ p: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func tracePoints(
        for phase: AgentVoiceScopePhase,
        t: TimeInterval,
        level: CGFloat,
        count: Int
    ) -> [CGPoint] {
        let step = 1.0 / Double(count - 1)
        return (0..<count).map { i in
            let x = Double(i) * step
            let y: Double
            switch phase {
            case .ready, .arming:
                y = 0.5 + sin(x * .pi * 2 + t * 0.5) * 0.005
            case .transmitting, .followUpRecording:
                let envelope = 0.4 * (1 - pow(2 * x - 1, 2))
                let base = sin(x * .pi * 14 + t * 8)
                let harm = sin(x * .pi * 36 + t * 5.5) * 0.35
                let amp = max(0.08, Double(level))
                y = 0.5 + envelope * amp * (base + harm)
            case .over, .followUpOver:
                let decay = (1 - x) * 0.08
                y = 0.5 + decay * sin(x * .pi * 6 + t * 4)
            case .thinking:
                // Slow seeker pulse — anticipation.
                let pulse = 0.04 + 0.04 * sin(t * 2.5)
                y = 0.5 + pulse * sin(x * .pi * 4 + t * 1.5)
            case .receiving:
                y = 0.5 + 0.22 * sin(x * .pi * 10 + t * 3) * cos(x * .pi * 3 + t * 1.5)
            case .error:
                // Square-ish glitch.
                y = 0.5 + 0.08 * (sin(x * .pi * 6) > 0 ? 1 : -1)
            }
            return CGPoint(x: x, y: y)
        }
    }

    private func cornerLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(inkSubtle)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .allowsHitTesting(false)
    }

    // MARK: - Response section

    @ViewBuilder
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let transcript = session.transcript {
                youSaidBlock(transcript)
            }

            if !session.toolInvocations.isEmpty {
                toolInvocationsBlock
            }

            switch session.phase {
            case .thinking:
                thinkingBlock
            case .receiving:
                if let reply = session.replyText {
                    talkieBlock(reply)
                }
            case .followUpRecording:
                if let reply = session.replyText {
                    talkieBlock(reply)
                }
            case .followUpOver:
                thinkingBlock
            case .error:
                errorBlock
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(amberEdgeFaint)
                .frame(height: 0.5)
        }
    }

    /// Live list of tool invocations the LLM ran during this turn.
    /// Each row is a compact monospace block — command + status +
    /// duration. The actual output stays on hover (via .help) so the
    /// panel doesn't blow up with JSON dumps.
    private var toolInvocationsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOOLS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(inkSubtle)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(session.toolInvocations) { invocation in
                    toolRow(invocation)
                }
            }
        }
    }

    private func toolRow(_ invocation: AgentVoiceToolInvocation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            statusGlyph(invocation.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(invocation.displayCommand)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case let .failed(detail) = invocation.status {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 0.85, green: 0.29, blue: 0.17))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let ms = invocation.durationMs {
                Text(latencyString(ms))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(inkSubtle)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(amberTrace.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(amberEdgeFaint, lineWidth: 0.5)
        )
        .help(invocation.output ?? "")
    }

    @ViewBuilder
    private func statusGlyph(_ status: AgentVoiceToolInvocation.Status) -> some View {
        switch status {
        case .running:
            ThinkingDot()
                .frame(width: 9, height: 9)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(amberTrace)
                .frame(width: 9, height: 9)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 0.85, green: 0.29, blue: 0.17))
                .frame(width: 9, height: 9)
        }
    }

    private func youSaidBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOU SAID")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(inkSubtle)
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(ink)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thinkingBlock: some View {
        HStack(spacing: 8) {
            ThinkingDot()
            Text("Thinking…")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(amberTraceDim)
        }
        .padding(.top, 4)
    }

    private func talkieBlock(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("AGENT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(amberTrace)
                if let ms = session.llmLatencyMs {
                    Text("· \(latencyString(ms))")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(inkSubtle)
                }
                Text("· \(modelMetaLabel)")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(inkSubtle)
                if session.continuationSessionId != nil {
                    Text("· SAME SESSION")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(amberTrace)
                }
                if let branchMetaLabel {
                    Text("· \(branchMetaLabel)")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(amberTrace)
                }
            }

            Text(reply)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(amberTrace)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            voiceFollowUpControl

            HStack(spacing: 8) {
                actionChip(label: "PLAY", systemImage: "play.fill", action: { session.playReply() })
                actionChip(label: "DONE", systemImage: "checkmark", action: onDismiss)
                Spacer()
                autoPlayToggle
            }
            .padding(.top, 2)

            followUpComposer
        }
    }

    private var voiceFollowUpControl: some View {
        Button(action: { session.toggleVoiceFollowUp() }) {
            HStack(spacing: 10) {
                Image(systemName: voiceFollowUpIcon)
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 16)
                Text(voiceFollowUpLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                Spacer(minLength: 8)
                Text(voiceFollowUpBadge)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(isRecordingFollowUp ? Color(red: 0.141, green: 0.078, blue: 0.031) : amberTrace)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isRecordingFollowUp ? amberTrace.opacity(0.78) : Color.black.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(amberTrace.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .foregroundStyle(isRecordingFollowUp ? Color(red: 0.141, green: 0.078, blue: 0.031) : amberTrace)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isRecordingFollowUp ? amberTrace : Color.black.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(amberTrace.opacity(isRecordingFollowUp ? 0 : 0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(executorBranchIsWorking)
        .help(voiceFollowUpHelp)
    }

    private var isRecordingFollowUp: Bool {
        session.phase == .followUpRecording
    }

    private var executorBranchIsWorking: Bool {
        session.executorBranchState == .working
    }

    private var voiceFollowUpIcon: String {
        if executorBranchIsWorking { return "hourglass" }
        return isRecordingFollowUp ? "stop.fill" : "mic.fill"
    }

    private var voiceFollowUpLabel: String {
        if executorBranchIsWorking { return "AGENT WORKING" }
        return isRecordingFollowUp ? "STOP & SEND" : "TALK FOLLOW-UP"
    }

    private var voiceFollowUpBadge: String {
        if executorBranchIsWorking { return "AGENT" }
        return isRecordingFollowUp ? session.formattedElapsed : "T"
    }

    private var voiceFollowUpHelp: String {
        if executorBranchIsWorking { return "The agent is still working" }
        return isRecordingFollowUp ? "Stop recording and send" : "Record a voice follow-up"
    }

    private var followUpComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Talk to the agent", text: $followUpText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(1...3)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(amberEdgeFaint, lineWidth: 0.5)
                )
                .onSubmit(sendFollowUp)
                .disabled(isRecordingFollowUp || executorBranchIsWorking)

            Button(action: sendFollowUp) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(canSendFollowUp ? Color(red: 0.141, green: 0.078, blue: 0.031) : inkSubtle)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(canSendFollowUp ? amberTrace : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(amberTrace.opacity(canSendFollowUp ? 0 : 0.55), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSendFollowUp)
            .help("Send follow-up")
        }
        .padding(.top, 2)
    }

    private var canSendFollowUp: Bool {
        session.phase == .receiving
            && !executorBranchIsWorking
            && !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendFollowUp() {
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        followUpText = ""
        session.sendFollowUp(text)
    }

    /// Persistent toggle for auto-speaking the reply on arrival.
    /// Mirrors `session.autoPlayEnabled`; persists via TalkieSharedSettings.
    private var autoPlayToggle: some View {
        Button(action: { session.autoPlayEnabled.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: session.autoPlayEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 9, weight: .semibold))
                Text(session.autoPlayEnabled ? "AUTO ON" : "AUTO OFF")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
            }
            .foregroundStyle(session.autoPlayEnabled ? Color(red: 0.141, green: 0.078, blue: 0.031) : amberTrace)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(session.autoPlayEnabled ? amberTrace : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(amberTrace.opacity(session.autoPlayEnabled ? 0 : 0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Speak replies automatically when they arrive")
    }

    private var errorBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ERROR")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color(red: 0.85, green: 0.29, blue: 0.17))
            Text(session.errorMessage ?? "Something went wrong.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                if session.offersVoiceRetry {
                    actionChip(
                        label: "TALK",
                        systemImage: "mic.circle",
                        action: { session.startVoiceRetryFromFallback() }
                    )
                }
                actionChip(label: "DISMISS", systemImage: "xmark", action: onDismiss)
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func actionChip(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
            }
            .foregroundStyle(amberTrace)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(amberTrace.opacity(0.55), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func latencyString(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            footerKeyCluster

            Spacer()

            if session.isLatchedTransmission && session.phase == .transmitting {
                actionChip(label: "SEND", systemImage: "paperplane.fill", action: sendLatchedTransmission)
            } else {
                Text("auto · talk now / agents later")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(inkSubtle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(amberEdgeFaint)
                .frame(height: 0.5)
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var footerKeyCluster: some View {
        HStack(spacing: 6) {
            if usesInlineFollowUpKey {
                keycap("T", accent: true)
            } else {
                ForEach(["⇧", "⌃", "⌥", "⌘"], id: \.self) { keycap($0, accent: false) }
                keycap("T", accent: true)
            }
            Text(footerHint)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(inkSubtle)
                .padding(.leading, 8)
        }
    }

    private var usesInlineFollowUpKey: Bool {
        session.phase == .receiving || session.phase == .followUpRecording
    }

    private func sendLatchedTransmission() {
        Task { @MainActor in
            await session.endTransmission()
        }
    }

    private func keycap(_ label: String, accent: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(accent ? Color(red: 0.141, green: 0.078, blue: 0.031) : ink)
            .frame(minWidth: 20, idealHeight: 20)
            .padding(.horizontal, accent ? 8 : 6)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        accent
                        ? LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.78, blue: 0.45),
                                Color(red: 0.91, green: 0.60, blue: 0.24),
                                Color(red: 0.71, green: 0.45, blue: 0.13),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [
                                Color(red: 0.165, green: 0.18, blue: 0.19),
                                Color(red: 0.11, green: 0.125, blue: 0.135),
                                Color(red: 0.078, green: 0.094, blue: 0.102),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        accent ? Color(red: 0.54, green: 0.35, blue: 0.10) : .white.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Phase-driven derived values

    private var phaseLabel: String {
        switch session.phase {
        case .ready: return "READY"
        case .arming: return "ARMING MIC"
        case .transmitting: return "TALKING"
        case .over: return "SENT"
        case .thinking: return "PROCESSING"
        case .receiving:
            switch session.executorBranchState {
            case .working:
                return "AGENT · WORKING"
            case .done:
                if session.routeMode == .async {
                    return "AGENT · RETURNED"
                }
            case .failed:
                return "AGENT · FAILED"
            case .idle:
                break
            }
            if session.routeMode == .async {
                return session.continuationSessionId == nil ? "AGENT · WORKING" : "AGENT · READY"
            }
            if let model = session.topLevelModelId, !model.isEmpty {
                return "OUT · \(shortModelLabel(model))"
            }
            return "OUT"
        case .followUpRecording: return "FOLLOW-UP"
        case .followUpOver: return "SENDING"
        case .error: return "ERROR"
        }
    }

    private var badgeIsHot: Bool {
        session.phase == .transmitting
            || session.phase == .arming
            || session.phase == .followUpRecording
            || session.phase == .receiving
            || session.phase == .thinking
    }

    private var liveDot: Bool {
        session.phase == .transmitting
            || session.phase == .arming
            || session.phase == .followUpRecording
            || session.phase == .receiving
            || session.phase == .thinking
    }

    private var channelDotColor: Color {
        liveDot ? amberTrace : inkSubtle
    }

    private var timecode: String {
        switch session.phase {
        case .ready: return "0:00.0"
        case .arming, .transmitting, .over, .thinking, .receiving, .followUpRecording, .followUpOver, .error:
            return session.formattedElapsed
        }
    }

    private var footerHint: String {
        switch session.phase {
        case .ready: return "HOLD TO TALK"
        case .arming: return "KEEP HOLDING"
        case .transmitting: return session.isLatchedTransmission ? "TALK THEN SEND" : "RELEASE TO SEND"
        case .over: return "PROCESSING…"
        case .thinking: return "ASKING AGENT…"
        case .receiving:
            return executorBranchIsWorking ? "WAITING ON AGENT" : "FOLLOW UP OR DONE"
        case .followUpRecording: return "STOP TO SEND"
        case .followUpOver: return "PROCESSING…"
        case .error: return session.offersVoiceRetry ? "TALK OR DISMISS" : "DISMISS TO RESET"
        }
    }

    private var branchMetaLabel: String? {
        switch session.executorBranchState {
        case .idle:
            return nil
        case .working:
            return "AGENT WORKING"
        case .done:
            return "AGENT RETURNED"
        case .failed:
            return "AGENT FAILED"
        }
    }

    private var modelMetaLabel: String {
        let provider = session.topLevelProviderName ?? "LLM"
        let model = session.topLevelModelId.map(shortModelLabel) ?? "auto"
        if let runtime = session.executorRuntimeName, session.routeMode == .async {
            return "\(provider) · \(model) → \(runtime)"
        }
        return "\(provider) · \(model)"
    }

    private func shortModelLabel(_ model: String) -> String {
        if model.count <= 18 { return model }
        return String(model.prefix(15)) + "…"
    }

    // MARK: - AMBER scheme palette

    private let amberBody = Color(red: 0.078, green: 0.094, blue: 0.102)
    private let amberTrace = Color(red: 1.0, green: 0.663, blue: 0.251)
    private let amberTraceDim = Color(red: 0.91, green: 0.60, blue: 0.24)
    private let amberEdge = Color(red: 1.0, green: 0.663, blue: 0.251).opacity(0.18)
    private let amberEdgeFaint = Color(red: 1.0, green: 0.663, blue: 0.251).opacity(0.08)
    private let amberGrid = Color(red: 0.91, green: 0.60, blue: 0.24).opacity(0.07)
    private let ink = Color(red: 0.788, green: 0.647, blue: 0.42)
    private let inkSubtle = Color(red: 0.353, green: 0.302, blue: 0.22)
}

// MARK: - Thinking dot

private struct ThinkingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.663, blue: 0.251))
            .frame(width: 7, height: 7)
            .opacity(pulse ? 1.0 : 0.35)
            .scaleEffect(pulse ? 1.0 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
