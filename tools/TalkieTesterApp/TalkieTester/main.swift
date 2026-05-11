import AppKit
import SwiftUI
import AVFoundation
import CoreAudio
import AudioToolbox

// MARK: - Braille Spinner

/// Minimal braille spinner for loading states
struct BrailleSpinner: View {
    var size: CGFloat = 14
    var speed: Double = 0.08
    var color: Color = .secondary

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: speed)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let frame = Int(elapsed / speed) % Self.frames.count
            Text(Self.frames[frame])
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .accessibilityLabel("Loading")
        }
    }
}

// MARK: - CoreAudio Device Helpers

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let sampleRate: Double
    let isInput: Bool
    let transportType: UInt32

    var transportTypeDescription: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        default: return "Unknown"
        }
    }

    var isBluetoothHFP: Bool {
        // HFP mode typically shows 8000 or 16000 Hz sample rate
        transportType == kAudioDeviceTransportTypeBluetooth && sampleRate <= 16000
    }
}

func getAudioInputDevices() -> [AudioDevice] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    var result = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize
    )

    guard result == noErr else {
        print("Failed to get device list size: \(result)")
        return []
    }

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

    result = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize,
        &deviceIDs
    )

    guard result == noErr else {
        print("Failed to get device list: \(result)")
        return []
    }

    print("Found \(deviceCount) total audio devices, checking for input capability...")
    var devices: [AudioDevice] = []

    for deviceID in deviceIDs {
        // Check if device has input
        var inputPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var bufferListSize: UInt32 = 0
        result = AudioObjectGetPropertyDataSize(deviceID, &inputPropertyAddress, 0, nil, &bufferListSize)
        guard result == noErr else { continue }

        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPtr.deallocate() }

        result = AudioObjectGetPropertyData(deviceID, &inputPropertyAddress, 0, nil, &bufferListSize, bufferListPtr)
        guard result == noErr else { continue }

        let bufferList = bufferListPtr.pointee
        guard bufferList.mNumberBuffers > 0 else { continue }

        // Get device name
        var namePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        result = AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &nameSize, &name)
        guard result == noErr else { continue }

        // Get device UID
        var uidPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        result = AudioObjectGetPropertyData(deviceID, &uidPropertyAddress, 0, nil, &uidSize, &uid)
        guard result == noErr else { continue }

        // Get sample rate
        var sampleRatePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var sampleRateSize = UInt32(MemoryLayout<Float64>.size)
        result = AudioObjectGetPropertyData(deviceID, &sampleRatePropertyAddress, 0, nil, &sampleRateSize, &sampleRate)
        if result != noErr { sampleRate = 44100 }

        // Get transport type
        var transportPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        result = AudioObjectGetPropertyData(deviceID, &transportPropertyAddress, 0, nil, &transportSize, &transportType)
        if result != noErr { transportType = 0 }

        devices.append(AudioDevice(
            id: deviceID,
            uid: uid as String,
            name: name as String,
            sampleRate: sampleRate,
            isInput: true,
            transportType: transportType
        ))
        
        // Log device info for debugging
        let transportName = AudioDevice(id: deviceID, uid: uid as String, name: name as String, sampleRate: sampleRate, isInput: true, transportType: transportType).transportTypeDescription
        print("  ✓ Input device: \(name as String) [\(transportName)] - \(sampleRate)Hz, ID: \(deviceID)")
    }

    print("Total input devices found: \(devices.count)")
    return devices
}

// MARK: - Sample Metadata

struct SampleMetadata {
    let sampleRate: Double
    let channels: Int
    let isHFP: Bool
    let peakLevel: Float
    let durationMs: Int
    let fileSize: Int

    var formattedSampleRate: String {
        if sampleRate >= 1000 {
            return String(format: "%.1fkHz", sampleRate / 1000)
        }
        return String(format: "%.0fHz", sampleRate)
    }
}

// MARK: - Device Slot

@Observable
class DeviceSlot: Identifiable {
    let id: String  // "A" or "B"
    var deviceUID: String?
    var deviceName: String?
    var sampleURL: URL?
    var metadata: SampleMetadata?
    var isRecording: Bool = false
    var isPlaying: Bool = false
    var recordingProgress: Double = 0

    init(id: String) {
        self.id = id
    }

    var storageURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".talkie/tester")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("slot_\(id.lowercased()).wav")
    }
}

// MARK: - Audio Recorder

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var peakLevel: Float = 0
    private var isRecording = false

    func record(deviceUID: String, duration: TimeInterval, to url: URL, progress: @escaping (Double) -> Void) async -> SampleMetadata? {
        // Check microphone permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("Microphone authorization status: \(authStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print("Microphone permission granted: \(granted)")
            if !granted {
                print("Microphone permission denied")
                return nil
            }
        } else if authStatus != .authorized {
            print("Microphone not authorized - please grant permission in System Settings > Privacy > Microphone")
            return nil
        }

        // Prevent concurrent recordings
        guard !isRecording else {
            print("Already recording, ignoring request")
            return nil
        }

        // Clean up any previous engine
        cleanup()

        isRecording = true
        defer { isRecording = false }

        // Find the device
        let devices = getAudioInputDevices()
        guard let device = devices.first(where: { $0.uid == deviceUID }) else {
            print("Device not found: \(deviceUID)")
            return nil
        }

        // Check what the system default input device is
        var defaultDeviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &defaultDeviceID)
        let originalDefaultDevice = defaultDeviceID
        print("System default input device ID: \(defaultDeviceID)")

        // For Bluetooth devices, we need to set them as system default to get audio
        let isBluetooth = device.transportType == kAudioDeviceTransportTypeBluetooth ||
                          device.transportType == kAudioDeviceTransportTypeBluetoothLE
        if isBluetooth && defaultDeviceID != device.id {
            print("Bluetooth device detected - temporarily setting as system default input")
            var newDefaultID = device.id
            propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice
            let setStatus = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &newDefaultID
            )
            if setStatus == noErr {
                print("Set system default input to device ID: \(device.id)")
                // Give the system time to switch
                try? await Task.sleep(for: .milliseconds(500))
            } else {
                print("Failed to set system default input: \(setStatus)")
            }
        }

        // Closure to restore original default device
        let restoreDefault = {
            if isBluetooth && originalDefaultDevice != device.id {
                var restoreID = originalDefaultDevice
                var restoreAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectSetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &restoreAddress,
                    0,
                    nil,
                    UInt32(MemoryLayout<AudioDeviceID>.size),
                    &restoreID
                )
                print("Restored system default input to device ID: \(originalDefaultDevice)")
            }
        }

        print("Setting up recording for device: \(device.name) (ID: \(device.id), rate: \(device.sampleRate)Hz)")

        // CRITICAL: Clean up any stale engine state
        self.audioEngine = nil
        
        // Create fresh engine - must set device BEFORE accessing inputNode's format
        var engine = AVAudioEngine()
        self.audioEngine = engine

        // Get the audio unit and set device FIRST
        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            print("Could not get audio unit")
            cleanup()
            restoreDefault()
            return nil
        }

        // For Bluetooth devices, we need to explicitly enable input on the audio unit
        var enableInput: UInt32 = 1
        var enableStatus = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,  // Input element
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        print("Enable input on audio unit: \(enableStatus == noErr ? "success" : "failed (\(enableStatus))")")

        var deviceID = device.id
        var status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            print("Failed to set device on audio unit: \(status) - will retry with fresh engine")
        }

        // Verify the device was set
        var verifyDeviceID: AudioDeviceID = 0
        var verifySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &verifyDeviceID,
            &verifySize
        )
        print("Verified device ID on AudioUnit: \(verifyDeviceID) (expected: \(device.id))")

        // Check if input is enabled
        var inputEnabled: UInt32 = 0
        var inputEnabledSize = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &inputEnabled,
            &inputEnabledSize
        )
        print("Input enabled on audio unit: \(inputEnabled)")

        // CRITICAL: Stop and reset the engine to pick up new device configuration
        engine.stop()
        engine.reset()

        // For Bluetooth, we need extra time for the audio routing to stabilize
        try? await Task.sleep(for: .milliseconds(isBluetooth ? 1000 : 300))

        // Initialize the audio unit to activate the device
        status = AudioUnitInitialize(audioUnit)
        if status != noErr {
            print("Failed to initialize audio unit: \(status)")
        } else {
            print("Audio unit initialized successfully")
        }

        // Verify the device is actually alive and can provide data
        var isAlive: UInt32 = 0
        var isAliveSize = UInt32(MemoryLayout<UInt32>.size)
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device.id, &aliveAddress, 0, nil, &isAliveSize, &isAlive)
        print("Device is alive: \(isAlive)")

        // Check if device is running (providing data)
        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device.id, &runningAddress, 0, nil, &isRunningSize, &isRunning)
        print("Device is running before start: \(isRunning)")

        // Check and log the current data source for the device
        var dataSource: UInt32 = 0
        var dataSourceSize = UInt32(MemoryLayout<UInt32>.size)
        var dataSourceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let dsStatus = AudioObjectGetPropertyData(device.id, &dataSourceAddress, 0, nil, &dataSourceSize, &dataSource)
        if dsStatus == noErr {
            print("Current input data source: \(dataSource)")
            
            // Try to get available data sources
            var dataSourcesSize: UInt32 = 0
            var dataSourcesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDataSources,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyDataSize(device.id, &dataSourcesAddress, 0, nil, &dataSourcesSize) == noErr {
                let count = Int(dataSourcesSize) / MemoryLayout<UInt32>.size
                var sources = [UInt32](repeating: 0, count: count)
                if AudioObjectGetPropertyData(device.id, &dataSourcesAddress, 0, nil, &dataSourcesSize, &sources) == noErr {
                    print("Available input data sources: \(sources)")
                }
            }
        } else {
            print("Could not get input data source (status: \(dsStatus))")
        }

        // For Bluetooth devices that aren't running, we may need to manually start them
        if isBluetooth && isRunning == 0 {
            print("Device not running - attempting to start device IO...")
            // Try to start the device by calling AudioDeviceStart (this is deprecated but sometimes necessary)
            // Note: Modern approach would be to use AudioObjectPropertyListener, but for testing this works
            var startStatus = AudioDeviceStart(device.id, nil)
            print("AudioDeviceStart result: \(startStatus) (\(startStatus == noErr ? "success" : "failed"))")
            
            // Give it time to start
            try? await Task.sleep(for: .milliseconds(500))
            
            // Check again
            AudioObjectGetPropertyData(device.id, &runningAddress, 0, nil, &isRunningSize, &isRunning)
            print("Device is running after manual start: \(isRunning)")
        }

        // For Bluetooth devices, we may need to enable OUTPUT as well to activate full-duplex mode
        // This is a quirk of Bluetooth - some devices need output enabled to start the microphone
        if isBluetooth {
            print("Enabling output for Bluetooth device to activate full-duplex mode...")
            var enableOutput: UInt32 = 1
            let outputStatus = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,  // Output element
                &enableOutput,
                UInt32(MemoryLayout<UInt32>.size)
            )
            print("Enable output on audio unit: \(outputStatus == noErr ? "success" : "failed (\(outputStatus))")")
            
            // Try to force the device into HFP mode by requesting a lower sample rate
            // HFP typically uses 8000 or 16000 Hz
            if device.sampleRate > 16000 {
                print("Device is at \(device.sampleRate)Hz (likely A2DP mode). Attempting to switch to HFP mode...")
                print("⚠️  NOTE: A2DP mode is for high-quality audio PLAYBACK. For microphone input, you need HFP mode.")
                print("⚠️  Try: Make a phone call, then use the device. Or manually switch in Sound Settings.")
                
                for targetRate: Float64 in [16000.0, 8000.0] {
                    var newRate = targetRate
                    var rateAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyNominalSampleRate,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    let rateStatus = AudioObjectSetPropertyData(
                        device.id,
                        &rateAddress,
                        0,
                        nil,
                        UInt32(MemoryLayout<Float64>.size),
                        &newRate
                    )
                    if rateStatus == noErr {
                        print("✅ Successfully changed sample rate to \(targetRate)Hz (HFP mode)")
                        try? await Task.sleep(for: .milliseconds(1000))
                        
                        // Recreate engine to pick up new rate
                        engine.stop()
                        engine.reset()
                        self.audioEngine = nil
                        engine = AVAudioEngine()
                        self.audioEngine = engine
                        try? await Task.sleep(for: .milliseconds(500))
                        
                        break
                    } else {
                        print("❌ Failed to change sample rate to \(targetRate)Hz: \(rateStatus) - device may not support HFP")
                    }
                }
            }
        }

        // CRITICAL: Get a FRESH inputNode reference after all engine resets
        // The previous inputNode reference is stale if we recreated the engine
        let currentInputNode = engine.inputNode
        
        // Now get the format - it should reflect the actual device
        let recordingFormat = currentInputNode.inputFormat(forBus: 0)
        let inputChannels = recordingFormat.channelCount

        print("Input format after reset: \(recordingFormat.sampleRate)Hz, \(inputChannels)ch")

        guard recordingFormat.sampleRate > 0 && inputChannels > 0 else {
            print("Invalid recording format: \(recordingFormat.sampleRate)Hz, \(inputChannels)ch")
            // Try output format as fallback
            let outputFormat = inputNode.outputFormat(forBus: 0)
            print("Output format: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount)ch")
            cleanup()
            restoreDefault()
            return nil
        }

        print("Recording format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch, device: \(device.name)")

        // Use the INPUT format for recording (what the hardware actually provides)
        // The inputFormat is the correct format to use for the tap
        let tapFormat = recordingFormat
        print("Using tap format: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch")

        // Delete existing file
        try? FileManager.default.removeItem(at: url)

        // Create audio file with tap format (what we'll actually receive)
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: tapFormat.sampleRate,
            AVNumberOfChannelsKey: Int(tapFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            self.audioFile = try AVAudioFile(forWriting: url, settings: fileSettings)
        } catch {
            print("Failed to create audio file: \(error)")
            cleanup()
            restoreDefault()
            return nil
        }

        // Setup for recording
        peakLevel = 0
        let totalFrames = Int(tapFormat.sampleRate * duration)
        var recordedFrames = 0
        let startTime = Date()

        var bufferCount = 0
        currentInputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, time in
            guard let self = self, let file = self.audioFile else { return }

            bufferCount += 1

            // Calculate peak level
            var bufferPeak: Float = 0
            if let channelData = buffer.floatChannelData {
                let frameCount = Int(buffer.frameLength)
                for ch in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<frameCount {
                        let sample = abs(channelData[ch][i])
                        if sample > bufferPeak {
                            bufferPeak = sample
                        }
                        if sample > self.peakLevel {
                            self.peakLevel = sample
                        }
                    }
                }
            }

            if bufferCount == 1 {
                print("First buffer: \(buffer.frameLength) frames, format: \(buffer.format.sampleRate)Hz, \(buffer.format.channelCount)ch, peak: \(bufferPeak)")
                // Print first few samples
                if let channelData = buffer.floatChannelData, buffer.frameLength > 0 {
                    let samples = (0..<min(10, Int(buffer.frameLength))).map { channelData[0][$0] }
                    print("First 10 samples: \(samples)")
                    
                    // Check for all-zero buffer (indicates no audio flowing)
                    if bufferPeak == 0.0 {
                        print("⚠️ WARNING: First buffer is all zeros - audio may not be flowing from device!")
                    }
                }
            } else if bufferCount == 5 && self.peakLevel == 0.0 {
                print("⚠️ WARNING: After 5 buffers, still receiving all zeros - check device connection and permissions")
            } else if bufferCount % 10 == 0 {
                print("Buffer \(bufferCount): peak=\(bufferPeak), overall peak=\(self.peakLevel)")
            }

            // Write to file
            do {
                try file.write(from: buffer)
                recordedFrames += Int(buffer.frameLength)

                let currentProgress = min(Double(recordedFrames) / Double(totalFrames), 1.0)
                Task { @MainActor in
                    progress(currentProgress)
                }
            } catch {
                print("Failed to write buffer: \(error)")
            }
        }

        // Start engine
        do {
            try engine.start()
            print("Engine started successfully, recording for \(duration)s...")
        } catch {
            print("Failed to start engine: \(error)")
            cleanup()
            restoreDefault()
            return nil
        }

        // Record for duration using async sleep (non-blocking)
        try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))

        // Stop recording
        currentInputNode.removeTap(onBus: 0)
        engine.stop()

        // Stop the device if we manually started it
        if isBluetooth {
            AudioDeviceStop(device.id, nil)
            print("Stopped Bluetooth device IO")
        }

        // Restore original system default input device
        restoreDefault()

        print("Recording stopped. Buffers: \(bufferCount), frames: \(recordedFrames), peak: \(peakLevel) (\(20 * log10(max(peakLevel, 0.00001)))dB)")

        // Close file
        let finalPeakLevel = peakLevel
        audioFile = nil

        // Get file info
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs?[.size] as? Int ?? 0

        let metadata = SampleMetadata(
            sampleRate: tapFormat.sampleRate,
            channels: Int(tapFormat.channelCount),
            isHFP: device.isBluetoothHFP,
            peakLevel: finalPeakLevel,
            durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
            fileSize: fileSize
        )

        // Clean up engine
        self.audioEngine = nil

        return metadata
    }

    func stop() {
        cleanup()
    }

    private func cleanup() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioFile = nil
        peakLevel = 0
    }
}

// MARK: - Audio Player

class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

    func play(url: URL, completion: @escaping () -> Void) {
        self.completion = completion

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
        } catch {
            print("Failed to play: \(error)")
            completion()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        completion?()
        completion = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.completion?()
            self?.completion = nil
        }
    }
}

// MARK: - App State

@Observable
class AppState {
    var slotA = DeviceSlot(id: "A")
    var slotB = DeviceSlot(id: "B")
    var availableDevices: [AudioDevice] = []

    private let recorder = AudioRecorder()
    private let player = AudioPlayer()

    init() {
        refreshDevices()
        loadSavedSamples()

        // Refresh devices periodically
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
    }

    func refreshDevices() {
        availableDevices = getAudioInputDevices()
    }

    func loadSavedSamples() {
        // Load slot A if exists
        if FileManager.default.fileExists(atPath: slotA.storageURL.path) {
            slotA.sampleURL = slotA.storageURL
            slotA.metadata = loadMetadata(for: slotA.storageURL)
        }

        // Load slot B if exists
        if FileManager.default.fileExists(atPath: slotB.storageURL.path) {
            slotB.sampleURL = slotB.storageURL
            slotB.metadata = loadMetadata(for: slotB.storageURL)
        }
    }

    func loadMetadata(for url: URL) -> SampleMetadata? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs?[.size] as? Int ?? 0

        return SampleMetadata(
            sampleRate: file.fileFormat.sampleRate,
            channels: Int(file.fileFormat.channelCount),
            isHFP: file.fileFormat.sampleRate <= 16000,
            peakLevel: 0,  // Can't determine from file without processing
            durationMs: Int(Double(file.length) / file.fileFormat.sampleRate * 1000),
            fileSize: fileSize
        )
    }

    func record(slot: DeviceSlot) async {
        guard let deviceUID = slot.deviceUID else { return }

        slot.isRecording = true
        slot.recordingProgress = 0

        let metadata = await recorder.record(
            deviceUID: deviceUID,
            duration: 3.0,
            to: slot.storageURL
        ) { progress in
            slot.recordingProgress = progress
        }

        slot.isRecording = false
        slot.recordingProgress = 0

        if let metadata = metadata {
            slot.sampleURL = slot.storageURL
            slot.metadata = metadata
        }
    }

    func play(slot: DeviceSlot) {
        guard let url = slot.sampleURL else { return }

        slot.isPlaying = true
        player.play(url: url) {
            slot.isPlaying = false
        }
    }

    func stopPlayback(slot: DeviceSlot) {
        player.stop()
        slot.isPlaying = false
    }

    func selectDevice(_ device: AudioDevice?, for slot: DeviceSlot) {
        slot.deviceUID = device?.uid
        slot.deviceName = device?.name
    }
}

// MARK: - Views

struct SlotView: View {
    let slot: DeviceSlot
    let devices: [AudioDevice]
    let onSelectDevice: (AudioDevice?) -> Void
    let onRecord: () -> Void
    let onPlay: () -> Void
    let onStop: () -> Void

    var selectedDevice: AudioDevice? {
        devices.first { $0.uid == slot.deviceUID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Slot header
            HStack {
                Text("Slot \(slot.id)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if let device = selectedDevice {
                    Text(device.transportTypeDescription)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(transportColor(for: device).opacity(0.2))
                        .foregroundStyle(transportColor(for: device))
                        .clipShape(Capsule())
                }
            }

            // Device picker
            Picker("Device", selection: Binding(
                get: { selectedDevice },
                set: { onSelectDevice($0) }
            )) {
                Text("Select device...").tag(nil as AudioDevice?)
                ForEach(devices) { device in
                    Text(device.name).tag(device as AudioDevice?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            // Controls
            HStack(spacing: 8) {
                // Record button
                Button {
                    onRecord()
                } label: {
                    HStack(spacing: 4) {
                        if slot.isRecording {
                            BrailleSpinner(size: 12)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        }
                        Text(slot.isRecording ? "Recording..." : "Record")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(slot.deviceUID == nil || slot.isRecording)

                // Play button
                Button {
                    if slot.isPlaying {
                        onStop()
                    } else {
                        onPlay()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: slot.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 9))
                        Text(slot.isPlaying ? "Stop" : "Play")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(slot.sampleURL == nil)

                Spacer()

                // Recording progress
                if slot.isRecording {
                    Text(String(format: "%.0f%%", slot.recordingProgress * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Metadata display
            if let metadata = slot.metadata {
                MetadataView(metadata: metadata)
            } else if slot.sampleURL == nil {
                Text("No sample recorded")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    func transportColor(for device: AudioDevice) -> Color {
        switch device.transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return device.isBluetoothHFP ? .orange : .blue
        case kAudioDeviceTransportTypeUSB:
            return .green
        case kAudioDeviceTransportTypeBuiltIn:
            return .gray
        default:
            return .purple
        }
    }
}

struct MetadataView: View {
    let metadata: SampleMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                MetadataItem(label: "Rate", value: metadata.formattedSampleRate)
                MetadataItem(label: "Ch", value: "\(metadata.channels)")
                MetadataItem(label: "Peak", value: String(format: "%.1fdB", 20 * log10(max(metadata.peakLevel, 0.00001))))
            }

            HStack(spacing: 12) {
                MetadataItem(label: "Duration", value: "\(metadata.durationMs)ms")
                MetadataItem(label: "Size", value: formatBytes(metadata.fileSize))

                if metadata.isHFP {
                    Text("HFP")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        return String(format: "%.1fMB", Double(bytes) / 1024 / 1024)
    }
}

struct MetadataItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

struct PanelView: View {
    @Bindable var state: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TALKIE TESTER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    state.refreshDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh devices")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Device count
            HStack {
                Text("\(state.availableDevices.count) input devices")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Slots
            VStack(spacing: 8) {
                SlotView(
                    slot: state.slotA,
                    devices: state.availableDevices,
                    onSelectDevice: { state.selectDevice($0, for: state.slotA) },
                    onRecord: { Task { await state.record(slot: state.slotA) } },
                    onPlay: { state.play(slot: state.slotA) },
                    onStop: { state.stopPlayback(slot: state.slotA) }
                )

                SlotView(
                    slot: state.slotB,
                    devices: state.availableDevices,
                    onSelectDevice: { state.selectDevice($0, for: state.slotB) },
                    onRecord: { Task { await state.record(slot: state.slotB) } },
                    onPlay: { state.play(slot: state.slotB) },
                    onStop: { state.stopPlayback(slot: state.slotB) }
                )
            }
            .padding(12)

            Divider()

            // Footer
            HStack {
                Text("~/.talkie/tester/")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create main window
        let contentRect = NSRect(x: 0, y: 0, width: 340, height: 500)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Talkie Tester"
        window.center()

        let hostingView = NSHostingView(rootView: PanelView(state: state, onClose: {
            NSApplication.shared.terminate(nil)
        }))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
