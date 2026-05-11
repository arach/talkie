import Foundation

public enum DictationNotification: String {
    case commandChanged = "talkie.dictation.commandChanged"
    case stateChanged = "talkie.dictation.stateChanged"

    fileprivate var cfName: CFNotificationName {
        CFNotificationName(rawValue: rawValue as CFString)
    }
}

public final class DictationNotificationCenter {
    public static let shared = DictationNotificationCenter()

    public final class Token {
        fileprivate let name: String
        fileprivate let callback: () -> Void

        fileprivate init(name: String, callback: @escaping () -> Void) {
            self.name = name
            self.callback = callback
        }
    }

    private init() {}

    public func post(_ notification: DictationNotification) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, notification.cfName, nil, nil, true)
    }

    public func addObserver(
        _ notification: DictationNotification,
        callback: @escaping () -> Void
    ) -> Token {
        let token = Token(name: notification.rawValue, callback: callback)
        let name = notification.rawValue as CFString
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(token).toOpaque())
        CFNotificationCenterAddObserver(
            center,
            observer,
            dictationNotificationCallback,
            name,
            nil,
            .deliverImmediately
        )
        return token
    }

    public func removeObserver(_ token: Token) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(token).toOpaque())
        let name = CFNotificationName(token.name as CFString)
        CFNotificationCenterRemoveObserver(center, observer, name, nil)
    }
}

private let dictationNotificationCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    let token = Unmanaged<DictationNotificationCenter.Token>
        .fromOpaque(observer)
        .takeUnretainedValue()
    DispatchQueue.main.async {
        token.callback()
    }
}
