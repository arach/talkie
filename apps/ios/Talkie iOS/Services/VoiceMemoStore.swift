//
//  VoiceMemoStore.swift
//  Talkie iOS
//
//  Small Core Data facade for memo list mutations used by Next chrome.
//

import CoreData
import Foundation
import TalkieMobileKit
import UIKit

@MainActor
final class VoiceMemoStore {
    static let shared = VoiceMemoStore()

    private let context: NSManagedObjectContext
    private let fileManager = FileManager.default

    private init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    func memo(id: String) -> VoiceMemo? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let request: NSFetchRequest<VoiceMemo> = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func delete(id: String) {
        guard let memo = memo(id: id) else { return }
        delete(memo)
    }

    func delete(_ memo: VoiceMemo) {
        let memoID = memo.id
        deleteAudioFile(for: memo)

        if let memoID {
            MemoAttachmentStore.shared.deleteAll(for: memoID)
        }

        context.delete(memo)

        do {
            try context.save()
            Self.publishChange(context: context)
        } catch {
            context.rollback()
            AppLogger.persistence.error("Failed to delete voice memo: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createTextMemo(
        text: String,
        title: String? = nil,
        createdAt: Date = Date(),
        engine: String = "text_memo"
    ) -> VoiceMemo? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let memo = VoiceMemo(context: context)
        memo.id = UUID()
        if let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedTitle.isEmpty {
            memo.title = trimmedTitle
        } else {
            memo.title = Self.deriveMemoTitle(from: trimmedText)
        }
        memo.createdAt = createdAt
        memo.lastModified = Date()
        memo.duration = 0
        memo.isTranscribing = false
        memo.sortOrder = Int32(createdAt.timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false
        memo.timezone = TimeZone.current.identifier
        memo.deviceModel = UIDevice.modelIdentifier

        memo.addSystemTranscript(
            content: trimmedText,
            fromMacOS: false,
            engine: engine
        )

        do {
            try context.save()
            Self.publishChange(context: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return memo
        } catch {
            context.rollback()
            AppLogger.persistence.error("Failed to create text memo: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func promoteKeyboardDictation(_ dictation: KeyboardDictation) -> Bool {
        let memo = VoiceMemo(context: context)
        memo.id = UUID()
        memo.title = Self.deriveMemoTitle(from: dictation.text)
        memo.createdAt = dictation.timestamp
        memo.lastModified = Date()
        memo.duration = dictation.durationSeconds ?? 0
        memo.isTranscribing = false
        memo.sortOrder = Int32(dictation.timestamp.timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false

        memo.addSystemTranscript(
            content: dictation.text,
            fromMacOS: false,
            engine: "keyboard_dictation"
        )

        do {
            try context.save()
            KeyboardDictationStore.shared.delete(dictation.id)
            Self.publishChange(context: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            context.rollback()
            AppLogger.persistence.error("Failed to promote dictation to memo: \(error.localizedDescription)")
            return false
        }
    }

    private func deleteAudioFile(for memo: VoiceMemo) {
        guard let filename = memo.fileURL, !filename.isEmpty else { return }
        let url = URL.documentsDirectory.appending(path: filename)
        try? fileManager.removeItem(at: url)
    }

    private static func deriveMemoTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count < text.count ? title + "…" : title
    }

    static func publishChange(context: NSManagedObjectContext) {
        PersistenceController.refreshWidgetData(context: context)
        NotificationCenter.default.post(name: .voiceMemosDidChange, object: nil)
    }
}

extension Notification.Name {
    static let voiceMemosDidChange = Notification.Name("com.jdi.talkie.voiceMemosDidChange")
}
