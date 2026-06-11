//
//  LibraryNotifications.swift
//  TalkieKit
//
//  Cross-process signals for shared library mutations.
//

import Foundation

public enum TalkieLibraryNotifications {
    /// Posted after a process writes durable rows into the shared recordings table.
    /// Talkie.app uses this to refresh views for writes that happened outside its
    /// own GRDB connection, such as Agent-owned screenshot and clip captures.
    public static let recordsDidChange = "to.talkie.library.recordsDidChange"
}
