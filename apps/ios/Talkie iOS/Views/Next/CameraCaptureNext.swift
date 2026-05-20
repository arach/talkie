//
//  CameraCaptureNext.swift
//  Talkie iOS
//
//  STUB — Phase-1 placeholder. To be implemented by a dedicated
//  Codex stream:
//    - AVFoundation `AVCaptureSession` preview (back camera default,
//      switchable to front).
//    - Shutter button captures still photo.
//    - Vision-framework OCR pass on the captured image (text extracted
//      as `recognizedText`).
//    - Writes to `CaptureStore` as a capture with `.scan` source
//      (or `.image`), title from OCR's first line, preview from OCR
//      body, image attached as the capture's thumbnail / image data.
//    - Visual: full-screen camera preview + Next-style chrome (top
//      Done/Settings corners + bottom shutter FAB). Use the
//      complications language; the tray's Camera button already
//      routes here via `AppShellRouter.openCameraCapture()`.
//    - Permission handling for `NSCameraUsageDescription` (already in
//      Info.plist).
//

import SwiftUI

struct CameraCaptureNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("CAMERA")
                    .talkieType(.channelLabel)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Text("Stub — implementation pending")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }
}
