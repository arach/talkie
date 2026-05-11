//
//  URLBookmarkImportService.swift
//  Talkie
//
//  Imports a web URL as a bookmark-style capture on macOS.
//

import Foundation
import TalkieKit

@MainActor
final class URLBookmarkImportService {
    static let shared = URLBookmarkImportService()

    private let repository = TalkieObjectRepository()
    private let log = Log(.sync)

    private init() {}

    func importBookmark(
        from url: URL,
        suggestedTitle: String? = nil,
        sourceApplicationName: String? = nil,
        sourceDevice: String = "Mac",
        ingestionMethod: String = "home"
    ) async throws -> UUID {
        let objectID = UUID()
        let metadata = try await fetchMetadata(from: url)
        let canonicalURL = metadata.canonicalURL ?? url.absoluteString
        let title = suggestedTitle?.trimmedNonEmpty
            ?? metadata.title
            ?? metadata.siteName
            ?? metadata.host
            ?? "Bookmark"

        var assets = TalkieObjectAssets()
        if let imageData = await downloadImage(from: metadata.imageURL, relativeTo: url),
           let savedURL = ScreenshotStorage.save(
            imageData,
            recordingId: objectID,
            timestampMs: 0,
            captureMode: "bookmark",
            windowTitle: title,
            appName: metadata.siteName ?? metadata.host
           ) {
            assets.screenshots = [
                RecordingScreenshot(
                    filename: savedURL.lastPathComponent,
                    timestampMs: 0,
                    captureMode: "bookmark"
                )
            ]
        }

        let object = TalkieObject(
            id: objectID,
            type: .capture,
            text: referenceText(
                title: title,
                summary: metadata.summary,
                siteName: metadata.siteName ?? metadata.host,
                canonicalURL: canonicalURL,
                sourceApplicationName: sourceApplicationName,
                sourceDevice: sourceDevice
            ),
            title: title,
            duration: 0,
            createdAt: Date(),
            source: .mac,
            transcriptionStatus: .success,
            assetsJSON: assets.isEmpty ? nil : assets.toJSON(),
            metadataJSON: metadataJSON(
                sourceURL: url.absoluteString,
                canonicalURL: canonicalURL,
                host: metadata.host,
                title: title,
                siteName: metadata.siteName,
                summary: metadata.summary,
                imageURL: metadata.imageURL,
                sourceApplicationName: sourceApplicationName,
                sourceDevice: sourceDevice,
                ingestionMethod: ingestionMethod
            )
        )

        try await repository.saveRecording(object)
        await RecordingsViewModel.shared.loadRecordings()
        NavigationState.shared.navigate(to: .recordings, params: ["recordingId": objectID.uuidString])
        log.info("Imported bookmark capture: \(canonicalURL)")
        return objectID
    }

    // MARK: - Fetch

    private func fetchMetadata(from url: URL) async throws -> BookmarkPageMetadata {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BookmarkImportError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let encoding: String.Encoding = {
            if let encodingName = httpResponse.textEncodingName {
                let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
                if cfEncoding != kCFStringEncodingInvalidId {
                    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                }
            }
            return .utf8
        }()

        guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
            throw BookmarkImportError.decodingFailed
        }

        return BookmarkPageMetadata(
            host: url.host,
            canonicalURL: extractCanonicalURL(from: html, relativeTo: url),
            title: extractTitle(from: html),
            siteName: extractMetaContent(from: html, property: "og:site_name"),
            summary: extractSummary(from: html),
            imageURL: extractImageURL(from: html, relativeTo: url)
        )
    }

    private func downloadImage(from rawValue: String?, relativeTo baseURL: URL) async -> Data? {
        guard let rawValue,
              let imageURL = resolveURL(rawValue, relativeTo: baseURL) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: imageURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count <= 5_000_000 else {
                return nil
            }
            return data
        } catch {
            log.debug("Bookmark image download failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Formatting

    private func referenceText(
        title: String,
        summary: String?,
        siteName: String?,
        canonicalURL: String,
        sourceApplicationName: String?,
        sourceDevice: String
    ) -> String {
        var lines = [title]

        if let summary = summary?.trimmedNonEmpty,
           summary.caseInsensitiveCompare(title) != .orderedSame {
            lines.append(summary)
        }

        if let siteName = siteName?.trimmedNonEmpty {
            lines.append("Site: \(siteName)")
        }

        lines.append("URL: \(canonicalURL)")

        if let sourceApplicationName = sourceApplicationName?.trimmedNonEmpty {
            lines.append("Shared from: \(sourceApplicationName) on \(sourceDevice)")
        } else {
            lines.append("Saved on: \(sourceDevice)")
        }

        return lines.joined(separator: "\n")
    }

    private func metadataJSON(
        sourceURL: String,
        canonicalURL: String,
        host: String?,
        title: String,
        siteName: String?,
        summary: String?,
        imageURL: String?,
        sourceApplicationName: String?,
        sourceDevice: String,
        ingestionMethod: String
    ) -> String? {
        var dictionary: [String: String] = [
            "ingestSourceType": "url",
            "sourceURL": sourceURL,
            "bookmarkCanonicalURL": canonicalURL,
            "bookmarkTitle": title,
            "sourceDevice": sourceDevice,
            "ingestMethod": ingestionMethod,
        ]

        if let host = host?.trimmedNonEmpty {
            dictionary["bookmarkHost"] = host
        }
        if let siteName = siteName?.trimmedNonEmpty {
            dictionary["bookmarkSiteName"] = siteName
        }
        if let summary = summary?.trimmedNonEmpty {
            dictionary["bookmarkSummary"] = summary
        }
        if let imageURL = imageURL?.trimmedNonEmpty {
            dictionary["bookmarkImageURL"] = imageURL
        }
        if let sourceApplicationName = sourceApplicationName?.trimmedNonEmpty {
            dictionary["sourceApplicationName"] = sourceApplicationName
        }

        guard let data = try? JSONEncoder().encode(dictionary) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - HTML

    private func extractTitle(from html: String) -> String? {
        if let ogTitle = extractMetaContent(from: html, property: "og:title")?.trimmedNonEmpty {
            return decodeHTMLEntities(ogTitle)
        }

        if let twitterTitle = extractMetaContent(from: html, property: "twitter:title")?.trimmedNonEmpty {
            return decodeHTMLEntities(twitterTitle)
        }

        if let titleRange = html.range(of: "<title[^>]*>", options: .regularExpression),
           let endRange = html.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<html.endIndex) {
            let value = String(html[titleRange.upperBound..<endRange.lowerBound]).trimmedNonEmpty
            return value.map(decodeHTMLEntities(_:))
        }

        return nil
    }

    private func extractSummary(from html: String) -> String? {
        let candidates = [
            extractMetaContent(from: html, property: "og:description"),
            extractMetaContent(from: html, property: "twitter:description"),
            extractMetaContent(from: html, property: "description"),
        ]

        for candidate in candidates {
            if let candidate = candidate?.trimmedNonEmpty {
                return decodeHTMLEntities(candidate)
            }
        }

        return nil
    }

    private func extractImageURL(from html: String, relativeTo baseURL: URL) -> String? {
        let candidates = [
            extractMetaContent(from: html, property: "og:image"),
            extractMetaContent(from: html, property: "twitter:image"),
        ]

        for candidate in candidates {
            if let candidate = candidate?.trimmedNonEmpty,
               let resolved = resolveURL(candidate, relativeTo: baseURL) {
                return resolved.absoluteString
            }
        }

        return nil
    }

    private func extractCanonicalURL(from html: String, relativeTo baseURL: URL) -> String? {
        let pattern = "<link[^>]+rel=\"canonical\"[^>]+href=\"([^\"]+)\"|<link[^>]+href=\"([^\"]+)\"[^>]+rel=\"canonical\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: html) else { continue }
            let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolved = resolveURL(value, relativeTo: baseURL) {
                return resolved.absoluteString
            }
        }

        return nil
    }

    private func extractMetaContent(from html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)=\"\(escaped)\"[^>]+content=\"([^\"]*)\"",
            "<meta[^>]+content=\"([^\"]*)\"[^>]+(?:property|name)=\"\(escaped)\"",
            "<meta[^>]+(?:property|name)='\(escaped)'[^>]+content='([^']*)'",
            "<meta[^>]+content='([^']*)'[^>]+(?:property|name)='\(escaped)'",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else {
                continue
            }
            return String(html[range])
        }

        return nil
    }

    private func resolveURL(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&ndash;", "-"),
            ("&mdash;", "--"),
            ("&hellip;", "..."),
            ("&laquo;", "\""),
            ("&raquo;", "\""),
            ("&ldquo;", "\""),
            ("&rdquo;", "\""),
            ("&lsquo;", "'"),
            ("&rsquo;", "'"),
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else {
                    continue
                }
                let rawCode = String(result[codeRange])
                let codePoint: UInt32?
                if rawCode.hasPrefix("x") || rawCode.hasPrefix("X") {
                    codePoint = UInt32(String(rawCode.dropFirst()), radix: 16)
                } else {
                    codePoint = UInt32(rawCode)
                }
                if let codePoint, let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }

        return result
    }
}

private struct BookmarkPageMetadata {
    let host: String?
    let canonicalURL: String?
    let title: String?
    let siteName: String?
    let summary: String?
    let imageURL: String?
}

private enum BookmarkImportError: LocalizedError {
    case httpError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode):
            return "Page fetch failed (HTTP \(statusCode))."
        case .decodingFailed:
            return "Could not decode page content."
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
