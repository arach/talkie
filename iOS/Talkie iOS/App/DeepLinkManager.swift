//
//  DeepLinkManager.swift
//  Talkie iOS
//
//  Handles URL deep links for widget and Siri integration
//

import Foundation
import SwiftUI

enum DeepLinkAction: Equatable {
    case none
    case record
    case openMemo(id: UUID)
    case openMemoActivity(id: UUID)  // Open memo and scroll to activity section
    case playLastMemo
    case search(query: String)
    case openSearch      // Just open search UI
    case openAllMemos    // Open main memo list
    case openSettings    // Open settings view
    case importAudio(url: URL)  // Import audio file from share sheet
}

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var pendingAction: DeepLinkAction = .none

    private init() {}

    /// Supported audio file extensions for import
    private static let audioExtensions = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "mp4", "3gp"]

    func handle(url: URL) {
        // Handle file:// URLs for audio import
        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if Self.audioExtensions.contains(ext) {
                AppLogger.app.info("Deep link: import audio from \(url.lastPathComponent)")
                pendingAction = .importAudio(url: url)
            } else {
                AppLogger.app.warning("Unsupported file type: \(ext)")
            }
            return
        }

        guard url.scheme == "talkie" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case "record":
            AppLogger.app.info("Deep link: record action triggered")
            pendingAction = .record

        case "memo":
            // Handle talkie://memo?id=<uuid>
            if let idString = components?.queryItems?.first(where: { $0.name == "id" })?.value,
               let id = UUID(uuidString: idString) {
                AppLogger.app.info("Deep link: open memo \(id)")
                pendingAction = .openMemo(id: id)
            }

        case "play-last":
            AppLogger.app.info("Deep link: play last memo")
            pendingAction = .playLastMemo

        case "search":
            // Handle talkie://search or talkie://search?q=<query>
            if let query = components?.queryItems?.first(where: { $0.name == "q" })?.value {
                AppLogger.app.info("Deep link: search for '\(query)'")
                pendingAction = .search(query: query)
            } else {
                AppLogger.app.info("Deep link: open search")
                pendingAction = .openSearch
            }

        case "memos":
            AppLogger.app.info("Deep link: open all memos")
            pendingAction = .openAllMemos

        case "settings":
            AppLogger.app.info("Deep link: open settings")
            pendingAction = .openSettings

        default:
            AppLogger.app.warning("Unknown deep link: \(url.absoluteString)")
        }
    }

    func clearAction() {
        pendingAction = .none
    }
}
