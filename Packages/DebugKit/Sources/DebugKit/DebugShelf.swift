//
//  DebugShelf.swift
//  DebugKit
//
//  A collapsible debug shelf for step-based flows (like onboarding)
//

import SwiftUI

// MARK: - Debug Shelf

/// A sliding debug toolbar for navigating through steps
public struct DebugShelf<StepType: RawRepresentable & CaseIterable & Hashable>: View
    where StepType.RawValue == Int {

    public let colors: DebugShelfColors
    @Binding public var currentStep: StepType
    public let onClose: () -> Void
    public let stepName: (StepType) -> String
    public let additionalActions: [DebugShelfAction]

    public init(
        colors: DebugShelfColors,
        currentStep: Binding<StepType>,
        onClose: @escaping () -> Void,
        stepName: @escaping (StepType) -> String,
        additionalActions: [DebugShelfAction] = []
    ) {
        self.colors = colors
        self._currentStep = currentStep
        self.onClose = onClose
        self.stepName = stepName
        self.additionalActions = additionalActions
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9))
                    Text("DEBUG NAVIGATION")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundColor(colors.textTertiary.opacity(0.6))

                Spacer()

                Text("⌘D to toggle • Jump to any step")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(colors.textTertiary.opacity(0.4))

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textTertiary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close (⌘D)")
            }

            // Step buttons + actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Step navigation buttons
                    ForEach(Array(StepType.allCases), id: \.self) { step in
                        DebugShelfStepButton(
                            colors: colors,
                            stepNumber: step.rawValue + 1,
                            stepName: stepName(step),
                            isActive: currentStep == step,
                            action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentStep = step
                                }
                            }
                        )
                    }

                    // Additional actions
                    if !additionalActions.isEmpty {
                        Divider()
                            .frame(height: 30)
                            .padding(.horizontal, 4)

                        ForEach(additionalActions) { action in
                            DebugShelfActionButton(
                                colors: colors,
                                action: action
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            Rectangle()
                .fill(colors.background)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.border.opacity(0.3))
                .frame(height: 1)
        }
    }
}

// MARK: - Colors

public struct DebugShelfColors {
    public let background: Color
    public let surfaceCard: Color
    public let border: Color
    public let accent: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color

    public init(
        background: Color,
        surfaceCard: Color,
        border: Color,
        accent: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color
    ) {
        self.background = background
        self.surfaceCard = surfaceCard
        self.border = border
        self.accent = accent
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
    }
}

// MARK: - Action

public struct DebugShelfAction: Identifiable {
    public let id = UUID()
    public let icon: String
    public let label: String
    public let isProcessing: Bool
    public let menu: [DebugShelfMenuItem]?
    public let action: () -> Void

    public init(
        icon: String,
        label: String,
        isProcessing: Bool = false,
        menu: [DebugShelfMenuItem]? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isProcessing = isProcessing
        self.menu = menu
        self.action = action
    }
}

public struct DebugShelfMenuItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let action: () -> Void

    public init(label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }
}

// MARK: - Step Button

private struct DebugShelfStepButton: View {
    let colors: DebugShelfColors
    let stepNumber: Int
    let stepName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(stepNumber)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? .white : colors.textSecondary)

                Text(stepName)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(isActive ? .white : colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? colors.accent : colors.surfaceCard)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Button

private struct DebugShelfActionButton: View {
    let colors: DebugShelfColors
    let action: DebugShelfAction

    var body: some View {
        if let menu = action.menu {
            Menu {
                ForEach(menu) { item in
                    Button(item.label) {
                        item.action()
                    }
                }
            } label: {
                buttonContent
            }
            .menuStyle(.borderlessButton)
        } else {
            Button(action: action.action) {
                buttonContent
            }
            .buttonStyle(.plain)
        }
    }

    private var buttonContent: some View {
        VStack(spacing: 2) {
            if action.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .bold))
            }

            Text(action.isProcessing ? "..." : action.label)
                .font(.system(size: 8, design: .monospaced))
        }
        .foregroundColor(action.isProcessing ? colors.textTertiary : colors.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(colors.surfaceCard)
        )
    }
}
