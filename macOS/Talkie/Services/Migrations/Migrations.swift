//
//  Migrations.swift
//  Talkie macOS
//
//  All data migrations. Append new migrations to the array below.
//  Each migration runs exactly once per device (tracked in UserDefaults).
//

import Foundation
import CoreData

// MARK: - All Migrations (append new ones here)

let allMigrations: [Migration] = [

    // 001: Mark existing memos as auto-processed so auto-run
    // workflows only trigger on NEW memos going forward.
    Migration(
        id: "001_auto_processed",
        description: "Mark existing memos as auto-processed"
    ) { context in
        let request = VoiceMemo.fetchRequest()
        request.predicate = NSPredicate(format: "autoProcessed == NO OR autoProcessed == nil")

        let memos = try context.fetch(request)
        for memo in memos {
            memo.autoProcessed = true
        }
        return memos.count
    },

    // 002: Backfill memoId on existing WorkflowRuns to enable
    // efficient CloudKit queries from iOS.
    Migration(
        id: "002_workflow_run_memo_id",
        description: "Backfill memoId on WorkflowRuns"
    ) { context in
        let request: NSFetchRequest<WorkflowRun> = WorkflowRun.fetchRequest()
        request.predicate = NSPredicate(format: "memoId == nil AND memo != nil")

        let runs = try context.fetch(request)
        for run in runs {
            run.memoId = run.memo?.id
        }
        return runs.count
    },

    // Add new migrations here...

]
