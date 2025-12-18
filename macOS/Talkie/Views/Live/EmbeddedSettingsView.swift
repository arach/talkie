//
//  EmbeddedSettingsView.swift
//  Talkie
//
//  Stub for TalkieLive's EmbeddedSettingsView
//

import SwiftUI

/// Stub that wraps Talkie's existing SettingsView
struct EmbeddedSettingsView: View {
    @Binding var initialSection: SettingsSection?

    var body: some View {
        // Use Talkie's existing SettingsView
        SettingsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
