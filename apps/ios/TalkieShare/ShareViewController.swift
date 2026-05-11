//
//  ShareViewController.swift
//  TalkieShare
//
//  Share Extension that queues content in the App Group container
//  and opens the main Talkie app to process it.
//
//  No networking here — the main app handles bridge communication.
//

import UIKit
import UniformTypeIdentifiers

private var kTalkieAppGroup: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "TalkieAppGroupIdentifier") as? String else {
        return "group.com.example.talkie"
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "group.com.example.talkie" : trimmed
}

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await processAndHandOff() }
    }

    private func processAndHandOff() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        do {
            let payload = try await extractPayload(from: items)
            let id = UUID().uuidString
            try writeToAppGroup(id: id, payload: payload)
            openMainApp(shareId: id)
        } catch {
            // If extraction fails, just close — nothing useful to hand off
            close()
        }
    }

    // MARK: - Extract Content

    private func extractPayload(from items: [NSExtensionItem]) async throws -> SharePayload {
        for item in items {
            guard let attachments = item.attachments else { continue }

            // Priority 1: URLs (from Safari, etc.)
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                       url.scheme == "http" || url.scheme == "https" {
                        return SharePayload(
                            sourceType: "url",
                            text: url.absoluteString,
                            title: item.attributedContentText?.string,
                            sourceURL: url.absoluteString
                        )
                    }
                }
            }

            // Priority 2: Plain text
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                       !text.isEmpty {
                        return SharePayload(
                            sourceType: "text",
                            text: text
                        )
                    }
                }
            }

            // Priority 3: Images
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let result = try await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
                    let image: UIImage?
                    if let url = result as? URL {
                        image = UIImage(contentsOfFile: url.path)
                    } else if let data = result as? Data {
                        image = UIImage(data: data)
                    } else if let img = result as? UIImage {
                        image = img
                    } else {
                        image = nil
                    }

                    if let image, let jpegData = image.jpegData(compressionQuality: 0.8) {
                        let filename = "share-\(UUID().uuidString.prefix(8)).jpg"
                        return SharePayload(
                            sourceType: "photo",
                            text: "Photo shared from iPhone",
                            imageBase64: jpegData.base64EncodedString(),
                            imageFilename: filename
                        )
                    }
                }
            }
        }

        throw ShareError.noContent
    }

    // MARK: - App Group Queue

    private func writeToAppGroup(id: String, payload: SharePayload) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: kTalkieAppGroup
        ) else {
            throw ShareError.noAppGroup
        }

        let queueDir = containerURL.appendingPathComponent("Library/Application Support/Talkie/share-queue")
        try FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)

        let fileURL = queueDir.appendingPathComponent("\(id).json")
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Open Main App

    private func openMainApp(shareId: String) {
        let url = URL(string: "talkie://share?id=\(shareId)")!

        // Share extensions can't call UIApplication.shared.open directly,
        // but we can use the responder chain trick
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let application = next as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in
                    self?.close()
                }
                return
            }
            responder = next
        }

        // Fallback: use openURL selector
        let selector = sel_registerName("openURL:")
        var current: UIResponder? = self
        while let next = current?.next {
            if next.responds(to: selector) {
                next.perform(selector, with: url)
                break
            }
            current = next
        }

        close()
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Models

struct SharePayload: Codable {
    let sourceType: String       // "url", "text", "photo"
    let text: String
    var title: String?
    var sourceURL: String?
    var imageBase64: String?
    var imageFilename: String?
}

enum ShareError: Error {
    case noContent
    case noAppGroup
}
