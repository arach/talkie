//
//  HomeDeviceCards.swift
//  Talkie
//
//  Device and bridge cards for the HomeGrid system.
//

import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import TalkieKit

// MARK: - Devices Card

@MainActor
struct HomeDevicesCard: HomeCard {
    let id = "devices-bridge"
    let cardType: HomeCardType = .devicesBridge
    let span: CardSpan

    init(span: CardSpan = .six) {
        self.span = span
    }

    func render() -> AnyView {
        AnyView(HomeDevicesCardView())
    }
}

@MainActor
private struct HomeDevicesCardView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var isWorking = false
    @State private var showingQRSheet = false

    private let visibleDeviceLimit = 3

    private var statusColor: Color {
        switch bridgeManager.bridgeStatus {
        case .running: return .green
        case .starting: return .orange
        case .stopped: return Theme.current.foregroundMuted
        case .error: return .red
        }
    }

    private var statusText: String {
        switch bridgeManager.bridgeStatus {
        case .running: return "Bridge live"
        case .starting: return "Starting"
        case .stopped: return "Bridge off"
        case .error: return "Needs attention"
        }
    }

    private var pairedSummary: String {
        let count = bridgeManager.pairedDevices.count
        if count == 1 {
            return "1 paired device"
        }
        return "\(count) paired devices"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    devicesList

                    Divider()
                        .opacity(0.55)

                    bridgePanel
                        .frame(width: 182, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    devicesList

                    Divider()
                        .opacity(0.55)

                    bridgePanel
                }
            }
            .cardStyle(cornerRadius: CornerRadius.cardLarge, padding: Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            await bridgeManager.checkStatusNow()
        }
        .sheet(isPresented: $showingQRSheet) {
            HomePairingQRCodeSheet()
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(SettingsManager.shared.uiAllCaps ? "DEVICES" : "Devices")
                .font(Theme.current.fontSMMedium)
                .tracking(SettingsManager.shared.uiAllCaps ? 1 : 0)
                .foregroundStyle(Theme.current.foregroundMuted)

            Text(pairedSummary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.current.foregroundMuted.opacity(0.75))

            if !bridgeManager.pendingPairings.isEmpty {
                Text("\(bridgeManager.pendingPairings.count) pending")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button {
                Task { await showPairingQR() }
            } label: {
                Label("Add Device", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Pair a device")
        }
    }

    private var devicesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if bridgeManager.pairedDevices.isEmpty {
                emptyDevicesView
            } else {
                let visibleDevices = Array(bridgeManager.pairedDevices.prefix(visibleDeviceLimit))
                ForEach(visibleDevices.indices, id: \.self) { index in
                    deviceRow(visibleDevices[index])

                    if index < visibleDevices.count - 1 {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 34)
                    }
                }

                if bridgeManager.pairedDevices.count > visibleDeviceLimit {
                    Divider()
                        .opacity(0.45)
                        .padding(.leading, 34)
                    Text("+\(bridgeManager.pairedDevices.count - visibleDeviceLimit) more")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.current.foregroundMuted)
                        .padding(.top, 8)
                }
            }
        }
        .frame(minWidth: 230, maxWidth: .infinity, alignment: .topLeading)
    }

    private var bridgePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text("Bridge")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.current.foreground)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(bridgeManager.bridgeStatus == .error ? .red : Theme.current.foregroundMuted)
                    .lineLimit(1)

                Text(bridgeDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                bridgeToggleButton

                if bridgeManager.bridgeStatus == .error {
                    Button {
                        Task { await toggleBridge() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isWorking || bridgeManager.bridgeStatus == .starting)
                    .help("Retry Bridge")
                }

                Button {
                    NavigationState.shared.navigateToSettings(.sync)
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Bridge settings")
            }
        }
    }

    private var bridgeToggleButton: some View {
        Button {
            Task { await toggleBridge() }
        } label: {
            if isWorking || bridgeManager.bridgeStatus == .starting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: bridgeManager.bridgeStatus == .running ? "stop.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isWorking || bridgeManager.bridgeStatus == .starting)
        .help(bridgeManager.bridgeStatus == .running ? "Stop Bridge" : "Start Bridge")
    }

    private var bridgeDetail: String {
        switch bridgeManager.bridgeStatus {
        case .running:
            return bridgeManager.qrData?.hostname ?? bridgeManager.tailscaleStatus.hostname ?? "Ready for device connections."
        case .starting:
            return "Starting local device services."
        case .stopped:
            return "Start to allow device pairing and live features."
        case .error:
            return bridgeManager.errorMessage ?? "Bridge needs attention."
        }
    }

    private var emptyDevicesView: some View {
        HStack(spacing: 10) {
            Image(systemName: "ipad.and.iphone")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.current.foregroundSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("No paired devices")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.current.foreground)
                Text(emptyDeviceDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await showPairingQR() }
            } label: {
                Label("Pair", systemImage: "qrcode")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func deviceRow(_ device: BridgeManager.PairedDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: deviceIcon(for: device))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(deviceStatusColor(for: device))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.current.foreground)
                    .lineLimit(1)

                Text(deviceDetailLine(for: device))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.md)

            Text(deviceStatusText(for: device))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(deviceStatusColor(for: device))
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }

    private var emptyDeviceDetail: String {
        switch bridgeManager.bridgeStatus {
        case .running:
            return "Bridge is ready for pairing."
        case .starting:
            return "Bridge is starting."
        case .stopped:
            return "Start Bridge to pair an iPhone."
        case .error:
            return bridgeManager.errorMessage ?? "Bridge needs attention."
        }
    }

    private func showPairingQR() async {
        isWorking = true
        defer { isWorking = false }

        if bridgeManager.bridgeStatus != .running {
            await bridgeManager.enableAndStartBridge()
        } else {
            await bridgeManager.checkStatusNow()
        }

        showingQRSheet = true
    }

    private func toggleBridge() async {
        isWorking = true
        defer { isWorking = false }

        if bridgeManager.bridgeStatus == .running {
            await bridgeManager.stopBridge()
        } else {
            await bridgeManager.enableAndStartBridge()
        }

        await bridgeManager.checkStatusNow()
    }

    private func deviceIcon(for device: BridgeManager.PairedDevice) -> String {
        let lowercasedName = device.name.localizedLowercase
        if lowercasedName.contains("ipad") {
            return "ipad"
        }
        return "iphone"
    }

    private func deviceStatusText(for device: BridgeManager.PairedDevice) -> String {
        if isRecentlyActive(device) {
            return "Active"
        }
        if device.setupState?.terminalImported == true {
            return "Ready"
        }
        return "Paired"
    }

    private func deviceStatusColor(for device: BridgeManager.PairedDevice) -> Color {
        if isRecentlyActive(device) {
            return .green
        }
        return Theme.current.foregroundMuted
    }

    private func deviceDetailLine(for device: BridgeManager.PairedDevice) -> String {
        var parts: [String] = [lastSeenText(for: device)]
        if let terminalHost = device.setupState?.terminalHost, !terminalHost.isEmpty {
            parts.append(terminalHost)
        }
        return parts.joined(separator: " · ")
    }

    private func lastSeenText(for device: BridgeManager.PairedDevice) -> String {
        guard let lastSeen = device.lastSeen,
              let date = parseBridgeDate(lastSeen) else {
            return "Last active unknown"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last active \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func isRecentlyActive(_ device: BridgeManager.PairedDevice) -> Bool {
        guard let lastSeen = device.lastSeen,
              let date = parseBridgeDate(lastSeen) else {
            return false
        }
        return Date().timeIntervalSince(date) < 600
    }

    private func parseBridgeDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

// MARK: - Bridge Debug Card

@MainActor
struct HomeBridgeDebugCard: HomeCard {
    let id = "bridge-debug"
    let cardType: HomeCardType = .bridgeDebug
    let span: CardSpan

    init(span: CardSpan = .six) {
        self.span = span
    }

    func render() -> AnyView {
        AnyView(HomeBridgeDebugCardView())
    }
}

@MainActor
private struct HomeBridgeDebugCardView: View {
    private let settings = SettingsManager.shared

    @State private var bridgeManager = BridgeManager.shared
    @State private var didCopyEndpoint = false

    private var bridgeHost: String {
        bridgeManager.qrData?.hostname
            ?? bridgeManager.tailscaleStatus.hostname
            ?? "localhost"
    }

    private var bridgeEndpoint: String {
        let port = bridgeManager.qrData?.port ?? 8765
        return "\(bridgeHost):\(port)"
    }

    private var bridgeRoute: String {
        if let hostname = bridgeManager.qrData?.hostname, hostname.hasSuffix(".local") {
            return "mDNS"
        }
        if bridgeManager.tailscaleStatus.hostname != nil {
            return "Tailscale"
        }
        return "local"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            VStack(alignment: .leading, spacing: Spacing.sm) {
                statusRows

                Divider()
                    .opacity(0.5)

                actionRow
            }
            .cardStyle(cornerRadius: CornerRadius.cardLarge, padding: Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            await bridgeManager.checkStatusNow()
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text(settings.uiAllCaps ? "BRIDGE DEBUG" : "Bridge Debug")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundStyle(Theme.current.foregroundMuted)

            Text("agent-managed")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.current.foregroundMuted.opacity(0.75))

            Spacer()

            Circle()
                .fill(bridgeManager.bridgeStatus == .running ? .green : .orange)
                .frame(width: 6, height: 6)
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            developerStatusRow(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Bridge",
                value: bridgeManager.bridgeStatus == .running ? "localhost:8765" : bridgeManager.bridgeStatus.rawValue,
                color: bridgeColor
            )

            developerStatusRow(
                icon: "network",
                title: "Relay",
                value: TalkieServer.shared.isRunning ? "localhost:8766" : "Stopped",
                color: TalkieServer.shared.isRunning ? .green : Theme.current.foregroundMuted
            )

            developerStatusRow(
                icon: "link",
                title: "Advertise",
                value: bridgeManager.bridgeStatus == .running ? bridgeEndpoint : bridgeManager.bridgeStatus.rawValue,
                color: bridgeColor
            )

            developerStatusRow(
                icon: "dot.radiowaves.left.and.right",
                title: "Route",
                value: bridgeManager.bridgeStatus == .running ? bridgeRoute : "Waiting",
                color: bridgeManager.bridgeStatus == .running ? .green : Theme.current.foregroundMuted
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                copyBridgeEndpoint()
            } label: {
                Label(didCopyEndpoint ? "Copied" : "Copy", systemImage: didCopyEndpoint ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Copy Bridge endpoint")

            Button {
                openBridgeHealth()
            } label: {
                Label("Health", systemImage: "heart.text.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open Bridge health")

            Spacer()

            Button {
                NavigationState.shared.navigateToSettings(.sync)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Bridge settings")
        }
    }

    private var bridgeColor: Color {
        switch bridgeManager.bridgeStatus {
        case .running: return .green
        case .starting: return .orange
        case .stopped: return Theme.current.foregroundMuted
        case .error: return .red
        }
    }

    private func developerStatusRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.current.foreground)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.current.foregroundMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func copyBridgeEndpoint() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bridgeEndpoint, forType: .string)
        didCopyEndpoint = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopyEndpoint = false
        }
    }

    private func openBridgeHealth() {
        if let url = URL(string: "http://localhost:8765/health") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
private struct HomePairingQRCodeSheet: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var isRefreshing = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Pair iPhone for Mac Bridge")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let qrData = bridgeManager.qrData {
                VStack(spacing: 12) {
                    if qrData.isPairingReady, let image = makeQRCode(from: qrData) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                            .background(Color.white)
                            .clipShape(.rect(cornerRadius: 12))
                    } else {
                        unavailableQRView(message: pairingReadinessMessage(for: qrData))
                    }

                    Text(qrData.isPairingReady ? "Scan in Talkie on iPhone to add Mac Bridge live features." : "Fix the bridge mode first, then generate a new QR.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if isRefreshing {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing pairing QR...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 260, height: 140)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("Bridge needs to be enabled first")
                        .font(.headline)
                    Text(bridgeManager.errorMessage ?? "Start the Mac Bridge, then Talkie can generate a pairing QR.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await enableBridge() }
                    } label: {
                        Label("Enable Bridge", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 280)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task {
            await refresh()
        }
    }

    private func refresh() async {
        isRefreshing = true
        await bridgeManager.checkStatusNow()
        isRefreshing = false
    }

    private func enableBridge() async {
        isRefreshing = true
        await bridgeManager.enableAndStartBridge()
        isRefreshing = false
    }

    @ViewBuilder
    private func unavailableQRView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("This Bridge Isn't Pairable Right Now")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 260, height: 260)
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func makeQRCode(from data: BridgeManager.QRData) -> NSImage? {
        guard let jsonData = try? JSONEncoder().encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let size: CGFloat = 260
        let scale = max(size / outputImage.extent.width, size / outputImage.extent.height)
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    private func pairingReadinessMessage(for qrData: BridgeManager.QRData) -> String {
        if qrData.mode == .localDev {
            return "This server is advertising localhost. Restart the agent-managed Bridge before pairing."
        }

        if qrData.hostname == "localhost" {
            return "This QR is advertising localhost, which only works on this Mac. Restart Bridge before pairing."
        }

        return "The bridge reported that it is not ready for device pairing."
    }
}
