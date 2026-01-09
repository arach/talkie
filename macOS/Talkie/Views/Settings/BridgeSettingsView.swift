//
//  BridgeSettingsView.swift
//  Talkie macOS
//
//  Settings view for iOS Bridge - device pairing and connectivity
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
                    title: "BRIDGE",
                    subtitle: "iOS device pairing and connectivity."
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
                // Pairing Section
                PairingSection(
                    serverStatus: bridgeManager.bridgeStatus,
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
                Divider()
                PairedDevicesSection(devices: bridgeManager.pairedDevices)

                // Message Queue (show when bridge is running)
                if bridgeManager.bridgeStatus == .running {
                    Divider()
                    BridgeMessageQueueSection()
                }

                Divider()
                    .padding(.vertical, 4)

                // Info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Bridge enables iOS devices to connect to this Mac. Pair your iPhone by scanning the QR code with Talkie iOS.")
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

// MARK: - Pairing Section

private struct PairingSection: View {
    let serverStatus: BridgeManager.BridgeStatus
    let onShowQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("PAIR NEW DEVICE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "iphone.badge.plus")
                    .font(.system(size: 24))
                    .foregroundColor(serverStatus == .running ? .blue : .gray)
                    .frame(width: 40, height: 40)
                    .background((serverStatus == .running ? Color.blue : Color.gray).opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(serverStatus == .running ? "Ready to Pair" : "Server Not Running")
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(serverStatus == .running
                         ? "Scan QR code with Talkie on iPhone"
                         : "Start TalkieServer to enable pairing")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                if serverStatus == .running {
                    Button(action: onShowQR) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode")
                                .font(Theme.current.fontXS)
                            Text("SHOW QR")
                                .font(Theme.current.fontXSMedium)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Theme.current.surface1)
            .cornerRadius(8)
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
                    .foregroundColor(devices.isEmpty ? Theme.current.foregroundSecondary : .green)
                Text("PAIRED DEVICES")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if !devices.isEmpty {
                    Text("(\(devices.count))")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            if devices.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No devices paired")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)
                        Text("Pair an iPhone to connect remotely")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    Spacer()
                }
                .padding(10)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            } else {
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

// MARK: - Bridge Message Queue Section (Troubleshooting)

private struct BridgeMessageQueueSection: View {
    @State private var queue = MessageQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.arrow.left")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                Text("MESSAGE QUEUE")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foregroundSecondary)

                if !queue.messages.isEmpty {
                    Text("(\(queue.messages.count))")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                Spacer()

                if !queue.messages.isEmpty {
                    Button("Clear") {
                        queue.clearAll()
                    }
                    .font(Theme.current.fontXS)
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }

            // Status summary
            HStack(spacing: 16) {
                let failed = queue.messages.filter { $0.status == .failed }.count
                let pending = queue.messages.filter { $0.status == .pending || $0.status == .sending }.count
                let sent = queue.messages.filter { $0.status == .sent }.count

                if queue.messages.isEmpty {
                    Text("No messages received from iOS")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                } else {
                    if failed > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("\(failed) failed")
                        }
                        .font(Theme.current.fontXS)
                    }

                    if pending > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                            Text("\(pending) pending")
                        }
                        .font(Theme.current.fontXS)
                    }

                    if sent > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(sent) sent")
                        }
                        .font(Theme.current.fontXS)
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(Theme.current.surface1)
            .cornerRadius(8)

            // Recent messages (last 5)
            if !queue.messages.isEmpty {
                VStack(spacing: 4) {
                    ForEach(queue.messages.prefix(5)) { message in
                        HStack(spacing: 8) {
                            // Status icon
                            Group {
                                switch message.status {
                                case .pending:
                                    Image(systemName: "clock")
                                        .foregroundColor(.orange)
                                case .sending:
                                    ProgressView()
                                        .controlSize(.mini)
                                case .sent:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                case .failed:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .frame(width: 14)

                            // Session + text preview
                            VStack(alignment: .leading, spacing: 1) {
                                Text(message.sessionId.prefix(8) + "...")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text(message.text.prefix(50) + (message.text.count > 50 ? "..." : ""))
                                    .font(Theme.current.fontXS)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Error or time
                            if let error = message.lastError {
                                Text(error.prefix(20))
                                    .font(.system(size: 9))
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            } else {
                                Text(message.createdAt, style: .time)
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                        }
                        .padding(6)
                        .background(Theme.current.surface1.opacity(0.5))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BridgeSettingsView()
        .frame(width: 500, height: 600)
        .padding()
}
