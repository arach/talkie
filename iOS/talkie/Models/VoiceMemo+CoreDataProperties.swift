//
//  VoiceMemo+CoreDataProperties.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import Foundation
import CoreData

extension VoiceMemo {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VoiceMemo> {
        return NSFetchRequest<VoiceMemo>(entityName: "VoiceMemo")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var duration: Double
    @NSManaged public var fileURL: String?
    @NSManaged public var transcription: String?
    @NSManaged public var isTranscribing: Bool
    @NSManaged public var waveformData: Data?

    public var wrappedTitle: String {
        title ?? "Recording"
    }

    public var wrappedCreatedAt: Date {
        createdAt ?? Date()
    }

    public var wrappedFileURL: URL? {
        guard let fileURL = fileURL else { return nil }
        return URL(string: fileURL)
    }
}

extension VoiceMemo: Identifiable {

}
