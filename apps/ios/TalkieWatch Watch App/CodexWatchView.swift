//
//  CodexWatchView.swift
//  TalkieWatch
//
//  Exact-task voice dispatch in the Watch instrument-console vocabulary.
//  Horizontal swipes belong to the Capture/Codex shell; task movement is
//  deliberately assigned to the Digital Crown and explicit arrow buttons.
//

import SwiftUI
import WatchKit

struct CodexWatchView: View {
    @EnvironmentObject private var sessionManager: WatchSessionManager
    @StateObject private var recorder = AudioRecorder()

    let isActive: Bool

    @FocusState private var isCrownFocused: Bool
    @State private var crownPosition = 0.0
    @State private var isRecording = false
    @State private var recordingChannel: CodexWatchChannel?
    @State private var recordingHostID: String?
    @State private var recordingAction: CodexWatchDispatchAction?
    @State private var isNewTaskArmed = false
    @State private var localFailure: String?

    var body: some View {
        ZStack {
            WatchInstrumentBackground()

            if let channel = sessionManager.selectedCodexChannel {
                channelSurface(channel)
            } else {
                emptySurface
            }
        }
        .focusable()
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownPosition,
            from: 0,
            through: Double(max(sessionManager.codexChannels.count - 1, 0)),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            synchronizeCrown()
            isCrownFocused = isActive
        }
        .onChange(of: isActive) { _, active in
            isCrownFocused = active
            if !active {
                isNewTaskArmed = false
                if isRecording {
                    cancelRecording()
                }
            }
        }
        .onChange(of: crownPosition) { _, position in
            guard !isRecording else {
                synchronizeCrown()
                return
            }
            selectChannel(at: Int(position.rounded()))
        }
        .onChange(of: sessionManager.selectedCodexTaskID) { _, _ in
            isNewTaskArmed = false
            synchronizeCrown()
        }
        .onChange(of: sessionManager.codexChannels) { _, _ in
            synchronizeCrown()
        }
        .onChange(of: sessionManager.codexDispatchReceipt?.state) { _, state in
            guard let state else { return }
            switch state {
            case .completed:
                WKInterfaceDevice.current().play(.success)
            case .failed:
                WKInterfaceDevice.current().play(.failure)
            case .sending, .queued, .transferred, .received, .running:
                break
            }
        }
        .onDisappear {
            isNewTaskArmed = false
            if isRecording {
                cancelRecording()
            }
        }
    }

    private func channelSurface(_ channel: CodexWatchChannel) -> some View {
        VStack(spacing: 6) {
            codexHeader

            WatchInstrumentPanel(annotation: "codex task") {
                HStack(spacing: 2) {
                    channelButton(systemImage: "chevron.left", offset: -1)

                    VStack(spacing: 3) {
                        Text(channel.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WatchTheme.current.panelInk)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        Text(channel.project.uppercased())
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(WatchTheme.current.panelInkFaint)
                            .lineLimit(1)

                        channelPositionLine(channel)
                    }
                    .frame(maxWidth: .infinity)

                    channelButton(systemImage: "chevron.right", offset: 1)
                }
            }
            .frame(maxHeight: 88)

            Spacer(minLength: 0)

            CodexHoldToTalkButton(
                isRecording: isRecording,
                isEnabled: true,
                taskTitle: channel.project,
                onPressChanged: handleTalkPress
            )

            dispatchStatusLine(channel)
        }
        .padding(.horizontal, 10)
        .padding(.top, 18)
        .padding(.bottom, 9)
    }

    private var codexHeader: some View {
        let chrome = WatchTheme.current
        return HStack(spacing: 5) {
            WatchEyebrow(text: "Codex", tint: .panelInk, showLeader: false)

            Spacer(minLength: 0)

            Button {
                isNewTaskArmed.toggle()
                WKInterfaceDevice.current().play(.click)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isNewTaskArmed ? "plus.square.fill" : "plus.square")
                    Text(isNewTaskArmed ? "NEW ARMED" : "NEW")
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(isNewTaskArmed ? chrome.accent : chrome.panelInkFaint)
            }
            .buttonStyle(.plain)
            .disabled(isRecording)
            .accessibilityLabel(
                isNewTaskArmed ? "Cancel new Codex task" : "Create a new Codex task"
            )

            WatchStatusDot(
                diameter: 5,
                pulses: isRecording,
                color: sessionManager.isReachable ? .green : .orange
            )
        }
    }

    private func channelPositionLine(_ channel: CodexWatchChannel) -> some View {
        let chrome = WatchTheme.current
        return HStack(spacing: 4) {
            WatchStatusDot(
                diameter: 4,
                pulses: channel.status == .running || channel.status == .receiving,
                color: statusColor(channel.status)
            )

            Text(channel.status.label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(chrome.panelInkFaint)
                .lineLimit(1)

            Text("\(selectedChannelPosition + 1)/\(sessionManager.codexChannels.count)")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(chrome.panelInkFaint)
        }
    }

    private func channelButton(systemImage: String, offset: Int) -> some View {
        Button {
            moveSelection(by: offset)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchTheme.current.accent)
                .frame(width: 32, height: 54)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isRecording || sessionManager.codexChannels.count < 2)
        .accessibilityLabel(offset < 0 ? "Previous Codex project" : "Next Codex project")
    }

    private func dispatchStatusLine(_ channel: CodexWatchChannel) -> some View {
        let chrome = WatchTheme.current
        let presentation = dispatchPresentation(channel)
        return HStack(spacing: 5) {
            WatchStatusDot(
                diameter: 4,
                pulses: presentation.pulses,
                color: presentation.color
            )

            Text(presentation.label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(chrome.panelInkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptySurface: some View {
        let chrome = WatchTheme.current
        return VStack(spacing: 10) {
            HStack {
                WatchEyebrow(text: "Codex", tint: .panelInk, showLeader: false)
                Spacer()
                WatchStatusDot(diameter: 5, color: sessionManager.isReachable ? .green : .orange)
            }

            Spacer(minLength: 0)

            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(chrome.accent)
                .watchAccentGlow()

            Text("NO PROJECTS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(chrome.panelInk)

            Text("Open the Codex deck on iPhone to load your projects.")
                .font(.caption2)
                .foregroundStyle(chrome.panelInkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var selectedChannelPosition: Int {
        guard let taskID = sessionManager.selectedCodexTaskID else { return 0 }
        return sessionManager.codexChannels.firstIndex(where: { $0.taskID == taskID }) ?? 0
    }

    private func moveSelection(by offset: Int) {
        let channels = sessionManager.codexChannels
        guard channels.count > 1 else { return }
        let nextIndex = (selectedChannelPosition + offset + channels.count) % channels.count
        sessionManager.selectCodexChannel(taskID: channels[nextIndex].taskID)
        WKInterfaceDevice.current().play(.click)
    }

    private func selectChannel(at index: Int) {
        let channels = sessionManager.codexChannels
        guard channels.indices.contains(index) else { return }
        sessionManager.selectCodexChannel(taskID: channels[index].taskID)
    }

    private func synchronizeCrown() {
        let position = Double(selectedChannelPosition)
        guard crownPosition != position else { return }
        crownPosition = position
    }

    private func handleTalkPress(_ pressed: Bool) {
        if pressed {
            startRecording()
        } else {
            stopAndDispatch()
        }
    }

    private func startRecording() {
        guard !isRecording,
              let channel = sessionManager.selectedCodexChannel,
              let hostID = sessionManager.codexSnapshot?.hostID,
              !hostID.isEmpty else {
            return
        }

        localFailure = nil
        recordingChannel = channel
        recordingHostID = hostID
        recordingAction = isNewTaskArmed ? .newTask : .continueTask
        recorder.startRecording()
        isRecording = recorder.isRecording

        if isRecording {
            WKInterfaceDevice.current().play(.start)
        } else {
            localFailure = "MICROPHONE UNAVAILABLE"
            recordingChannel = nil
            recordingHostID = nil
            recordingAction = nil
        }
    }

    private func stopAndDispatch() {
        guard isRecording,
              let channel = recordingChannel,
              let hostID = recordingHostID,
              let action = recordingAction else {
            return
        }

        let duration = recorder.recordingDuration
        isRecording = false
        recordingChannel = nil
        recordingHostID = nil
        recordingAction = nil
        if action == .newTask {
            isNewTaskArmed = false
        }
        WKInterfaceDevice.current().play(.stop)

        Task { @MainActor in
            guard let audioURL = await recorder.stopRecording() else {
                localFailure = "RECORDING FAILED"
                return
            }

            sessionManager.sendCodexAudio(
                fileURL: audioURL,
                duration: duration,
                requestID: UUID(),
                hostID: hostID,
                taskID: channel.taskID,
                taskTitle: channel.title,
                workingDirectory: channel.workingDirectory,
                action: action
            )
        }
    }

    private func cancelRecording() {
        recorder.cancelRecording()
        isRecording = false
        recordingChannel = nil
        recordingHostID = nil
        recordingAction = nil
    }

    private func dispatchPresentation(_ channel: CodexWatchChannel) -> (
        label: String,
        color: Color,
        pulses: Bool
    ) {
        if isRecording {
            return ("LISTENING \(elapsedLabel)", .red, true)
        }

        if let localFailure {
            return (localFailure, .red, false)
        }

        if let receipt = sessionManager.codexDispatchReceipt,
           receipt.taskID == channel.taskID {
            switch receipt.state {
            case .sending:
                return (receipt.state.label, WatchTheme.current.accent, true)
            case .queued:
                return (receipt.state.label, .orange, false)
            case .transferred:
                return (receipt.state.label, WatchTheme.current.panelInkFaint, false)
            case .received:
                return (receipt.state.label, .green, false)
            case .running:
                return (receipt.state.label, WatchTheme.current.accent, true)
            case .completed:
                return (receipt.state.label, .green, false)
            case .failed:
                return (receipt.detail ?? receipt.state.label, .red, false)
            }
        }

        if !sessionManager.isReachable {
            return ("HOLD · AUDIO WILL QUEUE", .orange, false)
        }

        return (
            isNewTaskArmed ? "HOLD · CREATE NEW TASK" : "HOLD · CONTINUE TASK",
            WatchTheme.current.accent,
            false
        )
    }

    private var elapsedLabel: String {
        let seconds = max(0, Int(recorder.recordingDuration))
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        let paddedSeconds = secondsPart < 10 ? "0\(secondsPart)" : "\(secondsPart)"
        return "\(minutesPart):\(paddedSeconds)"
    }

    private func statusColor(_ status: CodexWatchChannel.Status) -> Color {
        switch status {
        case .ready: return .green
        case .running, .receiving: return WatchTheme.current.accent
        case .queued: return .orange
        case .failed: return .red
        case .unavailable, .unknown: return WatchTheme.current.panelInkFaint
        }
    }
}

private struct CodexHoldToTalkButton: View {
    let isRecording: Bool
    let isEnabled: Bool
    let taskTitle: String
    let onPressChanged: (Bool) -> Void

    @State private var suppressTapAction = false
    @State private var isHoldArmed = false
    @State private var pendingHoldTask: Task<Void, Never>?

    var body: some View {
        let chrome = WatchTheme.current
        Button {
            if suppressTapAction {
                suppressTapAction = false
            } else {
                onPressChanged(!isRecording)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecording ? Color.red.opacity(0.22) : chrome.panelAlt)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                isRecording ? Color.red : chrome.accent.opacity(0.72),
                                lineWidth: 1
                            )
                    }

                HStack(spacing: 7) {
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isRecording ? Color.red : chrome.accent)
                        .symbolEffect(.variableColor.iterative, isActive: isRecording)

                    Text(isRecording ? "RELEASE" : "HOLD TO TALK")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(chrome.panelInk)
                }
            }
            .frame(width: 116, height: 42)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onLongPressGesture(
            minimumDuration: .infinity,
            maximumDistance: 18,
            pressing: handlePress,
            perform: {}
        )
        .onDisappear {
            pendingHoldTask?.cancel()
        }
        .accessibilityLabel(isRecording ? "Release to dispatch" : "Dispatch to \(taskTitle)")
        .accessibilityHint("Press and hold while speaking, then release to send")
    }

    private func handlePress(_ pressing: Bool) {
        pendingHoldTask?.cancel()

        if pressing {
            suppressTapAction = true
            pendingHoldTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    isHoldArmed = true
                    onPressChanged(true)
                } catch {
                    // A page swipe or early release cancelled the hold.
                }
            }
            return
        }

        pendingHoldTask = nil
        if isHoldArmed {
            isHoldArmed = false
            onPressChanged(false)
        }

        Task { @MainActor in
            // Let the Button action generated by this release observe the
            // suppression flag before restoring accessibility toggle behavior.
            await Task.yield()
            suppressTapAction = false
        }
    }
}

#Preview {
    CodexWatchView(isActive: true)
        .environmentObject(WatchSessionManager.shared)
}
