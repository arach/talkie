//
//  SingleKeyShortcutAction.swift
//  Talkie
//
//  Shared definitions for the app's single-key shortcuts.
//  Keeps keyboard handling and clickable shortcut affordances in sync.
//

enum SingleKeyShortcutAction: String, CaseIterable, Identifiable {
    case compose = "c"
    case record = "r"
    case library = "l"
    case dictations = "d"
    case notes = "n"
    case screenshots = "s"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compose: return "Compose"
        case .record: return "Record"
        case .library: return "Library"
        case .dictations: return "Dictations"
        case .notes: return "Notes"
        case .screenshots: return "Screenshots"
        }
    }

    var shortcutKey: String { rawValue.uppercased() }

    static func action(for characters: String) -> Self? {
        Self(rawValue: characters.lowercased())
    }

    @MainActor
    func perform() {
        switch self {
        case .compose:
            NavigationState.shared.navigateToCompose()
        case .record:
            MemoRecordingController.shared.startRecording()
        case .library:
            NavigationState.shared.navigate(to: .recordings)
        case .dictations:
            NavigationState.shared.navigateToDictations()
        case .notes:
            NavigationState.shared.navigate(to: .notes)
        case .screenshots:
            NavigationState.shared.navigate(to: .screenshots)
        }
    }
}
