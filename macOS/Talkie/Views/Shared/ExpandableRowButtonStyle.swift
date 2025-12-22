//
//  ExpandableRowButtonStyle.swift
//  Talkie macOS
//
//  Shared button style for expandable row components
//

import SwiftUI

extension ButtonStyle where Self == ExpandableRowButtonStyle {
    static var expandableRow: ExpandableRowButtonStyle {
        ExpandableRowButtonStyle()
    }
}

struct ExpandableRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.03) : Color.clear)
    }
}
