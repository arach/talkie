//
//  DebugToolbar.swift
//  DebugKit
//
//  A reusable debug toolbar for macOS SwiftUI apps
//

import SwiftUI
import AppKit

// MARK: - Position

/// Position options for the debug toolbar
public enum DebugToolbarPosition: String, CaseIterable, Sendable {
    case bottomTrailing = "bottomTrailing"
    case bottomLeading = "bottomLeading"
    case topTrailing = "topTrailing"
    case topLeading = "topLeading"

    public var alignment: Alignment {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }

    public var icon: String {
        switch self {
        case .bottomTrailing: return "arrow.down.right"
        case .bottomLeading: return "arrow.down.left"
        case .topTrailing: return "arrow.up.right"
        case .topLeading: return "arrow.up.left"
        }
    }

    public var next: DebugToolbarPosition {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }

    var isTop: Bool {
        self == .topTrailing || self == .topLeading
    }

    var isLeading: Bool {
        self == .bottomLeading || self == .topLeading
    }

    var horizontalAlignment: HorizontalAlignment {
        isLeading ? .leading : .trailing
    }

    var scaleAnchor: UnitPoint {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .bottomLeading: return .bottomLeading
        case .topTrailing: return .topTrailing
        case .topLeading: return .topLeading
        }
    }
}

// MARK: - Data Types

public struct DebugSection: Identifiable {
    public let id = UUID()
    public let title: String
    public let rows: [(key: String, value: String)]

    public init(_ title: String, _ rows: [(String, String)]) {
        self.title = title
        self.rows = rows.map { (key: $0.0, value: $0.1) }
    }
}

public struct DebugAction: Identifiable {
    public let id = UUID()
    public let icon: String
    public let label: String
    public let destructive: Bool
    public let action: () -> Void

    public init(_ label: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.destructive = destructive
        self.action = action
    }
}

// MARK: - Debug Controls

/// A control for editing values directly in the debug toolbar
public enum DebugControl: Identifiable {
    case toggle(label: String, value: Bool, onChange: (Bool) -> Void)
    case stepper(label: String, value: Int, range: ClosedRange<Int>?, step: Int, onChange: (Int) -> Void)
    case slider(label: String, value: Double, range: ClosedRange<Double>, step: Double?, onChange: (Double) -> Void)
    case text(label: String, value: String, placeholder: String, onChange: (String) -> Void)
    case picker(label: String, options: [String], selected: String, onChange: (String) -> Void)

    public var id: String {
        switch self {
        case .toggle(let label, _, _): return "toggle-\(label)"
        case .stepper(let label, _, _, _, _): return "stepper-\(label)"
        case .slider(let label, _, _, _, _): return "slider-\(label)"
        case .text(let label, _, _, _): return "text-\(label)"
        case .picker(let label, _, _, _): return "picker-\(label)"
        }
    }

    // MARK: - Convenience Initializers

    /// Toggle control for boolean values
    public static func toggle(_ label: String, value: Bool, onChange: @escaping (Bool) -> Void) -> DebugControl {
        .toggle(label: label, value: value, onChange: onChange)
    }

    /// Toggle control with binding
    public static func toggle(_ label: String, binding: Binding<Bool>) -> DebugControl {
        .toggle(label: label, value: binding.wrappedValue, onChange: { binding.wrappedValue = $0 })
    }

    /// Stepper control for integer values
    public static func stepper(_ label: String, value: Int, range: ClosedRange<Int>? = nil, step: Int = 1, onChange: @escaping (Int) -> Void) -> DebugControl {
        .stepper(label: label, value: value, range: range, step: step, onChange: onChange)
    }

    /// Stepper control with binding
    public static func stepper(_ label: String, binding: Binding<Int>, range: ClosedRange<Int>? = nil, step: Int = 1) -> DebugControl {
        .stepper(label: label, value: binding.wrappedValue, range: range, step: step, onChange: { binding.wrappedValue = $0 })
    }

    /// Slider control for double values
    public static func slider(_ label: String, value: Double, range: ClosedRange<Double>, step: Double? = nil, onChange: @escaping (Double) -> Void) -> DebugControl {
        .slider(label: label, value: value, range: range, step: step, onChange: onChange)
    }

    /// Slider control with binding
    public static func slider(_ label: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil) -> DebugControl {
        .slider(label: label, value: binding.wrappedValue, range: range, step: step, onChange: { binding.wrappedValue = $0 })
    }

    /// Text field control for string values
    public static func text(_ label: String, value: String, placeholder: String = "", onChange: @escaping (String) -> Void) -> DebugControl {
        .text(label: label, value: value, placeholder: placeholder, onChange: onChange)
    }

    /// Text field control with binding
    public static func text(_ label: String, binding: Binding<String>, placeholder: String = "") -> DebugControl {
        .text(label: label, value: binding.wrappedValue, placeholder: placeholder, onChange: { binding.wrappedValue = $0 })
    }

    /// Picker control for selecting from options
    public static func picker(_ label: String, options: [String], selected: String, onChange: @escaping (String) -> Void) -> DebugControl {
        .picker(label: label, options: options, selected: selected, onChange: onChange)
    }

    /// Picker control with binding
    public static func picker(_ label: String, options: [String], binding: Binding<String>) -> DebugControl {
        .picker(label: label, options: options, selected: binding.wrappedValue, onChange: { binding.wrappedValue = $0 })
    }
}

// MARK: - Keyboard Monitor Manager

/// Prevents duplicate keyboard monitors from being registered
private final class KeyboardMonitorManager {
    static let shared = KeyboardMonitorManager()
    private var isMonitorRegistered = false
    private var toggleCallback: (() -> Void)?

    func registerIfNeeded(toggle: @escaping () -> Void) {
        guard !isMonitorRegistered else {
            // Update callback in case the view was recreated
            toggleCallback = toggle
            return
        }

        toggleCallback = toggle
        isMonitorRegistered = true

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "d" {
                self?.toggleCallback?()
                return nil // Consume the event
            }
            return event
        }
    }
}

// MARK: - Debug Toolbar

public struct DebugToolbar<CustomContent: View>: View {
    @State private var isExpanded = false
    @State private var showCopiedFeedback = false

    // Persisted settings - uses app's UserDefaults
    @AppStorage("debugToolbar.isHidden") private var isHidden = false
    @AppStorage("debugToolbar.position") private var positionRaw = DebugToolbarPosition.bottomTrailing.rawValue

    private var position: DebugToolbarPosition {
        get { DebugToolbarPosition(rawValue: positionRaw) ?? .bottomTrailing }
        nonmutating set { positionRaw = newValue.rawValue }
    }

    let title: String
    let icon: String
    let sections: [DebugSection]
    let controls: [DebugControl]
    let actions: [DebugAction]
    let copyHandler: (() -> String)?
    let keyboardShortcutEnabled: Bool
    let customContent: CustomContent

    /// Initialize a debug toolbar with custom SwiftUI content
    /// - Parameters:
    ///   - title: Header title (default: "DEV")
    ///   - icon: SF Symbol name for the toggle button (default: "ant.fill")
    ///   - sections: Data sections to display
    ///   - controls: Interactive controls
    ///   - actions: Action buttons
    ///   - keyboardShortcut: Enable ⌘D to toggle visibility (default: true)
    ///   - copyHandler: Handler for "Copy Debug Info" action
    ///   - customContent: Custom SwiftUI content to display in the panel
    public init(
        title: String = "DEV",
        icon: String = "ant.fill",
        sections: [DebugSection] = [],
        controls: [DebugControl] = [],
        actions: [DebugAction] = [],
        keyboardShortcut: Bool = true,
        onCopy copyHandler: (() -> String)? = nil,
        @ViewBuilder customContent: () -> CustomContent
    ) {
        self.title = title
        self.icon = icon
        self.sections = sections
        self.controls = controls
        self.actions = actions
        self.keyboardShortcutEnabled = keyboardShortcut
        self.copyHandler = copyHandler
        self.customContent = customContent()
    }
}

extension DebugToolbar where CustomContent == EmptyView {
    /// Initialize a debug toolbar without custom content
    public init(
        title: String = "DEV",
        icon: String = "ant.fill",
        sections: [DebugSection] = [],
        controls: [DebugControl] = [],
        actions: [DebugAction] = [],
        keyboardShortcut: Bool = true,
        onCopy copyHandler: (() -> String)? = nil
    ) {
        self.init(
            title: title,
            icon: icon,
            sections: sections,
            controls: controls,
            actions: actions,
            keyboardShortcut: keyboardShortcut,
            onCopy: copyHandler
        ) { EmptyView() }
    }
}

extension DebugToolbar {
    public var body: some View {
        ZStack(alignment: position.alignment) {
            if !isHidden {
                toolbarContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
        .onAppear {
            if keyboardShortcutEnabled {
                setupKeyboardShortcut()
            }
        }
    }

    private var toolbarContent: some View {
        VStack(alignment: position.horizontalAlignment, spacing: 8) {
            // For top positions, button comes first
            if position.isTop {
                toggleButton
            }

            if isExpanded {
                expandedPanel
                    .transition(.opacity)
            }

            // For bottom positions, button comes last
            if !position.isTop {
                toggleButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .padding(.top, 8)
    }

    private func setupKeyboardShortcut() {
        KeyboardMonitorManager.shared.registerIfNeeded {
            withAnimation(.snappy(duration: 0.15)) {
                isHidden.toggle()
            }
        }
    }

    // MARK: - Toggle Button

    private var toggleButton: some View {
        Button(action: {
            withAnimation(.snappy(duration: 0.15)) {
                isExpanded.toggle()
            }
        }) {
            // Isolate icon to its own render layer for smooth rotation
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isExpanded ? .orange : .accentColor)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .drawingGroup() // Rasterize before animating
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .help("Debug Toolbar (⌘D to toggle)")
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.primary)

                Spacer()

                // Position toggle button
                Button(action: {
                    withAnimation(.snappy(duration: 0.15)) {
                        positionRaw = position.next.rawValue
                    }
                }) {
                    Image(systemName: position.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Move toolbar (⌘D to hide)")

                Button(action: {
                    withAnimation(.snappy(duration: 0.15)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sections) { section in
                    SectionView(section: section)
                }

                // Custom SwiftUI content (if provided)
                customContent

                if !controls.isEmpty {
                    ControlsView(controls: controls)
                }

                if !actions.isEmpty || copyHandler != nil {
                    ActionsView(
                        actions: actions,
                        copyHandler: copyHandler,
                        showCopiedFeedback: $showCopiedFeedback
                    )
                }
            }
            .padding(10)
            .padding(.bottom, 6)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Section View

private struct SectionView: View {
    let section: DebugSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.key)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(row.value)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(index % 2 == 0 ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Actions View

private struct ActionsView: View {
    let actions: [DebugAction]
    let copyHandler: (() -> String)?
    @Binding var showCopiedFeedback: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIONS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(actions) { action in
                    ActionButton(
                        icon: action.icon,
                        label: action.label,
                        destructive: action.destructive,
                        action: action.action
                    )
                }

                if let copyHandler = copyHandler {
                    ActionButton(
                        icon: showCopiedFeedback ? "checkmark" : "doc.on.clipboard",
                        label: showCopiedFeedback ? "Copied!" : "Copy Debug Info",
                        action: {
                            let text = copyHandler()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)

                            withAnimation {
                                showCopiedFeedback = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopiedFeedback = false
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let label: String
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(destructive ? .red : .accentColor)
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(destructive ? .red : .primary)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Controls View

private struct ControlsView: View {
    let controls: [DebugControl]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTROLS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(controls) { control in
                    ControlRow(control: control)
                }
            }
        }
    }
}

// MARK: - Control Row

private struct ControlRow: View {
    let control: DebugControl

    var body: some View {
        switch control {
        case .toggle(let label, let value, let onChange):
            ToggleControlView(label: label, value: value, onChange: onChange)
        case .stepper(let label, let value, let range, let step, let onChange):
            StepperControlView(label: label, value: value, range: range, step: step, onChange: onChange)
        case .slider(let label, let value, let range, let step, let onChange):
            SliderControlView(label: label, value: value, range: range, step: step, onChange: onChange)
        case .text(let label, let value, let placeholder, let onChange):
            TextControlView(label: label, value: value, placeholder: placeholder, onChange: onChange)
        case .picker(let label, let options, let selected, let onChange):
            PickerControlView(label: label, options: options, selected: selected, onChange: onChange)
        }
    }
}

// MARK: - Toggle Control

private struct ToggleControlView: View {
    let label: String
    let value: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { value },
                set: { onChange($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Stepper Control

private struct StepperControlView: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>?
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 4) {
                Button(action: {
                    let newValue = value - step
                    if let range = range {
                        onChange(max(range.lowerBound, newValue))
                    } else {
                        onChange(newValue)
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .disabled(range.map { value <= $0.lowerBound } ?? false)

                Text("\(value)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(minWidth: 30)
                    .foregroundColor(.primary)

                Button(action: {
                    let newValue = value + step
                    if let range = range {
                        onChange(min(range.upperBound, newValue))
                    } else {
                        onChange(newValue)
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .disabled(range.map { value >= $0.upperBound } ?? false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Slider Control

private struct SliderControlView: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%.1f", value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }

            if let step = step {
                Slider(
                    value: Binding(get: { value }, set: { onChange($0) }),
                    in: range,
                    step: step
                )
                .controlSize(.mini)
            } else {
                Slider(
                    value: Binding(get: { value }, set: { onChange($0) }),
                    in: range
                )
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Text Control

private struct TextControlView: View {
    let label: String
    let value: String
    let placeholder: String
    let onChange: (String) -> Void

    @State private var editingValue: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            TextField(placeholder, text: $editingValue)
                .font(.system(size: 10, design: .monospaced))
                .textFieldStyle(.plain)
                .frame(maxWidth: 120)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(3)
                .focused($isFocused)
                .onAppear { editingValue = value }
                .onChange(of: value) { newValue in
                    if !isFocused { editingValue = newValue }
                }
                .onSubmit { onChange(editingValue) }
                .onChange(of: isFocused) { focused in
                    if !focused { onChange(editingValue) }
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Picker Control

private struct PickerControlView: View {
    let label: String
    let options: [String]
    let selected: String
    let onChange: (String) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Picker("", selection: Binding(
                get: { selected },
                set: { onChange($0) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option)
                        .font(.system(size: 10, design: .monospaced))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}
