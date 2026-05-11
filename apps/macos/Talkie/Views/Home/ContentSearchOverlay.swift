//
//  ContentSearchOverlay.swift
//  Talkie
//
//  Full-screen overlay wrapper for ContentSearchView.
//  Mirrors CommandPaletteOverlay pattern.
//

import SwiftUI

struct ContentSearchOverlay: View {
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

                // Search view - positioned in upper third
                VStack {
                    Spacer()
                        .frame(height: 80)

                    ContentSearchView(isPresented: $isPresented)

                    Spacer()
                }
            }
        }
    }
}
