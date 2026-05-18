//
//  SettingsSheetController.swift
//  Talkie iOS
//
//  Presents the legacy SettingsView as a sheet over Next surfaces.
//  SettingsView is comprehensive and refined — iCloud auth, Bridge,
//  Appearance, Keyboard, AI providers — and gets brought in
//  wholesale rather than reimagined. Settings is content surface,
//  not interaction-design; the Next chrome rebuild is elsewhere.
//

import SwiftUI

@MainActor
final class SettingsSheetController: ObservableObject {
    static let shared = SettingsSheetController()
    @Published var isPresented: Bool = false
    private init() {}
}
