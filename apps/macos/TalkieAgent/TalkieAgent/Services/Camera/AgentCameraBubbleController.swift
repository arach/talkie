//
//  AgentCameraBubbleController.swift
//  TalkieAgent
//
//  Orchestrates Agent's capturable camera bubble.
//

import Foundation
import TalkieKit

private let agentCameraControllerLog = Log(.system)

@MainActor
@Observable
final class AgentCameraBubbleController {
    static let shared = AgentCameraBubbleController()

    enum State: Equatable {
        case hidden
        case previewing
    }

    private(set) var state: State = .hidden

    @ObservationIgnored
    private let panel = AgentCameraBubblePanel()
    @ObservationIgnored
    private var showGeneration = 0

    private init() {}

    @discardableResult
    func showForScreenRecording() -> Bool {
        guard state == .hidden else { return false }
        show()
        return true
    }

    func toggle() {
        switch state {
        case .hidden:
            show()
        case .previewing:
            hide()
        }
    }

    func show() {
        guard state == .hidden else { return }
        state = .previewing
        showGeneration += 1
        let generation = showGeneration

        Task {
            let capture = AgentCameraCaptureService.shared
            guard await capture.requestPermission() else {
                guard showGeneration == generation else { return }
                agentCameraControllerLog.warning("Camera permission denied, cannot show Agent camera bubble")
                state = .hidden
                return
            }

            guard await capture.startPreviewAsync() else {
                guard showGeneration == generation else { return }
                agentCameraControllerLog.error("Agent camera bubble preview failed to start")
                state = .hidden
                return
            }

            guard showGeneration == generation, state == .previewing else {
                capture.stopPreview()
                return
            }
            panel.show()
        }
    }

    func hide() {
        guard state != .hidden else { return }
        showGeneration += 1
        AgentCameraCaptureService.shared.stopPreview()
        panel.dismiss()
        state = .hidden
    }

    func teardown() {
        panel.dismiss()
        AgentCameraCaptureService.shared.teardown()
        state = .hidden
    }
}
