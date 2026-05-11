//
//  ScreenCapturePermissionManager.swift
//  Talkie
//
//  Single source of truth for screen capture permission state.
//  Capture remains optional and off by default; permission is only
//  requested when the user opts into capture features.
//

import AppKit
import Observation
import TalkieKit

enum ScreenCapturePermissionState: Equatable {
    case unknown
    case denied
    case granted

    var isGranted: Bool {
        self == .granted
    }
}

@MainActor
@Observable
final class ScreenCapturePermissionManager {
    static let shared = ScreenCapturePermissionManager()

    private(set) var appStatus: ScreenCapturePermissionState = .unknown
    private(set) var agentStatus: ScreenCapturePermissionState = .unknown
    private(set) var isRefreshing = false
    private(set) var isRequesting = false

    var captureFeatureEnabled: Bool {
        FeatureFlags.shared.enableCapture
    }

    var isReadyForCapture: Bool {
        appStatus.isGranted && agentStatus.isGranted
    }

    private init() {}

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        appStatus = Self.status(for: CGPreflightScreenCaptureAccess())

        if let screenRecording = await fetchAgentScreenRecordingPermission() {
            agentStatus = Self.status(for: screenRecording)
        } else {
            agentStatus = .unknown
        }
    }

    @discardableResult
    func requestForCaptureEnablement() async -> Bool {
        guard !isRequesting else { return isReadyForCapture }
        isRequesting = true
        defer { isRequesting = false }

        await refresh()

        if !appStatus.isGranted {
            _ = CGRequestScreenCaptureAccess()
        }

        if agentStatus != .granted, let granted = await requestAgentScreenRecordingPermission() {
            agentStatus = Self.status(for: granted)
        }

        await refresh()
        return isReadyForCapture
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func status(for granted: Bool) -> ScreenCapturePermissionState {
        granted ? .granted : .denied
    }

    private func fetchAgentScreenRecordingPermission() async -> Bool? {
        await withAgentService { service, reply in
            service.getPermissions { _, _, screenRecording in
                reply(screenRecording)
            }
        }
    }

    private func requestAgentScreenRecordingPermission() async -> Bool? {
        await withAgentService { service, reply in
            service.requestScreenRecordingPermission { granted in
                reply(granted)
            }
        }
    }

    private func withAgentService<T>(
        _ call: @escaping (TalkieAgentXPCServiceProtocol, @escaping (T?) -> Void) -> Void
    ) async -> T? {
        let connection = NSXPCConnection(machServiceName: kTalkieAgentXPCServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: TalkieAgentXPCServiceProtocol.self)
        connection.resume()

        defer {
            connection.invalidate()
        }

        return await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                continuation.resume(returning: nil)
            } as? TalkieAgentXPCServiceProtocol

            guard let proxy else {
                continuation.resume(returning: nil)
                return
            }

            call(proxy) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
