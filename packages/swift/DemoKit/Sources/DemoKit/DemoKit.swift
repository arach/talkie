//
//  DemoKit.swift
//  DemoKit
//
//  Lightweight synthetic cursor demo system for SwiftUI.
//  Zero overhead when disabled - all operations become no-ops.
//
//  ACTIVATION:
//    - Launch with: --demo
//    - Or set env: DEMO_MODE=1
//    - Or call: DemoMode.enable()
//
//  USAGE:
//    1. Mark views with .demoAnchor("id") - auto registers/unregisters
//    2. Add .syntheticCursor(cursor) to root view
//    3. Run scripts with DemoScriptRunner
//
//  EXAMPLE:
//
//      struct ContentView: View {
//          @State private var cursor = DemoCursor()
//
//          var body: some View {
//              VStack {
//                  Button("Start")
//                      .demoAnchor("start-btn")  // Auto registers
//
//                  TextField("Input")
//                      .demoAnchor("text-input")
//              }
//              .syntheticCursor(cursor)  // Only renders in demo mode
//              .task {
//                  guard DemoMode.isEnabled else { return }
//
//                  let runner = DemoScriptRunner(cursor: cursor)
//                  await runner.run([
//                      .moveTo(anchor: "start-btn"),
//                      .click,
//                      .wait(seconds: 0.5),
//                      .moveTo(anchor: "text-input"),
//                      .click,
//                  ])
//              }
//          }
//      }
//
//  HYBRID MODE (synthetic cursor + real OS clicks):
//
//      runner.onPositionEmit = { point in
//          // point contains screen coordinates
//          // Send to AppleScript or another local automation bridge for real interaction
//      }
//
//  DEBUG:
//
//      DemoAnchorRegistry.shared.dump()       // Print all anchors
//      DemoAnchorRegistry.shared.exportJSON() // Export for external tools
//

// Re-export all public types
@_exported import SwiftUI
