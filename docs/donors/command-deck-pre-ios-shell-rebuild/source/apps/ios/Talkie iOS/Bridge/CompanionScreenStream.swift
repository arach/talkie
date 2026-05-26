//
//  CompanionScreenStream.swift
//  Talkie iOS
//
//  Lightweight authenticated screen-preview stream for paired iPad/iPhone
//  devices. Receives throttled JPEG frames over the existing bridge.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CompanionScreenStream {
    static let shared = CompanionScreenStream()

    var latestFrame: UIImage?
    var latestFrameAt: Date?
    var isConnecting = false
    var isStreaming = false
    var errorMessage: String?
    var appliedFPS = 2
    var frameCount = 0

    private let bridgeManager = BridgeManager.shared
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private init() {}

    func start(fps: Int = 2, maxDimension: Int = 1400, quality: Double = 0.6) {
        guard receiveTask == nil else { return }

        latestFrame = nil
        latestFrameAt = nil
        frameCount = 0
        errorMessage = nil
        isConnecting = true
        isStreaming = false

        receiveTask = Task { [weak self] in
            await self?.runStream(fps: fps, maxDimension: maxDimension, quality: quality)
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        isConnecting = false
        isStreaming = false
    }

    private func runStream(fps: Int, maxDimension: Int, quality: Double) async {
        defer {
            receiveTask = nil
            webSocketTask = nil
            isConnecting = false
            isStreaming = false
        }

        do {
            if bridgeManager.status != .connected {
                await bridgeManager.connect()
            }

            guard bridgeManager.status == .connected else {
                throw BridgeError.connectionFailed
            }

            let request = try await bridgeManager.client.screenStreamRequest(
                fps: fps,
                maxDimension: maxDimension,
                quality: quality
            )

            let task = URLSession.shared.webSocketTask(with: request)
            webSocketTask = task
            task.resume()

            while !Task.isCancelled {
                let message = try await task.receive()
                try Task.checkCancellation()
                await handle(message)
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .string(let text):
            guard let textData = text.data(using: .utf8) else { return }
            data = textData
        case .data(let bytes):
            data = bytes
        @unknown default:
            return
        }

        guard let envelope = try? JSONDecoder().decode(StreamEnvelope.self, from: data) else {
            return
        }

        switch envelope.type {
        case "screen:ready":
            appliedFPS = envelope.fps ?? appliedFPS
            isConnecting = false
            isStreaming = true

        case "screen:config:applied":
            appliedFPS = envelope.fps ?? appliedFPS

        case "screen:frame":
            guard let frameBase64 = envelope.frameBase64,
                  let frameData = Data(base64Encoded: frameBase64),
                  let image = UIImage(data: frameData) else {
                return
            }

            latestFrame = image
            latestFrameAt = envelope.capturedAt.flatMap(Self.iso8601Formatter.date(from:))
            frameCount += 1
            isConnecting = false
            isStreaming = true
            errorMessage = nil

        case "screen:error":
            errorMessage = envelope.error ?? "Screen preview unavailable"
            isConnecting = false

        default:
            break
        }
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    private struct StreamEnvelope: Decodable {
        let type: String
        let error: String?
        let frameBase64: String?
        let capturedAt: String?
        let fps: Int?
    }
}
