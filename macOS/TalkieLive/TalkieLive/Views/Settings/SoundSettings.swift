//
//  SoundSettings.swift
//  TalkieLive
//
//  Sound picker and storage settings components
//

import SwiftUI

// MARK: - Sound Picker Row

struct SoundPickerRow: View {
    let label: String
    @Binding var sound: TalkieSound

    var body: some View {
        HStack {
            Picker(label, selection: $sound) {
                ForEach(TalkieSound.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.menu)

            Button(action: {
                SoundManager.shared.preview(sound)
            }) {
                Image(systemName: "speaker.wave.2")
                    .font(Design.fontXS)
            }
            .buttonStyle(.plain)
            .foregroundColor(TalkieTheme.textSecondary)
            .disabled(sound == .none)
        }
    }
}

// MARK: - Storage Info Row

struct StorageInfoRow: View {
    @State private var storageSize = AudioStorage.formattedStorageSize()
    @State private var pastLivesCount = LiveDatabase.count()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Storage")
                    .font(Design.fontSM)
                Text("\(pastLivesCount) recordings • \(storageSize)")
                    .font(Design.fontXS)
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            Spacer()

            Button("Clear All") {
                LiveDatabase.deleteAll()
                refreshStats()
            }
            .font(Design.fontXS)
            .buttonStyle(.tiny)
            .foregroundColor(SemanticColor.error.opacity(0.8))
        }
        .onAppear {
            refreshStats()
        }
    }

    private func refreshStats() {
        storageSize = AudioStorage.formattedStorageSize()
        pastLivesCount = LiveDatabase.count()
    }
}
