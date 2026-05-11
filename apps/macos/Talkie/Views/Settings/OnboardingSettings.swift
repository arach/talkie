//
//  OnboardingSettings.swift
//  Talkie
//
//  Redirects to Apps settings.
//  The "Scripting" menu item now shows the Apps settings view.
//

import SwiftUI

// MARK: - Onboarding Settings View

struct OnboardingSettingsView: View {
    var body: some View {
        AppsSettingsView()
    }
}

// MARK: - Preview

#Preview("Apps Settings") {
    OnboardingSettingsView()
        .frame(width: 600, height: 700)
        .padding()
}
