//
//  AgentCameraBubbleView.swift
//  TalkieAgent
//
//  Configurable camera preview used as picture-in-picture for screen recordings.
//

import AVFoundation
import SwiftUI
import TalkieKit

struct AgentCameraBubbleView: View {
    private let captureService = AgentCameraCaptureService.shared

    @State private var isHovering = false

    private var shape: CameraBubbleShape { captureService.bubbleShape }
    private var size: CGSize { shape.dimensions(for: captureService.bubbleSize) }
    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: shape.cornerRadius(for: size), style: .continuous)
    }

    var body: some View {
        ZStack {
            AgentCameraPreviewRepresentable()
                .frame(width: size.width, height: size.height)
                .clipShape(bubbleShape)

            bubbleShape
                .stroke(.white.opacity(0.45), lineWidth: 2)
                .frame(width: size.width, height: size.height)

            VStack {
                HStack {
                    Button {
                        AgentCameraBubbleController.shared.hide()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                Spacer()
            }
            .padding(2)
            .opacity(isHovering ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(bubbleShape)
        .onHover { isHovering = $0 }
        .contextMenu {
            cameraGeometryMenu
            Divider()
            Button("Hide Camera") {
                AgentCameraBubbleController.shared.hide()
            }
        }
    }

    private var cameraGeometryMenu: some View {
        Group {
            Menu("Size") {
                ForEach(CameraBubbleSize.allCases) { size in
                    Button {
                        update(AgentSettingsKey.cameraBubbleSize, to: size.rawValue)
                    } label: {
                        Label(size.label, systemImage: captureService.bubbleSize == size ? "checkmark" : "circle")
                    }
                }
            }
            Menu("Shape") {
                ForEach(CameraBubbleShape.allCases) { shape in
                    Button {
                        update(AgentSettingsKey.cameraBubbleShape, to: shape.rawValue)
                    } label: {
                        Label(shape.label, systemImage: shape.symbolName)
                    }
                }
            }
            Menu("Position") {
                ForEach(CameraBubblePlacement.allCases) { placement in
                    Button {
                        update(AgentSettingsKey.cameraBubblePlacement, to: placement.rawValue)
                    } label: {
                        Label(placement.label, systemImage: placement.symbolName)
                    }
                    .disabled(placement == .custom && TalkieSharedSettings.dictionary(forKey: AgentSettingsKey.cameraBubbleCustomPosition) == nil)
                }
            }
        }
    }

    private func update(_ key: String, to value: String) {
        TalkieSharedSettings.set(value, forKey: key)
        CameraBubbleSettingsBridge.notifyChanged()
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
