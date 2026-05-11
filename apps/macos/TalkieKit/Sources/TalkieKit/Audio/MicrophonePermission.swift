import AVFoundation

public enum MicrophonePermissionStatus: Sendable {
    case granted
    case denied
    case notDetermined

    public var isGranted: Bool {
        self == .granted
    }
}

public enum MicrophonePermission {
    public static var status: MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    public static var isGranted: Bool {
        status.isGranted
    }

    @discardableResult
    public static func request() async -> Bool {
        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
