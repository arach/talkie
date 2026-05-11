import SwiftUI

// MARK: - Minimap View

public struct MinimapView: View {
    @Bindable var state: CanvasState
    let canvasSize: CGSize
    let minimapSize: CGSize = CGSize(width: 200, height: 150)

    @State private var isDraggingViewport = false
    @Environment(\.wfTheme) private var theme

    public init(state: CanvasState, canvasSize: CGSize) {
        self.state = state
        self.canvasSize = canvasSize
    }

    // Corner bracket color: white on dark, black on light (subdued)
    private var bracketColor: Color {
        theme.isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }

    // Subtle tint that distinguishes minimap from canvas
    private var tintColor: Color {
        theme.isDark
            ? Color.white.opacity(0.03)  // Slightly lighter than canvas
            : Color.black.opacity(0.03)  // Slightly darker than canvas
    }

    public var body: some View {
        Canvas { context, size in
            // Background with subtle tint
            let backgroundRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(backgroundRect),
                with: .color(theme.canvasBackground)
            )
            // Add subtle tint layer
            context.fill(
                Path(backgroundRect),
                with: .color(tintColor)
            )

            // Draw corner brackets
            drawCornerBrackets(context: context, size: size)

            guard let bounds = calculateContentBounds() else { return }

            let scaleX = (size.width - 20) / bounds.width
            let scaleY = (size.height - 20) / bounds.height
            let minimapScale = min(scaleX, scaleY)

            let offsetX = (size.width - bounds.width * minimapScale) / 2 - bounds.minX * minimapScale
            let offsetY = (size.height - bounds.height * minimapScale) / 2 - bounds.minY * minimapScale

            // Draw connections
            for connection in state.connections {
                if let startPos = state.portPosition(nodeId: connection.sourceNodeId, portId: connection.sourcePortId),
                   let endPos = state.portPosition(nodeId: connection.targetNodeId, portId: connection.targetPortId) {
                    var path = Path()
                    path.move(to: CGPoint(
                        x: startPos.x * minimapScale + offsetX,
                        y: startPos.y * minimapScale + offsetY
                    ))
                    path.addLine(to: CGPoint(
                        x: endPos.x * minimapScale + offsetX,
                        y: endPos.y * minimapScale + offsetY
                    ))
                    context.stroke(
                        path,
                        with: .color(Color.gray.opacity(0.25)),
                        lineWidth: 1
                    )
                }
            }

            // Draw nodes
            for node in state.nodes {
                let rect = CGRect(
                    x: node.position.x * minimapScale + offsetX,
                    y: node.position.y * minimapScale + offsetY,
                    width: node.size.width * minimapScale,
                    height: node.size.height * minimapScale
                )

                let path = Path(roundedRect: rect, cornerRadius: 2)

                context.fill(path, with: .color(node.type.color.opacity(0.85)))

                if state.selectedNodeIds.contains(node.id) {
                    context.stroke(
                        path,
                        with: .color(.white),
                        lineWidth: 1.5
                    )
                }
            }

            // Draw viewport as dashed rectangle
            let viewportRect = calculateViewportRect(
                canvasSize: canvasSize,
                minimapSize: size,
                contentBounds: bounds,
                minimapScale: minimapScale,
                offsetX: offsetX,
                offsetY: offsetY
            )

            drawDashedViewport(context: context, rect: viewportRect)
        }
        .frame(width: minimapSize.width, height: minimapSize.height)
        .gesture(minimapDragGesture)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state.offset)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state.scale)
    }

    // MARK: - Corner Brackets Drawing

    private func drawCornerBrackets(context: GraphicsContext, size: CGSize) {
        let bracketLength: CGFloat = 5
        let bracketThickness: CGFloat = 1
        let inset: CGFloat = 0

        // Top-left bracket
        var topLeft = Path()
        topLeft.move(to: CGPoint(x: inset, y: inset + bracketLength))
        topLeft.addLine(to: CGPoint(x: inset, y: inset))
        topLeft.addLine(to: CGPoint(x: inset + bracketLength, y: inset))

        // Top-right bracket
        var topRight = Path()
        topRight.move(to: CGPoint(x: size.width - inset - bracketLength, y: inset))
        topRight.addLine(to: CGPoint(x: size.width - inset, y: inset))
        topRight.addLine(to: CGPoint(x: size.width - inset, y: inset + bracketLength))

        // Bottom-left bracket
        var bottomLeft = Path()
        bottomLeft.move(to: CGPoint(x: inset, y: size.height - inset - bracketLength))
        bottomLeft.addLine(to: CGPoint(x: inset, y: size.height - inset))
        bottomLeft.addLine(to: CGPoint(x: inset + bracketLength, y: size.height - inset))

        // Bottom-right bracket
        var bottomRight = Path()
        bottomRight.move(to: CGPoint(x: size.width - inset - bracketLength, y: size.height - inset))
        bottomRight.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
        bottomRight.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - bracketLength))

        let strokeStyle = StrokeStyle(lineWidth: bracketThickness, lineCap: .butt, lineJoin: .miter)

        context.stroke(topLeft, with: .color(bracketColor), style: strokeStyle)
        context.stroke(topRight, with: .color(bracketColor), style: strokeStyle)
        context.stroke(bottomLeft, with: .color(bracketColor), style: strokeStyle)
        context.stroke(bottomRight, with: .color(bracketColor), style: strokeStyle)
    }

    // MARK: - Dashed Viewport Drawing

    private func drawDashedViewport(context: GraphicsContext, rect: CGRect) {
        let viewportPath = Path(rect)

        let dashStyle = StrokeStyle(
            lineWidth: 1,
            lineCap: .butt,
            lineJoin: .miter,
            dash: [4, 3]  // 4px dash, 3px gap
        )

        context.stroke(
            viewportPath,
            with: .color(bracketColor.opacity(0.6)),
            style: dashStyle
        )
    }

    // MARK: - Calculations

    private func calculateContentBounds() -> CGRect? {
        guard !state.nodes.isEmpty else { return nil }

        let padding: CGFloat = 50

        let minX = state.nodes.map { $0.position.x }.min() ?? 0
        let maxX = state.nodes.map { $0.position.x + $0.size.width }.max() ?? 0
        let minY = state.nodes.map { $0.position.y }.min() ?? 0
        let maxY = state.nodes.map { $0.position.y + $0.size.height }.max() ?? 0

        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: (maxX - minX) + padding * 2,
            height: (maxY - minY) + padding * 2
        )
    }

    private func calculateViewportRect(
        canvasSize: CGSize,
        minimapSize: CGSize,
        contentBounds: CGRect,
        minimapScale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> CGRect {
        let visibleMinX = -state.offset.width / state.scale
        let visibleMinY = -state.offset.height / state.scale
        let visibleMaxX = visibleMinX + canvasSize.width / state.scale
        let visibleMaxY = visibleMinY + canvasSize.height / state.scale

        let x = visibleMinX * minimapScale + offsetX
        let y = visibleMinY * minimapScale + offsetY
        let width = (visibleMaxX - visibleMinX) * minimapScale
        let height = (visibleMaxY - visibleMinY) * minimapScale

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func minimapPointToCanvasPoint(_ point: CGPoint) -> CGPoint {
        guard let bounds = calculateContentBounds() else { return .zero }

        let scaleX = (minimapSize.width - 20) / bounds.width
        let scaleY = (minimapSize.height - 20) / bounds.height
        let minimapScale = min(scaleX, scaleY)

        let offsetX = (minimapSize.width - bounds.width * minimapScale) / 2 - bounds.minX * minimapScale
        let offsetY = (minimapSize.height - bounds.height * minimapScale) / 2 - bounds.minY * minimapScale

        let canvasX = (point.x - offsetX) / minimapScale
        let canvasY = (point.y - offsetY) / minimapScale

        return CGPoint(x: canvasX, y: canvasY)
    }

    // MARK: - Gestures

    private var minimapDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDraggingViewport = true

                let canvasPoint = minimapPointToCanvasPoint(value.location)

                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    state.offset = CGSize(
                        width: canvasSize.width / 2 - canvasPoint.x * state.scale,
                        height: canvasSize.height / 2 - canvasPoint.y * state.scale
                    )
                }
            }
            .onEnded { _ in
                isDraggingViewport = false
            }
    }
}
