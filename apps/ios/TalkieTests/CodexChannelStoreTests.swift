//
//  CodexChannelStoreTests.swift
//  TalkieTests
//

import XCTest
@testable import Talkie_iOS

@MainActor
final class CodexChannelStoreTests: XCTestCase {
    func testSelectingChannelWithoutLaneDoesNotMutateLaneBindings() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let store = CodexLaneStore(defaults: defaults)
        let assigned = task(id: "assigned", cwd: "/projects/talkie", updatedAt: 20)
        let direct = task(id: "new", cwd: "/projects/openscout", updatedAt: 30)

        store.assign(assigned, to: 1)
        let originalLanes = store.lanes

        store.selectChannel(direct)

        XCTAssertEqual(store.lanes, originalLanes)
        XCTAssertNil(store.activeLaneNumber)
        XCTAssertEqual(store.selectedTask, direct)
    }

    func testClearingSelectionDoesNotRemoveLaneBindings() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let store = CodexLaneStore(defaults: defaults)
        let assigned = task(id: "assigned", cwd: "/projects/talkie", updatedAt: 20)

        store.assign(assigned, to: 3)
        store.selectChannel(assigned)
        store.clearSelection()

        XCTAssertNil(store.selectedTask)
        XCTAssertNil(store.activeLaneNumber)
        XCTAssertEqual(store.lane(3)?.task, assigned)
    }

    func testEnteringNewTaskModeKeepsLaneBindingsAndDefersTaskIdentity() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let store = CodexLaneStore(defaults: defaults, hostIDOverride: "test-host")
        let assigned = task(id: "assigned", cwd: "/projects/talkie", updatedAt: 20)
        let project = CodexProjectSummary(
            hostID: "test-host",
            cwd: "/projects/openscout",
            name: "openscout",
            updatedAt: 30,
            isAssignedToLane: false
        )

        store.assign(assigned, to: 3)
        let originalLanes = store.lanes

        XCTAssertTrue(store.enterNewTaskMode(in: project, submissionID: UUID()))
        XCTAssertEqual(store.lanes, originalLanes)
        XCTAssertNil(store.selectedTask)
        XCTAssertEqual(store.newTaskProject, project)
        XCTAssertTrue(store.hasDispatchDestination)
    }

    func testSelectingExistingTaskLeavesNewTaskMode() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let store = CodexLaneStore(defaults: defaults, hostIDOverride: "test-host")
        let existing = task(id: "existing", cwd: "/projects/talkie", updatedAt: 20)
        let project = CodexProjectSummary(
            hostID: "test-host",
            cwd: "/projects/openscout",
            name: "openscout",
            updatedAt: 30,
            isAssignedToLane: false
        )

        XCTAssertTrue(store.enterNewTaskMode(in: project, submissionID: UUID()))
        store.selectChannel(existing)

        XCTAssertNil(store.newTaskProject)
        XCTAssertEqual(store.selectedTask, existing)
    }

    func testClearingSelectionRemainsUnarmedAfterReload() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let assigned = task(id: "assigned", cwd: "/projects/talkie", updatedAt: 20)

        let store = CodexLaneStore(defaults: defaults, hostIDOverride: "test-host")
        store.assign(assigned, to: 3)
        store.selectChannel(assigned)
        store.clearSelection()

        let reloaded = CodexLaneStore(defaults: defaults, hostIDOverride: "test-host")

        XCTAssertNil(reloaded.selectedTask)
        XCTAssertNil(reloaded.activeLaneNumber)
        XCTAssertEqual(reloaded.lane(3)?.task, assigned)
    }

    func testCatalogMergePreservesOrderAndDeduplicatesByTaskID() {
        let first = task(id: "first", cwd: "/projects/talkie", updatedAt: 30)
        let second = task(id: "second", cwd: "/projects/studio", updatedAt: 20)
        let duplicateSecond = task(id: "second", cwd: "/projects/changed", updatedAt: 10)
        let third = task(id: "third", cwd: "/projects/openscout", updatedAt: 5)

        let merged = CodexLaneStore.mergingCatalog(
            [first, second],
            with: [duplicateSecond, third]
        )

        XCTAssertEqual(merged.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(merged[1].cwd, "/projects/studio")
    }

    func testCatalogMergeRefreshesCreationPlaceholderWithNewerTaskMetadata() {
        let placeholder = CodexTaskSummary(
            id: "created",
            title: "New task",
            preview: "",
            cwd: "/projects/talkie",
            project: nil,
            updatedAt: 10
        )
        let refreshed = CodexTaskSummary(
            id: "created",
            title: "Explain the Watch bridge",
            preview: "Inspect the durable handoff.",
            cwd: "/projects/talkie",
            project: nil,
            updatedAt: 20
        )

        let merged = CodexLaneStore.mergingCatalog([placeholder], with: [refreshed])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "Explain the Watch bridge")
        XCTAssertEqual(merged[0].preview, "Inspect the durable handoff.")
    }

    func testCatalogRefreshReplacesSelectedAndPinnedCreationPlaceholders() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let store = CodexLaneStore(defaults: defaults)
        let placeholder = CodexTaskSummary(
            id: "created",
            title: "New task",
            preview: "",
            cwd: "/projects/talkie",
            updatedAt: 10
        )
        let refreshed = CodexTaskSummary(
            id: "created",
            title: "Make Watch dispatch visible",
            preview: "Show the task in Codex Desktop.",
            cwd: "/projects/talkie",
            updatedAt: 20
        )

        store.assign(placeholder, to: 2)
        store.selectChannel(placeholder)
        store.refreshTaskReferences(with: [refreshed])

        XCTAssertEqual(store.selectedTask, refreshed)
        XCTAssertEqual(store.lane(2)?.task, refreshed)
        XCTAssertEqual(store.activeLaneNumber, 2)
    }

    func testProjectsPutLaneDirectoriesFirstAndDeduplicateCanonicalPath() {
        let pinned = task(id: "lane", cwd: "/projects/talkie", updatedAt: 10)
        let duplicate = task(id: "recent", cwd: "/projects/./talkie", updatedAt: 50)
        let recent = task(id: "other", cwd: "/projects/studio", updatedAt: 40)

        let projects = CodexLaneStore.deriveProjects(
            hostID: "mac-1",
            lanes: [CodexLane(number: 2, task: pinned)],
            catalog: [duplicate, recent]
        )

        XCTAssertEqual(projects.map(\.cwd), ["/projects/talkie", "/projects/studio"])
        XCTAssertTrue(projects[0].isAssignedToLane)
        XCTAssertFalse(projects[1].isAssignedToLane)
        XCTAssertEqual(projects.map(\.hostID), ["mac-1", "mac-1"])
    }

    func testAssigningTaskMovesItInsteadOfDuplicatingItAcrossLanes() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "CodexChannelStoreTests.\(UUID().uuidString)")
        )
        let store = CodexLaneStore(defaults: defaults)
        let channel = task(id: "move-me", cwd: "/projects/talkie", updatedAt: 20)

        store.assign(channel, to: 2)
        store.assign(channel, to: 5)

        XCTAssertNil(store.lane(2))
        XCTAssertEqual(store.lane(5)?.task.id, channel.id)
        XCTAssertEqual(store.sortedLanes.filter { $0.task.id == channel.id }.map(\.number), [5])
    }

    func testTaskCompactsPairedMacHomePathOnPhone() {
        let remoteTask = task(
            id: "remote",
            cwd: "/Users/arach/dev/talkie",
            updatedAt: 20
        )

        XCTAssertEqual(remoteTask.compactPath, "~/dev/talkie")
    }

    func testProjectCompactsRemoteHomeAndPreservesSystemPath() {
        let remoteProject = CodexProjectSummary(
            hostID: "mac-1",
            cwd: "/Users/arach",
            name: "Home",
            updatedAt: 20,
            isAssignedToLane: false
        )
        let systemProject = CodexProjectSummary(
            hostID: "mac-1",
            cwd: "/opt/talkie",
            name: "Talkie",
            updatedAt: 10,
            isAssignedToLane: false
        )

        XCTAssertEqual(remoteProject.compactPath, "~")
        XCTAssertEqual(systemProject.compactPath, "/opt/talkie")
    }

    func testWatchProjectDirectorySurvivesColdCatalog() throws {
        let directory = try CodexLaneStore.resolveWatchProjectDirectory(
            requestedDirectory: "/Users/arach/dev/./talkie",
            projectAnchor: nil
        )

        XCTAssertEqual(directory, "/Users/arach/dev/talkie")
    }

    func testWatchProjectDirectoryMustMatchHydratedAnchor() {
        let anchor = task(id: "anchor", cwd: "/projects/talkie", updatedAt: 20)

        XCTAssertThrowsError(
            try CodexLaneStore.resolveWatchProjectDirectory(
                requestedDirectory: "/projects/openscout",
                projectAnchor: anchor
            )
        ) { error in
            XCTAssertEqual(error as? CodexDispatchError, .projectMismatch)
        }
    }

    func testWatchInboxRestoresSubmittedJobAfterColdRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WatchCodexPendingDispatchStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchCodexPendingDispatchStore(
            url: directory.appending(path: "pending-dispatches.json")
        )
        let requestID = UUID()
        let submitted = WatchCodexPendingDispatch(
            id: requestID,
            hostID: "mac-1",
            anchorTaskID: "anchor-task",
            projectDirectory: "/projects/talkie",
            taskTitle: "Continue Talkie",
            action: .continueTask,
            audioFilename: "\(requestID.uuidString).m4a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            stage: .submitted,
            transcript: "Continue the task.",
            jobID: "job-1",
            createdTaskID: "created-task",
            attemptCount: 1,
            lastError: "Phone suspended"
        )

        try store.save([submitted])
        let restored = try WatchCodexPendingDispatchStore(url: store.url).load()

        XCTAssertEqual(restored, [submitted])
        XCTAssertEqual(restored.first?.stage, .submitted)
        XCTAssertEqual(restored.first?.jobID, "job-1")
        XCTAssertEqual(restored.first?.createdTaskID, "created-task")
    }

    func testWatchInboxAtomicSaveReplacesPriorSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WatchCodexPendingDispatchStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchCodexPendingDispatchStore(
            url: directory.appending(path: "pending-dispatches.json")
        )
        let requestID = UUID()
        var dispatch = WatchCodexPendingDispatch(
            id: requestID,
            hostID: "mac-1",
            anchorTaskID: "anchor-task",
            projectDirectory: "/projects/talkie",
            taskTitle: "Continue Talkie",
            action: .continueTask,
            audioFilename: "\(requestID.uuidString).m4a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            stage: .received,
            transcript: nil,
            jobID: nil,
            createdTaskID: nil,
            attemptCount: 0,
            lastError: nil
        )
        try store.save([dispatch])

        dispatch.stage = .transcribed
        dispatch.transcript = "Ship it."
        dispatch.updatedAt = Date(timeIntervalSince1970: 200)
        try store.save([dispatch])

        XCTAssertEqual(try store.load(), [dispatch])
    }

    func testPhoneTurnInboxRestoresMacReceiptAfterColdRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CodexPendingTurnStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexPendingTurn.Store(
            url: directory.appending(path: "pending-phone-turns.json")
        )
        let submissionID = UUID()
        let task = task(id: "task-1", cwd: "/projects/talkie", updatedAt: 20)
        let receipt = CodexTurnJob(
            id: "job-1",
            submissionId: submissionID.uuidString,
            taskId: task.id,
            taskTitle: task.title,
            status: "running",
            mode: .queue,
            createdAt: "2026-07-30T23:00:00.000Z",
            updatedAt: "2026-07-30T23:00:01.000Z",
            turnId: "turn-1",
            delivery: CodexTurnDelivery.queuedTurn.rawValue,
            response: nil,
            updates: nil,
            error: nil,
            code: nil,
            hint: nil,
            retryable: nil,
            task: task
        )
        let pending = CodexPendingTurn(
            id: submissionID,
            hostID: "mac-1",
            task: task,
            instruction: "Keep going.",
            laneNumber: 2,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            job: receipt
        )

        try store.save([pending])
        let restored = try CodexPendingTurn.Store(url: store.url).load()

        XCTAssertEqual(restored, [pending])
        XCTAssertEqual(restored.first?.job.id, "job-1")
        XCTAssertEqual(restored.first?.job.status, "running")
        XCTAssertEqual(restored.first?.laneNumber, 2)
    }

    func testWatchIncomingHandoffPersistsBeforeMainActorAndDeduplicates() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "WatchCodexIncomingDispatchStoreTests-\(UUID().uuidString)")
        let audioDirectory = root.appending(path: "WatchAudio", directoryHint: .isDirectory)
        let incomingDirectory = root.appending(path: "Incoming", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var scheduledResumeCount = 0
        let store = WatchCodexIncomingDispatchStore(
            directoryURL: incomingDirectory,
            audioDirectoryURL: audioDirectory,
            onStaged: { scheduledResumeCount += 1 }
        )
        let requestID = UUID()
        let firstAudio = audioDirectory.appending(path: "first.m4a")
        try Data("first".utf8).write(to: firstAudio)
        let metadata: [String: Any] = [
            "requestID": requestID.uuidString,
            "hostID": "mac-1",
            "taskID": "anchor-task",
            "taskTitle": "Continue Talkie",
            "cwd": "/projects/talkie",
            "codexAction": "continue",
        ]

        let staged = try store.stage(audioURL: firstAudio, metadata: metadata)
        XCTAssertEqual(staged.id, requestID)
        XCTAssertEqual(staged.taskTitle, "Continue Talkie")
        XCTAssertEqual(staged.action, .continueTask)
        XCTAssertEqual(staged.audioFilename, "first.m4a")
        XCTAssertEqual(try store.load(), [staged])
        XCTAssertEqual(scheduledResumeCount, 1)

        let duplicateAudio = audioDirectory.appending(path: "duplicate.m4a")
        try Data("duplicate".utf8).write(to: duplicateAudio)
        let duplicate = try store.stage(audioURL: duplicateAudio, metadata: metadata)

        XCTAssertEqual(duplicate, staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateAudio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstAudio.path))
        XCTAssertEqual(try store.load(), [staged])
        XCTAssertEqual(scheduledResumeCount, 2)

        try store.remove(staged)
        XCTAssertEqual(try store.load(), [])
    }

    func testWatchIncomingHandoffDefaultsToContinueForLegacyPayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "WatchCodexIncomingDispatchStoreTests-\(UUID().uuidString)")
        let audioDirectory = root.appending(path: "WatchAudio", directoryHint: .isDirectory)
        let incomingDirectory = root.appending(path: "Incoming", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WatchCodexIncomingDispatchStore(
            directoryURL: incomingDirectory,
            audioDirectoryURL: audioDirectory
        )
        let requestID = UUID()
        let audioURL = audioDirectory.appending(path: "legacy.m4a")
        try Data("legacy".utf8).write(to: audioURL)

        let staged = try store.stage(
            audioURL: audioURL,
            metadata: [
                "requestID": requestID.uuidString,
                "hostID": "mac-1",
                "taskID": "existing-task",
                "taskTitle": "Existing task",
                "cwd": "/projects/talkie",
            ]
        )

        XCTAssertEqual(staged.action, .continueTask)
    }

    func testWatchIncomingHandoffCreatesOnlyForExplicitNewTaskAction() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "WatchCodexIncomingDispatchStoreTests-\(UUID().uuidString)")
        let audioDirectory = root.appending(path: "WatchAudio", directoryHint: .isDirectory)
        let incomingDirectory = root.appending(path: "Incoming", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WatchCodexIncomingDispatchStore(
            directoryURL: incomingDirectory,
            audioDirectoryURL: audioDirectory
        )
        let requestID = UUID()
        let audioURL = audioDirectory.appending(path: "new-task.m4a")
        try Data("new".utf8).write(to: audioURL)

        let staged = try store.stage(
            audioURL: audioURL,
            metadata: [
                "requestID": requestID.uuidString,
                "hostID": "mac-1",
                "taskID": "anchor-task",
                "taskTitle": "Anchor task",
                "cwd": "/projects/talkie",
                "codexAction": "new-task",
            ]
        )

        XCTAssertEqual(staged.action, .newTask)
    }

    private func task(
        id: String,
        cwd: String,
        updatedAt: Double
    ) -> CodexTaskSummary {
        CodexTaskSummary(
            id: id,
            title: "Task \(id)",
            preview: "",
            cwd: cwd,
            project: nil,
            updatedAt: updatedAt
        )
    }
}
