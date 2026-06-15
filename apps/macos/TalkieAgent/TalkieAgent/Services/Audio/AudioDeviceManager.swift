//
//  AudioDeviceManager.swift
//  TalkieAgent
//
//  Manages audio input device selection with persistent UID-based selection
//

import Foundation
import CoreAudio
import AVFoundation
import TalkieKit

private let logger = Log(.audio)
private let deviceLog = Log(.audio)

extension Notification.Name {
    static let audioInputDeviceDidChange = Notification.Name("audioInputDeviceDidChange")
}

/// Result of resolving which device to use for recording
struct DeviceResolution {
    let device: AudioInputDevice
    let reason: SelectionReason

    enum SelectionReason: String {
        case fixedDevice = "fixed_device"      // User's selected device found by UID
        case systemDefault = "system_default"  // Using system default (by user choice)
        case fallback = "fallback"             // Fixed device unavailable, fell back to default
    }
}

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String  // Persistent UID that survives reconnects
    let name: String
    let isDefault: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.uid == rhs.uid
    }
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var defaultDeviceID: AudioDeviceID = 0
    @Published private(set) var inputChangeRevision = 0

    private var lastDeviceSignature = ""
    private var lastDefaultDeviceID: AudioDeviceID = 0
    private var pendingDeviceChangeTask: Task<Void, Never>?

    private init() {
        refreshDevices(announce: false, reason: "startup")
        setupDeviceChangeListener()
    }

    func refreshDevices() {
        refreshDevices(announce: false, reason: "manual")
    }

    private func refreshDevices(announce: Bool, reason: String) {
        inputDevices = getInputDevices()
        defaultDeviceID = getDefaultInputDeviceID()
        let signature = deviceSignature(inputDevices)
        let didChange = signature != lastDeviceSignature || defaultDeviceID != lastDefaultDeviceID

        if didChange {
            lastDeviceSignature = signature
            lastDefaultDeviceID = defaultDeviceID
        }

        logger.info("Found \(self.inputDevices.count) input devices, default: \(self.defaultDeviceID)")

        guard announce, didChange else { return }
        inputChangeRevision += 1

        let defaultName = inputDevices.first(where: { $0.id == defaultDeviceID })?.name
        let deviceLabel = defaultName ?? "system input"
        deviceLog.info("Audio input changed", detail: "\(reason): \(deviceLabel)")

        NotificationCenter.default.post(
            name: .audioInputDeviceDidChange,
            object: self,
            userInfo: [
                "deviceName": deviceLabel,
                "reason": reason,
                "revision": inputChangeRevision
            ]
        )
    }

    /// Get the currently selected device ID (from settings, or default)
    /// Note: Prefer using resolveSelectedDevice() for recording to get proper fallback logic
    var selectedDeviceID: AudioDeviceID {
        // New UID-based selection
        let mode = LiveSettings.shared.selectedMicrophoneMode
        if mode == .fixedUID, let uid = LiveSettings.shared.selectedMicrophoneUID {
            if let device = inputDevices.first(where: { $0.uid == uid }) {
                return device.id
            }
        }

        // Legacy ID-based fallback for migration
        let savedID = LiveSettings.shared.selectedMicrophoneID
        if savedID != 0, inputDevices.contains(where: { $0.id == savedID }) {
            return savedID
        }

        return defaultDeviceID
    }

    /// Get the name of the currently selected device
    var selectedDeviceName: String? {
        inputDevices.first(where: { $0.id == selectedDeviceID })?.name
    }

    /// Resolve which device to use for recording, with fallback logic
    /// Returns the device and the reason it was selected (for logging)
    func resolveSelectedDevice() -> DeviceResolution? {
        let mode = LiveSettings.shared.selectedMicrophoneMode

        switch mode {
        case .systemDefault:
            // User explicitly chose to follow system default
            if let device = inputDevices.first(where: { $0.isDefault }) {
                return DeviceResolution(device: device, reason: .systemDefault)
            }
            // No default device found (shouldn't happen)
            return inputDevices.first.map { DeviceResolution(device: $0, reason: .systemDefault) }

        case .fixedUID:
            // User selected a specific device - try to find by UID
            if let uid = LiveSettings.shared.selectedMicrophoneUID,
               let device = inputDevices.first(where: { $0.uid == uid }) {
                return DeviceResolution(device: device, reason: .fixedDevice)
            }

            // Fixed device not found - fallback to system default with warning
            let savedName = LiveSettings.shared.selectedMicrophoneName ?? "Unknown"
            logger.warning("Fixed device '\(savedName)' not found, falling back to system default")

            if let device = inputDevices.first(where: { $0.isDefault }) {
                return DeviceResolution(device: device, reason: .fallback)
            }
            return inputDevices.first.map { DeviceResolution(device: $0, reason: .fallback) }
        }
    }

    /// Select a specific device by its ID (sets mode to fixedUID)
    func selectDevice(_ device: AudioInputDevice) {
        AgentConsole.info("🎤 AudioDeviceManager.selectDevice: \(device.name) (uid: \(device.uid))")

        // Save UID-based selection
        LiveSettings.shared.selectedMicrophoneMode = .fixedUID
        LiveSettings.shared.selectedMicrophoneUID = device.uid
        LiveSettings.shared.selectedMicrophoneName = device.name

        // Keep legacy ID for backwards compatibility
        LiveSettings.shared.selectedMicrophoneID = device.id

        logger.info("Selected audio input device: \(device.name) (uid: \(device.uid))")
    }

    /// Select system default (sets mode to systemDefault)
    func selectSystemDefault() {
        AgentConsole.info("🎤 AudioDeviceManager.selectSystemDefault()")

        LiveSettings.shared.selectedMicrophoneMode = .systemDefault
        LiveSettings.shared.selectedMicrophoneUID = nil
        LiveSettings.shared.selectedMicrophoneName = nil
        LiveSettings.shared.selectedMicrophoneID = 0

        logger.info("Selected system default microphone")
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

            // Get device name and UID
            guard let name = getDeviceName(deviceID),
                  let uid = getDeviceUID(deviceID) else { return nil }

            return AudioInputDevice(
                id: deviceID,
                uid: uid,
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

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)

        guard status == noErr, let cfUID = uid?.takeRetainedValue() else { return nil }

        return cfUID as String
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

    private func setupDeviceChangeListener() {
        // Listen for device changes
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.scheduleDeviceRefresh(reason: "device-list")
            }
        }

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.scheduleDeviceRefresh(reason: "default-input")
            }
        }
    }

    private func scheduleDeviceRefresh(reason: String) {
        pendingDeviceChangeTask?.cancel()
        pendingDeviceChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refreshDevices(announce: true, reason: reason)
        }
    }

    private func deviceSignature(_ devices: [AudioInputDevice]) -> String {
        devices
            .map { "\($0.uid):\($0.id):\($0.isDefault)" }
            .sorted()
            .joined(separator: "|")
    }
}
