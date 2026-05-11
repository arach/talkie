//
//  RadioButtonRow.swift
//  Talkie
//
//  Reusable radio button row for settings selection
//

import SwiftUI

struct RadioButtonRow<T: Equatable>: View {
    let title: String
    let description: String
    let value: T
    let selectedValue: T
    let onSelect: () -> Void
    var preview: AnyView? = nil

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: selectedValue == value ? "largecircle.fill.circle" : "circle")
                    .font(Theme.current.fontBody)
                    .foregroundColor(selectedValue == value ? .accentColor : Theme.current.foregroundSecondary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foreground)
                    Text(description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                if let preview = preview {
                    preview
                        .frame(width: 80, height: 40)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.xs)
    }
}

#Preview {
    VStack(spacing: 0) {
        RadioButtonRow(
            title: "Option A",
            description: "This is the first option",
            value: "a",
            selectedValue: "a",
            onSelect: {}
        )
        RadioButtonRow(
            title: "Option B",
            description: "This is the second option",
            value: "b",
            selectedValue: "a",
            onSelect: {}
        )
    }
    .padding()
    .background(Theme.current.background)
}
