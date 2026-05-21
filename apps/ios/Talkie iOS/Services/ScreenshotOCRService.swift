//
//  ScreenshotOCRService.swift
//  Talkie iOS
//
//  On-device text extraction from images using Vision document APIs.
//

import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum ScreenshotOCRService {

    /// Result of an OCR operation.
    struct OCRResult {
        let text: String
        let image: UIImage
        let pageCount: Int
        let didDetectPage: Bool
    }

    /// Result of an OCR operation that preserves per-observation confidence.
    struct OCRChunkResult {
        let chunks: [OCRChunk]
        let image: UIImage
        let pageCount: Int
        let didDetectPage: Bool

        var text: String {
            chunks.map(\.text).joined(separator: "\n").normalizedDocumentText
        }
    }

    enum OCRError: LocalizedError {
        case noTextFound
        case recognitionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noTextFound:
                return "No text was found in this image."
            case .recognitionFailed(let error):
                return "Text recognition failed: \(error.localizedDescription)"
            }
        }
    }

    private struct PreparedPage {
        let image: UIImage
        let text: String
        let didDetectPage: Bool
    }

    private struct PreparedChunkPage {
        let image: UIImage
        let chunks: [OCRChunk]
        let didDetectPage: Bool
    }

    private static let ciContext = CIContext()

    static func extractText(from image: UIImage) async throws -> OCRResult {
        try await extractText(from: [image])
    }

    static func extractChunks(from image: UIImage) async throws -> OCRChunkResult {
        try await extractChunks(from: [image])
    }

    static func extractText(from images: [UIImage]) async throws -> OCRResult {
        guard !images.isEmpty else {
            throw OCRError.noTextFound
        }

        var preparedPages: [PreparedPage] = []
        preparedPages.reserveCapacity(images.count)

        for image in images {
            let normalizedImage = image.normalizedForOCR()
            let correctedImage = await correctedDocumentImage(from: normalizedImage)
            let preparedImage = correctedImage ?? normalizedImage
            let text = try await recognizedText(from: preparedImage)

            preparedPages.append(
                PreparedPage(
                    image: preparedImage,
                    text: text,
                    didDetectPage: correctedImage != nil || images.count > 1
                )
            )
        }

        let combinedText = preparedPages
            .map(\.text)
            .map(\.normalizedDocumentText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        guard !combinedText.isEmpty else {
            throw OCRError.noTextFound
        }

        let previewImage = compositePreviewImage(from: preparedPages.map(\.image)) ?? preparedPages[0].image
        let didDetectPage = preparedPages.contains(where: { $0.didDetectPage })

        AppLogger.ai.info("OCR extracted \(combinedText.count) characters from \(preparedPages.count) page(s)")
        return OCRResult(
            text: combinedText,
            image: previewImage,
            pageCount: preparedPages.count,
            didDetectPage: didDetectPage
        )
    }

    static func extractChunks(from images: [UIImage]) async throws -> OCRChunkResult {
        guard !images.isEmpty else {
            throw OCRError.noTextFound
        }

        var preparedPages: [PreparedChunkPage] = []
        preparedPages.reserveCapacity(images.count)

        for image in images {
            let normalizedImage = image.normalizedForOCR()
            let correctedImage = await correctedDocumentImage(from: normalizedImage)
            let preparedImage = correctedImage ?? normalizedImage
            let chunks = try await recognizeLegacyChunks(from: preparedImage)

            preparedPages.append(
                PreparedChunkPage(
                    image: preparedImage,
                    chunks: chunks,
                    didDetectPage: correctedImage != nil || images.count > 1
                )
            )
        }

        let combinedChunks = preparedPages
            .flatMap(\.chunks)
            .filter { !$0.text.normalizedDocumentText.isEmpty }

        guard !combinedChunks.isEmpty else {
            throw OCRError.noTextFound
        }

        let previewImage = compositePreviewImage(from: preparedPages.map(\.image)) ?? preparedPages[0].image
        let didDetectPage = preparedPages.contains(where: { $0.didDetectPage })
        let characterCount = combinedChunks.reduce(0) { $0 + $1.text.count }

        AppLogger.ai.info("OCR extracted \(characterCount) characters from \(preparedPages.count) page(s) with confidence")
        return OCRChunkResult(
            chunks: combinedChunks,
            image: previewImage,
            pageCount: preparedPages.count,
            didDetectPage: didDetectPage
        )
    }

    private static func recognizedText(from image: UIImage) async throws -> String {
        if #available(iOS 26.0, *) {
            do {
                let documentText = try await recognizeDocumentText(from: image)
                if !documentText.isEmpty {
                    return documentText
                }
            } catch {
                AppLogger.ai.debug("Document OCR fell back to legacy OCR: \(error.localizedDescription)")
            }
        }

        return try await recognizeLegacyText(from: image)
    }

    @available(iOS 26.0, *)
    private static func recognizeDocumentText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.noTextFound
        }

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.maximumCandidateCount = 1

        let observations = try await ImageRequestHandler(cgImage).perform(request)
        let documents = observations.compactMap(documentText(from:))
        return documents.joined(separator: "\n\n").normalizedDocumentText
    }

    @available(iOS 26.0, *)
    private static func documentText(from observation: DocumentObservation) -> String? {
        var sections: [String] = []

        if let title = observation.document.title?.transcript.normalizedDocumentText,
           !title.isEmpty {
            sections.append(title)
        }

        let paragraphs = observation.document.paragraphs
            .map(\.transcript)
            .map(\.normalizedDocumentText)
            .filter { !$0.isEmpty }

        if !paragraphs.isEmpty {
            sections.append(paragraphs.joined(separator: "\n\n"))
        } else {
            let body = observation.document.text.transcript.normalizedDocumentText
            if !body.isEmpty {
                sections.append(body)
            }
        }

        let combined = sections.joined(separator: "\n\n").normalizedDocumentText
        return combined.isEmpty ? nil : combined
    }

    private static func recognizeLegacyText(from image: UIImage) async throws -> String {
        let chunks = try await recognizeLegacyChunks(from: image)
        let trimmed = chunks
            .map(\.text)
            .joined(separator: "\n")
            .normalizedDocumentText

        guard !trimmed.isEmpty else {
            throw OCRError.noTextFound
        }

        return trimmed
    }

    private static func recognizeLegacyChunks(from image: UIImage) async throws -> [OCRChunk] {
        guard let cgImage = image.cgImage else {
            throw OCRError.noTextFound
        }

        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                let results = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: results)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            Task.detached(priority: .userInitiated) {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                }
            }
        }

        let chunks = observations.compactMap { observation -> OCRChunk? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string.normalizedDocumentText
            guard !text.isEmpty else {
                return nil
            }

            return OCRChunk(
                text: text,
                confidence: Double(candidate.confidence)
            )
        }

        guard !chunks.isEmpty else {
            throw OCRError.noTextFound
        }

        return chunks
    }

    private static func correctedDocumentImage(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        if #available(iOS 18.0, *) {
            do {
                let observation = try await ImageRequestHandler(cgImage).perform(DetectDocumentSegmentationRequest())
                guard let observation else {
                    return nil
                }

                let boundingBox = observation.boundingBox
                guard boundingBox.width * boundingBox.height > 0.2 else {
                    return nil
                }

                return perspectiveCorrectedImage(from: cgImage, using: observation, scale: image.scale)
            } catch {
                AppLogger.ai.debug("Document segmentation failed: \(error.localizedDescription)")
            }
        }

        return nil
    }

    private static func perspectiveCorrectedImage(
        from cgImage: CGImage,
        using document: some QuadrilateralProviding,
        scale: CGFloat
    ) -> UIImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = document.topLeft.toImageCoordinates(imageSize, origin: .lowerLeft)
        filter.topRight = document.topRight.toImageCoordinates(imageSize, origin: .lowerLeft)
        filter.bottomRight = document.bottomRight.toImageCoordinates(imageSize, origin: .lowerLeft)
        filter.bottomLeft = document.bottomLeft.toImageCoordinates(imageSize, origin: .lowerLeft)

        guard let outputImage = filter.outputImage,
              let correctedCGImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: correctedCGImage, scale: scale, orientation: .up)
    }

    private static func compositePreviewImage(from images: [UIImage]) -> UIImage? {
        guard let firstImage = images.first else {
            return nil
        }

        if images.count == 1 {
            return firstImage
        }

        let targetWidth = images.map(\.size.width).max() ?? firstImage.size.width
        let gap: CGFloat = 12
        let scaledSizes = images.map { image in
            let scale = targetWidth / max(image.size.width, 1)
            return CGSize(width: targetWidth, height: image.size.height * scale)
        }
        let totalHeight = scaledSizes.reduce(0) { $0 + $1.height } + gap * CGFloat(images.count - 1)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: totalHeight))

        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: targetWidth, height: totalHeight)))

            var yOffset: CGFloat = 0
            for (image, size) in zip(images, scaledSizes) {
                image.draw(in: CGRect(origin: CGPoint(x: 0, y: yOffset), size: size))
                yOffset += size.height + gap
            }
        }
    }
}

private extension UIImage {
    func normalizedForOCR() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension String {
    var normalizedDocumentText: String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
