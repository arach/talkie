//
//  MemosSettings.swift
//  Talkie
//
//  Memos-specific settings (placeholder for future)
//

import SwiftUI

struct MemosSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "doc.text",
                title: "PREFERENCES",
                subtitle: "Configure memo display and behavior."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                // Placeholder content
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Memo preferences coming soon.")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

#Preview {
    MemosSettingsView()
        .frame(width: 600, height: 400)
}
