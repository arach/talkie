//
//  URLBookmarkMetadataService.swift
//  Talkie iOS
//
//  Builds bookmark-style captures for inbound URLs.
//

import Foundation
import TalkieMobileKit

enum URLBookmarkMetadataService {
    struct Result {
        let capture: Capture
        let imageData: Data?
    }

    static func buildCapture(
        from url: URL,
        suggestedTitle: String? = nil,
        sourceApplicationBundleID: String? = nil,
        sourceApplicationName: String? = nil,
        sourceDevice: String,
        ingestionMethod: String
    ) async -> Result {
        do {
            let metadata = try await fetchMetadata(from: url)
            let finalURL = metadata.canonicalURL ?? url.absoluteString
            let bookmark = CaptureBookmark(
                url: url.absoluteString,
                canonicalURL: metadata.canonicalURL,
                host: metadata.host,
                title: suggestedTitle ?? metadata.title,
                siteName: metadata.siteName,
                summary: metadata.summary,
                imageURL: metadata.imageURL,
                sourceApplicationBundleID: sourceApplicationBundleID,
                sourceApplicationName: resolvedSourceApplicationName(
                    explicitName: sourceApplicationName,
                    bundleID: sourceApplicationBundleID
                ),
                sourceDevice: sourceDevice,
                ingestionMethod: ingestionMethod
            )

            let capture = Capture(
                sourceType: "url",
                text: referenceText(
                    title: suggestedTitle ?? metadata.title,
                    summary: metadata.summary,
                    siteName: metadata.siteName ?? metadata.host,
                    canonicalURL: finalURL,
                    sourceApplicationName: bookmark.sourceApplicationName,
                    sourceDevice: sourceDevice
                ),
                title: suggestedTitle ?? metadata.title ?? metadata.siteName ?? metadata.host ?? "Bookmark",
                sourceURL: finalURL,
                bookmark: bookmark
            )

            let imageData = await downloadImage(from: metadata.imageURL, relativeTo: url)
            return Result(capture: capture, imageData: imageData)
        } catch {
            AppLogger.app.warning("Bookmark metadata fetch failed for \(url.absoluteString): \(error.localizedDescription)")

            let bookmark = CaptureBookmark(
                url: url.absoluteString,
                canonicalURL: nil,
                host: url.host,
                title: suggestedTitle,
                siteName: url.host,
                summary: nil,
                imageURL: nil,
                sourceApplicationBundleID: sourceApplicationBundleID,
                sourceApplicationName: resolvedSourceApplicationName(
                    explicitName: sourceApplicationName,
                    bundleID: sourceApplicationBundleID
                ),
                sourceDevice: sourceDevice,
                ingestionMethod: ingestionMethod
            )

            let capture = Capture(
                sourceType: "url",
                text: referenceText(
                    title: suggestedTitle ?? url.host,
                    summary: nil,
                    siteName: url.host,
                    canonicalURL: url.absoluteString,
                    sourceApplicationName: bookmark.sourceApplicationName,
                    sourceDevice: sourceDevice
                ),
                title: suggestedTitle ?? url.host ?? "Bookmark",
                sourceURL: url.absoluteString,
                bookmark: bookmark
            )

            return Result(capture: capture, imageData: nil)
        }
    }

    // MARK: - Fetch

    private static func fetchMetadata(from url: URL) async throws -> PageMetadata {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLContentExtractorError.httpError(statusCode: statusCode)
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
            throw URLContentExtractorError.decodingFailed
        }

        return PageMetadata(
            host: url.host,
            canonicalURL: extractCanonicalURL(from: html, relativeTo: url),
            title: extractTitle(from: html),
            siteName: extractMetaContent(from: html, property: "og:site_name"),
            summary: extractSummary(from: html),
            imageURL: extractImageURL(from: html, relativeTo: url)
        )
    }

    private static func downloadImage(from rawValue: String?, relativeTo baseURL: URL) async -> Data? {
        guard let rawValue,
              let imageURL = resolveURL(rawValue, relativeTo: baseURL) else {
            return nil
        }

        do {
            var request = URLRequest(url: imageURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count <= 5_000_000 else {
                return nil
            }
            return data
        } catch {
            AppLogger.app.debug("Bookmark image download failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Formatting

    private static func referenceText(
        title: String?,
        summary: String?,
        siteName: String?,
        canonicalURL: String,
        sourceApplicationName: String?,
        sourceDevice: String?
    ) -> String {
        var lines: [String] = []

        if let title, !title.isEmpty {
            lines.append(title)
        }

        if let summary,
           !summary.isEmpty,
           summary.caseInsensitiveCompare(title ?? "") != .orderedSame {
            lines.append(summary)
        }

        if let siteName, !siteName.isEmpty {
            lines.append("Site: \(siteName)")
        }

        lines.append("URL: \(canonicalURL)")

        if let sourceDescription = sourceDescription(
            applicationName: sourceApplicationName,
            sourceDevice: sourceDevice
        ) {
            lines.append("Shared from: \(sourceDescription)")
        }

        return lines.joined(separator: "\n")
    }

    private static func sourceDescription(
        applicationName: String?,
        sourceDevice: String?
    ) -> String? {
        switch (applicationName.nilIfEmpty, sourceDevice.nilIfEmpty) {
        case let (app?, device?):
            return "\(app) on \(device)"
        case let (app?, nil):
            return app
        case let (nil, device?):
            return device
        case (nil, nil):
            return nil
        }
    }

    private static func resolvedSourceApplicationName(
        explicitName: String?,
        bundleID: String?
    ) -> String? {
        if let explicitName = explicitName.nilIfEmpty {
            return explicitName
        }

        switch bundleID {
        case "com.apple.mobilesafari", "com.apple.Safari":
            return "Safari"
        case "com.google.chrome.ios", "com.google.Chrome":
            return "Chrome"
        case "org.mozilla.ios.Firefox", "org.mozilla.firefox":
            return "Firefox"
        case "com.duckduckgo.mobile.ios":
            return "DuckDuckGo"
        case "com.microsoft.msedge":
            return "Edge"
        default:
            return nil
        }
    }

    // MARK: - HTML Parsing

    private static func extractTitle(from html: String) -> String? {
        if let ogTitle = extractMetaContent(from: html, property: "og:title")?.trimmedNonEmpty {
            return decodeHTMLEntities(ogTitle)
        }

        if let twitterTitle = extractMetaContent(from: html, property: "twitter:title")?.trimmedNonEmpty {
            return decodeHTMLEntities(twitterTitle)
        }

        if let titleRange = html.range(of: "<title[^>]*>", options: .regularExpression),
           let endRange = html.range(
                of: "</title>",
                options: .caseInsensitive,
                range: titleRange.upperBound..<html.endIndex
           ) {
            let value = String(html[titleRange.upperBound..<endRange.lowerBound]).trimmedNonEmpty
            return value.map(decodeHTMLEntities(_:))
        }

        return nil
    }

    private static func extractSummary(from html: String) -> String? {
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

    private static func extractImageURL(from html: String, relativeTo baseURL: URL) -> String? {
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

    private static func extractCanonicalURL(from html: String, relativeTo baseURL: URL) -> String? {
        let pattern = "<link[^>]+rel=\"canonical\"[^>]+href=\"([^\"]+)\"|<link[^>]+href=\"([^\"]+)\"[^>]+rel=\"canonical\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else {
            return nil
        }

        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: html) else { continue }
            let candidate = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolved = resolveURL(candidate, relativeTo: baseURL) {
                return resolved.absoluteString
            }
        }

        return nil
    }

    private static func extractMetaContent(from html: String, property: String) -> String? {
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

    private static func resolveURL(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }

        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
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

private struct PageMetadata {
    let host: String?
    let canonicalURL: String?
    let title: String?
    let siteName: String?
    let summary: String?
    let imageURL: String?
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case .some(let value) where !value.isEmpty:
            return value
        default:
            return nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
