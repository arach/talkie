//
//  CameraBubbleView.swift
//  Talkie
//
//  SwiftUI circular camera preview with record/stop button.
//  Hosted inside CameraBubblePanel. Reads state from CameraBubbleController.
//

import SwiftUI
import AVFoundation

// MARK: - Camera Bubble View

struct CameraBubbleView: View {
    private let controller = CameraBubbleController.shared
    private let captureService = CameraCaptureService.shared
    private let clipTray = ClipTray.shared

    @State private var showSavedFlash = false
    @State private var lastClipCount = 0

    private var size: CGFloat { captureService.bubbleSize.points }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewRepresentable()
                .frame(width: size, height: size)
                .clipShape(Circle())

            // "Saved" flash overlay
            if showSavedFlash {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: size, height: size)
                    .transition(.opacity)
            }

            // Border ring — glows red when recording, green flash on save
            Circle()
                .stroke(borderColor, lineWidth: borderWidth)
                .frame(width: size, height: size)

            // Clip count badge (top-right)
            if clipTray.count > 0 && controller.state != .recording {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(clipTray.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                                    .shadow(color: Color.accentColor.opacity(0.5), radius: 3, y: 1)
                            )
                    }
                    Spacer()
                }
                .padding(2)
            }

            // Close button (top-left) — always visible
            VStack {
                HStack {
                    Button(action: {
                        CameraBubbleController.shared.toggle()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
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

            // Record/stop button at bottom
            VStack {
                Spacer()
                recordButton
            }
        }
        .frame(width: size, height: size)
        .contextMenu {
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
        .onChange(of: clipTray.count) { oldCount, newCount in
            if newCount > oldCount {
                // New clip added — flash
                withAnimation(.easeOut(duration: 0.15)) {
                    showSavedFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        showSavedFlash = false
                    }
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
        if showSavedFlash { return .green }
        return controller.state == .recording ? .red : .white.opacity(0.4)
    }

    private var borderWidth: CGFloat {
        if showSavedFlash { return 3 }
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

/// NSView wrapping AVCaptureVideoPreviewLayer for circular camera preview
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
