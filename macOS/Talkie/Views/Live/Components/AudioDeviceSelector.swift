//
//  AudioDeviceSelector.swift
//  Talkie
//
//  Audio device selector with live level monitoring for Live settings
//  Ported from TalkieLive with instrumentation
//

import SwiftUI
import TalkieKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

// MARK: - Audio Device Selector with Level Meter

struct AudioDeviceSelector: View {
    private let audioDevices = AudioDeviceManager.shared
    private let liveState = TalkieLiveStateMonitor.shared
    @State private var isHovered = false

    private var selectedDeviceName: String {
        if let device = audioDevices.inputDevices.first(where: { $0.id == audioDevices.selectedDeviceID }) {
            return device.name
        } else if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return defaultDevice.name
        }
        return "System Default"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Device Dropdown
            Menu {
                ForEach(audioDevices.inputDevices) { device in
                    Button(action: {
                        audioDevices.selectDevice(device.id)
                        logger.info("User selected audio device: \(device.name) (id: \(device.id))")
                    }) {
                        HStack {
                            Text(device.name)
                            if device.isDefault {
                                Text("(System Default)")
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            if device.id == audioDevices.selectedDeviceID {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "mic")
                        .font(.labelMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text(selectedDeviceName)
                        .font(.labelMedium)
                        .foregroundColor(Theme.current.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(Color.primary.opacity(isHovered ? Opacity.light : Opacity.subtle))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .onHover { isHovered = $0 }

            // Audio Level Meter - only visible when TalkieLive is running
            if liveState.isRunning {
                AudioLevelMeter()
                    .frame(width: 80, height: 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Text("Enable Live Mode to see levels")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 80, height: 32)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: liveState.isRunning)
        .onAppear {
            logger.debug("AudioDeviceSelector appeared, device count: \(audioDevices.inputDevices.count)")
        }
    }
}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    private let liveState = TalkieLiveStateMonitor.shared

    private let barCount = 8
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    AudioLevelBar(
                        level: liveState.audioLevel,
                        index: index,
                        totalBars: barCount
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(Color.primary.opacity(Opacity.subtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(Color.primary.opacity(Opacity.light), lineWidth: 0.5)
        )
        .onAppear {
            logger.debug("AudioLevelMeter appeared")
        }
    }
}

// MARK: - Individual Audio Level Bar

struct AudioLevelBar: View {
    let level: Float
    let index: Int
    let totalBars: Int

    private var isActive: Bool {
        let threshold = Float(index) / Float(totalBars)
        return level >= threshold
    }

    private var barColor: Color {
        let ratio = Float(index) / Float(totalBars)
        if ratio < 0.6 {
            return .green
        } else if ratio < 0.85 {
            return .yellow
        } else {
            return .red
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(isActive ? barColor : Color.primary.opacity(0.1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }
}
