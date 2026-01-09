//
//  CommandPaletteView.swift
//  Talkie macOS
//
//  Spotlight-style command palette for quick keyboard navigation
//

import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    @State private var keyMonitor: Any?

    private let registry = CommandRegistry.shared

    private var filteredCommands: [PaletteCommand] {
        registry.search(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)

                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelected()
                    }

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Theme.current.backgroundSecondary)

            Divider()

            // Command list
            if filteredCommands.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.current.foregroundMuted)
                    Text("No commands found")
                        .font(.body)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.xl)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                CommandRow(
                                    command: command,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer with hints
            HStack(spacing: Spacing.lg) {
                HStack(spacing: Spacing.xs) {
                    KeyboardKey("↑↓")
                    Text("navigate")
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                HStack(spacing: Spacing.xs) {
                    KeyboardKey("↵")
                    Text("select")
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                HStack(spacing: Spacing.xs) {
                    KeyboardKey("esc")
                    Text("close")
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Theme.current.backgroundSecondary)
        }
        .frame(width: 500, height: 400)
        .background(Theme.current.background)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                isPresented = false
                return nil // Consume event
            case 125: // Down arrow
                if selectedIndex < filteredCommands.count - 1 {
                    selectedIndex += 1
                }
                return nil
            case 126: // Up arrow
                if selectedIndex > 0 {
                    selectedIndex -= 1
                }
                return nil
            case 36: // Return
                executeSelected()
                return nil
            default:
                return event // Pass through other keys (for typing)
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        let command = filteredCommands[selectedIndex]
        isPresented = false
        // Small delay to let the palette dismiss before executing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            command.action()
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon
            Image(systemName: command.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : Theme.current.foregroundSecondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(isSelected ? Theme.current.accent : Theme.current.backgroundSecondary)
                )

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.current.foreground)

                Text(command.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            // Shortcut hint
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(Theme.current.backgroundSecondary)
                    )
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            isSelected
                ? Theme.current.accent.opacity(0.15)
                : Color.clear
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Keyboard Key Badge

private struct KeyboardKey: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.current.foregroundSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.current.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Theme.current.border, lineWidth: 0.5)
            )
    }
}

// MARK: - Command Palette Overlay

struct CommandPaletteOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        if isPresented {
            ZStack {
                // Backdrop
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }

                // Palette
                CommandPaletteView(isPresented: $isPresented)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            .animation(.easeOut(duration: 0.15), value: isPresented)
        }
    }
}
