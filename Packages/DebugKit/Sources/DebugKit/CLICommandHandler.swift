//
//  CLICommandHandler.swift
//  DebugKit
//
//  Generic headless CLI command handler
//  Usage: YourApp.app/Contents/MacOS/YourApp --debug=<command> [args...]
//

import Foundation

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
        let args = CommandLine.arguments

        // Look for --debug=<command>
        guard let debugArg = args.first(where: { $0.hasPrefix("--debug=") }) else {
            return false
        }

        let command = String(debugArg.dropFirst("--debug=".count))

        // Get additional arguments (everything after the --debug flag)
        let additionalArgs = args.dropFirst(args.firstIndex(of: debugArg)! + 1)

        print("🐛 Debug command: \(command)")

        await executeCommand(command, args: Array(additionalArgs))
        return true
    }

    private func executeCommand(_ command: String, args: [String]) async {
        if command == "help" {
            printHelp()
            exit(0)
            return
        }

        guard let handler = commands[command] else {
            print("❌ Unknown debug command: \(command)")
            print("")
            printHelp()
            exit(1)
            return
        }

        await handler(args)
    }

    private func printHelp() {
        print("""
        Debug Commands
        ==============

        Usage: YourApp.app/Contents/MacOS/YourApp --debug=<command> [args...]

        Available Commands:

        """)

        let sortedCommands = commands.keys.sorted()
        for command in sortedCommands {
            if let description = commandDescriptions[command] {
                print("  \(command)")
                print("      \(description)")
                print("")
            }
        }

        print("""
          help
              Show this help message

        """)
    }
}
