//
//  CloudInventoryView.swift
//  Talkie
//
//  Legacy name kept for compatibility. This view now shows external sync
//  diagnostics and avoids direct CloudKit access from the main app.
//

import SwiftUI
import TalkieKit

private let log = Log(.sync)

struct CloudInventoryView: View {
    @State private var isChecking = false
    @State private var serviceAvailable = false
    @State private var statusDetail = "Not checked yet"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            statusCard
            actionRow
            Spacer(minLength: 0)
        }
        .padding(.top, Spacing.md)
        .task {
            await refreshStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("EXTERNAL SYNC")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Text("Talkie delegates cross-device sync to TalkieSync. This panel only checks service reachability.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(serviceAvailable ? SemanticColor.success : SemanticColor.warning)
                    .frame(width: 8, height: 8)

                Text(serviceAvailable ? "TalkieSync Available" : "TalkieSync Unavailable")
                    .font(Theme.current.fontSMMedium)
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(statusDetail)
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
    }

    private var actionRow: some View {
        HStack {
            Button {
                Task {
                    await refreshStatus()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                    Text("Check Again")
                }
                .font(Theme.current.fontXSMedium)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
    }

    private func refreshStatus() async {
        isChecking = true

        let availability = await SyncClient.shared.checkiCloudAvailability()
        serviceAvailable = availability.available
        statusDetail = availability.available
            ? "XPC ping succeeded. TalkieSync is ready to run sync operations."
            : (availability.error ?? "XPC ping failed. TalkieSync is not connected.")

        log.info("External sync diagnostics status: available=\(availability.available), detail=\(statusDetail)")

        isChecking = false
    }
}

#Preview {
    CloudInventoryView()
        .frame(width: 700, height: 420)
}
