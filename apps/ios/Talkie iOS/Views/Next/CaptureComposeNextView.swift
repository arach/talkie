//
//  CaptureComposeNextView.swift
//  Talkie iOS
//
//  Thin Option-A router shell for the capture creation stack. The
//  source picker delegates to existing per-mode surfaces instead of
//  retiring them: text compose, dictation, camera scan, and web capture.
//

import SwiftUI
import TalkieMobileKit

struct CaptureComposeNextView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case text
        case dictation
        case camera
        case web

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "Text"
            case .dictation: return "Dictation"
            case .camera: return "Camera"
            case .web: return "Web"
            }
        }

        var subtitle: String {
            switch self {
            case .text: return "Start a text note"
            case .dictation: return "Record a memo"
            case .camera: return "Scan pages or photos"
            case .web: return "Browse and capture"
            }
        }

        var systemImage: String {
            switch self {
            case .text: return "square.and.pencil"
            case .dictation: return "mic.fill"
            case .camera: return "doc.viewfinder"
            case .web: return "globe"
            }
        }
    }

    private let initialURL: URL?
    private let initialMode: Mode?
    private let onCaptureSaved: ((String) -> Void)?

    @ObservedObject private var theme = ThemeManager.shared
    @State private var routedMode: Mode?

    init(
        initialURL: URL? = nil,
        initialMode: Mode? = nil,
        onCaptureSaved: ((String) -> Void)? = nil
    ) {
        self.initialURL = initialURL
        self.initialMode = initialMode
        self.onCaptureSaved = onCaptureSaved
    }

    var body: some View {
        Group {
            if let routedMode {
                routedSurface(for: routedMode)
            } else {
                sourcePicker
            }
        }
        .onAppear {
            guard routedMode == nil else { return }
            if initialURL != nil {
                routedMode = .web
            } else if let initialMode {
                routedMode = initialMode
            }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("· NEW CAPTURE")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                        Text("Choose a source")
                            .talkieType(.headlineSecondary)
                            .foregroundStyle(theme.colors.textPrimary)
                        Text("Text, dictation, camera scans, and web links stay on their dedicated surfaces.")
                            .talkieType(.preview)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Mode.allCases) { mode in
                            sourceCell(mode)
                        }
                    }
                    .padding(.horizontal, 12)

                    Text("Saved camera and web captures open in Compose for follow-up edits.")
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)

                    Spacer(minLength: 120)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                Text("Cancel")
                    .talkieType(.preview)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Capture")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()
                .frame(width: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }

    private func sourceCell(_ mode: Mode) -> some View {
        Button {
            route(to: mode)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .frame(width: 38, height: 38)
                    .background(theme.colors.background, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .talkieType(.listTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(mode.subtitle)
                        .talkieType(.hint)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("Open")
                        .talkieType(.fieldLabel)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(mode.title) capture")
    }

    private func route(to mode: Mode) {
        switch mode {
        case .text:
            AppShellRouter.shared.openComposeSeeded(text: "")
        case .dictation:
            RecordingSheetController.shared.isPresented = true
        case .camera, .web:
            routedMode = mode
        }
    }

    @ViewBuilder
    private func routedSurface(for mode: Mode) -> some View {
        switch mode {
        case .text:
            sourcePicker
                .onAppear {
                    AppShellRouter.shared.openComposeSeeded(text: "")
                    routedMode = nil
                }
        case .dictation:
            sourcePicker
                .onAppear {
                    RecordingSheetController.shared.isPresented = true
                    routedMode = nil
                }
        case .camera:
            CameraCaptureNext(onCaptureSaved: handleCaptureSaved)
        case .web:
            WebCaptureBrowserNext(initialURL: initialURL, onCaptureSaved: handleCaptureSaved)
        }
    }

    private func handleCaptureSaved(_ captureID: String) {
        if let onCaptureSaved {
            onCaptureSaved(captureID)
        } else {
            AppShellRouter.shared.openCompose(documentID: captureID)
        }
    }
}
