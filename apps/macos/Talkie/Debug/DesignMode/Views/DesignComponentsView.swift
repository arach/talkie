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
        VStack(alignment: .leading, spacing: 0) {
            LibraryVariantsPicker()
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(ScopeCanvas.surface.opacity(0.5))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ScopeEdge.faint)
                        .frame(height: 0.5)
                }
            ScopeShowcase()
        }
    }
}

/// A/B switcher for the Library view's readout body variant. The
/// filter ribbon is locked to Patch Bay and the inspector empty state
/// is locked to Library Readout; what flexes is the *content* inside
/// the readout bay. State is `@AppStorage`-backed in `ScopeLibraryView`,
/// so changes here propagate live to an open Library window.
private struct LibraryVariantsPicker: View {
    @AppStorage("scopeLibrary.readoutBodyVariant")
    private var readoutBodyVariantRaw: String = LibraryReadoutBodyVariant.stats.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("· LIBRARY READOUT")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                Text("Switch live · the bay morphs to host each body")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                Spacer()
            }

            pickerRow(
                label: "Body",
                options: LibraryReadoutBodyVariant.allCases,
                selection: $readoutBodyVariantRaw,
                rawOf: { $0.rawValue },
                nameOf: { $0.displayName }
            )
        }
    }

    @ViewBuilder
    private func pickerRow<Option: Hashable>(
        label: String,
        options: [Option],
        selection: Binding<String>,
        rawOf: @escaping (Option) -> String,
        nameOf: @escaping (Option) -> String
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label.uppercased())
                .font(ScopeType.chrome)
                .tracking(ScopeType.Tracking.wide)
                .foregroundStyle(ScopeInk.muted)
                .frame(width: 140, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    let raw = rawOf(option)
                    let isActive = selection.wrappedValue == raw
                    Button {
                        selection.wrappedValue = raw
                    } label: {
                        Text(nameOf(option))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(isActive ? ScopePanel.bg : ScopeInk.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isActive ? ScopeAmber.solid : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        isActive ? ScopeAmber.solid : ScopeEdge.faint,
                                        lineWidth: 0.5
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview("Design Components") {
    DesignComponentsView()
        .frame(width: 800, height: 600)
}

#endif
