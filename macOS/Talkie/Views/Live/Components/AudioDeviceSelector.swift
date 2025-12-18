//
//  AudioDeviceSelector.swift
//  Talkie
//
//  Audio device selector with live level monitoring for Live settings
//  Ported from TalkieLive with instrumentation
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

// MARK: - Audio Device Selector with Level Meter

struct AudioDeviceSelector: View {
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @ObservedObject private var audioLevel = AudioLevelMonitor.shared
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
                                    .foregroundColor(.secondary)
                            }
                            if device.id == audioDevices.selectedDeviceID {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text(selectedDeviceName)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0.05))
                )
            }
            .menuStyle(.borderlessButton)
            .onHover { isHovered = $0 }

            // Audio Level Meter
            AudioLevelMeter()
                .frame(width: 80, height: 32)
        }
        .onAppear {
            logger.debug("AudioDeviceSelector appeared, device count: \(audioDevices.inputDevices.count)")
        }
    }
}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    @ObservedObject private var audioLevel = AudioLevelMonitor.shared

    private let barCount = 8
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    AudioLevelBar(
                        level: audioLevel.level,
                        index: index,
                        totalBars: barCount
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
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
