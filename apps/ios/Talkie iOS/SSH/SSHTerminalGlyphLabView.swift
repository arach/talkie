//
//  SSHTerminalGlyphLabView.swift
//  Talkie iOS
//
//  Pure xterm renderer page for debugging glyph and box-drawing issues on
//  device without involving SSH or tmux.
//

import SwiftUI

struct SSHTerminalGlyphLabView: View {
    @Environment(\.dismiss) private var dismiss
    let captureData: Data?
    let chunkRecords: [SSHTerminalOutputChunkRecord]
    @State private var refitRequestID = 0
    @State private var showingTranscriptInspector = false
    @State private var sourceMode: SourceMode = .ansi

    private enum SourceMode: String, CaseIterable, Identifiable {
        case unicode
        case ansi
        case live

        var id: String { rawValue }
    }

    private static let ansiFixtureBase64 = """
    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
    """

    private static let ansiFixtureData = Data(base64Encoded: ansiFixtureBase64)

    private var hasCaptureData: Bool {
        !(captureData?.isEmpty ?? true)
    }

    private var hasChunkRecords: Bool {
        !chunkRecords.isEmpty
    }

    private var sourceDescription: String {
        switch sourceMode {
        case .unicode:
            return "Source: bundled Unicode fixture."
        case .ansi:
            return "Source: extracted ANSI control-stream fixture."
        case .live:
            if hasChunkRecords {
                return "Source: live SSH output chunks (\(chunkRecords.count))."
            }
            if hasCaptureData {
                return "Source: live SSH session capture."
            }
            return "Source: bundled renderer fixture."
        }
    }

    private var selectedCaptureData: Data? {
        switch sourceMode {
        case .unicode:
            nil
        case .ansi:
            Self.ansiFixtureData
        case .live:
            captureData
        }
    }

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                surface
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !hasCaptureData && !hasChunkRecords {
                sourceMode = .ansi
            }
            refitRequestID += 1
        }
        .sheet(isPresented: $showingTranscriptInspector) {
            if sourceMode == .live, let captureData {
                SSHTerminalTranscriptInspectorView(
                    captureData: captureData,
                    chunkRecords: chunkRecords
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(Color.surfaceSecondary)
                        .clipShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close renderer lab")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Xterm Renderer Lab")
                        .font(.headlineMedium)
                        .foregroundStyle(Color.textPrimary)

                    Text(sourceDescription)
                        .font(.labelSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer(minLength: 0)

                Button(sourceMode == .live && hasCaptureData ? "Transcript" : "Transcript") {
                    showingTranscriptInspector = true
                }
                .buttonStyle(.bordered)
                .disabled(sourceMode != .live || !hasCaptureData)

                Button("Refit") {
                    refitRequestID += 1
                }
                .buttonStyle(.bordered)
            }

            Picker("Source", selection: $sourceMode) {
                Text("Unicode").tag(SourceMode.unicode)
                Text("ANSI").tag(SourceMode.ansi)
                Text("Live").tag(SourceMode.live)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var surface: some View {
        SSHTerminalGlyphLabSurfaceView(
            refitRequestID: refitRequestID,
            captureData: selectedCaptureData,
            chunkRecords: sourceMode == .live ? chunkRecords : []
        )
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.borderPrimary.opacity(0.85), lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }
}
