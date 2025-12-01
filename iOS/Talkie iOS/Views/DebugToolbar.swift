//
//  DebugToolbar.swift
//  Talkie iOS
//
//  Debug toolbar overlay - available on all screens in DEBUG builds
//

import SwiftUI

#if DEBUG
/// Global debug toolbar that floats in bottom-right corner
struct DebugToolbarOverlay: View {
    @State private var showToolbar = false
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Expanded panel
            if showToolbar {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text("DEV")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showToolbar = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surfaceSecondary.opacity(0.5))

                    Divider()
                        .background(Color.borderPrimary)

                    // Content
                    VStack(alignment: .leading, spacing: 10) {
                        // Side-by-side TXT + SYNC preview
                        VStack(alignment: .leading, spacing: 6) {
                            Text("STATUS")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.textTertiary)

                            // Combined row showing both indicators side by side
                            CombinedStatusRow()
                        }

                        // Info
                        VStack(alignment: .leading, spacing: 4) {
                            DebugInfoRow(label: "Theme", value: themeManager.appearanceMode.rawValue)
                        }
                    }
                    .padding(10)
                    .padding(.bottom, 6)
                }
                .frame(width: 180)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.surfacePrimary.opacity(0.98))
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
                )
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            }

            // Toggle button (always visible)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showToolbar.toggle()
                }
            }) {
                Image(systemName: "ant.fill")
                    .font(.system(size: 14))
                    .foregroundColor(showToolbar ? .active : .textTertiary)
                    .rotationEffect(.degrees(showToolbar ? 180 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showToolbar)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.surfaceSecondary)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.textTertiary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
#endif
