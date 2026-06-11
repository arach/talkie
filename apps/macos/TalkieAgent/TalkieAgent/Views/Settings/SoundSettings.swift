//
//  SoundSettings.swift
//  TalkieAgent
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
                    .font(OpsType.ui(OpsSize.xs))
            }
            .buttonStyle(.plain)
            .foregroundStyle(OpsInk.muted)
            .disabled(sound == .none)
        }
    }
}

// MARK: - Storage Info Row

struct StorageInfoRow: View {
    @State private var storageSize = AudioStorage.cachedFormattedStorageSize()
    @State private var pastLivesCount = UnifiedDatabase.countDictations()
    @State private var isLoading = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Audio Storage")
                    .font(OpsType.ui(OpsSize.sm))
                    .foregroundStyle(OpsInk.ink)
                Text("\(pastLivesCount) recordings • \(storageSize)")
                    .font(OpsType.ui(OpsSize.xs))
                    .foregroundStyle(OpsInk.muted)
            }

            Spacer()

            Button("Clear All") {
                UnifiedDatabase.deleteAllDictations()
                AudioStorage.invalidateCache()
                Task { await refreshStats() }
            }
            .font(OpsType.ui(OpsSize.xs))
            .buttonStyle(.tiny)
            .foregroundStyle(OpsInk.statusError.opacity(0.8))
        }
        .task {
            await refreshStats()
        }
    }

    private func refreshStats() async {
        storageSize = await AudioStorage.formattedStorageSizeAsync()
        pastLivesCount = UnifiedDatabase.countDictations()
    }
}
