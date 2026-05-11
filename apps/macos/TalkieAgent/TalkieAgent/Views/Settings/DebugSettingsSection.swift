//
//  DebugSettingsSection.swift
//  TalkieAgent
//
//  Debug settings dump - only visible in DEBUG builds
//

#if DEBUG
import SwiftUI
import TalkieKit

struct DebugSettingsSection: View {
    @State private var settingsJSON: String = "Loading..."
    @State private var dumpPath: String = ""
    @State private var simulateHALFailure = AudioEngine.simulateHALFailure
    @State private var simulateNoBuffers = AudioEngine.simulateNoBuffers

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "ladybug",
                title: "DEBUG",
                subtitle: "Settings dump for troubleshooting"
            )
        } content: {
            SettingsCard(title: "AUDIO DEBUG") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle(isOn: $simulateHALFailure) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulate HAL Failure")
                                .font(.system(size: 12, weight: .medium))
                            Text("Test recovery when audio device setup fails")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: simulateHALFailure) { _, newValue in
                        AudioEngine.simulateHALFailure = newValue
                    }

                    if simulateHALFailure {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("HAL failure simulation ACTIVE - will fall back to system default")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    Toggle(isOn: $simulateNoBuffers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Simulate No Audio Buffers")
                                .font(.system(size: 12, weight: .medium))
                            Text("Test recovery when mic produces no audio")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: simulateNoBuffers) { _, newValue in
                        AudioEngine.simulateNoBuffers = newValue
                    }

                    if simulateNoBuffers {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("NO BUFFERS simulation ACTIVE - recordings WILL FAIL after retries")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            SettingsCard(title: "SETTINGS DUMP") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Path:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                        Text(dumpPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TalkieTheme.textSecondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Refresh") {
                            loadSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    ScrollView {
                        Text(settingsJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(TalkieTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 400)
                }
            }

            SettingsCard(title: "ACTIONS") {
                HStack(spacing: Spacing.md) {
                    Button(action: {
                        NSWorkspace.shared.selectFile(dumpPath, inFileViewerRootedAtPath: "")
                    }) {
                        Label("Reveal in Finder", systemImage: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(settingsJSON, forType: .string)
                    }) {
                        Label("Copy JSON", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("TalkieAgent")
        let file = tmpDir.appendingPathComponent("settings-dump.json")
        dumpPath = file.path

        if let data = try? Data(contentsOf: file),
           let json = String(data: data, encoding: .utf8) {
            settingsJSON = json
        } else {
            settingsJSON = "No settings dump found.\nSettings will be dumped on next app launch or settings change."
        }
    }
}

#Preview {
    DebugSettingsSection()
        .frame(width: 500, height: 600)
        .background(TalkieTheme.background)
        .preferredColorScheme(.dark)
}
#endif
