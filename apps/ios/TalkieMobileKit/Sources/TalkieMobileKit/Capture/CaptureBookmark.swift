//
//  CaptureBookmark.swift
//  TalkieMobileKit
//
//  Structured bookmark metadata for URL captures.
//

import Foundation

public struct CaptureBookmark: Codable, Hashable, Sendable {
    public let url: String
    public let canonicalURL: String?
    public let host: String?
    public let title: String?
    public let siteName: String?
    public let summary: String?
    public let imageURL: String?
    public let sourceApplicationBundleID: String?
    public let sourceApplicationName: String?
    public let sourceDevice: String?
    public let ingestionMethod: String?

    public init(
        url: String,
        canonicalURL: String? = nil,
        host: String? = nil,
        title: String? = nil,
        siteName: String? = nil,
        summary: String? = nil,
        imageURL: String? = nil,
        sourceApplicationBundleID: String? = nil,
        sourceApplicationName: String? = nil,
        sourceDevice: String? = nil,
        ingestionMethod: String? = nil
    ) {
        self.url = url
        self.canonicalURL = canonicalURL
        self.host = host
        self.title = title
        self.siteName = siteName
        self.summary = summary
        self.imageURL = imageURL
        self.sourceApplicationBundleID = sourceApplicationBundleID
        self.sourceApplicationName = sourceApplicationName
        self.sourceDevice = sourceDevice
        self.ingestionMethod = ingestionMethod
    }
}
