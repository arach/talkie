//
//  DesignComponentsView.swift
//  Talkie macOS
//
//  Component Library - Showcase of reusable UI components
//  Low priority for V0 - just a placeholder
//
//  IMPORTANT: This entire file is DEBUG-only. Nothing ships to production.
//

import SwiftUI

#if DEBUG

struct DesignComponentsView: View {
    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.current.foregroundMuted)

            VStack(spacing: Spacing.sm) {
                Text("Component Library")
                    .font(Theme.current.fontTitle)
                    .foregroundColor(Theme.current.foreground)

                Text("Coming Soon")
                    .font(Theme.current.fontBody)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            Text("Future home of reusable component showcase")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
    }
}

#Preview("Design Components") {
    DesignComponentsView()
        .frame(width: 800, height: 600)
}

#endif
