//
//  RecentMemosView.swift
//  TalkieWatch
//
//  Shows recent recordings sent from Watch
//

import SwiftUI

struct RecentMemosView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        List {
            if sessionManager.recentMemos.isEmpty {
                Text("No recent memos")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sessionManager.recentMemos) { memo in
                    MemoRow(memo: memo)
                        .listRowBackground(Color.white.opacity(0.05))
                }
            }
        }
        .navigationTitle("Recent")
    }
}

struct MemoRow: View {
    let memo: WatchMemo

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                // Time
                Text(memo.timestamp, style: .time)
                    .font(.system(size: 13, weight: .medium))

                // Duration & preset
                HStack(spacing: 4) {
                    Text(formatDuration(memo.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let presetName = memo.presetName {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(presetName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                // Preview if available
                if let preview = memo.transcriptionPreview {
                    Text(preview)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Group {
            switch memo.status {
            case .sending:
                Image(systemName: "arrow.up.circle")
                    .foregroundColor(.orange)
            case .sent:
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.blue)
            case .received:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            case .transcribed:
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.red)
            }
        }
        .font(.system(size: 16))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    RecentMemosView()
        .environmentObject(WatchSessionManager.shared)
}
