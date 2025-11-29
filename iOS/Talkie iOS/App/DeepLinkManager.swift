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
    case playLastMemo
    case search(query: String)
}

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var pendingAction: DeepLinkAction = .none

    private init() {}

    func handle(url: URL) {
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
            // Handle talkie://search?q=<query>
            if let query = components?.queryItems?.first(where: { $0.name == "q" })?.value {
                AppLogger.app.info("Deep link: search for '\(query)'")
                pendingAction = .search(query: query)
            }

        default:
            AppLogger.app.warning("Unknown deep link: \(url.absoluteString)")
        }
    }

    func clearAction() {
        pendingAction = .none
    }
}
