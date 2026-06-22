//
//  ShareExportPanelController.swift
//  Talkie
//
//  Embedded web export panel for prepared screenshot sharing.
//

import AppKit
import Foundation
import ImageIO
import TalkieKit
import UniformTypeIdentifiers
import WebKit

private let shareExportLog = Log(.ui)

@MainActor
final class ShareExportPanelController: NSObject {
    static let shared = ShareExportPanelController()

    private var panel: NSPanel?
    private var webView: WKWebView?
    private var payload: [String: Any] = [:]

    private override init() {
        super.init()
    }

    func open(
        imageURL: URL,
        title: String,
        sourceLabel: String? = nil,
        detail: String? = nil
    ) {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            ToastService.shared.showError("Could not find the screenshot to export.")
            return
        }
        guard let resourceDirectory = Self.bundledResourceDirectory() else {
            ToastService.shared.showError("Export panel resources are missing.")
            shareExportLog.error("Share export resources missing from bundle")
            return
        }
        let indexURL = resourceDirectory.appending(path: "index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            ToastService.shared.showError("Export panel could not load.")
            shareExportLog.error("Share export index missing", detail: indexURL.path)
            return
        }

        do {
            payload = try Self.makePayload(
                imageURL: imageURL,
                title: title,
                sourceLabel: sourceLabel,
                detail: detail
            )
        } catch {
            ToastService.shared.showError("Could not prepare export: \(error.localizedDescription)")
            shareExportLog.error("Share export payload failed", detail: error.localizedDescription)
            return
        }

        closePanel()

        let panel = makePanel()
        let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        panel.contentView = contentView
        panel.delegate = self

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        #if DEBUG
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        configuration.userContentController.add(self, name: "talkieExport")

        let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        contentView.addSubview(webView)

        self.panel = panel
        self.webView = webView

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.loadFileURL(indexURL, allowingReadAccessTo: resourceDirectory)
    }

    private func closePanel() {
        guard let panel else { return }
        panel.close()
        if self.panel != nil {
            teardown()
        }
    }

    private func teardown() {
        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "talkieExport")
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
        panel?.delegate = nil
        panel = nil
        payload.removeAll(keepingCapacity: false)
    }

    private func sendPayload() {
        guard let webView,
              !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.talkieExport && window.talkieExport.init(\(json));")
    }

    private func handleBridgeMessage(_ body: Any) {
        guard let dictionary = body as? [String: Any],
              let type = dictionary["type"] as? String else { return }

        switch type {
        case "export.ready":
            sendPayload()
        case "export.copy":
            guard let artifact = ShareExportArtifact(message: dictionary) else {
                ToastService.shared.showError("Could not copy the export.")
                return
            }
            copy(artifact)
        case "export.save":
            guard let artifact = ShareExportArtifact(message: dictionary) else {
                ToastService.shared.showError("Could not save the export.")
                return
            }
            save(artifact)
        case "export.close":
            closePanel()
        case "export.error":
            let message = (dictionary["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                ToastService.shared.showError(message)
            } else {
                ToastService.shared.showError("Export failed.")
            }
        default:
            break
        }
    }

    private func copy(_ artifact: ShareExportArtifact) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(artifact.data, forType: artifact.format.pasteboardType)
        if let image = NSImage(data: artifact.data),
           let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        ToastService.shared.showSuccess("Export copied")
    }

    private func save(_ artifact: ShareExportArtifact) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [artifact.format.contentType]
        savePanel.nameFieldStringValue = artifact.filename

        let write: (URL) -> Void = { url in
            do {
                try artifact.data.write(to: url, options: .atomic)
                ToastService.shared.showSuccess("Saved \(url.lastPathComponent)")
            } catch {
                ToastService.shared.showError("Could not save export: \(error.localizedDescription)")
                shareExportLog.error("Share export save failed", detail: error.localizedDescription)
            }
        }

        if let panel {
            savePanel.beginSheetModal(for: panel) { response in
                guard response == .OK, let url = savePanel.url else { return }
                write(url)
            }
        } else if savePanel.runModal() == .OK, let url = savePanel.url {
            write(url)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Talkie Export"
        panel.minSize = NSSize(width: 880, height: 580)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.center()
        return panel
    }

    private static func bundledResourceDirectory() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "Resources/ShareExport"),
            Bundle.main.resourceURL?.appending(path: "ShareExport"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func makePayload(
        imageURL: URL,
        title: String,
        sourceLabel: String?,
        detail: String?
    ) throws -> [String: Any] {
        let imageData = try Data(contentsOf: imageURL)
        let dimensions = imageDimensions(for: imageURL)
        let fileSize = detail?.isEmpty == false ? detail : formatBytes(imageData.count)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = cleanTitle.isEmpty ? imageURL.deletingPathExtension().lastPathComponent : cleanTitle
        var payload: [String: Any] = [
            "title": displayTitle,
            "filename": imageURL.lastPathComponent,
            "fileSize": fileSize ?? "",
            "imageDataURL": "data:\(mimeType(for: imageURL));base64,\(imageData.base64EncodedString())",
            "suggestedName": shareExportSanitizedFileBase(displayTitle),
        ]
        if let sourceLabel, !sourceLabel.isEmpty {
            payload["sourceLabel"] = sourceLabel
        }
        if let dimensions {
            payload["width"] = dimensions.width
            payload["height"] = dimensions.height
        }
        return payload
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "image/png"
        }
    }

    private static func imageDimensions(for url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = intProperty(kCGImagePropertyPixelWidth, in: properties),
              let height = intProperty(kCGImagePropertyPixelHeight, in: properties) else {
            return nil
        }
        return (width, height)
    }

    private static func intProperty(_ key: CFString, in properties: [CFString: Any]) -> Int? {
        if let value = properties[key] as? Int { return value }
        if let value = properties[key] as? NSNumber { return value.intValue }
        return nil
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

}

extension ShareExportPanelController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "talkieExport" else { return }
        handleBridgeMessage(message.body)
    }
}

extension ShareExportPanelController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendPayload()
    }
}

extension ShareExportPanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        teardown()
    }
}

private func shareExportSanitizedFileBase(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    let cleaned = value
        .components(separatedBy: invalid)
        .joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Talkie Export" : cleaned
}

private struct ShareExportArtifact {
    let data: Data
    let format: ShareExportFileFormat
    let filename: String

    init?(message: [String: Any]) {
        guard let dataURL = message["dataURL"] as? String,
              let decoded = Self.decode(dataURL: dataURL) else { return nil }
        let declaredFormat = message["format"] as? String
        format = ShareExportFileFormat.resolve(declared: declaredFormat, mimeType: decoded.mimeType)
        data = decoded.data

        let suggested = (message["suggestedName"] as? String) ?? "Talkie Export"
        filename = Self.filename(base: suggested, format: format)
    }

    private static func decode(dataURL: String) -> (mimeType: String, data: Data)? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let header = String(dataURL[..<comma])
        let payload = String(dataURL[dataURL.index(after: comma)...])
        guard header.hasPrefix("data:"),
              header.localizedStandardContains(";base64"),
              let data = Data(base64Encoded: payload) else {
            return nil
        }
        let mimeType = header
            .dropFirst("data:".count)
            .split(separator: ";")
            .first
            .map(String.init) ?? "image/png"
        return (mimeType, data)
    }

    private static func filename(base: String, format: ShareExportFileFormat) -> String {
        let sanitized = shareExportSanitizedFileBase(base)
        let extensionSuffix = ".\(format.fileExtension)"
        if sanitized.lowercased().hasSuffix(extensionSuffix) {
            return sanitized
        }
        return "\(sanitized)\(extensionSuffix)"
    }
}

private enum ShareExportFileFormat {
    case png
    case jpeg

    var contentType: UTType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        }
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(contentType.identifier)
    }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }

    static func resolve(declared: String?, mimeType: String) -> ShareExportFileFormat {
        let normalized = (declared ?? mimeType).lowercased()
        if normalized.contains("jpeg") || normalized.contains("jpg") {
            return .jpeg
        }
        return .png
    }
}
