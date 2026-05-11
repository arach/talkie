//
//  SSHTerminalTranscriptInspectorView.swift
//  Talkie iOS
//
//  Raw transcript inspector for the SSH terminal renderer lab.
//

import SwiftUI

struct SSHTerminalTranscriptInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportItems: [Any] = []
    @State private var showingShareSheet = false

    let captureData: Data
    let chunkRecords: [SSHTerminalOutputChunkRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    escapedPreviewCard
                    hexPreviewCard(title: "Head", lines: makeHexDumpLines(for: headBytes))
                    hexPreviewCard(title: "Tail", lines: makeHexDumpLines(for: tailBytes))
                }
                .padding(16)
            }
            .background(Color.surfacePrimary.ignoresSafeArea())
            .navigationTitle("Transcript Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Export") {
                        exportTranscript()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: exportItems)
        }
    }

    private var summaryCard: some View {
        inspectorCard(title: "Summary") {
            VStack(alignment: .leading, spacing: 8) {
                inspectorRow(label: "Bytes", value: "\(captureData.count)")
                inspectorRow(label: "Chunks", value: "\(chunkRecords.count)")
                inspectorRow(label: "Head sample", value: "\(headBytes.count)")
                inspectorRow(label: "Tail sample", value: "\(tailBytes.count)")
            }
        }
    }

    private var escapedPreviewCard: some View {
        inspectorCard(title: "Escaped Preview") {
            Text(escapedPreview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hexPreviewCard(title: String, lines: [String]) -> some View {
        inspectorCard(title: "\(title) Hex") {
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inspectorCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headlineSmall)
                .foregroundStyle(Color.textSecondary)

            content()
        }
        .padding(14)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
    }

    private func inspectorRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            Spacer(minLength: 0)
        }
    }

    private var headBytes: [UInt8] {
        Array(captureData.prefix(1024))
    }

    private var tailBytes: [UInt8] {
        Array(captureData.suffix(1024))
    }

    private var escapedPreview: String {
        let sample = Array(captureData.prefix(1400))
        var output = ""

        for byte in sample {
            switch byte {
            case 0x0D:
                output += "\\r"
            case 0x0A:
                output += "\\n\n"
            case 0x1B:
                output += "\\e"
            case 0x20...0x7E:
                output.append(Character(UnicodeScalar(byte)))
            default:
                output += String(format: "\\x%02X", byte)
            }
        }

        if captureData.count > sample.count {
            output += "\n…"
        }

        return output
    }

    private func makeHexDumpLines(for bytes: [UInt8]) -> [String] {
        guard !bytes.isEmpty else { return ["(empty)"] }

        var lines: [String] = []
        var offset = 0

        while offset < bytes.count {
            let chunk = Array(bytes[offset..<min(offset + 16, bytes.count)])
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = chunk.map { byte -> Character in
                if (0x20...0x7E).contains(byte) {
                    return Character(UnicodeScalar(byte))
                }
                return "."
            }
            let paddedHex = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            lines.append(String(format: "%04X  %@  %@", offset, paddedHex, String(ascii)))
            offset += 16
        }

        return lines
    }

    private func exportTranscript() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: .now)

        let tempDirectory = URL.temporaryDirectory.appending(path: "talkie-ssh-transcript-\(stamp)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let escapedURL = tempDirectory.appending(path: "transcript.txt")
        let rawURL = tempDirectory.appending(path: "transcript.bin")
        let chunksURL = tempDirectory.appending(path: "chunks.json")

        let escapedText = fullEscapedTranscript

        do {
            try escapedText.write(to: escapedURL, atomically: true, encoding: .utf8)
            try captureData.write(to: rawURL)
            let chunkData = try JSONEncoder.prettyPrintedSorted.encode(chunkRecords)
            try chunkData.write(to: chunksURL)
            exportItems = [escapedURL, rawURL, chunksURL]
            showingShareSheet = true
        } catch {
            exportItems = []
            showingShareSheet = false
        }
    }

    private var fullEscapedTranscript: String {
        var output = ""

        for byte in captureData {
            switch byte {
            case 0x0D:
                output += "\\r"
            case 0x0A:
                output += "\\n\n"
            case 0x1B:
                output += "\\e"
            case 0x20...0x7E:
                output.append(Character(UnicodeScalar(byte)))
            default:
                output += String(format: "\\x%02X", byte)
            }
        }

        return output
    }
}

private extension JSONEncoder {
    static var prettyPrintedSorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
