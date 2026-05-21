//
//  ComposeNoteStore.swift
//  Talkie iOS
//

import CoreData
import Foundation

@MainActor
enum ComposeNoteStore {
    @discardableResult
    static func delete(id: String, context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        guard let note = (try? context.fetch(request))?.first else { return false }

        context.delete(note)
        do {
            try context.save()
            NotificationCenter.default.post(name: .composeNotesDidChange, object: nil)
            return true
        } catch {
            context.rollback()
            AppLogger.persistence.error("Failed to delete compose note: \(error.localizedDescription)")
            return false
        }
    }
}
