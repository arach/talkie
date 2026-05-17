//
//  HyperScanCaptureView.swift
//  Talkie iOS
//
//  Experimental image capture flow for mapping a target and sending snaps to
//  the Mac for stitching and OCR analysis.
//

import SwiftUI
import PhotosUI
import UIKit
import Vision
import ImageIO

struct HyperScanCaptureView: View {
    static var isSupported: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var snaps: [HyperScanClientSnap] = []
    @State private var showingCamera = false
    @State private var pendingRole: HyperScanSnapRole = .detail
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var isSending = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var retainCaptures = TalkieAppSettings.shared.hyperScanRetainCaptures

    private var overviewSnap: HyperScanClientSnap? {
        snaps.first { $0.role == .overview }
    }

    private var detailSnaps: [HyperScanClientSnap] {
        snaps.filter { $0.role == .detail }
    }

    private var allFragments: [String] {
        snaps.flatMap(\.fragments)
    }

    private var stitchCandidates: [TalkieAIProviderCredentialStitchCandidate] {
        TalkieAIProviderCredentialOCRService.stitchCandidates(from: allFragments)
    }

    private var bestCandidate: TalkieAIProviderCredentialStitchCandidate? {
        stitchCandidates.first
    }

    private var reconstructedText: String {
        if let bestCandidate {
            return bestCandidate.apiKey
        }

        return TalkieAIProviderCredentialOCRService.stitchedKeyText(from: allFragments)
    }

    private var progress: Double {
        let snapProgress = min(Double(snaps.count) / 16, 1)
        let fragmentProgress = min(Double(allFragments.count) / 24, 1)
        let confidenceProgress = Double(bestCandidate?.confidencePercent ?? 0) / 100
        return min((snapProgress * 0.35) + (fragmentProgress * 0.25) + (confidenceProgress * 0.4), 1)
    }

    private var progressPercent: Int {
        min(max(Int((progress * 100).rounded()), 0), 100)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        header
                        targetMap
                        actionStrip
                        reconstructionCard
                        snapStrip
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Hyper Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraImagePicker { image in
                let role = pendingRole
                Task { @MainActor in
                    await addImage(image, role: role)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            selectedPhotoItem = nil
            Task { @MainActor in
                await importPhoto(newItem)
            }
        }
        .onAppear {
            retainCaptures = TalkieAppSettings.shared.hyperScanRetainCaptures
        }
        .onChange(of: retainCaptures) { _, newValue in
            TalkieAppSettings.shared.hyperScanRetainCaptures = newValue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Scan")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text("Start with the whole target, then add close-up snaps where coverage is thin.")
                .font(.system(size: 14))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Target Map", systemImage: "viewfinder.rectangular")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Text("\(progressPercent)%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))

                if let overviewSnap {
                    Image(uiImage: overviewSnap.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 8))
                        .padding(1)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.metering.matrix")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)

                        Text("Take the big picture first")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                HyperScanCoverageOverlay(snaps: detailSnaps, progress: progress)
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(1)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1.35, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderPrimary.opacity(0.8), lineWidth: 0.7)
            }
        }
        .padding(14)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary.opacity(0.6), lineWidth: 0.7)
        }
    }

    private var actionStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    pendingRole = .overview
                    showingCamera = true
                } label: {
                    Label(overviewSnap == nil ? "Big Picture" : "Retake", systemImage: "rectangle.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || isSending || !Self.isSupported)

                Button {
                    pendingRole = overviewSnap == nil ? .overview : .detail
                    showingCamera = true
                } label: {
                    Label("Snap", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing || isSending || !Self.isSupported)
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Import", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing || isSending)

                Button {
                    Task { @MainActor in
                        await sendToMac()
                    }
                } label: {
                    Label(isSending ? "Sending" : "Send to Mac", systemImage: "macbook.and.iphone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(snaps.isEmpty || isProcessing || isSending)
            }

            Toggle("Keep on Mac", isOn: $retainCaptures)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .tint(.accentColor)

            if isProcessing {
                ProgressView("Reading text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var reconstructionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Best Guess", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Text("\(bestCandidate?.confidencePercent ?? 0)%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
            }

            Text(reconstructedText.isEmpty ? "No candidate yet" : reconstructedText)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !allFragments.isEmpty {
                Text(allFragments.prefix(12).map { $0.talkieHyperScanShortened(maxLength: 16) }.joined(separator: "  "))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary.opacity(0.6), lineWidth: 0.7)
        }
    }

    private var snapStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Snaps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Text("\(snaps.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
            }

            if snaps.isEmpty {
                Text("No snaps yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(snaps) { snap in
                            HyperScanSnapThumb(snap: snap)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not read the selected image."
                return
            }

            await addImage(image, role: overviewSnap == nil ? .overview : .detail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addImage(_ image: UIImage, role: HyperScanSnapRole) async {
        isProcessing = true
        errorMessage = nil
        statusMessage = nil

        do {
            let reading = try HyperScanImageOCR.read(image: image)
            let fragments = TalkieAIProviderCredentialOCRService.keyFragments(in: reading.recognizedText)
            guard let imageData = image.jpegData(compressionQuality: 0.78) else {
                errorMessage = "Could not encode the snap."
                isProcessing = false
                return
            }

            let normalizedRole = snaps.isEmpty ? HyperScanSnapRole.overview : role
            let snap = HyperScanClientSnap(
                id: UUID().uuidString,
                image: image,
                imageData: imageData,
                role: normalizedRole,
                addedAt: Date(),
                recognizedText: reading.recognizedText,
                textLines: reading.lines,
                fragments: fragments
            )

            if normalizedRole == .overview {
                snaps.removeAll { $0.role == .overview }
                snaps.insert(snap, at: 0)
            } else {
                snaps.append(snap)
            }

            statusMessage = fragments.isEmpty ? "Snap saved. No key-shaped text yet." : "Snap saved."
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    @MainActor
    private func sendToMac() async {
        guard !snaps.isEmpty else { return }

        isSending = true
        errorMessage = nil
        statusMessage = nil

        do {
            let request = makeUploadRequest()
            let response = try await BridgeManager.shared.sendHyperScanCapture(body: request)
            if response.retain {
                statusMessage = "Saved \(response.savedCount) snap(s) on Mac."
            } else if let expiresAt = response.expiresAt {
                statusMessage = "Sent \(response.savedCount) snap(s). Expires \(expiresAt)."
            } else {
                statusMessage = "Sent \(response.savedCount) snap(s)."
            }
        } catch BridgeError.notConfigured {
            errorMessage = "Pair a Mac to receive Hyper Scan captures."
        } catch BridgeError.connectionFailed {
            errorMessage = "Could not reach your paired Mac."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    private func makeUploadRequest() -> HyperScanUploadRequest {
        let fragments = allFragments
        let candidates = stitchCandidates
        let bestGuess = candidates.first?.apiKey
        let expected = TalkieAIProviderCredentialOCRService.localTestAPIKey
        let comparison = expected.isEmpty || bestGuess == nil
            ? nil
            : TalkieAIProviderCredentialOCRService.localComparison(
                candidate: bestGuess ?? "",
                expected: expected
            )

        let uploadSnaps = snaps.enumerated().map { index, snap in
            snap.uploadSnap(index: index)
        }

        return HyperScanUploadRequest(
            schemaVersion: 3,
            captureId: UUID().uuidString,
            captureKind: "hyper-scan",
            createdAt: HyperScanClientSnap.timestamp(Date()),
            recognizedText: snaps.map(\.recognizedText).filter { !$0.isEmpty }.joined(separator: "\n\n"),
            coverage: HyperScanUploadSummary(
                targetSnapCount: 16,
                targetSegmentCount: 24,
                snapCount: snaps.count,
                processedSnapCount: snaps.count,
                queuedSnapCount: 0,
                readySnapCount: snaps.filter { !$0.recognizedText.isEmpty }.count,
                segmentCount: fragments.count,
                progress: progress,
                hasTargetCoverage: overviewSnap != nil
            ),
            fragments: fragments,
            stitchCandidates: candidates.map { candidate in
                HyperScanUploadStitchCandidate(
                    apiKey: candidate.apiKey,
                    confidencePercent: candidate.confidencePercent,
                    fragmentCount: candidate.fragments.count,
                    isValidShape: candidate.isValidShape
                )
            },
            puzzle: HyperScanUploadPuzzle(
                bestGuess: bestGuess,
                confidencePercent: candidates.first?.confidencePercent ?? 0,
                isKnownGoodMatch: comparison?.isMatch,
                similarityPercent: comparison?.similarityPercent,
                editDistance: comparison?.editDistance,
                candidateLength: comparison?.candidateLength ?? bestGuess?.count,
                expectedLength: comparison?.expectedLength
            ),
            snaps: uploadSnaps,
            retain: retainCaptures
        )
    }
}

private struct HyperScanCoverageOverlay: View {
    let snaps: [HyperScanClientSnap]
    let progress: Double

    private var coveredSlots: Set<Int> {
        Set(snaps.enumerated().map { index, _ in min(index, 15) })
    }

    var body: some View {
        Canvas { context, size in
            let columns = 4
            let rows = 4
            let gap = 5.0
            let cellWidth = (size.width - (gap * Double(columns - 1))) / Double(columns)
            let cellHeight = (size.height - (gap * Double(rows - 1))) / Double(rows)

            for index in 0..<(columns * rows) {
                let column = index % columns
                let row = index / columns
                let rect = CGRect(
                    x: Double(column) * (cellWidth + gap),
                    y: Double(row) * (cellHeight + gap),
                    width: cellWidth,
                    height: cellHeight
                )

                let isCovered = coveredSlots.contains(index)
                let fill = isCovered
                    ? Color.green.opacity(0.28 + min(progress, 1) * 0.22)
                    : Color.white.opacity(0.08)
                let stroke = isCovered ? Color.green.opacity(0.85) : Color.white.opacity(0.22)
                let path = Path(roundedRect: rect, cornerRadius: 6)
                context.fill(path, with: .color(fill))
                context.stroke(path, with: .color(stroke), lineWidth: isCovered ? 1.2 : 0.7)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HyperScanSnapThumb: View {
    let snap: HyperScanClientSnap

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(uiImage: snap.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 116, height: 86)
                .clipped()
                .clipShape(.rect(cornerRadius: 8))

            Text(snap.role.label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(snap.role == .overview ? .blue : .green)

            Text(snap.displayFragment)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .frame(width: 116, alignment: .leading)
        }
        .padding(8)
        .background(Color.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderPrimary.opacity(0.6), lineWidth: 0.7)
        }
    }
}

private struct HyperScanClientSnap: Identifiable {
    let id: String
    let image: UIImage
    let imageData: Data
    let role: HyperScanSnapRole
    let addedAt: Date
    let recognizedText: String
    let textLines: [HyperScanOCRLine]
    let fragments: [String]

    var displayFragment: String {
        if let fragment = fragments.first {
            return fragment.talkieHyperScanShortened(maxLength: 20)
        }

        if recognizedText.isEmpty {
            return "No text"
        }

        return recognizedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .talkieHyperScanShortened(maxLength: 22)
    }

    var pixelWidth: Int {
        Int((image.size.width * image.scale).rounded())
    }

    var pixelHeight: Int {
        Int((image.size.height * image.scale).rounded())
    }

    var status: String {
        recognizedText.isEmpty ? "no_text" : "ready"
    }

    var quality: HyperScanUploadQuality {
        HyperScanUploadQuality(
            recognizedCharacterCount: recognizedText.count,
            fragmentCount: fragments.count,
            geometryArea: nil,
            orientationClass: pixelWidth >= pixelHeight ? "landscape" : "portrait",
            isLikelyUsable: !recognizedText.isEmpty || role == .overview,
            note: recognizedText.isEmpty ? "No OCR text" : nil
        )
    }

    func uploadSnap(index: Int) -> HyperScanUploadSnap {
        HyperScanUploadSnap(
            id: id,
            captureIndex: index,
            role: role.rawValue,
            addedAt: Self.timestamp(addedAt),
            status: status,
            displayFragment: displayFragment,
            recognizedText: recognizedText,
            textLines: textLines.enumerated().map { lineIndex, line in
                HyperScanUploadTextLine(
                    blockIndex: 0,
                    lineIndex: lineIndex,
                    text: line.text,
                    fragments: TalkieAIProviderCredentialOCRService.keyFragments(in: line.text),
                    geometry: line.geometry
                )
            },
            fragments: fragments,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            mimeType: "image/jpeg",
            dataBase64: imageData.base64EncodedString(),
            geometry: estimatedGeometry(index: index),
            motion: nil,
            quality: quality
        )
    }

    private func estimatedGeometry(index: Int) -> HyperScanUploadGeometry {
        guard role == .detail else {
            return HyperScanUploadGeometry(
                normalizedX: 0,
                normalizedY: 0,
                normalizedWidth: 1,
                normalizedHeight: 1,
                centerX: 0.5,
                centerY: 0.5,
                angleDegrees: 0
            )
        }

        let slot = max(index - 1, 0)
        let columns = 4
        let rows = 4
        let width = 0.34
        let height = 0.28
        let column = slot % columns
        let row = (slot / columns) % rows
        let x = min(Double(column) / Double(columns), 1 - width)
        let y = min(Double(row) / Double(rows), 1 - height)

        return HyperScanUploadGeometry(
            normalizedX: x,
            normalizedY: y,
            normalizedWidth: width,
            normalizedHeight: height,
            centerX: x + width / 2,
            centerY: y + height / 2,
            angleDegrees: 0
        )
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private enum HyperScanSnapRole: String {
    case overview
    case detail

    var label: String {
        switch self {
        case .overview:
            "BIG PICTURE"
        case .detail:
            "DETAIL"
        }
    }
}

private struct HyperScanOCRLine {
    let text: String
    let geometry: HyperScanUploadGeometry?
}

private enum HyperScanImageOCR {
    static func read(image: UIImage) throws -> (recognizedText: String, lines: [HyperScanOCRLine]) {
        guard let cgImage = image.cgImage else {
            return ("", [])
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.enumerated().compactMap { index, observation -> HyperScanOCRLine? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let box = observation.boundingBox
            return HyperScanOCRLine(
                text: candidate.string,
                geometry: HyperScanUploadGeometry(
                    normalizedX: box.minX,
                    normalizedY: 1 - box.maxY,
                    normalizedWidth: box.width,
                    normalizedHeight: box.height,
                    centerX: box.midX,
                    centerY: 1 - box.midY,
                    angleDegrees: 0
                )
            )
        }

        return (lines.map(\.text).joined(separator: "\n"), lines)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

private extension String {
    func talkieHyperScanShortened(maxLength: Int) -> String {
        guard count > maxLength, maxLength > 3 else {
            return self
        }

        let headCount = max(1, (maxLength - 1) / 2)
        let tailCount = max(1, maxLength - headCount - 1)
        return "\(prefix(headCount))...\(suffix(tailCount))"
    }
}
