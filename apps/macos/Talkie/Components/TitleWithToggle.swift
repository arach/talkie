//
//  TitleWithToggle.swift
//  Talkie
//
//  Title with integrated type toggle that flows naturally from the title typography.
//

import SwiftUI

// MARK: - Title with Toggle

/// A page title with an integrated toggle for filtering options.
/// The toggle options flow naturally from the title typography.
///
/// Typography harmony:
/// - Title and toggle options share the same font size (20pt)
/// - Active option: light weight, primary color (matches title)
/// - Inactive options: regular weight, secondary color (clearly clickable)
/// - All options baseline-aligned for visual flow
struct TitleWithToggle<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    var labelForOption: (T) -> String

    // Typography: 20pt for both title and toggles, weight differentiates state
    private let fontSize: CGFloat = 20

    init(
        title: String,
        options: [T],
        selection: Binding<T>,
        labelForOption: @escaping (T) -> String
    ) {
        self.title = title
        self.options = options
        self._selection = selection
        self.labelForOption = labelForOption
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Title
            Text(title)
                .font(.system(size: fontSize, weight: .light))
                .tracking(-0.3)
                .foregroundColor(Theme.current.foreground)

            // Toggle options - same font size, weight shows state
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    if index > 0 {
                        Text("·")
                            .font(.system(size: fontSize, weight: .light))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .padding(.horizontal, 8)
                    }

                    ToggleOption(
                        label: labelForOption(option),
                        isSelected: selection == option,
                        fontSize: fontSize
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = option
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Toggle Option

private struct ToggleOption: View {
    let label: String
    let isSelected: Bool
    let fontSize: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: isSelected ? .light : .regular))
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                .opacity(isHovered && !isSelected ? 0.8 : 1)
                .overlay(alignment: .bottom) {
                    if isHovered && !isSelected {
                        Rectangle()
                            .fill(Theme.current.foregroundSecondary.opacity(0.4))
                            .frame(height: 1)
                            .offset(y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview("Title with Toggle") {
    VStack(alignment: .leading, spacing: 40) {
        // Compare with standard PageHeader
        PageHeader("Memos")

        Divider()

        // Title with toggle - All selected
        TitleWithToggle(
            title: "Recordings",
            options: ["All", "Memos", "Dictations"],
            selection: .constant("All")
        ) { $0 }

        // Title with toggle - Memos selected
        TitleWithToggle(
            title: "Recordings",
            options: ["All", "Memos", "Dictations"],
            selection: .constant("Memos")
        ) { $0 }

        // Title with toggle - Dictations selected
        TitleWithToggle(
            title: "Recordings",
            options: ["All", "Memos", "Dictations"],
            selection: .constant("Dictations")
        ) { $0 }
    }
    .padding(40)
    .frame(width: 600)
    .background(Theme.current.background)
}
