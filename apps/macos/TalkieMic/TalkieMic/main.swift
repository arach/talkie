import Cocoa
import TalkieKit

private let log = Log(.system)

autoreleasepool {
    TalkieLogger.configure(source: .talkieLive)
    log.info("TalkieMic starting", critical: true)

    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
    }

    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
