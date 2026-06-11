#if os(macOS)
import AppKit

public enum CaptureMode: String, Sendable {
    case region
    case fullscreen
    case window
}

public enum CaptureBarMode: String, CaseIterable, Sendable {
    case screenshot
    case video
}

public enum CaptureHUDPosition: String, CaseIterable, Codable, Sendable {
    case cursor
    case fixed
}

public struct CaptureResult {
    public let data: Data
    public let image: CGImage
    public let previewImage: CGImage
    public let capturedAt: Date
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let appName: String?
    public let appBundleID: String?
    public let displayName: String?

    public init(
        data: Data,
        image: CGImage,
        previewImage: CGImage,
        capturedAt: Date,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        appBundleID: String?,
        displayName: String?
    ) {
        self.data = data
        self.image = image
        self.previewImage = previewImage
        self.capturedAt = capturedAt
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.appName = appName
        self.appBundleID = appBundleID
        self.displayName = displayName
    }
}
#endif
