//
//  ComposeNoteStore.swift
//  Talkie iOS
//

import CoreData
import Foundation
import TalkieMobileKit

@MainActor
enum ComposeNoteStore {
    struct NoteSummary: Identifiable, Equatable {
        let id: String
        let title: String
        let preview: String
        let modifiedLabel: String
    }

    struct RevisionRecord: Identifiable, Codable, Equatable {
        let id: UUID
        let instruction: String
        let scope: String
        let revisedText: String
        let documentText: String
        let providerName: String
        let modelId: String
        let createdAt: Date

        init(
            id: UUID = UUID(),
            instruction: String,
            scope: String,
            revisedText: String,
            documentText: String,
            providerName: String,
            modelId: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.instruction = instruction
            self.scope = scope
            self.revisedText = revisedText
            self.documentText = documentText
            self.providerName = providerName
            self.modelId = modelId
            self.createdAt = createdAt
        }
    }

    static func all(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) -> [NoteSummary] {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false),
        ]

        let notes = (try? context.fetch(request)) ?? []
        return notes.compactMap(noteSummary(from:))
    }

    @discardableResult
    static func create(
        title: String = "Untitled note",
        content: String = "",
        id: UUID = UUID(),
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) -> ComposeNote {
        let note = ComposeNote(context: context)
        note.id = id
        note.title = cleanTitle(title, fallback: "Untitled note")
        note.content = content
        note.createdAt = Date()
        note.lastModified = Date()
        save(context)
        return note
    }

    @discardableResult
    static func create(from capture: Capture, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) -> ComposeNote {
        let title = cleanTitle(capture.title, fallback: defaultCaptureTitle(capture))
        let content = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return create(title: title, content: content, id: capture.id, context: context)
    }

    @discardableResult
    static func save(
        id: UUID,
        title: String,
        content: String,
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext
    ) -> Bool {
        let note = fetch(id: id, context: context) ?? create(title: title, content: content, id: id, context: context)
        note.title = cleanTitle(title, fallback: "Untitled note")
        note.content = content
        note.lastModified = Date()
        return save(context)
    }

    static func fetch(id: UUID, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) -> ComposeNote? {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    static func revisions(for noteID: UUID) -> [RevisionRecord] {
        guard let data = try? Data(contentsOf: revisionsURL(for: noteID)) else { return [] }
        return (try? JSONDecoder().decode([RevisionRecord].self, from: data)) ?? []
    }

    static func saveRevisions(_ revisions: [RevisionRecord], for noteID: UUID) {
        do {
            let directory = revisionsDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(revisions)
            try data.write(to: revisionsURL(for: noteID), options: [.atomic])
        } catch {
            AppLogger.persistence.error("Failed to save compose revision history: \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func delete(id: String, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        guard let note = fetch(id: uuid, context: context) else { return false }

        context.delete(note)
        do {
            try context.save()
            try? FileManager.default.removeItem(at: revisionsURL(for: uuid))
            NotificationCenter.default.post(name: .composeNotesDidChange, object: nil)
            return true
        } catch {
            context.rollback()
            AppLogger.persistence.error("Failed to delete compose note: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private static func save(_ context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            NotificationCenter.default.post(name: .composeNotesDidChange, object: nil)
            return true
        } catch {
            context.rollback()
            AppLogger.persistence.error("Failed to save compose note: \(error.localizedDescription)")
            return false
        }
    }

    private static func noteSummary(from note: ComposeNote) -> NoteSummary? {
        guard let id = note.id?.uuidString else { return nil }
        let content = note.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NoteSummary(
            id: id,
            title: cleanTitle(note.title, fallback: "Untitled note"),
            preview: content.isEmpty ? "Empty note" : String(content.prefix(120)),
            modifiedLabel: modifiedLabel(note.lastModified ?? note.createdAt)
        )
    }

    private static func cleanTitle(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        return value
    }

    private static func defaultCaptureTitle(_ capture: Capture) -> String {
        switch capture.sourceType {
        case "url":
            return "Web capture"
        case "photo":
            return "Photo capture"
        default:
            return "Capture note"
        }
    }

    private static func modifiedLabel(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return "Today · \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday · \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(time)"
    }

    private static var revisionsDirectory: URL {
        URL.documentsDirectory.appending(path: "compose-revisions", directoryHint: .isDirectory)
    }

    private static func revisionsURL(for noteID: UUID) -> URL {
        revisionsDirectory.appending(path: "\(noteID.uuidString).json")
    }
}
