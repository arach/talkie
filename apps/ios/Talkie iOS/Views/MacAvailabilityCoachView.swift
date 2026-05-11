//
//  MacAvailabilityCoachView.swift
//  Talkie iOS
//
//  Macs screen driven primarily by direct Talkie knowledge:
//  Bridge pairing and saved SSH terminal access.
//

import SwiftUI
import UIKit

struct MacAvailabilityCoachView: View {
    @State private var directRegistry = DirectMacRegistry.shared
    @State private var cloudObserver = MacStatusObserver.shared
    private var bridgeManager = BridgeManager.shared
    @State private var showingQRScanner = false
    @State private var showingTerminalDestinations = false
    @State private var pendingRemovalMac: DirectMacRegistry.MacEntry?
    @State private var showingAvailabilityTips = false
    @State private var showingBackgroundSignals = false

    var body: some View {
        ZStack {
            Color.surfacePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    directMacsSection
                    connectionActionsSection
                    availabilityHelpSection

                    if !freshCloudStatuses.isEmpty {
                        cloudSignalsSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Macs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingQRScanner, onDismiss: {
            directRegistry.refresh()
            bridgeManager.justCompletedPairing = false
            Task {
                await cloudObserver.refresh()
            }
        }) {
            QRScannerView()
        }
        .navigationDestination(isPresented: $showingTerminalDestinations) {
            SSHTerminalView()
        }
        .alert(
            pendingRemovalTitle,
            isPresented: Binding(
                get: { pendingRemovalMac != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRemovalMac = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingRemovalMac = nil
            }
            Button("Remove", role: .destructive) {
                guard let pendingRemovalMac else { return }
                removeMacEntry(pendingRemovalMac)
                self.pendingRemovalMac = nil
            }
        } message: {
            Text(pendingRemovalMessage)
        }
        .task {
            directRegistry.refresh()
            await cloudObserver.refresh()
        }
    }

    private var freshCloudStatuses: [MacStatusObserver.MacStatusInfo] {
        cloudObserver.macStatuses.filter { !$0.isStale }
    }

    private var directMacsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !directRegistry.macs.isEmpty {
                Text(directRegistry.macs.count == 1 ? "YOUR MAC" : "YOUR MACS")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, Spacing.md)
            }

            if directRegistry.macs.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 30))
                        .foregroundColor(.textTertiary)

                    Text("No Macs Yet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Text("Scan a QR from any Mac to add direct pairing or terminal access.")
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)

                    Button("Scan QR") {
                        showingQRScanner = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.active)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
                .background(Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                )
            } else {
                ForEach(directRegistry.macs) { mac in
                    SwipeRevealMacCard(
                        isEnabled: mac.bridgePaired || mac.hasTerminalAccess,
                        onRemove: { pendingRemovalMac = mac }
                    ) {
                        DirectMacCard(
                            mac: mac,
                            terminalRow: terminalRow(for: mac)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var connectionActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("ADD")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            AddMacActionCard(title: "Scan QR Code", systemImage: "qrcode.viewfinder") {
                showingQRScanner = true
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    private var availabilityHelpSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("AVAILABILITY")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            DisclosureGroup(isExpanded: $showingAvailabilityTips) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("If you want a Mac to stay reachable longer while you step away, configure that on the Mac itself.")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Popular option")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)

                        Text("Amphetamine is a free Mac app that keeps a Mac awake when you want it to. Install it on the Mac itself if you want that behavior.")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Built-in option")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)

                        Text("You can also adjust Energy or Battery settings directly on the Mac.")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, Spacing.sm)
            } label: {
                HStack(spacing: 8) {
                    LeadingIconContainer {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.active)
                    }

                    Text("Keep your Mac available")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    private var cloudSignalsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("BACKGROUND PROCESSING")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textTertiary)
                .padding(.horizontal, Spacing.md)

            DisclosureGroup(isExpanded: $showingBackgroundSignals) {
                VStack(spacing: 0) {
                    ForEach(Array(freshCloudStatuses.enumerated()), id: \.element.id) { index, status in
                        if index > 0 {
                            Divider().background(Color.borderPrimary)
                        }
                        CloudSignalRow(status: status)
                    }
                }
                .padding(.top, Spacing.sm)
            } label: {
                Text("Memo processing signals")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
        }
    }

    private func terminalRow(for mac: DirectMacRegistry.MacEntry) -> AnyView {
        if mac.hasTerminalAccess {
            return AnyView(
                Button {
                    showingTerminalDestinations = true
                } label: {
                    CapabilityButton(title: "Terminals", icon: "terminal")
                }
                .buttonStyle(.plain)
            )
        }

        return AnyView(
            Button {
                showingQRScanner = true
            } label: {
                CapabilityButton(title: "Set Up Terminal", icon: "terminal")
            }
            .buttonStyle(.plain)
        )
    }

    private var pendingRemovalTitle: String {
        guard let pendingRemovalMac else {
            return "Remove Mac?"
        }

        if pendingRemovalMac.bridgePaired && pendingRemovalMac.hasTerminalAccess {
            return "Remove this Mac?"
        }

        if pendingRemovalMac.bridgePaired {
            return "Disconnect this Mac?"
        }

        return "Delete terminal access?"
    }

    private var pendingRemovalMessage: String {
        guard let pendingRemovalMac else {
            return ""
        }

        if pendingRemovalMac.bridgePaired && pendingRemovalMac.hasTerminalAccess {
            return "This removes the direct Mac pairing and all saved terminal destinations for \(pendingRemovalMac.name) from this iPhone."
        }

        if pendingRemovalMac.bridgePaired {
            return "This removes the direct Mac pairing for \(pendingRemovalMac.name) from this iPhone."
        }

        return "This removes the saved terminal destinations for \(pendingRemovalMac.name) from this iPhone."
    }

    private func removeMacEntry(_ mac: DirectMacRegistry.MacEntry) {
        if mac.bridgePaired {
            bridgeManager.unpair()
        }

        if mac.hasTerminalAccess {
            for savedHost in mac.sshHosts {
                _ = SSHTerminalConnectionManager.shared.delete(savedHost)
            }
        }

        directRegistry.refresh()
    }
}

private struct DirectMacCard: View {
    let mac: DirectMacRegistry.MacEntry
    let terminalRow: AnyView

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                LeadingIconContainer {
                    MacDeviceGlyph(kind: mac.deviceKind)
                }

                Text(mac.name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)

                    Text(mac.bridgeConnected || mac.terminalConnected ? "Connected" : mac.lastSeenText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(mac.bridgeConnected || mac.terminalConnected ? .success : .textSecondary)
                }
            }

            if let technicalConnectionText = mac.technicalConnectionText {
                HStack(alignment: .center, spacing: 6) {
                    Text(technicalConnectionText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Button {
                        UIPasteboard.general.string = technicalConnectionText
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                if mac.bridgePaired {
                    MacCapabilityBadge(
                        icon: "link",
                        title: "Paired",
                        tint: mac.bridgeConnected ? .success : .active
                    )
                }

                terminalRow

                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
        )
    }

}

private struct SwipeRevealMacCard<Content: View>: View {
    let isEnabled: Bool
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    @State private var horizontalOffset: CGFloat = 0

    private let revealWidth: CGFloat = 92

    var body: some View {
        ZStack(alignment: .trailing) {
            if isEnabled {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        horizontalOffset = 0
                        onRemove()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Remove")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.recording)
                    }
                    .buttonStyle(.plain)
                }
                .clipShape(.rect(cornerRadius: CornerRadius.sm))
            }

            content
                .offset(x: horizontalOffset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard isEnabled else { return }
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }

                            let proposedOffset: CGFloat
                            if horizontalOffset <= -revealWidth + 1 {
                                proposedOffset = -revealWidth + value.translation.width
                            } else {
                                proposedOffset = value.translation.width
                            }

                            horizontalOffset = min(0, max(-revealWidth, proposedOffset))
                        }
                        .onEnded { value in
                            guard isEnabled else { return }

                            let isHorizontalSwipe = abs(value.translation.width) > abs(value.translation.height)
                            guard isHorizontalSwipe else {
                                horizontalOffset = 0
                                return
                            }

                            let shouldReveal = value.translation.width < -40 || horizontalOffset < -(revealWidth * 0.45)
                            horizontalOffset = shouldReveal ? -revealWidth : 0
                        }
                )
                .animation(.easeInOut(duration: 0.18), value: horizontalOffset)
        }
        .clipShape(.rect(cornerRadius: CornerRadius.sm))
    }
}

private struct MacCapabilityBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surfacePrimary.opacity(0.45))
        .cornerRadius(CornerRadius.sm)
    }
}

private struct CapabilityButton: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.active)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.surfacePrimary.opacity(0.45))
        .cornerRadius(CornerRadius.sm)
    }
}

private struct AddMacActionCard: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LeadingIconContainer {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.active)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.active)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(Color.surfaceSecondary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .stroke(Color.borderPrimary, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LeadingIconContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.active.opacity(0.12))
                .frame(width: 42, height: 42)

            content
                .frame(width: 24, height: 24)
        }
    }
}

private struct MacDeviceGlyph: View {
    let kind: DirectMacRegistry.MacEntry.DeviceKind

    var body: some View {
        switch kind {
        case .laptop:
            Image(systemName: "laptopcomputer")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.active)
        case .mini:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.active.opacity(0.7), lineWidth: 1)
                    }

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.active.opacity(0.7))
                    .frame(width: 8, height: 2)
                    .offset(y: -3)
            }
            .frame(width: 24, height: 18)
        case .desktop:
            Image(systemName: "desktopcomputer")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.active)
        }
    }
}

private struct CloudSignalRow: View {
    let status: MacStatusObserver.MacStatusInfo

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(status.hostname)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)

                Text(status.statusDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            Text(status.timeSinceLastSeen)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    NavigationStack {
        MacAvailabilityCoachView()
    }
}
