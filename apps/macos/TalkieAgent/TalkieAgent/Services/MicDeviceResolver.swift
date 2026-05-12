import Foundation
import AVFoundation
import CoreAudio
import TalkieKit

private let log = Log(.audio)

struct MicDeviceSelection {
    let deviceID: AudioDeviceID
    let uid: String
    let name: String
    let isFixedDevice: Bool
}

enum MicDeviceResolverError: LocalizedError {
    case selectedDeviceUnavailable(String)
    case noAudioInputDevice
    case deviceNotResponding(String)

    var errorDescription: String? {
        switch self {
        case .selectedDeviceUnavailable(let label):
            return "Selected microphone unavailable: \(label)"
        case .noAudioInputDevice:
            return "No audio input device found. Connect a microphone or headset to record."
        case .deviceNotResponding(let label):
            return "Audio device not responding: \(label)"
        }
    }
}

struct MicDeviceResolver {
    func resolveSelection() throws -> MicDeviceSelection {
        let selection: MicDeviceSelection
        switch resolveDevice() {
        case .selection(let value):
            selection = value
        case .missingFixed(let uid, let name):
            let label = name ?? uid ?? "Unknown device"
            throw MicDeviceResolverError.selectedDeviceUnavailable(label)
        }

        guard isDeviceResponding(selection.deviceID) else {
            if selection.deviceID == 0 {
                throw MicDeviceResolverError.noAudioInputDevice
            }
            throw MicDeviceResolverError.deviceNotResponding(selection.name)
        }

        if selection.isFixedDevice {
            let currentDefault = getDefaultInputDeviceID()
            if currentDefault != selection.deviceID {
                _ = setDefaultInputDevice(selection.deviceID)
            }
        }

        return selection
    }

    private enum DeviceResolution {
        case selection(MicDeviceSelection)
        case missingFixed(uid: String?, name: String?)
    }

    private func resolveDevice() -> DeviceResolution {
        let store = TalkieSharedSettings
        let modeRaw = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode)
            ?? MicrophoneSelectionMode.systemDefault.rawValue
        let mode = MicrophoneSelectionMode(rawValue: modeRaw) ?? .systemDefault

        switch mode {
        case .systemDefault:
            return .selection(selectSystemDefault())
        case .fixedUID:
            return selectConfiguredDevice()
        }
    }

    private func selectSystemDefault() -> MicDeviceSelection {
        let deviceID = getDefaultInputDeviceID()
        guard deviceID != 0 else {
            log.warning("Bridge mic found no audio input device")
            return MicDeviceSelection(deviceID: 0, uid: "none", name: "No Input Device", isFixedDevice: false)
        }

        let uid = getDeviceUID(deviceID) ?? "system_default"
        let name = getDeviceName(deviceID) ?? "System Default"
        return MicDeviceSelection(deviceID: deviceID, uid: uid, name: name, isFixedDevice: false)
    }

    private func selectConfiguredDevice() -> DeviceResolution {
        let store = TalkieSharedSettings
        let requestedUID = store.string(forKey: AgentSettingsKey.selectedMicrophoneUID)
        let requestedName = store.string(forKey: AgentSettingsKey.selectedMicrophoneName)

        guard let requestedUID else {
            return .missingFixed(uid: nil, name: requestedName)
        }

        if let deviceID = findDeviceByUID(requestedUID),
           let name = getDeviceName(deviceID) {
            return .selection(
                MicDeviceSelection(
                    deviceID: deviceID,
                    uid: requestedUID,
                    name: name,
                    isFixedDevice: true
                )
            )
        }

        return .missingFixed(uid: requestedUID, name: requestedName)
    }

    private func isDeviceResponding(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0 else {
            return getDefaultInputDeviceID() != 0
        }

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        if status == noErr, let cfName = name?.takeRetainedValue() {
            let _ = cfName as String
            return true
        }

        return false
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

    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &mutableDeviceID
        )

        return status == noErr
    }

    private func findDeviceByUID(_ uid: String) -> AudioDeviceID? {
        for deviceID in getAllDeviceIDs() {
            if getDeviceUID(deviceID) == uid, hasInputStreams(deviceID) {
                return deviceID
            }
        }

        return nil
    }

    private func getAllDeviceIDs() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard sizeStatus == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return [] }
        return deviceIDs
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList)
        guard status == noErr else { return false }

        return bufferList.pointee.mNumberBuffers > 0
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
        guard status == noErr, let value = uid?.takeRetainedValue() else { return nil }
        return value as String
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
        guard status == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }
}
