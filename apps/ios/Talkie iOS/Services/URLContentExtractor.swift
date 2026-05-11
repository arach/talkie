//
//  URLContentExtractor.swift
//  Talkie iOS
//
//  Fetches a URL and extracts readable text content from the page.
//  Uses Foundation-only approach — no external dependencies.
//

import Foundation
import TalkieMobileKit

/// Extracted content from a web page
struct URLContent {
    /// Page title (from <title> tag or og:title)
    let title: String?
    /// Readable text content extracted from the HTML body
    let text: String
    /// The source URL
    let sourceURL: URL
}

/// Fetches URLs and extracts readable text content
enum URLContentExtractor {

    // MARK: - Public

    /// Fetch a URL and extract readable text content.
    /// Throws on network errors or if no meaningful text could be extracted.
    static func extract(from url: URL) async throws -> URLContent {
        AppLogger.app.info("URLContentExtractor: fetching \(url.absoluteString)")

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLContentExtractorError.httpError(statusCode: status)
        }

        // Determine encoding from response or default to UTF-8
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

        let title = extractTitle(from: html)
        let text = extractReadableText(from: html)

        guard !text.isEmpty else {
            throw URLContentExtractorError.noContentExtracted
        }

        AppLogger.app.info("URLContentExtractor: extracted \(text.count) chars, title: \(title ?? "none")")

        return URLContent(title: title, text: text, sourceURL: url)
    }

    // MARK: - HTML Parsing

    /// Extract the page title from HTML
    private static func extractTitle(from html: String) -> String? {
        // Try og:title first (usually cleaner)
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            return ogTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fall back to <title> tag
        if let titleRange = html.range(of: "<title[^>]*>", options: .regularExpression),
           let endRange = html.range(of: "</title>", options: .caseInsensitive, range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : decodeHTMLEntities(title)
        }

        return nil
    }

    /// Extract meta tag content by property name
    private static func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta[^>]+(?:property|name)=\"\(NSRegularExpression.escapedPattern(for: property))\"[^>]+content=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let contentRange = Range(match.range(at: 1), in: html) else {
            // Try reversed attribute order: content before property
            let altPattern = "<meta[^>]+content=\"([^\"]*)\"[^>]+(?:property|name)=\"\(NSRegularExpression.escapedPattern(for: property))\""
            guard let altRegex = try? NSRegularExpression(pattern: altPattern, options: .caseInsensitive),
                  let altMatch = altRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let altRange = Range(altMatch.range(at: 1), in: html) else {
                return nil
            }
            return String(html[altRange])
        }
        return String(html[contentRange])
    }

    /// Extract readable text from HTML by stripping tags and non-content elements
    private static func extractReadableText(from html: String) -> String {
        var text = html

        // Remove script, style, nav, header, footer, aside blocks entirely
        let stripPatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<noscript[^>]*>[\\s\\S]*?</noscript>",
            "<!--[\\s\\S]*?-->",
        ]

        for pattern in stripPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }

        // Replace block-level elements with newlines for structure
        let blockTags = ["p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "blockquote", "article", "section"]
        for tag in blockTags {
            if let regex = try? NSRegularExpression(pattern: "</?\\s*\(tag)[^>]*>", options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
            }
        }

        // Strip all remaining HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // Decode HTML entities
        text = decodeHTMLEntities(text)

        // Clean up whitespace: collapse runs of spaces, normalize line breaks
        text = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        // Collapse excessive blank lines (3+ newlines -> 2)
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Trim and cap length to avoid huge transcripts
        text = String(text.prefix(50_000)).trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    /// Decode common HTML entities
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

        // Handle numeric entities: &#123; and &#x1F; forms
        if let numericRegex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);") {
            let matches = numericRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else { continue }
                let codeStr = String(result[codeRange])
                let codePoint: UInt32?
                if codeStr.hasPrefix("x") || codeStr.hasPrefix("X") {
                    codePoint = UInt32(String(codeStr.dropFirst()), radix: 16)
                } else {
                    codePoint = UInt32(codeStr)
                }
                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }

        return result
    }
}

// MARK: - Errors

enum URLContentExtractorError: LocalizedError {
    case httpError(statusCode: Int)
    case decodingFailed
    case noContentExtracted

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "Failed to fetch page (HTTP \(code))"
        case .decodingFailed:
            return "Could not decode page content"
        case .noContentExtracted:
            return "No readable content found on page"
        }
    }
}
