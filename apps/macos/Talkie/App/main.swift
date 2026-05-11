//
//  main.swift
//  Talkie
//
//  Entry point that routes to either:
//    - LITE MODE: --interstitial --id=ID --text="..." (fast panel)
//    - FULL MODE: everything else
//
//  Lite mode is launched by TalkieAgent via direct Process() spawn.
//  Text is passed directly - NO database fetch needed for first paint.
//

import AppKit

// ============================================================
// STEP 1: Log process start (before ANY initialization)
// ============================================================
let processStart = CFAbsoluteTimeGetCurrent()
let args = ProcessInfo.processInfo.arguments

NSLog("[main.swift] ========== TALKIE PROCESS START ==========")
NSLog("[main.swift] PID: \(ProcessInfo.processInfo.processIdentifier)")

// ============================================================
// STEP 2: Detect mode and SET IT FIRST (before any singletons)
// ============================================================
let isLiteMode = args.contains("--interstitial")
AppMode.set(isLiteMode ? .lite : .full)

// ============================================================
// STEP 3: Parse arguments (FAST - no dependencies)
// ============================================================
// TalkieAgent spawns: Talkie --interstitial --payload=/path/to/payload.json
// Payload JSON contains: { "id": 8178, "text": "transcribed text", "timestamp": ... }
//
// Security: Text is passed via file (not CLI) to avoid exposure in `ps` output

var isInterstitial = false
var payloadPath: String? = nil
var recordId: Int64? = nil
var text: String? = nil
var audioFilename: String? = nil

for arg in args {
    if arg == "--interstitial" {
        isInterstitial = true
    } else if arg.hasPrefix("--payload=") {
        payloadPath = String(arg.dropFirst("--payload=".count))
    }
    // Legacy support for direct args (less secure, but works)
    else if arg.hasPrefix("--id=") {
        let idString = String(arg.dropFirst("--id=".count))
        recordId = Int64(idString)
    } else if arg.hasPrefix("--text=") {
        text = String(arg.dropFirst("--text=".count))
    }
}

// If payload file specified, read from it (preferred secure method)
if let payloadPath = payloadPath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: payloadPath))
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let id = json["id"] as? Int64 {
                recordId = id
            } else if let id = json["id"] as? Int {
                recordId = Int64(id)
            }
            text = json["text"] as? String
            audioFilename = json["audioFilename"] as? String
        }
        // Clean up payload file after reading (contains sensitive text)
        try? FileManager.default.removeItem(atPath: payloadPath)
        NSLog("[main.swift] Read payload from file, cleaned up")
    } catch {
        NSLog("[main.swift] Failed to read payload: \(error.localizedDescription)")
    }
}

// ============================================================
// STEP 3: Route to appropriate mode
// ============================================================
if isInterstitial, let text = text {
    //
    // ========== LITE MODE ==========
    //
    let elapsed = (CFAbsoluteTimeGetCurrent() - processStart) * 1000
    NSLog("[main.swift] >>> LITE MODE in \(String(format: "%.1f", elapsed))ms")
    NSLog("[main.swift] recordId: \(recordId ?? -1), text: \(text.prefix(50))...")

    // Initialize minimal NSApplication and run lite mode
    // We're on the main thread at startup, so use MainActor.assumeIsolated
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // No dock icon

    MainActor.assumeIsolated {
        InterstitialOnlyApp.run(app: app, text: text, recordId: recordId, audioFilename: audioFilename)
    }

} else {
    //
    // ========== FULL MODE ==========
    //
    let elapsed = (CFAbsoluteTimeGetCurrent() - processStart) * 1000
    NSLog("[main.swift] >>> FULL MODE in \(String(format: "%.1f", elapsed))ms")

    TalkieApp.main()
}
