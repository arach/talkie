//
//  AudioDeviceManager.swift
//  Talkie
//
//  Manages audio input device selection
//  Ported from TalkieLive with instrumentation
//

import Foundation
import CoreAudio
import AVFoundation
import os
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "AudioDeviceManager")

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@Observable
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    private(set) var inputDevices: [AudioInputDevice] = []
    private(set) var defaultDeviceID: AudioDeviceID = 0

    private var isInitialized = false

    private init() {
        StartupProfiler.shared.mark("singleton.AudioDeviceManager.start")
        // CoreAudio initialization is deferred until first actual use
        // This avoids ~100ms system init cost during startup
        StartupProfiler.shared.mark("singleton.AudioDeviceManager.done")
    }

    /// Ensures CoreAudio is initialized (call before accessing devices)
    func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true
        setupDeviceChangeListener()
        refreshDevices()
    }

    func refreshDevices() {
        let startTime = CFAbsoluteTimeGetCurrent()

        inputDevices = getInputDevices()
        defaultDeviceID = getDefaultInputDeviceID()

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.info("Found \(self.inputDevices.count) input devices, default: \(self.defaultDeviceID) (took \(String(format: "%.1f", elapsed))ms)")
    }

    /// Get the currently selected device ID (from settings, or default)
    var selectedDeviceID: AudioDeviceID {
        let savedID = LiveSettings.shared.selectedMicrophoneID
        if savedID != 0, inputDevices.contains(where: { $0.id == savedID }) {
            return savedID
        }
        return defaultDeviceID
    }

    /// Set the selected device as the system input (for AVAudioEngine to use)
    func selectDevice(_ deviceID: AudioDeviceID) {
        let deviceName = inputDevices.first(where: { $0.id == deviceID })?.name ?? "Unknown"

        // Save to settings
        LiveSettings.shared.selectedMicrophoneID = deviceID

        // Set as default input device for this process
        setDefaultInputDevice(deviceID)

        logger.info("Selected audio input device: \(deviceID) (\(deviceName))")
    }

    // MARK: - CoreAudio Helpers

    private func getInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            logger.error("Failed to get devices size: \(status)")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            logger.error("Failed to get devices: \(status)")
            return []
        }

        let defaultID = getDefaultInputDeviceID()

        return deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            // Check if device has input channels
            guard hasInputChannels(deviceID) else { return nil }

            // Get device name
            guard let name = getDeviceName(deviceID) else { return nil }

            return AudioInputDevice(
                id: deviceID,
                name: name,
                isDefault: deviceID == defaultID
            )
        }
    }

    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)

        guard getStatus == noErr else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)

        guard status == noErr, let cfName = name?.takeRetainedValue() else { return nil }

        return cfName as String
    }

    private func getDefaultInputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : 0
    }

    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
        // Note: This sets the aggregate device for this process, not the system default
        // AVAudioEngine will pick up the change on next start
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        // This typically requires elevated privileges for system-wide change
        // For per-app selection, we handle it differently in MicrophoneCapture
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
    }

    private func setupDeviceChangeListener() {
        // Listen for device changes
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                logger.debug("Audio device configuration changed, refreshing device list")
                self?.refreshDevices()
            }
        }
    }
}
