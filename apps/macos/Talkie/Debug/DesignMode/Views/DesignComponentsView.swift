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

/// A/B switcher for the Library view's filter ribbon + inspector empty
/// pane variants. State is `@AppStorage`-backed in `ScopeLibraryView`,
/// so changes here propagate live to an open Library window.
private struct LibraryVariantsPicker: View {
    @AppStorage("scopeLibrary.filterRibbonVariant")
    private var filterRibbonVariantRaw: String = LibraryFilterRibbonVariant.classic.rawValue

    @AppStorage("scopeLibrary.inspectorEmptyVariant")
    private var inspectorEmptyVariantRaw: String = LibraryInspectorEmptyVariant.simple.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("· LIBRARY VARIANTS")
                    .font(ScopeType.eyebrow)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeAmber.solid)
                Text("Switch live · changes propagate to an open Library window")
                    .font(ScopeType.chrome)
                    .tracking(ScopeType.Tracking.wide)
                    .foregroundStyle(ScopeInk.subtle)
                Spacer()
            }

            pickerRow(
                label: "Filter Ribbon",
                options: LibraryFilterRibbonVariant.allCases,
                selection: $filterRibbonVariantRaw,
                rawOf: { $0.rawValue },
                nameOf: { $0.displayName }
            )

            pickerRow(
                label: "Inspector Empty",
                options: LibraryInspectorEmptyVariant.allCases,
                selection: $inspectorEmptyVariantRaw,
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
