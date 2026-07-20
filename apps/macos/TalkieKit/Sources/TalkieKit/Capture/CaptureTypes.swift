#if os(macOS)
import AppKit

public enum CaptureMode: String, Sendable {
    case region
    case fullscreen
    case window
}

public enum RegionCaptureBehavior: String, Sendable, Equatable {
    case visibleContent
    case scrollingContent

    public var captureModeValue: String {
        switch self {
        case .visibleContent: "region"
        case .scrollingContent: "scrolling-region"
        }
    }
}

public struct CaptureRegionSelection: Sendable {
    public let rect: CGRect
    public let behavior: RegionCaptureBehavior

    public init(rect: CGRect, behavior: RegionCaptureBehavior = .visibleContent) {
        self.rect = rect
        self.behavior = behavior
    }
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
    /// Stable persisted mode value. Region captures can refine the broad
    /// `CaptureMode.region` target into `scrolling-region`.
    public let captureMode: String
    /// Screen-points rect (global AppKit coords) the capture covers, for
    /// fullscreen/region modes. `nil` for window captures, which have no
    /// screen-relative frame. Used to rebase desktop-ink layers onto the shot.
    public let captureRect: CGRect?

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
        displayName: String?,
        captureMode: String = "region",
        captureRect: CGRect? = nil
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
        self.captureMode = captureMode
        self.captureRect = captureRect
    }
}
#endif
