//
//  AgentCameraBubbleView.swift
//  TalkieAgent
//
//  Circular camera preview used as picture-in-picture for screen recordings.
//

import AVFoundation
import SwiftUI

struct AgentCameraBubbleView: View {
    private let captureService = AgentCameraCaptureService.shared

    private var size: CGFloat { captureService.bubbleSize }

    var body: some View {
        ZStack {
            AgentCameraPreviewRepresentable()
                .frame(width: size, height: size)
                .clipShape(Circle())

            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 2)
                .frame(width: size, height: size)

            VStack {
                HStack {
                    Button {
                        AgentCameraBubbleController.shared.hide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                Spacer()
            }
            .padding(2)
        }
        .frame(width: size, height: size)
        .contextMenu {
            Button("Hide Camera") {
                AgentCameraBubbleController.shared.hide()
            }
        }
    }
}

private struct AgentCameraPreviewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> AgentCameraPreviewNSView {
        AgentCameraPreviewNSView()
    }

    func updateNSView(_ nsView: AgentCameraPreviewNSView, context: Context) {
        nsView.updateSession()
    }
}

private final class AgentCameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupPreview()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupPreview()
    }

    private func setupPreview() {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        self.layer?.addSublayer(layer)
        previewLayer = layer
        updateSession()
    }

    @MainActor
    func updateSession() {
        previewLayer?.session = AgentCameraCaptureService.shared.captureSession
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
