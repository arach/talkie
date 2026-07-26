//
//  CameraBubbleView.swift
//  Talkie
//
//  SwiftUI camera preview with record/stop button.
//  Hosted inside CameraBubblePanel. Reads state from CameraBubbleController.
//

import SwiftUI
import AVFoundation
import TalkieKit

// MARK: - Camera Bubble View

struct CameraBubbleView: View {
    private let controller = CameraBubbleController.shared
    private let captureService = CameraCaptureService.shared

    @State private var isHovering = false

    private var shape: CameraBubbleShape { captureService.bubbleShape }
    private var size: CGSize { shape.dimensions(for: captureService.bubbleSize) }
    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: shape.cornerRadius(for: size), style: .continuous)
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewRepresentable()
                .frame(width: size.width, height: size.height)
                .clipShape(bubbleShape)

            // Border ring — glows red when recording
            bubbleShape
                .stroke(borderColor, lineWidth: borderWidth)
                .frame(width: size.width, height: size.height)

            // Close button (top-left) — appears on hover
            VStack {
                HStack {
                    Button(action: {
                        CameraBubbleController.shared.toggle()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                Spacer()
            }
            .padding(2)
            .opacity(isHovering ? 1 : 0)

            // Record/stop button at bottom
            VStack {
                Spacer()
                recordButton
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(bubbleShape)
        .onHover { isHovering = $0 }
        .contextMenu {
            cameraGeometryMenu
            Divider()
            Button("Hide Camera") {
                CameraBubbleController.shared.hide()
            }
            Divider()
            if controller.state == .recording {
                Button("Stop Recording") {
                    controller.stopClip()
                }
            } else {
                Button("Record Clip") {
                    controller.startClip()
                }
            }
        }
    }

    private var cameraGeometryMenu: some View {
        Group {
            Menu("Size") {
                ForEach(CameraBubbleSize.allCases) { size in
                    Button {
                        captureService.bubbleSize = size
                    } label: {
                        Label(size.label, systemImage: captureService.bubbleSize == size ? "checkmark" : "circle")
                    }
                }
            }
            Menu("Shape") {
                ForEach(CameraBubbleShape.allCases) { shape in
                    Button {
                        captureService.bubbleShape = shape
                    } label: {
                        Label(shape.label, systemImage: shape.symbolName)
                    }
                }
            }
            Menu("Position") {
                ForEach(CameraBubblePlacement.allCases) { placement in
                    Button {
                        captureService.bubblePlacement = placement
                    } label: {
                        Label(placement.label, systemImage: placement.symbolName)
                    }
                    .disabled(placement == .custom && TalkieSharedSettings.dictionary(forKey: AgentSettingsKey.cameraBubbleCustomPosition) == nil)
                }
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: {
            if controller.state == .recording {
                controller.stopClip()
            } else {
                controller.startClip()
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 24, height: 24)

                if controller.state == .recording {
                    // Stop icon (rounded square)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                } else {
                    // Record icon (filled circle)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .offset(y: -4)
    }

    // MARK: - Appearance

    private var borderColor: Color {
        return controller.state == .recording ? .red : .white.opacity(0.4)
    }

    private var borderWidth: CGFloat {
        return controller.state == .recording ? 3 : 2
    }
}

// MARK: - Camera Preview (NSViewRepresentable)

struct CameraPreviewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView()
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.updateSession()
    }
}

/// NSView wrapping AVCaptureVideoPreviewLayer for camera preview.
final class CameraPreviewNSView: NSView {
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
        self.previewLayer = layer
        updateSession()
    }

    @MainActor
    func updateSession() {
        previewLayer?.session = CameraCaptureService.shared.captureSession
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
