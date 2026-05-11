//
//  CommandPaletteView.swift
//  Talkie macOS
//
//  Raycast-style command palette for quick keyboard navigation
//

import SwiftUI
import AppKit

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @FocusState private var isSearchFocused: Bool
    @State private var keyMonitor: Any?
    @State private var appearAnimation = false
    @State private var debounceTask: Task<Void, Never>?

    private let registry = CommandRegistry.shared

    private var filteredCommands: [PaletteCommand] {
        registry.search(debouncedSearchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field - hero element
            searchField

            // Subtle separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.06), .white.opacity(0.02), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Command list
            if filteredCommands.isEmpty {
                emptyState
            } else {
                commandList
            }

            // Footer
            footer
        }
        .frame(width: 560, height: 420)
        .background(paletteBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .scaleEffect(appearAnimation ? 1 : 0.95)
        .opacity(appearAnimation ? 1 : 0)
        .onAppear {
            selectedIndex = 0
            setupKeyMonitor()
            // Delay focus slightly so the view is fully in the hierarchy
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isSearchFocused = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
        .onDisappear {
            removeKeyMonitor()
            debounceTask?.cancel()
            appearAnimation = false
        }
        .onChange(of: searchText) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                debouncedSearchText = newValue
                selectedIndex = 0
            }
        }
        // Re-grab focus if it drifts (e.g. clicking inside the palette but outside the text field)
        .onChange(of: isSearchFocused) { _, focused in
            if !focused {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    // Only re-focus if palette is still open
                    if appearAnimation {
                        isSearchFocused = true
                    }
                }
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            // Search icon with subtle glow
            ZStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.7), .white.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            TextField("Search commands...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.white.opacity(0.95))
                .focused($isSearchFocused)
                .onSubmit {
                    executeSelected()
                }

            if !searchText.isEmpty {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Command List

    private var commandList: some View {
        let commands = filteredCommands
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(
                            command: command,
                            isSelected: index == selectedIndex,
                            isHovered: index == hoveredIndex
                        )
                        .id(command.id)
                        .onTapGesture {
                            selectedIndex = index
                            executeSelected()
                        }
                        .onHover { hovering in
                            if hovering {
                                hoveredIndex = index
                            } else if hoveredIndex == index {
                                hoveredIndex = nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) { _, newIndex in
                guard newIndex < commands.count else { return }
                // Only scroll enough to keep the selected item visible — no centering
                proxy.scrollTo(commands[newIndex].id, anchor: nil)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("No commands found")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 20) {
            keyHint(keys: "↑↓", label: "navigate")
            keyHint(keys: "↵", label: "select")
            keyHint(keys: "esc", label: "close")

            Spacer()

            // Branding
            Text("⌘⇧K")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
    }

    private func keyHint(keys: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    // MARK: - Background

    private var paletteBackground: some View {
        ZStack {
            // Base dark layer
            Color(red: 0.08, green: 0.08, blue: 0.10)

            // Subtle gradient
            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Noise texture effect (simulated)
            Color.white.opacity(0.015)
        }
    }

    // MARK: - Key Handling

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                withAnimation(.easeOut(duration: 0.15)) {
                    isPresented = false
                }
                return nil
            case 125: // Down arrow
                if selectedIndex < filteredCommands.count - 1 {
                    withAnimation(.easeOut(duration: 0.08)) {
                        selectedIndex += 1
                    }
                }
                return nil
            case 126: // Up arrow
                if selectedIndex > 0 {
                    withAnimation(.easeOut(duration: 0.08)) {
                        selectedIndex -= 1
                    }
                }
                return nil
            case 36: // Return
                executeSelected()
                return nil
            default:
                return event
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

        withAnimation(.easeOut(duration: 0.12)) {
            isPresented = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            command.action()
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool
    let isHovered: Bool

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(
                        isHighlighted
                            ? LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: command.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHighlighted ? .white : .white.opacity(0.7))
            }

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(isHighlighted ? 1 : 0.9))

                Text(command.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(isHighlighted ? 0.6 : 0.4))
            }

            Spacer()

            // Shortcut badge
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : (isHovered ? Color.white.opacity(0.06) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: isHighlighted)
    }
}

// MARK: - Command Palette Overlay

struct CommandPaletteOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        if isPresented {
            ZStack {
                // Blurred backdrop
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)
                    .background(SettingsManager.shared.modalBackdropStandard)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isPresented = false
                        }
                    }

                // Palette - positioned in upper third
                VStack {
                    Spacer()
                        .frame(height: 80)

                    CommandPaletteView(isPresented: $isPresented)

                    Spacer()
                }
            }
        }
    }
}
