//
//  TalkieHelperRuntimeState.swift
//  TalkieKit
//
//  File-backed helper runtime identity stored in Application Support so the
//  main app can validate helper liveness against a concrete process identity.
//

import Foundation

public struct TalkieHelperRuntimeState: Codable, Sendable {
    public let helper: String
    public let bundleId: String
    public let processId: Int32
    public let startedAt: Date
    public let executablePath: String?
    public let updatedAt: Date

    public init(
        helper: String,
        bundleId: String,
        processId: Int32,
        startedAt: Date,
        executablePath: String?,
        updatedAt: Date = Date()
    ) {
        self.helper = helper
        self.bundleId = bundleId
        self.processId = processId
        self.startedAt = startedAt
        self.executablePath = executablePath
        self.updatedAt = updatedAt
    }
}

public enum TalkieHelperRuntimeStateStore {
    public static func statusURL(
        for helper: TalkieHelper,
        environment: TalkieEnvironment = .current
    ) -> URL {
        environment.appSupportDirectory
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: "\(helper.rawValue).json")
    }

    public static func writeCurrentProcess(
        for helper: TalkieHelper,
        environment: TalkieEnvironment = .current,
        processId: pid_t = ProcessInfo.processInfo.processIdentifier,
        executablePath: String? = Bundle.main.executableURL?.path
    ) throws {
        let startedAt = talkieProcessStartTime(pid: processId) ?? Date()
        let state = TalkieHelperRuntimeState(
            helper: helper.rawValue,
            bundleId: helper.bundleId(for: environment),
            processId: processId,
            startedAt: startedAt,
            executablePath: executablePath
        )

        let url = statusURL(for: helper, environment: environment)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    public static func clear(
        for helper: TalkieHelper,
        environment: TalkieEnvironment = .current
    ) {
        let url = statusURL(for: helper, environment: environment)
        try? FileManager.default.removeItem(at: url)
    }

    public static func validatedState(
        for helper: TalkieHelper,
        environment: TalkieEnvironment = .current
    ) -> TalkieHelperRuntimeState? {
        let url = statusURL(for: helper, environment: environment)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let state = try? decoder.decode(TalkieHelperRuntimeState.self, from: data),
              state.helper == helper.rawValue,
              state.bundleId == helper.bundleId(for: environment),
              talkieProcessExists(pid: state.processId) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        guard let actualStart = talkieProcessStartTime(pid: state.processId),
              abs(actualStart.timeIntervalSince(state.startedAt)) < 1 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return state
    }
}

public func talkieProcessExists(pid: pid_t) -> Bool {
    guard pid > 0 else { return false }
    if Darwin.kill(pid, 0) == 0 {
        return true
    }

    return errno == EPERM
}

public func talkieProcessStartTime(pid: pid_t) -> Date? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
        return nil
    }

    let tv = info.kp_proc.p_starttime
    return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
}
