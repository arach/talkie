//
//  CommandPaletteView.swift
//  Talkie macOS
//
//  Raycast-style command palette for quick keyboard navigation
//

import SwiftUI
import AppKit
import TalkieKit

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
    @State private var indicatorPulse = false

    private let registry = CommandRegistry.shared

    private var filteredCommands: [PaletteCommand] {
        registry.search(debouncedSearchText)
    }

    private var commandGroups: [PaletteCommandGroup] {
        PaletteCommandGroup.group(filteredCommands)
    }

    var body: some View {
        VStack(spacing: 0) {
            paletteChromeStrip

            searchField

            paletteDivider

            // Command list
            if filteredCommands.isEmpty {
                emptyState
            } else {
                commandList
            }

            // Footer
            footer
        }
        .frame(width: 600, height: 460)
        .background(paletteBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ScopePalette.ruleStrong, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 14)
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
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
            // Start the chrome-strip dot pulse — gentle "palette is
            // live" signal, runs the whole time the palette is up.
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                indicatorPulse = true
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

    private var paletteChromeStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ScopePalette.amber)
                .frame(width: 6, height: 6)
                .shadow(
                    color: ScopePalette.amber.opacity(indicatorPulse ? 0.85 : 0.35),
                    radius: indicatorPulse ? 6 : 3
                )
                .opacity(indicatorPulse ? 1.0 : 0.65)

            Text("· PALETTE · cmd ⇧ K")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(ScopePalette.amber.opacity(0.85))

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(ScopePalette.amber.opacity(0.13))
        .overlay(alignment: .bottom) {
            paletteDivider
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ScopePalette.inkFaint)

            TextField(
                "",
                text: $searchText,
                prompt: Text("Search commands...")
                    .foregroundStyle(ScopePalette.inkFainter)
            )
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(ScopePalette.ink)
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
                        .foregroundStyle(ScopePalette.inkFainter)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(ScopePalette.bgRaised)
    }

    // MARK: - Command List

    private var commandList: some View {
        let commands = filteredCommands
        let groups = commandGroups
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                        if groupIndex > 0 {
                            // Breath between groups — small palette-bg gap
                            // so each section reads as its own block.
                            Color.clear.frame(height: 4)
                        }
                        CommandSectionHeader(title: group.title)

                        ForEach(group.commands) { command in
                            if let index = commands.firstIndex(where: { $0.id == command.id }) {
                                Button {
                                    selectedIndex = index
                                    executeSelected()
                                } label: {
                                    CommandRow(
                                        command: command,
                                        isSelected: index == selectedIndex,
                                        isHovered: index == hoveredIndex
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(command.id)
                                .onHover { hovering in
                                    if hovering {
                                        hoveredIndex = index
                                    } else if hoveredIndex == index {
                                        hoveredIndex = nil
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
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
                .foregroundStyle(ScopePalette.inkFainter)

            Text("No commands found")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ScopePalette.inkFainter)
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
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(ScopePalette.glyphOnAmber)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                        .fill(ScopePalette.amber)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                        .strokeBorder(ScopePalette.amberSoft, lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(ScopePalette.bgRaised)
        .overlay(alignment: .top) {
            paletteDivider
        }
    }

    private func keyHint(keys: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(ScopePalette.inkFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                        .fill(ScopePalette.ink.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                        .strokeBorder(ScopePalette.rule, lineWidth: 0.5)
                )

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(ScopePalette.inkFainter)
        }
    }

    // MARK: - Background

    private var paletteBackground: some View {
        // Flat PORCELAIN — light surface doesn't need depth gradients
        // to read as a panel. The dark-glass era's multi-layer
        // background fought legibility; the porcelain version lets the
        // ink and amber accents do the work.
        ScopePalette.bg
    }

    private var paletteDivider: some View {
        Rectangle()
            .fill(ScopePalette.rule)
            .frame(height: 0.5)
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

// MARK: - Command Groups

private struct PaletteCommandGroup: Identifiable {
    let title: String
    let commands: [PaletteCommand]

    var id: String { title }

    static func group(_ commands: [PaletteCommand]) -> [PaletteCommandGroup] {
        var orderedTitles: [String] = []
        var commandsByTitle: [String: [PaletteCommand]] = [:]

        for command in commands {
            let title = command.subtitle.isEmpty ? "Other" : command.subtitle
            if commandsByTitle[title] == nil {
                orderedTitles.append(title)
                commandsByTitle[title] = []
            }
            commandsByTitle[title]?.append(command)
        }

        return orderedTitles.map { title in
            PaletteCommandGroup(title: title, commands: commandsByTitle[title] ?? [])
        }
    }
}

private struct CommandSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(ScopePalette.amber.opacity(0.85))

            Rectangle()
                .fill(ScopePalette.rule)
                .frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(ScopePalette.bgSunk)
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
        HStack(spacing: 0) {
            // Selected-row accent bar — 3pt amber edge at the leading
            // side. Bigger than the prior 2pt sliver so the selection
            // reads decisively against the porcelain panel.
            Rectangle()
                .fill(isSelected ? ScopePalette.amber : .clear)
                .frame(width: 3)

            HStack(spacing: 12) {
                Image(systemName: command.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? ScopePalette.amber : ScopePalette.inkFaint)
                    .frame(width: 22, height: 22)

                // Single-line row — the prior secondary "Navigation"
                // line was a duplicate of the section header above it.
                // Title alone keeps the list scannable and crisp.
                Text(command.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isHighlighted ? ScopePalette.ink : ScopePalette.ink.opacity(0.86))

                Spacer()

                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? ScopePalette.amberDeep : ScopePalette.inkFainter)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                                .fill(isSelected ? ScopePalette.amberFaint : ScopePalette.ink.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous)
                                .strokeBorder(
                                    isSelected ? ScopePalette.amberSoft : ScopePalette.rule,
                                    lineWidth: 0.5
                                )
                        )
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 38)
            .background(
                isSelected
                    ? ScopePalette.amber.opacity(0.16)
                    : (isHovered ? ScopePalette.ink.opacity(0.045) : Color.clear)
            )
        }
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
