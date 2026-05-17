//
//  AppShellNext.swift
//  Talkie iOS
//
//  Phase 0 shell scaffold. Chrome layer is owned by Claude.
//

import SwiftUI

struct AppShellNext<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
        }
    }
}
