import SwiftUI

// MARK: - Context Menu Item Model

public struct WFMenuItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let icon: String?
    public let shortcut: String?
    public let isDisabled: Bool
    public let isDivider: Bool
    public let submenu: [WFMenuItem]?
    public let action: (() -> Void)?

    public init(
        label: String,
        icon: String? = nil,
        shortcut: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.shortcut = shortcut
        self.isDisabled = isDisabled
        self.isDivider = false
        self.submenu = nil
        self.action = action
    }

    public init(
        label: String,
        icon: String? = nil,
        submenu: [WFMenuItem]
    ) {
        self.label = label
        self.icon = icon
        self.shortcut = nil
        self.isDisabled = false
        self.isDivider = false
        self.submenu = submenu
        self.action = nil
    }

    public static var divider: WFMenuItem {
        WFMenuItem(divider: true)
    }

    private init(divider: Bool) {
        self.label = ""
        self.icon = nil
        self.shortcut = nil
        self.isDisabled = false
        self.isDivider = true
        self.submenu = nil
        self.action = nil
    }
}

// MARK: - Context Menu State

@Observable
public class WFContextMenuState {
    public var isVisible: Bool = false
    public var position: CGPoint = .zero
    public var items: [WFMenuItem] = []
    public var expandedSubmenuId: UUID? = nil

    public init() {}

    public func show(at position: CGPoint, items: [WFMenuItem]) {
        self.position = position
        self.items = items
        self.expandedSubmenuId = nil
        self.isVisible = true
    }

    public func hide() {
        isVisible = false
        expandedSubmenuId = nil
    }
}

// MARK: - Context Menu View

public struct WFContextMenuOverlay: View {
    @Bindable var menuState: WFContextMenuState
    @Environment(\.wfTheme) private var theme

    public init(menuState: WFContextMenuState) {
        self.menuState = menuState
    }

    public var body: some View {
        if menuState.isVisible {
            ZStack {
                // Backdrop to catch clicks outside
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        menuState.hide()
                    }

                // Menu positioned at click location
                WFContextMenuContent(
                    items: menuState.items,
                    expandedSubmenuId: $menuState.expandedSubmenuId,
                    onDismiss: { menuState.hide() }
                )
                .position(
                    x: menuState.position.x + 90,
                    y: menuState.position.y + 10
                )
            }
        }
    }
}

// MARK: - Context Menu Content

struct WFContextMenuContent: View {
    let items: [WFMenuItem]
    @Binding var expandedSubmenuId: UUID?
    let onDismiss: () -> Void
    @Environment(\.wfTheme) private var theme
    @State private var hoveredItemId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                if item.isDivider {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                } else if let submenu = item.submenu {
                    WFSubmenuItem(
                        item: item,
                        submenu: submenu,
                        isExpanded: expandedSubmenuId == item.id,
                        isHovered: hoveredItemId == item.id,
                        onHover: { hoveredItemId = item.id },
                        onExpand: { expandedSubmenuId = item.id },
                        onDismiss: onDismiss
                    )
                } else {
                    WFMenuItemView(
                        item: item,
                        isHovered: hoveredItemId == item.id,
                        onHover: {
                            hoveredItemId = item.id
                            expandedSubmenuId = nil
                        },
                        onDismiss: onDismiss
                    )
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: WFDesign.radiusMD)
                .fill(theme.panelBackground)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WFDesign.radiusMD)
                .strokeBorder(theme.border.opacity(0.5), lineWidth: 1)
        )
        .fixedSize()
    }
}

// MARK: - Menu Item View

struct WFMenuItemView: View {
    let item: WFMenuItem
    let isHovered: Bool
    let onHover: () -> Void
    let onDismiss: () -> Void
    @Environment(\.wfTheme) private var theme

    var body: some View {
        Button(action: {
            if !item.isDisabled {
                item.action?()
                onDismiss()
            }
        }) {
            HStack(spacing: 8) {
                if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundColor(item.isDisabled ? theme.textTertiary : theme.textSecondary)
                } else {
                    Spacer().frame(width: 16)
                }

                Text(item.label)
                    .font(.system(size: 12))
                    .foregroundColor(item.isDisabled ? theme.textTertiary : theme.textPrimary)

                Spacer()

                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: WFDesign.radiusXS)
                    .fill(isHovered && !item.isDisabled ? theme.accent.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.isDisabled)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}

// MARK: - Submenu Item View

struct WFSubmenuItem: View {
    let item: WFMenuItem
    let submenu: [WFMenuItem]
    let isExpanded: Bool
    let isHovered: Bool
    let onHover: () -> Void
    let onExpand: () -> Void
    let onDismiss: () -> Void
    @Environment(\.wfTheme) private var theme
    @State private var submenuHoveredId: UUID?

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundColor(theme.textSecondary)
            } else {
                Spacer().frame(width: 16)
            }

            Text(item.label)
                .font(.system(size: 12))
                .foregroundColor(theme.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: WFDesign.radiusXS)
                .fill(isHovered || isExpanded ? theme.accent.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                onHover()
                onExpand()
            }
        }
        .overlay(alignment: .topLeading) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(submenu) { subItem in
                        if subItem.isDivider {
                            Rectangle()
                                .fill(theme.divider)
                                .frame(height: 1)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                        } else {
                            WFMenuItemView(
                                item: subItem,
                                isHovered: submenuHoveredId == subItem.id,
                                onHover: { submenuHoveredId = subItem.id },
                                onDismiss: onDismiss
                            )
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: WFDesign.radiusMD)
                        .fill(theme.panelBackground)
                        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WFDesign.radiusMD)
                        .strokeBorder(theme.border.opacity(0.5), lineWidth: 1)
                )
                .fixedSize()
                .offset(x: 155, y: -6)
            }
        }
    }
}

// MARK: - View Modifier for Custom Context Menu

public struct WFContextMenuModifier: ViewModifier {
    @Bindable var menuState: WFContextMenuState
    let menuItems: () -> [WFMenuItem]

    public func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in }
            )
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded { }
            )
            .onAppear {
                NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                    let location = event.locationInWindow
                    if let window = event.window,
                       let contentView = window.contentView {
                        let viewLocation = contentView.convert(location, from: nil)
                        let flippedY = contentView.bounds.height - viewLocation.y
                        menuState.show(
                            at: CGPoint(x: viewLocation.x, y: flippedY),
                            items: menuItems()
                        )
                    }
                    return nil // Consume the event
                }
            }
    }
}

public extension View {
    func wfContextMenu(
        state: WFContextMenuState,
        @WFMenuBuilder items: @escaping () -> [WFMenuItem]
    ) -> some View {
        self.modifier(WFContextMenuModifier(menuState: state, menuItems: items))
    }
}

// MARK: - Menu Builder

@resultBuilder
public struct WFMenuBuilder {
    public static func buildBlock(_ components: WFMenuItem...) -> [WFMenuItem] {
        components
    }

    public static func buildArray(_ components: [[WFMenuItem]]) -> [WFMenuItem] {
        components.flatMap { $0 }
    }
}
