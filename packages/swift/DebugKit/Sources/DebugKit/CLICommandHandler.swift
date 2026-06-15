//
//  CLICommandHandler.swift
//  DebugKit
//
//  Generic headless CLI command handler
//  Usage: YourApp.app/Contents/MacOS/YourApp --debug=<command> [args...]
//

import Foundation

@MainActor
public class CLICommandHandler {
    public typealias CommandHandler = ([String]) async -> Void

    private var commands: [String: CommandHandler] = [:]
    private var commandDescriptions: [String: String] = [:]

    public init() {}

    /// Register a debug command
    public func register(
        _ command: String,
        description: String,
        handler: @escaping CommandHandler
    ) {
        commands[command] = handler
        commandDescriptions[command] = description
    }

    /// Check command line arguments and execute debug command if present
    /// Returns true if a debug command was executed (app should exit)
    public func handleCommandLineArguments() async -> Bool {
        DebugKitConsole.formatted("[CLICommandHandler] handleCommandLineArguments START")
        let args = CommandLine.arguments
        DebugKitConsole.formatted("[CLICommandHandler] Args count: %d", args.count)

        // Look for --debug=<command>
        DebugKitConsole.formatted("[CLICommandHandler] Looking for debug arg...")
        guard let debugArg = args.first(where: { $0.hasPrefix("--debug=") }) else {
            DebugKitConsole.formatted("[CLICommandHandler] No debug arg found")
            return false
        }
        DebugKitConsole.formatted("[CLICommandHandler] Found debug arg: %@", debugArg)

        let command = String(debugArg.dropFirst("--debug=".count))
        DebugKitConsole.formatted("[CLICommandHandler] Parsed command: %@", command)

        // Get additional arguments (everything after the --debug flag)
        let additionalArgs = args.dropFirst(args.firstIndex(of: debugArg)! + 1)
        DebugKitConsole.formatted("[CLICommandHandler] Additional args: %@", Array(additionalArgs).joined(separator: ", "))

        DebugKitConsole.formatted("[CLICommandHandler] Executing command: %@", command)
        await executeCommand(command, args: Array(additionalArgs))
        DebugKitConsole.formatted("[CLICommandHandler] Command execution finished")
        return true
    }

    private func executeCommand(_ command: String, args: [String]) async {
        DebugKitConsole.formatted("[CLICommandHandler] executeCommand: %@", command)

        if command == "help" {
            printHelp()
            exit(0)
            return
        }

        DebugKitConsole.formatted("[CLICommandHandler] Looking for handler in %d registered commands", commands.count)
        guard let handler = commands[command] else {
            DebugKitConsole.formatted("[CLICommandHandler] ❌ Unknown command: %@", command)
            DebugKitConsole.info("❌ Unknown debug command: \(command)")
            DebugKitConsole.info("")
            printHelp()
            exit(1)
            return
        }

        DebugKitConsole.formatted("[CLICommandHandler] Found handler, calling it...")
        await handler(args)
        DebugKitConsole.formatted("[CLICommandHandler] Handler completed")
    }

    private func printHelp() {
        DebugKitConsole.info("""
        Debug Commands
        ==============

        Usage: YourApp.app/Contents/MacOS/YourApp --debug=<command> [args...]

        Available Commands:

        """)

        let sortedCommands = commands.keys.sorted()
        for command in sortedCommands {
            if let description = commandDescriptions[command] {
                DebugKitConsole.info("  \(command)")
                DebugKitConsole.info("      \(description)")
                DebugKitConsole.info("")
            }
        }

        DebugKitConsole.info("""
          help
              Show this help message

        """)
    }
}
