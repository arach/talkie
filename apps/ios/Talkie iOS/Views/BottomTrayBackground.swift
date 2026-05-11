//
//  BottomTrayBackground.swift
//  Talkie iOS
//
//  Shared bottom tray surface for dock-style controls.
//

import SwiftUI

struct BottomTrayBackground: View {
    var extendsIntoBottomSafeArea = true

    var body: some View {
        Color.clear
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 0.5)
            }
            .modifier(BottomSafeAreaExtension(enabled: extendsIntoBottomSafeArea))
    }
}

private struct BottomSafeAreaExtension: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(edges: .bottom)
        } else {
            content
        }
    }
}
