import Cocoa
import AVFoundation
import TalkieKit

private let log = Log(.system)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureService = MicCaptureService()
    private var bridge: ServiceBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await ensureMicPermission()
            NSApp.setActivationPolicy(.accessory)
            IdleWatchdog.shared.start()
            startBridge()
            log.info("TalkieMic ready")
        }
    }

    private func ensureMicPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            log.info("Microphone permission: authorized")
        case .notDetermined:
            log.info("Microphone permission: requesting...")
            // Keep as regular app until permission is granted so macOS shows the dialog
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            log.info("Microphone permission: \(granted ? "granted" : "denied")")
        case .denied, .restricted:
            log.error("Microphone permission: DENIED — open System Settings → Privacy & Security → Microphone to enable TalkieMic")
        @unknown default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge?.stop()
        bridge = nil
        IdleWatchdog.shared.stop()
        captureService.shutdown()
    }

    private func startBridge() {
        let bridge = ServiceBridge(port: 19824, serviceName: "TalkieMic")

        bridge.handle("ping") { _, reply in
            IdleWatchdog.shared.markActivity()
            reply(["pong": true], nil)
        }

        bridge.handle("status") { [weak self] _, reply in
            guard let self else {
                reply(nil, "service_unavailable")
                return
            }

            reply([
                "activeSessions": self.captureService.activeSessionCount,
                "engineRunning": self.captureService.isEngineRunning,
                "sessions": self.captureService.sessionStats
            ], nil)
        }

        bridge.handle("startSession") { [weak self] params, reply in
            guard let self else {
                reply(nil, "service_unavailable")
                return
            }

            let clientId = params?["clientId"] as? String ?? "unknown"
            let persist = params?["persist"] as? Bool ?? true
            let label = params?["label"] as? String

            Task {
                do {
                    let sessionId = try await self.captureService.startSession(
                        clientId: clientId,
                        persist: persist,
                        label: label
                    )
                    reply(["sessionId": sessionId], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("stopSession") { [weak self] params, reply in
            guard let self else {
                reply(nil, "service_unavailable")
                return
            }

            guard let sessionId = params?["sessionId"] as? String else {
                reply(nil, "missing_session_id")
                return
            }

            Task {
                do {
                    let result = try await self.captureService.stopSession(sessionId: sessionId)
                    reply([
                        "sessionId": sessionId,
                        "filePath": result.filePath,
                        "duration": result.duration,
                        "fileSize": result.fileSize
                    ], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("cancelSession") { [weak self] params, reply in
            guard let self else {
                reply(nil, "service_unavailable")
                return
            }

            guard let sessionId = params?["sessionId"] as? String else {
                reply(nil, "missing_session_id")
                return
            }

            Task {
                do {
                    try await self.captureService.cancelSession(sessionId: sessionId)
                    reply(["cancelled": true], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("shutdown") { [weak self] _, reply in
            IdleWatchdog.shared.markActivity()
            reply(["ok": true], nil)
            Task { @MainActor [weak self] in
                self?.captureService.shutdown()
                NSApp.terminate(nil)
            }
        }

        bridge.start()
        self.bridge = bridge
    }
}
