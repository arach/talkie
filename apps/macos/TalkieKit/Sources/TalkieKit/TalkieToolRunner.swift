import Foundation

public struct TalkieToolRunner {
    public struct Result: Equatable, Sendable {
        public var output: TalkieTool.Output
        public var stdout: String
        public var stderr: String
        public var exitCode: Int32

        public init(
            output: TalkieTool.Output,
            stdout: String,
            stderr: String,
            exitCode: Int32
        ) {
            self.output = output
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }
    }

    public enum Error: LocalizedError, Equatable, Sendable {
        case missingEntry(URL)
        case timedOut(toolID: String, timeoutMs: Int)
        case nonZeroExit(toolID: String, status: Int32, stderr: String)
        case invalidUTF8(toolID: String, stream: String)
        case invalidOutput(toolID: String, details: String)

        public var errorDescription: String? {
            switch self {
            case .missingEntry(let url):
                return "Tool entry `\(url.path(percentEncoded: false))` does not exist."
            case .timedOut(let toolID, let timeoutMs):
                return "Tool `\(toolID)` timed out after \(timeoutMs)ms."
            case .nonZeroExit(let toolID, let status, let stderr):
                if stderr.isEmpty {
                    return "Tool `\(toolID)` exited with status \(status)."
                }

                return "Tool `\(toolID)` exited with status \(status): \(stderr)"
            case .invalidUTF8(let toolID, let stream):
                return "Tool `\(toolID)` produced invalid UTF-8 on \(stream)."
            case .invalidOutput(let toolID, let details):
                return "Tool `\(toolID)` returned invalid JSON output: \(details)"
            }
        }
    }

    public init() {}

    @concurrent
    public func run(
        manifest: TalkieToolManifest,
        in directoryURL: URL,
        input: TalkieTool.Input
    ) async throws -> Result {
        try manifest.validate()

        let invocation = try resolveInvocation(for: manifest, in: directoryURL)
        let process = Process()
        let processBox = ProcessBox(process: process)
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = directoryURL

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task { try await collectOutput(from: stdoutPipe.fileHandleForReading) }
        let stderrTask = Task { try await collectOutput(from: stderrPipe.fileHandleForReading) }

        do {
            try process.run()
        } catch {
            stdoutTask.cancel()
            stderrTask.cancel()
            throw error
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let inputData = try encoder.encode(input)
            try stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            process.terminate()
            stdoutTask.cancel()
            stderrTask.cancel()
            throw error
        }

        let exitCode = try await awaitTermination(
            of: processBox,
            toolID: manifest.id,
            timeoutMs: manifest.timeoutMs
        )

        let stdoutData = try await stdoutTask.value
        let stderrData = try await stderrTask.value
        let stdout = try string(from: stdoutData, toolID: manifest.id, stream: "stdout")
        let stderr = try string(from: stderrData, toolID: manifest.id, stream: "stderr")

        guard exitCode == 0 else {
            throw Error.nonZeroExit(toolID: manifest.id, status: exitCode, stderr: stderr)
        }

        let decoder = JSONDecoder()

        do {
            let output = try decoder.decode(TalkieTool.Output.self, from: stdoutData)
            return Result(
                output: output,
                stdout: stdout,
                stderr: stderr,
                exitCode: exitCode
            )
        } catch {
            let details = stdout.isEmpty ? error.localizedDescription : stdout
            throw Error.invalidOutput(toolID: manifest.id, details: details)
        }
    }
}

private extension TalkieToolRunner {
    struct Invocation: Sendable {
        var executableURL: URL
        var arguments: [String]
    }

    final class ProcessBox: @unchecked Sendable {
        let process: Process

        init(process: Process) {
            self.process = process
        }
    }

    func resolveInvocation(for manifest: TalkieToolManifest, in directoryURL: URL) throws -> Invocation {
        let entryURL: URL
        if manifest.entry.hasPrefix("/") {
            entryURL = URL(fileURLWithPath: manifest.entry)
        } else {
            entryURL = directoryURL.appending(path: manifest.entry)
        }

        guard FileManager.default.fileExists(atPath: entryURL.path(percentEncoded: false)) else {
            throw Error.missingEntry(entryURL)
        }

        switch manifest.runtime {
        case .node:
            return Invocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["node", entryURL.path(percentEncoded: false)]
            )
        case .python:
            return Invocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", entryURL.path(percentEncoded: false)]
            )
        case .shell:
            return Invocation(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [entryURL.path(percentEncoded: false)]
            )
        case .binary:
            return Invocation(
                executableURL: entryURL,
                arguments: []
            )
        }
    }

    func awaitTermination(
        of processBox: ProcessBox,
        toolID: String,
        timeoutMs: Int
    ) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    processBox.process.terminationHandler = { process in
                        continuation.resume(returning: process.terminationStatus)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .milliseconds(timeoutMs))
                if processBox.process.isRunning {
                    processBox.process.terminate()
                }

                throw Error.timedOut(toolID: toolID, timeoutMs: timeoutMs)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw Error.invalidOutput(toolID: toolID, details: "Process ended without a termination result.")
            }

            return result
        }
    }

    func collectOutput(from handle: FileHandle) async throws -> Data {
        var data = Data()

        for try await byte in handle.bytes {
            data.append(byte)
        }

        return data
    }

    func string(from data: Data, toolID: String, stream: String) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw Error.invalidUTF8(toolID: toolID, stream: stream)
        }

        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
