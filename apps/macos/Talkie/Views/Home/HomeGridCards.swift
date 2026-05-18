//
//  HomeGridCards.swift
//  Talkie
//
//  Card implementations for the HomeGrid system.
//  Each card conforms to HomeCard protocol and renders itself.
//

import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import TalkieKit

// MARK: - Brand Hero Card

/// Full-width editorial hero for onboarding
@MainActor
struct BrandHeroCard: HomeCard {
    let id = "brand-hero"
    let cardType: HomeCardType = .brandHero
    let span: CardSpan = .twelve

    func render() -> AnyView {
        AnyView(BrandHeroCardView())
    }
}

@MainActor
private struct BrandHeroCardView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            // Editorial headline - New York serif
            (Text("Your voice,")
                .font(.system(size: 32, weight: .light, design: .serif))
                .foregroundColor(Theme.current.foreground)
            + Text(" amplified")
                .font(.system(size: 32, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(Theme.current.foreground))

            // Clean subtitle
            Text("Dictate anywhere  ·  Transcribe locally  ·  Work faster")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .tracking(0.3)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.lg)
        .liquidGlassCard(
            cornerRadius: CornerRadius.cardLarge,
            isInteractive: false,
            fallbackFill: Theme.current.surface2,
            fallbackStroke: Theme.current.divider
        )
    }
}

// MARK: - Stat Card

/// Displays a single statistic
@MainActor
struct HomeStatCard: HomeCard {
    let cardType: HomeCardType
    let icon: String
    let value: String
    let label: String
    let detail: String?
    let span: CardSpan = .three

    var id: String { cardType.rawValue }

    @MainActor
    func render() -> AnyView {
        AnyView(HomeStatCardView(icon: icon, value: value, label: label, detail: detail))
    }
}

@MainActor
private struct HomeStatCardView: View {
    let icon: String
    let value: String
    let label: String
    let detail: String?

    @State private var isHovered = false
    private let settings = SettingsManager.shared
    private var isTechnical: Bool { TechnicalStyle.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // KPI: number + label on same line
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.current.foreground)

                Text(label.lowercased())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            // Detail line
            if let detail = detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: CornerRadius.cardLarge)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Action Card

/// Quick action button card
@MainActor
struct HomeActionCard: HomeCard {
    let cardType: HomeCardType
    let icon: String
    let title: String
    let color: Color
    var badge: String? = nil
    let action: () -> Void
    let span: CardSpan = .three

    var id: String { cardType.rawValue }

    @MainActor
    func render() -> AnyView {
        AnyView(HomeActionCardView(icon: icon, title: title, color: color, badge: badge, action: action))
    }
}

@MainActor
private struct HomeActionCardView: View {
    let icon: String
    let title: String
    let color: Color
    var badge: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(color)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(color))
                            .offset(x: 8, y: -6)
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
            }
            .frame(maxWidth: .infinity)
            .cardStyle(cornerRadius: CornerRadius.cardLarge, padding: Spacing.md)
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

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
                .foregroundColor(Theme.current.foregroundMuted)

            Text(pairedSummary)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.current.foregroundMuted.opacity(0.75))

            if !bridgeManager.pendingPairings.isEmpty {
                Text("\(bridgeManager.pendingPairings.count) pending")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
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
                        .foregroundColor(Theme.current.foregroundMuted)
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
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(bridgeManager.bridgeStatus == .error ? .red : Theme.current.foregroundMuted)
                    .lineLimit(1)

                Text(bridgeDetail)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
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
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("No paired devices")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
                Text(emptyDeviceDetail)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
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
                .foregroundColor(deviceStatusColor(for: device))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                Text(deviceDetailLine(for: device))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.md)

            Text(deviceStatusText(for: device))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(deviceStatusColor(for: device))
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
                .foregroundColor(Theme.current.foregroundMuted)

            Text("agent-managed")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.current.foregroundMuted.opacity(0.75))

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
                .foregroundColor(color)
                .frame(width: 18, height: 18)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.current.foreground)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.current.foregroundMuted)
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
                        .foregroundColor(.secondary)
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
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if isRefreshing {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing pairing QR...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(width: 260, height: 140)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.badge.clock")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text("Bridge needs to be enabled first")
                        .font(.headline)
                    Text(bridgeManager.errorMessage ?? "Start the Mac Bridge, then Talkie can generate a pairing QR.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                .foregroundColor(.orange)
            Text("This Bridge Isn't Pairable Right Now")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
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

// MARK: - Widget Cards (Wrappers)

/// Trending apps widget card
@MainActor
struct TrendingWidgetCard: HomeCard {
    let id = "widget-trending"
    let cardType: HomeCardType = .widgetTrending
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(TrendingWidgetCardView())
    }
}

@MainActor
private struct TrendingWidgetCardView: View {
    @State private var topApps: [(name: String, bundleID: String?, count: Int)] = []
    private let recordingRepo = TalkieObjectRepository()

    var body: some View {
        HomeTrendingWidget(apps: topApps)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {
                guard DatabaseManager.shared.isInitialized else { return }
                if let apps = try? await recordingRepo.topDictationApps(limit: 5) {
                    topApps = apps
                }
            }
    }
}

/// Shortcuts widget card
@MainActor
struct ShortcutsWidgetCard: HomeCard {
    let id = "widget-shortcuts"
    let cardType: HomeCardType = .widgetShortcuts
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(
            HomeShortcutsWidget()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }
}

/// Activity heatmap widget card
@MainActor
struct ActivityWidgetCard: HomeCard {
    let id = "widget-activity"
    let cardType: HomeCardType = .widgetActivity
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(ActivityWidgetCardView())
    }
}

@MainActor
private struct ActivityWidgetCardView: View {
    @State private var activityData: [DayActivity] = []
    @State private var streak: Int = 0
    @State private var totalCount: Int = 0

    private let recordingRepo = TalkieObjectRepository()
    private var memosVM: MemosViewModel { MemosViewModel.shared }

    var body: some View {
        HomeActivityWidget(data: activityData, streak: streak, totalCount: totalCount)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {
                guard DatabaseManager.shared.isInitialized else { return }
                let (data, dayMap) = await buildActivityData()
                activityData = data
                totalCount = dayMap.values.reduce(0, +)
                streak = computeStreak(dayMap: dayMap)
            }
    }

    private func buildActivityData() async -> ([DayActivity], [Date: Int]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeksToShow = 13

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var dayMap: [Date: Int] = [:]

        // Add memo counts from heatmapData (already aggregated)
        for (dateString, count) in memosVM.heatmapData {
            if let date = dateFormatter.date(from: dateString) {
                dayMap[calendar.startOfDay(for: date)] = count
            }
        }

        // Add dictation counts from SQL (fast GROUP BY)
        if let dictationActivity = try? await recordingRepo.dictationActivityByDay(days: 365) {
            for (dateString, count) in dictationActivity {
                if let date = dateFormatter.date(from: dateString) {
                    dayMap[calendar.startOfDay(for: date), default: 0] += count
                }
            }
        }

        let maxCount = max(dayMap.values.max() ?? 1, 1)

        // Build 13 weeks of data
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysBack = (weeksToShow - 1) * 7 + (todayWeekday - 1)
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: today) else { return ([], dayMap) }

        var data: [DayActivity] = []
        var currentDate = startDate

        while currentDate <= today {
            let count = dayMap[currentDate] ?? 0
            let level = ActivityLevel.from(count: count, max: maxCount)
            data.append(DayActivity(date: currentDate, count: count, level: level))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return (data, dayMap)
    }

    private func computeStreak(dayMap: [Date: Int]) -> Int {
        let calendar = Calendar.current
        var date = calendar.startOfDay(for: Date())
        var count = 0
        while dayMap[date, default: 0] > 0 {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return count
    }
}

/// Calendar widget card
@MainActor
struct CalendarWidgetCard: HomeCard {
    let id = "widget-calendar"
    let cardType: HomeCardType = .widgetCalendar
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(
            HomeCalendarWidget()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
    }
}

// MARK: - Recent Content Cards

/// Recent memos card
@MainActor
struct RecentMemosCard: HomeCard {
    let id = "recent-memos"
    let cardType: HomeCardType = .recentMemos
    let span: CardSpan = .six

    func render() -> AnyView {
        AnyView(RecentMemosCardView())
    }
}

@MainActor
private struct RecentMemosCardView: View {
    private var memosVM: MemosViewModel { MemosViewModel.shared }
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title outside the card
            Text(settings.uiAllCaps ? "RECENT MEMOS" : "Recent Memos")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            // Card content
            VStack(spacing: 0) {
                if memosVM.memos.isEmpty {
                    EmptyStateView(
                        icon: "mic.badge.plus",
                        gradientColors: [.cyan, .blue],
                        title: "No memos yet",
                        subtitle: "Record your first voice memo",
                        buttonTitle: "Record Now"
                    ) {
                        NavigationState.shared.navigate(to: .recordings)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .init("ShowRecordingView"), object: nil)
                        }
                    }
                } else {
                    ForEach(Array(memosVM.memos.prefix(5))) { memo in
                        MemoActivityRow(memo: memo) {
                            NavigationState.shared.navigateToMemo(memo.id)
                        }
                    }
                }
            }
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Recent dictations card
@MainActor
struct RecentDictationsCard: HomeCard {
    let id = "recent-dictations"
    let cardType: HomeCardType = .recentDictations
    let span: CardSpan = .six

    func render() -> AnyView {
        AnyView(RecentDictationsCardView())
    }
}

@MainActor
private struct RecentDictationsCardView: View {
    private let dictationStore = DictationStore.shared
    private let settings = SettingsManager.shared
    private let liveState = ServiceManager.shared.live

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Title outside the card
            Text(settings.uiAllCaps ? "RECENT DICTATIONS" : "Recent Dictations")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            // Card content
            VStack(spacing: 0) {
                if dictationStore.dictations.isEmpty && dictationStore.cachedCount == 0 && liveState.state == .idle {
                    EmptyStateView(
                        icon: "waveform.badge.plus",
                        gradientColors: [.cyan, .green],
                        title: "No dictations yet",
                        subtitle: "Use your hotkey to start dictating",
                        buttonTitle: "Set Up Dictation"
                    ) {
                        NavigationState.shared.navigateToDictations()
                    }
                } else if dictationStore.dictations.isEmpty {
                    BrailleSpinner()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                } else {
                    ForEach(Array(dictationStore.dictations.prefix(5))) { dictation in
                        DictationActivityRow(dictation: dictation) {
                            NavigationState.shared.navigateToDictation(dictation.id)
                        }
                    }
                }
            }
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}


// MARK: - Status Size

/// Size variants for the system status widget
enum StatusSize: String, CaseIterable {
    case quick  // 1/4 width - ultra minimal, just dots
    case one    // 1/4 width - dots with short labels
    case two    // 2/4 width - half row, grouped info
    case four   // 4/4 width - full row diagnostic

    var span: CardSpan {
        switch self {
        case .quick, .one: return .three
        case .two: return .six
        case .four: return .twelve
        }
    }
}

// MARK: - System Status Cards (All Sizes)

/// Quick status - action row sibling, just 3 dots
@MainActor
struct SystemStatusQuickCard: HomeCard {
    let id = "system-status-quick"
    let cardType: HomeCardType = .systemStatus
    let span: CardSpan = .three

    func render() -> AnyView {
        AnyView(SystemStatusCardView(size: .quick))
    }
}

/// One status - 1/4 width with labels
@MainActor
struct SystemStatusOneCard: HomeCard {
    let id = "system-status-one"
    let cardType: HomeCardType = .systemStatus
    let span: CardSpan = .three

    func render() -> AnyView {
        AnyView(SystemStatusCardView(size: .one))
    }
}

/// Two status - 2/4 width, grouped overview
@MainActor
struct SystemStatusTwoCard: HomeCard {
    let id = "system-status-two"
    let cardType: HomeCardType = .systemStatus
    let span: CardSpan = .six

    func render() -> AnyView {
        AnyView(SystemStatusCardView(size: .two))
    }
}

/// Four status - full width diagnostic
@MainActor
struct SystemStatusFourCard: HomeCard {
    let id = "system-status-four"
    let cardType: HomeCardType = .systemStatus
    let span: CardSpan = .twelve

    func render() -> AnyView {
        AnyView(SystemStatusCardView(size: .four))
    }
}

// MARK: - Legacy Aliases (Backwards Compatibility)

/// System status card - elegant grouped overview (2-up layout)
@MainActor
struct SystemStatusCard: HomeCard {
    let id = "system-status"
    let cardType: HomeCardType = .systemStatus
    let span: CardSpan = .six

    func render() -> AnyView {
        AnyView(SystemStatusCardView(size: .two))
    }
}

/// System status card for 3-up widget row
@MainActor
struct SystemStatusWidgetCard: HomeCard {
    let id = "system-status-widget"
    let cardType: HomeCardType = .systemStatus
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(SystemStatusCardView(size: .one))
    }
}

// MARK: - System Status Card View

@MainActor
private struct SystemStatusCardView: View {
    let size: StatusSize

    private let liveState = ServiceManager.shared.live
    private let engineState = ServiceManager.shared.engine
    private let permissions = PermissionsManager.shared
    private let settings = SettingsManager.shared
    private let liveSettings = AgentSettings.shared

    @State private var isExpanded = false
    @State private var isHovered = false

    private var detailLevel: DetailLevel { settings.detailLevel }

    // Overall status — only count critical permission issues, not services
    private var issueCount: Int {
        var count = 0
        if permissions.microphoneStatus != .granted { count += 1 }
        if permissions.accessibilityStatus != .granted { count += 1 }
        return count
    }

    private var overallColor: Color {
        if issueCount == 0 { return SemanticColor.success }
        if issueCount <= 2 { return SemanticColor.warning }
        return SemanticColor.error
    }

    var body: some View {
        Group {
            switch size {
            case .quick:
                quickBody
            case .one:
                oneBody
            case .two:
                twoBody
            case .four:
                fourBody
            }
        }
        .onAppear {
            permissions.refreshPassivePermissions()
        }
    }

    // MARK: - Quick Size (Ultra Minimal - 3 dots)

    private var quickBody: some View {
        Button {
            NavigationState.shared.navigate(to: .settings)
        } label: {
            HStack(spacing: Spacing.sm) {
                // Three status dots — services use soft warning, permissions use error
                HStack(spacing: 6) {
                    statusDot(ok: liveState.isRunning, soft: true)
                    statusDot(ok: engineState.isRunning, soft: true)
                    statusDot(ok: permissions.microphoneStatus == .granted)
                }

                Text("Status")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .liquidGlassCard(
                cornerRadius: CornerRadius.card,
                isInteractive: true,
                fallbackFill: Theme.current.surface2,
                fallbackStroke: Theme.current.divider
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: - One Size (1/4 width - dots with labels)

    private var oneBody: some View {
        Button {
            NavigationState.shared.navigate(to: .settings)
        } label: {
            VStack(spacing: Spacing.sm) {
                // Status header
                HStack(spacing: 4) {
                    Circle()
                        .fill(overallColor)
                        .frame(width: 6, height: 6)
                    Text(issueCount == 0 ? "Ready" : "\(issueCount) issues")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foreground)
                }

                // Three status items inline — services use soft warning
                HStack(spacing: Spacing.sm) {
                    statusPill("Live", ok: liveState.isRunning, soft: true)
                    statusPill("Engine", ok: engineState.isRunning, soft: true)
                    statusPill("Mic", ok: permissions.microphoneStatus == .granted)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .liquidGlassCard(
                cornerRadius: CornerRadius.card,
                isInteractive: true,
                fallbackFill: Theme.current.surface2,
                fallbackStroke: Theme.current.divider
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: - Two Size (2/4 width - grouped overview)

    private var twoBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header row - always clickable to expand
            headerRow

            // Content adapts to detail level and expansion state
            contentView
        }
        .cardStyle()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Four Size (Full width diagnostic)

    private var fourBody: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(overallColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: overallColor.opacity(0.4), radius: 4)

                Text("System Status")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                if issueCount > 0 {
                    Text("\(issueCount) issue\(issueCount == 1 ? "" : "s") need attention")
                        .font(.system(size: 11))
                        .foregroundColor(SemanticColor.warning)
                }
            }

            // Full diagnostic grid - always expanded
            fullDiagnosticView
        }
        .cardStyle()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Shared Components

    private func statusDot(ok: Bool, soft: Bool = false) -> some View {
        Circle()
            .fill(ok ? SemanticColor.success : (soft ? SemanticColor.warning : SemanticColor.error))
            .frame(width: 8, height: 8)
            .shadow(color: (ok ? SemanticColor.success : (soft ? SemanticColor.warning : SemanticColor.error)).opacity(0.4), radius: 2)
    }

    private func statusPill(_ label: String, ok: Bool, soft: Bool = false) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(ok ? SemanticColor.success : (soft ? SemanticColor.warning : SemanticColor.error))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.current.backgroundTertiary.opacity(0.5))
        .cornerRadius(4)
    }

    // Full diagnostic for size .four
    private var fullDiagnosticView: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            fullDiagnosticServicesColumn
            fullDiagnosticPermissionsColumn
            fullDiagnosticConfigurationColumn
        }
    }

    private var fullDiagnosticServicesColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Services")
            diagnosticRow("TalkieAgent", status: liveState.isRunning ? "Running" : "Stopped", ok: liveState.isRunning, isInfo: !liveState.isRunning, action: liveLaunchAction, actionLabel: "Start")
            diagnosticRow("Transcription", status: engineState.isRunning ? "Ready" : (liveState.isRunning ? "Starting" : "Agent stopped"), ok: engineState.isRunning, isInfo: !engineState.isRunning, action: liveLaunchAction, actionLabel: "Start Agent")
            diagnosticRow("Sync", status: ServiceManager.shared.sync.isRunning ? "Active" : "Idle", ok: true, isInfo: true)

            if let modelId = engineState.loadedModelId {
                diagnosticRow("Model", status: modelShortName(modelId), ok: true, isInfo: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullDiagnosticPermissionsColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Permissions")
            diagnosticRow("Microphone", status: permissions.microphoneStatus.displayName, ok: permissions.microphoneStatus == .granted, action: microphoneSettingsAction)
            diagnosticRow("Accessibility", status: permissions.accessibilityStatus.displayName, ok: permissions.accessibilityStatus == .granted, action: accessibilitySettingsAction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullDiagnosticConfigurationColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Configuration")
            diagnosticRow("Hotkey", status: liveSettings.hotkey.displayString, ok: true, isInfo: true)
            diagnosticRow("Environment", status: TalkieEnvironment.current.badge, ok: true, isInfo: true)

            if engineState.memoryUsage > 0 {
                diagnosticRow("Memory", status: formatBytes(engineState.memoryUsage), ok: true, isInfo: true)
            }
            if engineState.uptime > 0 {
                diagnosticRow("Uptime", status: formatUptime(engineState.uptime), ok: true, isInfo: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Theme.current.foregroundMuted)
            .tracking(0.5)
    }

    private func diagnosticRow(_ label: String, status: String, ok: Bool, isInfo: Bool = false, action: (() -> Void)? = nil, actionLabel: String = "Fix") -> some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isInfo ? Theme.current.foregroundMuted.opacity(0.5) : (ok ? SemanticColor.success : SemanticColor.warning))
                .frame(width: 6, height: 6)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Text(status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isInfo ? Theme.current.foregroundMuted : (ok ? Theme.current.foregroundSecondary : SemanticColor.warning))

            if let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.current.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Header Row (Clickable)

    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // Status indicator
                Circle()
                    .fill(overallColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: overallColor.opacity(0.4), radius: 4)

                // Status text
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.current.foreground)

                Spacer()

                // Quick chips when collapsed and all good
                if !isExpanded && issueCount == 0 {
                    quickChips
                }

                // Expand indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        if issueCount == 0 {
            return isExpanded ? "All systems ready" : "Ready"
        } else {
            return "\(issueCount) issue\(issueCount == 1 ? "" : "s")"
        }
    }

    private var quickChips: some View {
        HStack(spacing: Spacing.xs) {
            if let modelId = engineState.loadedModelId {
                Text(modelChipName(modelId))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.current.foregroundMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.current.backgroundTertiary.opacity(0.6))
                    .cornerRadius(3)
            }

            Text(liveSettings.hotkey.displayString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.current.foregroundMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.current.backgroundTertiary.opacity(0.6))
                .cornerRadius(3)
        }
    }

    // MARK: - Content View (Expandable)

    @ViewBuilder
    private var contentView: some View {
        // Always show issues when there are any
        if issueCount > 0 {
            issuesSection
        }

        // Expanded content
        if isExpanded {
            expandedContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !liveState.isRunning {
                issueRow("Live service not running", action: nil)
            }
            if !engineState.isRunning {
                issueRow("Engine not running", action: nil)
            }
            if permissions.microphoneStatus != .granted {
                issueRow("Microphone permission needed", action: openMicSettings)
            }
            if permissions.accessibilityStatus != .granted {
                issueRow("Accessibility permission needed", action: openAccessibilitySettings)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Divider()
                .padding(.vertical, Spacing.xs)

            // Detail level determines what we show
            switch detailLevel {
            case .minimal, .standard:
                standardExpandedView
            case .detailed:
                detailedExpandedView
            case .max:
                maxExpandedView
            }
        }
    }

    // MARK: - Expanded View Variants

    private var standardExpandedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            standardServiceChips
            standardPermissionChips

            if size == .two {
                standardConfigurationChips
            }
        }
    }

    private var standardServiceChips: some View {
        HStack(spacing: Spacing.md) {
            statusChip("Live", ok: liveState.isRunning)
            statusChip("Engine", ok: engineState.isRunning)
        }
    }

    private var standardPermissionChips: some View {
        HStack(spacing: Spacing.md) {
            statusChip("Mic", ok: permissions.microphoneStatus == .granted, action: microphoneSettingsAction)
            statusChip("Accessibility", ok: permissions.accessibilityStatus == .granted, action: accessibilitySettingsAction)
        }
    }

    private var standardConfigurationChips: some View {
        HStack(spacing: Spacing.md) {
            if let modelId = engineState.loadedModelId {
                infoChip("Model", value: modelShortName(modelId))
            }
            infoChip("Hotkey", value: liveSettings.hotkey.displayString)
        }
    }

    private var detailedExpandedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            detailedStatusRows

            if size == .two {
                detailedExtraInfo
            }
        }
    }

    private var detailedStatusRows: some View {
        Group {
            statusRow("Live", value: liveState.isRunning ? "Running" : "Stopped", ok: liveState.isRunning)
            statusRow("Engine", value: engineState.isRunning ? "Ready" : "Stopped", ok: engineState.isRunning)
            statusRow("Mic", value: permissions.microphoneStatus.displayName, ok: permissions.microphoneStatus == .granted, action: microphoneSettingsAction)
            statusRow("Accessibility", value: permissions.accessibilityStatus.displayName, ok: permissions.accessibilityStatus == .granted, action: accessibilitySettingsAction)
        }
    }

    private var detailedExtraInfo: some View {
        Group {
            Divider()
                .padding(.vertical, 4)

            if let modelId = engineState.loadedModelId {
                infoRow("Model", value: modelShortName(modelId))
            }
            infoRow("Hotkey", value: liveSettings.hotkey.displayString)
        }
    }

    private var maxExpandedView: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            maxServicesColumn
            maxMetaColumn
        }
        .padding(Spacing.sm)
        .background {
            Color.black.opacity(0.4)
        }
        .cornerRadius(6)
    }

    private var maxServicesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            devSectionHeader("LIVE")
            devLine("status", value: liveState.isRunning ? "running" : "stopped", ok: liveState.isRunning)
            if let pid = liveState.processId {
                devLine("pid", value: "\(pid)", ok: true, isInfo: true)
            }
            devLine("xpc", value: liveState.isXPCConnected ? "connected" : "disconnected", ok: liveState.isXPCConnected)
            devLine("state", value: liveState.state.rawValue, ok: true, isInfo: true)

            devSectionHeader("ENGINE")
            devLine("status", value: engineState.isRunning ? "running" : "stopped", ok: engineState.isRunning)
            if let pid = engineState.processId {
                devLine("pid", value: "\(pid)", ok: true, isInfo: true)
            }
            devLine("model", value: engineState.loadedModelId ?? "none", ok: engineState.loadedModelId != nil, isInfo: engineState.loadedModelId != nil)
            if engineState.uptime > 0 {
                devLine("uptime", value: formatUptime(engineState.uptime), ok: true, isInfo: true)
            }
            if engineState.memoryUsage > 0 {
                devLine("memory", value: formatBytes(engineState.memoryUsage), ok: true, isInfo: true)
            }

            devSectionHeader("SYNC")
            devLine("status", value: ServiceManager.shared.sync.isRunning ? "running" : "stopped", ok: ServiceManager.shared.sync.isRunning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var maxMetaColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            devSectionHeader("PERMISSIONS")
            devLine("mic", value: permissions.microphoneStatus.codeValue, ok: permissions.microphoneStatus == .granted, action: microphoneSettingsAction)
            devLine("a11y", value: permissions.accessibilityStatus.codeValue, ok: permissions.accessibilityStatus == .granted, action: accessibilitySettingsAction)

            devSectionHeader("CONFIG")
            devLine("hotkey", value: liveSettings.hotkey.displayString, ok: true, isInfo: true)
            devLine("env", value: TalkieEnvironment.current.badge, ok: true, isInfo: true)
            devLine("bundle", value: Bundle.main.bundleIdentifier?.components(separatedBy: ".").last ?? "—", ok: true, isInfo: true)

            devSectionHeader("DATA")
            devLine("memos", value: "\(MemosViewModel.shared.memos.count)", ok: true, isInfo: true)
            devLine("dictations", value: "\(DictationStore.shared.cachedCount)", ok: true, isInfo: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var liveLaunchAction: (() -> Void)? {
        liveState.isRunning ? nil : { ServiceManager.shared.launchLive(resolvingConflicts: true) }
    }

    private var microphoneSettingsAction: (() -> Void)? {
        permissions.microphoneStatus == .granted ? nil : { openMicSettings() }
    }

    private var accessibilitySettingsAction: (() -> Void)? {
        permissions.accessibilityStatus == .granted ? nil : { openAccessibilitySettings() }
    }

    private func devSectionHeader(_ title: String) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .frame(width: 65, alignment: .trailing)
            Spacer()
        }
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .foregroundColor(Color.white.opacity(0.5))
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_000_000
        if mb > 1000 {
            return String(format: "%.1fGB", mb / 1000)
        }
        return String(format: "%.0fMB", mb)
    }

    // MARK: - Row Components

    private func issueRow(_ text: String, action: (() -> Void)?) -> some View {
        HStack(spacing: Spacing.xs) {
            Text("•")
                .foregroundColor(SemanticColor.warning)

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundSecondary)

            if let action = action {
                Button(action: action) {
                    Text("Fix →")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.current.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusChip(_ label: String, ok: Bool, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? SemanticColor.success : SemanticColor.error)
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(ok ? Theme.current.foregroundSecondary : SemanticColor.error)

            if let action = action {
                Button(action: action) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.current.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.current.backgroundTertiary.opacity(0.5))
        .cornerRadius(4)
    }

    private func infoChip(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.current.foregroundMuted)

            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.current.backgroundTertiary.opacity(0.5))
        .cornerRadius(4)
    }

    private func statusRow(_ label: String, value: String, ok: Bool, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(ok ? SemanticColor.success : SemanticColor.error)
                .frame(width: 5, height: 5)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foreground)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.system(size: 10))
                .foregroundColor(ok ? Theme.current.foregroundMuted : SemanticColor.error)

            Spacer()

            if let action = action {
                Button(action: action) {
                    Text("Fix")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.current.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundMuted)
                .frame(width: 75, alignment: .leading)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()
        }
        .padding(.leading, 10)
    }

    private func devLine(_ key: String, value: String, ok: Bool, isInfo: Bool = false, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 0) {
            // Key - right aligned
            Text(key)
                .frame(width: 65, alignment: .trailing)
                .foregroundColor(Color.white.opacity(0.35))

            // Separator
            Text("  ")

            // Status dot
            Circle()
                .fill(isInfo ? Color.white.opacity(0.3) : (ok ? SemanticColor.success : SemanticColor.error))
                .frame(width: 5, height: 5)

            Text(" ")

            // Value - left aligned
            Text(value)
                .foregroundColor(isInfo ? Color.white.opacity(0.7) : (ok ? SemanticColor.success : SemanticColor.error))

            Spacer()

            // Action button if needed
            if let action = action {
                Button(action: action) {
                    Text("fix")
                        .foregroundColor(Theme.current.accent.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func modelChipName(_ modelId: String) -> String {
        if modelId.contains("parakeet") { return "PKT" }
        if modelId.contains("whisper") { return "WSP" }
        return "AI"
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("parakeet") {
            return modelId.contains("v3") ? "Parakeet v3" : "Parakeet"
        } else if modelId.contains("whisper") {
            if modelId.contains("large") { return "Whisper Large" }
            if modelId.contains("turbo") { return "Whisper Turbo" }
            return "Whisper"
        }
        return modelId
    }

    private func openMicSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func openAccessibilitySettings() {
        PermissionsManager.shared.openAccessibilitySettings()
    }
}

// MARK: - Permission Status Extension

private extension PermissionStatus {
    var codeValue: String {
        switch self {
        case .granted: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "pending"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Setup Guide Card (2-up version)

/// Onboarding setup guidance - pairs with SystemStatusCard
@MainActor
struct SetupGuideCard: HomeCard {
    let id = "setup-guide"
    let cardType: HomeCardType = .setupHotkey
    let span: CardSpan = .six

    func render() -> AnyView {
        AnyView(SetupGuideCardView(compact: false))
    }
}

// MARK: - Setup Guide Widget Card (3-up version)

/// Setup guidance for 3-up widget row
@MainActor
struct SetupGuideWidgetCard: HomeCard {
    let id = "setup-guide-widget"
    let cardType: HomeCardType = .setupHotkey
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(SetupGuideCardView(compact: true))
    }
}

@MainActor
private struct SetupGuideCardView: View {
    let compact: Bool

    private let settings = SettingsManager.shared
    private let liveSettings = AgentSettings.shared
    private let engineState = ServiceManager.shared.engine
    private let dictationStore = DictationStore.shared

    // Computed completion states
    private var isHotkeyConfigured: Bool {
        liveSettings.hotkey != .default
    }

    private var isModelLoaded: Bool {
        engineState.loadedModelId != nil
    }

    private var hasDictated: Bool {
        dictationStore.cachedCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            Text(settings.uiAllCaps ? "SETUP" : "Setup")
                .font(Theme.current.fontSMMedium)
                .tracking(settings.uiAllCaps ? 1 : 0)
                .foregroundColor(Theme.current.foregroundMuted)

            // Setup items
            VStack(alignment: .leading, spacing: compact ? Spacing.xs : Spacing.sm) {
                SetupItem(
                    number: "1",
                    title: "Set your hotkey",
                    subtitle: compact ? nil : "Press to dictate anywhere",
                    isDone: isHotkeyConfigured,
                    action: { NavigationState.shared.navigate(to: .settings) }
                )

                SetupItem(
                    number: "2",
                    title: "Choose a model",
                    subtitle: compact ? nil : "Whisper for transcription",
                    isDone: isModelLoaded,
                    action: { NavigationState.shared.navigate(to: .models) }
                )

                SetupItem(
                    number: "3",
                    title: "Try dictating",
                    subtitle: compact ? nil : "Hold hotkey, speak, release",
                    isDone: hasDictated,
                    action: { NavigationState.shared.navigateToDictations() }
                )
            }
        }
        .cardStyle()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Setup Item

@MainActor
private struct SetupItem: View {
    let number: String
    let title: String
    let subtitle: String?
    let isDone: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                // Checkbox circle - empty or checked
                ZStack {
                    Circle()
                        .strokeBorder(
                            isDone ? SemanticColor.success : Theme.current.foregroundMuted.opacity(0.4),
                            lineWidth: 1.5
                        )

                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(SemanticColor.success)
                    }
                }
                .frame(width: 18, height: 18)

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isDone ? .regular : .medium))
                        .foregroundColor(isDone ? Theme.current.foregroundMuted : Theme.current.foreground)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }

                Spacer()

                // Arrow for incomplete items
                if !isDone {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .opacity(isHovered ? 1 : 0.5)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered && !isDone ? Theme.current.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Feature Cards

/// Captures feature card — shows tray capture count and last capture
@MainActor
struct CapturesFeatureCard: HomeCard {
    let id = "feature-captures"
    let cardType: HomeCardType = .featureCaptures
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(CapturesFeatureCardView())
    }
}

@MainActor
private struct CapturesFeatureCardView: View {
    private let screenshotTray = ScreenshotTray.shared
    private let clipTray = ClipTray.shared
    private let selectionTray = SelectionTray.shared
    private let settings = SettingsManager.shared

    @State private var isHovered = false
    @State private var showingURLImport = false
    @State private var totalAttached: Int = 0
    @State private var topContexts: [(name: String, count: Int)] = []

    private var accent: Color {
        settings.accentColor.color ?? Color.accentColor
    }

    private var unattachedCount: Int {
        screenshotTray.count + clipTray.count + selectionTray.count
    }

    private var totalCount: Int {
        totalAttached + unattachedCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                NavigationState.shared.navigate(to: .screenshots)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accent)

                        Text(settings.uiAllCaps ? "CAPTURES" : "Captures")
                            .font(Theme.current.fontSMMedium)
                            .tracking(settings.uiAllCaps ? 1 : 0)
                            .foregroundColor(Theme.current.foregroundMuted)

                        Spacer()

                        Text("\(totalCount)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.current.foreground)
                    }

                    if totalCount == 0 {
                        Text("Capture screenshots, clips, selections, and bookmarked URLs")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            if unattachedCount > 0 {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(accent)
                                        .frame(width: 5, height: 5)
                                    Text("\(unattachedCount) unattached")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Theme.current.foreground)
                                }
                            }

                            if topContexts.isEmpty {
                                if unattachedCount == 0 {
                                    Text("\(totalAttached) attached to memos")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.current.foregroundMuted)
                                }
                            } else {
                                ForEach(topContexts.prefix(3), id: \.name) { ctx in
                                    HStack(spacing: 6) {
                                        Text(ctx.name)
                                            .font(.system(size: 10))
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(ctx.count)")
                                            .font(.system(size: 10, design: .rounded))
                                            .foregroundColor(Theme.current.foregroundMuted)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()

            Divider()
                .overlay(Theme.current.border.opacity(0.2))

            Button {
                showingURLImport = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accent)
                    Text("Save URL Bookmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.current.foreground)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardStyle(cornerRadius: CornerRadius.cardLarge)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
        .task {
            await loadStats()
        }
        .sheet(isPresented: $showingURLImport) {
            URLBookmarkImportModal()
        }
    }

    private func loadStats() async {
        // Count attached screenshots by scanning the storage directory.
        let dir = ScreenshotStorage.screenshotsDirectory
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
        totalAttached = pngs.count

        // Top contexts from the tray (where we have app metadata).
        var tally: [String: Int] = [:]
        for item in screenshotTray.items {
            let name = item.appName ?? item.windowTitle ?? "Unknown"
            tally[name, default: 0] += 1
        }
        topContexts = tally
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

/// Workflow runs feature card — shows recent runs with status
@MainActor
struct WorkflowRunsFeatureCard: HomeCard {
    let id = "feature-workflow-runs"
    let cardType: HomeCardType = .featureWorkflowRuns
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(WorkflowRunsFeatureCardView())
    }
}

@MainActor
private struct WorkflowRunsFeatureCardView: View {
    @State private var recentRuns: [WorkflowRunModel] = []
    private let settings = SettingsManager.shared

    @State private var isHovered = false

    private var accent: Color {
        settings.accentColor.color ?? Color.accentColor
    }

    var body: some View {
        Button {
            NavigationState.shared.navigateToWorkflows()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(accent)

                    Text(settings.uiAllCaps ? "WORKFLOW RUNS" : "Workflow Runs")
                        .font(Theme.current.fontSMMedium)
                        .tracking(settings.uiAllCaps ? 1 : 0)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Spacer()
                }

                if recentRuns.isEmpty {
                    VStack(spacing: 4) {
                        Text("No runs yet")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Text("Run a workflow to see results here")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                } else {
                    VStack(spacing: 4) {
                        ForEach(recentRuns.prefix(3)) { run in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(run.status))
                                    .frame(width: 6, height: 6)

                                Image(systemName: run.workflowIcon ?? "wand.and.stars")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(accent)

                                Text(run.workflowName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.current.foreground)
                                    .lineLimit(1)

                                Spacer()

                                Text(run.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
        .task {
            guard DatabaseManager.shared.isInitialized else { return }
            if let runs = try? await LocalRepository().allWorkflowRuns() {
                recentRuns = Array(runs.prefix(3))
            }
        }
    }

    private func statusColor(_ status: WorkflowRunModel.Status) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        case .pending: return .yellow
        case .cancelled: return .gray
        }
    }
}

/// Agent & Console feature card — shows agent status and console access
@MainActor
struct AgentConsoleFeatureCard: HomeCard {
    let id = "feature-agent-console"
    let cardType: HomeCardType = .featureAgentConsole
    let span: CardSpan = .four

    func render() -> AnyView {
        AnyView(AgentConsoleFeatureCardView())
    }
}

@MainActor
private struct AgentConsoleFeatureCardView: View {
    private let liveState = ServiceManager.shared.live
    private let settings = SettingsManager.shared

    @State private var isHovered = false

    private var accent: Color {
        settings.accentColor.color ?? Color.accentColor
    }

    var body: some View {
        Button {
            NavigationState.shared.navigateToConsole()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(accent)

                    Text(settings.uiAllCaps ? "AGENT & CONSOLE" : "Agent & Console")
                        .font(Theme.current.fontSMMedium)
                        .tracking(settings.uiAllCaps ? 1 : 0)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Spacer()

                    Circle()
                        .fill(liveState.isRunning ? .green : .red)
                        .frame(width: 7, height: 7)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Agent")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.current.foreground)

                        Text(liveState.isRunning ? "Running" : "Stopped")
                            .font(.system(size: 11))
                            .foregroundColor(liveState.isRunning ? Theme.current.foregroundSecondary : .red)
                    }

                    if liveState.isXPCConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                            Text("XPC Connected")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }

                    if liveState.isRunning, liveState.uptime > 0 {
                        Text("Up \(formatUptime(liveState.uptime))")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    if TalkieServer.shared.isRunning {
                        HStack(spacing: 6) {
                            Image(systemName: "network")
                                .font(.system(size: 9))
                                .foregroundColor(accent)
                            Text("Server active")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardStyle(cornerRadius: CornerRadius.cardLarge)
            .scaleEffect(isHovered ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Grid Cards") {
    VStack(spacing: Spacing.lg) {
        BrandHeroCardView()

        HStack(spacing: Spacing.md) {
            HomeStatCardView(icon: "calendar", value: "12", label: "Today", detail: "5 memos, 7 dictations")
            HomeStatCardView(icon: "doc.text.fill", value: "254", label: "Memos", detail: "Voice recordings")
            HomeStatCardView(icon: "waveform", value: "6.8k", label: "Dictations", detail: nil)
            HomeStatCardView(icon: "text.word.spacing", value: "142K", label: "Words", detail: nil)
        }

        HStack(spacing: Spacing.md) {
            HomeActionCardView(icon: "mic.fill", title: "Record", color: .cyan, action: {})
            HomeActionCardView(icon: "app.connected.to.app.below.fill", title: "Helpers", color: .green, badge: nil, action: {})
            HomeActionCardView(icon: "wand.and.stars", title: "Workflows", color: .orange, action: {})
            HomeActionCardView(icon: "gear", title: "Settings", color: .gray, action: {})
        }
    }
    .padding()
    .frame(width: 700)
    .background(Theme.current.surfaceBase)
}
#endif
