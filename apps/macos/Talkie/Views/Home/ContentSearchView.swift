//
//  ContentSearchView.swift
//  Talkie
//
//  Content search overlay for finding recordings and dictations by text.
//  Mirrors CommandPaletteView styling with dark bg, gradient border, shadow.
//

import SwiftUI
import AppKit
import TalkieKit

// MARK: - Search State (class-based for stable NSEvent closure capture)

@MainActor
final class ContentSearchState: ObservableObject {
    @Published var searchText = ""
    @Published var selectedIndex = 0
    @Published var results: [TalkieObject] = []

    private var keyMonitor: Any?
    private var searchTask: Task<Void, Never>?
    private let recordingRepo = TalkieObjectRepository()

    var dismiss: (() -> Void)?

    func search(query: String) {
        searchTask?.cancel()
        selectedIndex = 0
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            do {
                let found = try await self.recordingRepo.searchRecordings(query: trimmed, limit: 30)
                guard !Task.isCancelled else { return }
                self.results = found
            } catch {
                // Search failed silently
            }
        }
    }

    func moveDown() {
        if selectedIndex < results.count - 1 {
            selectedIndex += 1
        }
    }

    func moveUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func openSelected() {
        guard selectedIndex < results.count else { return }
        let recording = results[selectedIndex]

        dismiss?()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            switch recording.type {
            case .memo, .note, .capture:
                NavigationState.shared.navigateToMemo(recording.id)
            case .dictation:
                NavigationState.shared.navigateToDictation(recording.id)
            case .segment:
                break
            case .selection:
                NavigationState.shared.navigateToDictation(recording.id)
            }
        }
    }

    func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Escape
                self.dismiss?()
                return nil
            case 125: // Down arrow
                self.moveDown()
                return nil
            case 126: // Up arrow
                self.moveUp()
                return nil
            case 36: // Return
                self.openSelected()
                return nil
            default:
                return event
            }
        }
    }

    func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func reset() {
        searchText = ""
        selectedIndex = 0
        results = []
        searchTask?.cancel()
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Content Search View

struct ContentSearchView: View {
    @Binding var isPresented: Bool
    @StateObject private var state = ContentSearchState()
    @FocusState private var isSearchFocused: Bool
    @State private var appearAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            // Separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.06), .white.opacity(0.02), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Results
            if state.searchText.isEmpty {
                emptyPrompt
            } else if state.results.isEmpty {
                noResults
            } else {
                resultsList
            }

            // Footer
            footer
        }
        .frame(width: 560, height: 480)
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
            state.reset()
            state.dismiss = {
                withAnimation(.easeOut(duration: 0.15)) {
                    isPresented = false
                }
            }
            state.setupKeyMonitor()
            // Stagger animation and focus to avoid first-open jank
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    appearAnimation = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFocused = true
            }
        }
        .onDisappear {
            state.removeKeyMonitor()
            appearAnimation = false
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.7), .white.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            TextField("Search recordings...", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.white.opacity(0.95))
                .focused($isSearchFocused)
                .onSubmit {
                    state.openSelected()
                }
                .onChange(of: state.searchText) { _, newValue in
                    state.search(query: newValue)
                }

            if !state.searchText.isEmpty {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        state.searchText = ""
                        state.results = []
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

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(state.results.enumerated()), id: \.element.id) { index, recording in
                        ContentSearchRow(
                            recording: recording,
                            isSelected: index == state.selectedIndex
                        )
                        .id(index)
                        .onTapGesture {
                            state.selectedIndex = index
                            state.openSelected()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: state.selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty / No Results

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Search your recordings and dictations")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
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

            Text("No results for '\(state.searchText)'")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 20) {
            keyHint(keys: "\u{2191}\u{2193}", label: "navigate")
            keyHint(keys: "\u{21A9}", label: "open")
            keyHint(keys: "esc", label: "close")

            Spacer()

            Text("Content Search")
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
            Color(red: 0.08, green: 0.08, blue: 0.10)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Color.white.opacity(0.015)
        }
    }
}

// MARK: - Content Search Row

private struct ContentSearchRow: View {
    let recording: TalkieObject
    let isSelected: Bool

    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
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

                Image(systemName: recording.type == .memo ? "doc.text.fill" : "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHighlighted ? .white : .white.opacity(0.7))
            }

            // Title and preview
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(isHighlighted ? 1 : 0.9))
                    .lineLimit(1)

                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(isHighlighted ? 0.6 : 0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Type badge
            Text(recording.type == .memo ? "Memo" : "Dictation")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )

            // Relative date
            Text(relativeDate)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
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
        .onHover { isHovered = $0 }
    }

    private var displayTitle: String {
        if let title = recording.title, !title.isEmpty {
            return title
        }
        return recording.type == .memo ? "Untitled Memo" : "Dictation"
    }

    private var previewText: String? {
        guard let text = recording.text, !text.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "..."
        }
        return trimmed
    }

    private var relativeDate: String {
        let seconds = Int(-recording.createdAt.timeIntervalSinceNow)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        let days = seconds / 86400
        if days < 30 { return "\(days)d" }
        return "\(days / 30)mo"
    }
}
