import SwiftUI

// MARK: - Toolbar View

public struct ToolbarView: View {
    @Bindable var state: CanvasState
    @Binding var showNodePalette: Bool
    @Environment(\.wfTheme) private var theme

    public init(state: CanvasState, showNodePalette: Binding<Bool>) {
        self.state = state
        self._showNodePalette = showNodePalette
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: { showNodePalette.toggle() }) {
                Label("Add Node", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .popover(isPresented: $showNodePalette) {
                NodePaletteView(state: state, isPresented: $showNodePalette)
            }

            Spacer()

            // Style picker
            Menu {
                ForEach(WFStyle.allCases) { style in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            theme.style = style
                        }
                    }) {
                        HStack {
                            Image(systemName: style.icon)
                            VStack(alignment: .leading) {
                                Text(style.displayName)
                                Text(style.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if theme.style == style {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: theme.style.icon)
                        .font(.system(size: 13))
                    Text(theme.style.displayName)
                        .font(.system(size: 11))
                }
                .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.borderless)
            .help("Change Style")

            // Appearance picker
            Menu {
                ForEach(WFAppearance.allCases) { appearance in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            theme.appearance = appearance
                        }
                    }) {
                        HStack {
                            Image(systemName: appearance.icon)
                            Text(appearance.displayName)
                            if theme.appearance == appearance {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: theme.appearance.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.textSecondary)
            .help("Change Appearance")

            // Connection style picker
            Menu {
                ForEach(WFConnectionStyle.allCases) { connectionStyle in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            theme.connectionStyleOverride = connectionStyle
                        }
                    }) {
                        HStack {
                            Image(systemName: connectionStyle.icon)
                            Text(connectionStyle.displayName)
                            if theme.connectionStyle == connectionStyle {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme.connectionStyleOverride = nil
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Use Theme Default")
                        if theme.connectionStyleOverride == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                Image(systemName: theme.connectionStyle.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.textSecondary)
            .help("Change Connection Style")

            Divider()
                .frame(height: 20)
                .background(theme.divider.opacity(0.3))

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 11))
                    Text("\(state.nodes.count)")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(theme.textSecondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                    Text("\(state.connections.count)")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.toolbarBackground)
    }
}

// MARK: - Node Palette View

public struct NodePaletteView: View {
    @Bindable var state: CanvasState
    @Binding var isPresented: Bool

    public init(state: CanvasState, isPresented: Binding<Bool>) {
        self.state = state
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Node")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(NodeType.allCases) { type in
                    NodeTypeButton(type: type) {
                        addNode(type: type)
                    }
                }
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func addNode(type: NodeType) {
        let centerPosition = CGPoint(
            x: 300 - state.offset.width / state.scale,
            y: 300 - state.offset.height / state.scale
        )
        state.addNode(type: type, at: centerPosition)
        isPresented = false
    }
}

// MARK: - Node Type Button

struct NodeTypeButton: View {
    let type: NodeType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(type.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(type.rawValue)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
