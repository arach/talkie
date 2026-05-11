import SwiftUI
import AppKit
import WFKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main App

@main
struct WorkflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var canvasState = CanvasState.sampleState()
    @State private var themeManager = WFThemeManager()
    @State private var showInspector = true
    @State private var showNodePalette = false

    var body: some Scene {
        WindowGroup {
            WFWorkflowEditor(state: canvasState, showInspector: $showInspector)
                .environment(\.wfTheme, themeManager)
                .frame(minWidth: 800, minHeight: 600)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: { showNodePalette.toggle() }) {
                            Label("Add Node", systemImage: "plus.circle.fill")
                        }
                        .popover(isPresented: $showNodePalette) {
                            NodePaletteView(state: canvasState, isPresented: $showNodePalette)
                        }
                    }

                    ToolbarItemGroup(placement: .secondaryAction) {
                        // Style picker
                        Menu {
                            ForEach(WFStyle.allCases) { style in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        themeManager.style = style
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: style.icon)
                                        Text(style.displayName)
                                        if themeManager.style == style {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(themeManager.style.displayName, systemImage: themeManager.style.icon)
                        }

                        // Appearance picker
                        Menu {
                            ForEach(WFAppearance.allCases) { appearance in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        themeManager.appearance = appearance
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: appearance.icon)
                                        Text(appearance.displayName)
                                        if themeManager.appearance == appearance {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label(themeManager.appearance.displayName, systemImage: themeManager.appearance.icon)
                        }
                    }

                    ToolbarItemGroup(placement: .status) {
                        HStack(spacing: 12) {
                            Label("\(canvasState.nodes.count)", systemImage: "square.stack.3d.up")
                                .font(.system(size: 11, design: .monospaced))
                            Label("\(canvasState.connections.count)", systemImage: "arrow.right")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    canvasState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canvasState.canUndo)

                Button("Redo") {
                    canvasState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!canvasState.canRedo)
            }

            CommandGroup(after: .undoRedo) {
                Divider()

                Button("Select All") {
                    canvasState.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Delete Selected") {
                    canvasState.removeSelectedNodes()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!canvasState.hasSelection)
            }

            CommandGroup(after: .toolbar) {
                Divider()

                Button("Zoom In") {
                    canvasState.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    canvasState.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    canvasState.resetView()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
