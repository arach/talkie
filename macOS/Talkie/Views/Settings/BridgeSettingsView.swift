//
//  BridgeSettingsView.swift
//  Talkie macOS
//
//  Settings view for managing TalkieBridge (iOS connectivity via Tailscale)
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import TalkieKit

struct BridgeSettingsView: View {
    @State private var bridgeManager = BridgeManager.shared
    @State private var showingQRSheet = false
    @State private var isRefreshing = false

    var body: some View {
        SettingsPageContainer {
            HStack {
                SettingsPageHeader(
                    icon: "iphone.gen3.radiowaves.left.and.right",
                    title: "iOS BRIDGE",
                    subtitle: "Connect your iPhone to view Claude Code sessions remotely."
                )
                Spacer()
                Button(action: refresh) {
                    Group {
                        if isRefreshing {
                            BrailleSpinner(speed: 0.08)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                // Tailscale Status
                TailscaleStatusSection(status: bridgeManager.tailscaleStatus)

                Divider()

                // Bridge Server Status
                BridgeServerSection(
                    status: bridgeManager.bridgeStatus,
                    tailscaleReady: bridgeManager.tailscaleStatus.isReady,
                    onStart: { Task { await bridgeManager.startBridge() } },
                    onStop: { Task { await bridgeManager.stopBridge() } },
                    onShowQR: { showingQRSheet = true }
                )

                // Pending Pairings
                if !bridgeManager.pendingPairings.isEmpty {
                    Divider()
                    PendingPairingsSection(
                        pairings: bridgeManager.pendingPairings,
                        onApprove: { id in Task { await bridgeManager.approvePairing(id) } },
                        onReject: { id in Task { await bridgeManager.rejectPairing(id) } }
                    )
                }

                // Paired Devices
                if !bridgeManager.pairedDevices.isEmpty {
                    Divider()
                    PairedDevicesSection(devices: bridgeManager.pairedDevices)
                }

                // Logs (show when bridge is running)
                if bridgeManager.bridgeStatus == .running {
                    Divider()
                    BridgeLogsSection()
                }

                Divider()
                    .padding(.vertical, 4)

                // Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("The iOS Bridge uses Tailscale to securely connect your iPhone to this Mac. Both devices must be on the same Tailscale network.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showingQRSheet) {
            QRCodeSheet(qrData: bridgeManager.qrData)
        }
        .onAppear {
            bridgeManager.checkStatus()
        }
    }

    private func refresh() {
        isRefreshing = true
        bridgeManager.checkStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRefreshing = false
        }
    }
}

// MARK: - Tailscale Status Section

private struct TailscaleStatusSection: View {
    let status: BridgeManager.TailscaleStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "network")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("TAILSCALE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: statusIcon)
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
                    .frame(width: 40, height: 40)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(status.message)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Action button based on status
                actionButton
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }

    private var statusIcon: String {
        switch status {
        case .notInstalled: return "xmark.circle.fill"
        case .notRunning: return "pause.circle.fill"
        case .needsLogin: return "person.crop.circle.badge.exclamationmark"
        case .offline: return "wifi.slash"
        case .noPeers: return "checkmark.circle.fill"
        case .ready: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .notInstalled, .notRunning: return .red
        case .needsLogin, .offline: return .orange
        case .noPeers, .ready: return .green
        }
    }

    private var statusTitle: String {
        switch status {
        case .notInstalled: return "Not Installed"
        case .notRunning: return "Not Running"
        case .needsLogin: return "Login Required"
        case .offline: return "Offline"
        case .noPeers: return "Connected"
        case .ready: return "Ready"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch status {
        case .notInstalled:
            Button(action: openTailscaleDownload) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(Theme.current.fontXS)
                    Text("INSTALL")
                        .font(Theme.current.fontXSMedium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .notRunning:
            Button(action: openTailscale) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(Theme.current.fontXS)
                    Text("OPEN")
                        .font(Theme.current.fontXSMedium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .needsLogin(let authUrl):
            Button(action: { openAuthUrl(authUrl) }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(Theme.current.fontXS)
                    Text("LOGIN")
                        .font(Theme.current.fontXSMedium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .offline:
            EmptyView()

        case .noPeers:
            Text("Set up Tailscale on iPhone")
                .font(Theme.current.fontXS)
                .foregroundColor(.orange)

        case .ready:
            EmptyView()
        }
    }

    private func openTailscaleDownload() {
        if let url = URL(string: "https://tailscale.com/download/mac") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openTailscale() {
        let tailscaleURL = URL(fileURLWithPath: "/Applications/Tailscale.app")
        NSWorkspace.shared.openApplication(at: tailscaleURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openAuthUrl(_ authUrl: String?) {
        if let urlString = authUrl, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            openTailscale()
        }
    }
}

// MARK: - Bridge Server Section

private struct BridgeServerSection: View {
    let status: BridgeManager.BridgeStatus
    let tailscaleReady: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onShowQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("BRIDGE SERVER")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: status.icon)
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
                    .frame(width: 40, height: 40)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.rawValue)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(statusDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                // Controls
                HStack(spacing: 8) {
                    if status == .running {
                        Button(action: onShowQR) {
                            HStack(spacing: 4) {
                                Image(systemName: "qrcode")
                                    .font(Theme.current.fontXS)
                                Text("PAIR")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: onStop) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(Theme.current.fontXS)
                                Text("STOP")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else if status == .stopped {
                        Button(action: onStart) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(Theme.current.fontXS)
                                Text("START")
                                    .font(Theme.current.fontXSMedium)
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!tailscaleReady)
                    } else if status == .starting {
                        BrailleSpinner(speed: 0.08)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
        }
    }

    private var statusColor: Color {
        switch status {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }

    private var statusDescription: String {
        switch status {
        case .stopped: return "Bridge is not running"
        case .starting: return "Starting bridge server..."
        case .running: return "Listening on port 8765"
        case .error: return "Bridge encountered an error"
        }
    }
}

// MARK: - Pending Pairings Section

private struct PendingPairingsSection: View {
    let pairings: [BridgeManager.PendingPairing]
    let onApprove: (String) -> Void
    let onReject: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.orange)
                Text("PENDING PAIRINGS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(.orange)
            }

            ForEach(pairings) { pairing in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                        .frame(width: 36, height: 36)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pairing.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Wants to connect")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Button(action: { onReject(pairing.deviceId) }) {
                            Image(systemName: "xmark")
                                .font(Theme.current.fontSM)
                                .foregroundColor(.red)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: { onApprove(pairing.deviceId) }) {
                            Image(systemName: "checkmark")
                                .font(Theme.current.fontSM)
                                .foregroundColor(.green)
                                .frame(width: 28, height: 28)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Paired Devices Section

private struct PairedDevicesSection: View {
    let devices: [BridgeManager.PairedDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(Theme.current.fontXS)
                    .foregroundColor(.green)
                Text("PAIRED DEVICES")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            ForEach(devices) { device in
                HStack(spacing: 12) {
                    Image(systemName: "iphone")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Paired \(formatDate(device.pairedAt))")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(Theme.current.fontSM)
                        .foregroundColor(.green)
                }
                .padding(10)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
        }
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .abbreviated
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Bridge Logs Section

private struct BridgeLogsSection: View {
    @State private var logContent: String = ""
    @State private var isAutoRefresh = true
    private let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".talkie-bridge/bridge.log")
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("BRIDGE LOGS")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Toggle("Auto", isOn: $isAutoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()

                Button(action: loadLogs) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.current.foregroundSecondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logContent.isEmpty ? "No logs yet..." : logContent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(logContent.isEmpty ? Theme.current.foregroundSecondary : Theme.current.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .frame(height: 150)
                .padding(8)
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .onChange(of: logContent) { _, _ in
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
        .onAppear {
            loadLogs()
        }
        .onReceive(timer) { _ in
            if isAutoRefresh {
                loadLogs()
            }
        }
    }

    private func loadLogs() {
        do {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            // Get last 50 lines
            let lines = content.components(separatedBy: "\n")
            let lastLines = lines.suffix(50)
            logContent = lastLines.joined(separator: "\n")
        } catch {
            logContent = "Could not read log file: \(error.localizedDescription)"
        }
    }
}

// MARK: - QR Code Sheet

private struct QRCodeSheet: View {
    let qrData: BridgeManager.QRData?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Pair iPhone")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let qrData = qrData {
                VStack(spacing: 12) {
                    if let image = generateQRCode(from: qrData) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .background(Color.white)
                            .cornerRadius(12)
                    }

                    Text("Scan with Talkie on iPhone")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hostname:")
                                .foregroundColor(.secondary)
                            Text(qrData.hostname)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Port:")
                                .foregroundColor(.secondary)
                            Text("\(qrData.port)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .font(.caption)
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text("Unable to generate QR code")
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    private func generateQRCode(from data: BridgeManager.QRData) -> NSImage? {
        guard let jsonData = try? JSONEncoder().encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for better quality
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}

// MARK: - Preview

#Preview {
    BridgeSettingsView()
        .frame(width: 500, height: 600)
        .padding()
}
