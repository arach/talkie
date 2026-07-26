import Foundation

public enum CameraBubbleSettingsBridge {
    public static let settingsDidChange = "to.talkie.cameraBubble.settingsDidChange"

    public static func notifyChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(settingsDidChange),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
