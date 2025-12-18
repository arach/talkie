//
//  FormControls.swift
//  Talkie
//
//  Reusable form controls with consistent styling
//  Aligned with Talkie design system
//

import SwiftUI

// MARK: - Styled Toggle

struct StyledToggle: View {
    let label: String
    @Binding var isOn: Bool
    var help: String? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(.bodyMedium)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            // Custom toggle switch
            ZStack {
                // Background track
                Capsule()
                    .fill(isOn ? Color.accentColor.opacity(Opacity.medium) : Color.secondary.opacity(Opacity.light))
                    .frame(width: 40, height: 22)

                // Thumb
                Circle()
                    .fill(isOn ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .offset(x: isOn ? 9 : -9)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .onHover { isHovered = $0 }
        }
        .padding(.vertical, Spacing.xs)
        .help(help ?? "")
    }
}

// MARK: - Styled Dropdown

struct StyledDropdown<T: Hashable & CustomStringConvertible>: View {
    let label: String
    let options: [T]
    @Binding var selection: T
    var help: String? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(.bodyMedium)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(action: { selection = option }) {
                        HStack {
                            Text(option.description)
                            if selection == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(selection.description)
                        .font(.bodyMedium)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Image(systemName: "chevron.down")
                        .font(.labelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isHovered ? Color.primary.opacity(Opacity.light) : Color.primary.opacity(Opacity.subtle))
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
        .padding(.vertical, Spacing.xs)
        .help(help ?? "")
    }
}

// MARK: - Styled Checkbox

struct StyledCheckbox: View {
    let label: String
    @Binding var isChecked: Bool
    var help: String? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Checkbox
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isChecked ? Color.accentColor : Color.secondary, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isChecked ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                    )
                    .frame(width: 18, height: 18)

                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.labelSmall)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isChecked.toggle()
                }
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)

            Text(label)
                .font(.bodyMedium)
                .foregroundColor(Theme.current.foreground)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isChecked.toggle()
            }
        }
        .onHover { isHovered = $0 }
        .padding(.vertical, Spacing.xs)
        .help(help ?? "")
    }
}

// MARK: - Tab Selector

struct TabSelector<T: Hashable & CustomStringConvertible>: View {
    let options: [T]
    @Binding var selection: T

    @State private var hoveredOption: T? = nil
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = option
                    }
                }) {
                    Text(option.description)
                        .font(.bodyMedium)
                        .fontWeight(selection == option ? .semibold : .regular)
                        .foregroundColor(selection == option ? .accentColor : Theme.current.foregroundSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            ZStack {
                                if selection == option {
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .fill(Color.accentColor.opacity(Opacity.medium))
                                        .matchedGeometryEffect(id: "selection", in: animation)
                                } else if hoveredOption == option {
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .fill(Color.primary.opacity(Opacity.light))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    hoveredOption = isHovered ? option : nil
                }
            }
        }
        .padding(Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color.primary.opacity(Opacity.subtle))
        )
    }
}

// MARK: - Preview

#Preview("Form Controls") {
    VStack(spacing: Spacing.lg) {
        StyledToggle(label: "Enable feature", isOn: .constant(true))
        StyledToggle(label: "Disabled option", isOn: .constant(false))

        Divider()

        StyledDropdown(
            label: "Quality",
            options: ["Low", "Medium", "High", "Ultra"],
            selection: .constant("High")
        )

        Divider()

        StyledCheckbox(label: "Send notifications", isChecked: .constant(true))
        StyledCheckbox(label: "Auto-update", isChecked: .constant(false))

        Divider()

        TabSelector(
            options: ["All", "Active", "Archived"],
            selection: .constant("Active")
        )
    }
    .padding()
    .frame(width: 400)
    .background(Color.black)
}
