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
import TalkieKit

#if DEBUG

struct DesignComponentsView: View {
    var body: some View {
        ScopeShowcase()
    }
}

#Preview("Design Components") {
    DesignComponentsView()
        .frame(width: 800, height: 600)
}

#endif
