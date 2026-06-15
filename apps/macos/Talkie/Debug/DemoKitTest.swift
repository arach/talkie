//
//  DemoKitTest.swift
//  Talkie
//
//  Test view for DemoKit synthetic cursor system.
//  Launch with a demo-only build that defines DEMO_KIT_ENABLED to enable.
//
import SwiftUI

#if DEMO_KIT_ENABLED && canImport(DemoKit)
import DemoKit
#endif

#if DEMO_KIT_ENABLED && canImport(DemoKit)
/// Test view demonstrating DemoKit integration
struct DemoKitTestView: View {
    @State private var cursor = DemoCursor()
    @State private var isRunning = false
    @State private var logText = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("DemoKit Test")
                .font(.title)

            Text("Mode: \(DemoMode.isEnabled ? "ENABLED ✅" : "DISABLED ❌")")
                .foregroundStyle(DemoMode.isEnabled ? .green : .secondary)

            HStack(spacing: 40) {
                // Test buttons with anchors
                Button("Button A") {
                    log("Button A clicked")
                }
                .demoAnchor("btn-a")

                Button("Button B") {
                    log("Button B clicked")
                }
                .demoAnchor("btn-b")

                Button("Button C") {
                    log("Button C clicked")
                }
                .demoAnchor("btn-c")
            }

            TextField("Text Input", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .demoAnchor("text-input")

            Divider()

            HStack {
                Button("Run Demo") {
                    Task { await runDemo() }
                }
                .disabled(isRunning || !DemoMode.isEnabled)

                Button("Dump Anchors") {
                    DemoAnchorRegistry.shared.dump()
                    log("Anchors: \(DemoAnchorRegistry.shared.anchors.count)")
                }

                Button("Export JSON") {
                    let json = DemoAnchorRegistry.shared.exportJSON()
                    TalkieConsole.info(json)
                    log("JSON exported to console")
                }
            }

            // Log output
            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 100)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(40)
        .frame(width: 500, height: 450)
        .syntheticCursor(cursor)
        .onAppear {
            log("DemoMode.isEnabled: \(DemoMode.isEnabled)")
            if DemoMode.isEnabled {
                log("Launch with --demo flag detected")
            }
        }
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logText += "[\(timestamp)] \(message)\n"
    }

    @MainActor
    private func runDemo() async {
        isRunning = true
        log("Starting demo...")

        let runner = DemoScriptRunner(cursor: cursor)

        // Hybrid mode: emit positions for debugging
        runner.onPositionEmit = { point in
            TalkieConsole.info("📍 Position emitted: \(point)")
        }

        await runner.run([
            .wait(seconds: 0.5),
            .moveTo(anchor: "btn-a", duration: 0.4),
            .click,
            .wait(seconds: 0.3),
            .moveTo(anchor: "btn-b", duration: 0.3),
            .click,
            .wait(seconds: 0.3),
            .moveTo(anchor: "btn-c", duration: 0.3),
            .click,
            .wait(seconds: 0.3),
            .moveTo(anchor: "text-input", duration: 0.4),
            .click,
            .wait(seconds: 1),
            .hide,
        ])

        log("Demo complete!")
        isRunning = false
    }
}

// MARK: - Preview

#Preview {
    DemoKitTestView()
        .onAppear {
            DemoMode.enable() // Enable for preview
        }
}

// MARK: - Debug Command Registration

extension DemoKitTestView {
    /// Register demo command with DebugCommandHandler
    static func registerDebugCommand() {
        // This would be called from AppDelegate to add --debug=demo-test command
    }
}
#endif // DEMO_KIT_ENABLED && canImport(DemoKit)
