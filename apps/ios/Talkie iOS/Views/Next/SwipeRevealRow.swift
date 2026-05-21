//
//  SwipeRevealRow.swift
//  Talkie iOS
//
//  Custom trailing destructive swipe for Next card rows that are built
//  from ScrollView/VStack rather than List.
//

import SwiftUI

struct SwipeRevealRow<Content: View>: View {
    private static var revealWidth: CGFloat { 82 }
    private static var triggerWidth: CGFloat { 108 }

    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @ObservedObject private var theme = ThemeManager.shared
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteChip
                .padding(.trailing, 10)

            content()
                .background(theme.colors.cardBackground)
                .offset(x: offset)
                .gesture(dragGesture)
                .animation(.spring(response: 0.24, dampingFraction: 0.86), value: offset)
        }
        .clipped()
    }

    private var deleteChip: some View {
        Button(action: delete) {
            Text("DELETE")
                .talkieType(.chipLabel)
                .foregroundStyle(theme.colors.cardBackground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Self.warnOrange))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if !isDragging {
                    dragStartOffset = offset
                    isDragging = true
                }

                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let proposed = dragStartOffset + value.translation.width
                offset = min(0, max(-Self.revealWidth, proposed))
            }
            .onEnded { value in
                isDragging = false
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    settle(closed: true)
                    return
                }

                let projected = dragStartOffset + value.predictedEndTranslation.width
                if projected <= -Self.triggerWidth {
                    delete()
                } else if offset <= -Self.revealWidth * 0.45 {
                    settle(closed: false)
                } else {
                    settle(closed: true)
                }
            }
    }

    private func settle(closed: Bool) {
        offset = closed ? 0 : -Self.revealWidth
        dragStartOffset = offset
    }

    private func delete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            offset = 0
            dragStartOffset = 0
            isDragging = false
        }
        onDelete()
    }

    private static var warnOrange: Color {
        Color(red: 0.85, green: 0.46, blue: 0.34)
    }
}
