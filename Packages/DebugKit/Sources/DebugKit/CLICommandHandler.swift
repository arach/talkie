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
        NSLog("[CLICommandHandler] handleCommandLineArguments START")
        let args = CommandLine.arguments
        NSLog("[CLICommandHandler] Args count: %d", args.count)

        // Look for --debug=<command>
        NSLog("[CLICommandHandler] Looking for debug arg...")
        guard let debugArg = args.first(where: { $0.hasPrefix("--debug=") }) else {
            NSLog("[CLICommandHandler] No debug arg found")
            return false
        }
        NSLog("[CLICommandHandler] Found debug arg: %@", debugArg)

        let command = String(debugArg.dropFirst("--debug=".count))
        NSLog("[CLICommandHandler] Parsed command: %@", command)

        // Get additional arguments (everything after the --debug flag)
        let additionalArgs = args.dropFirst(args.firstIndex(of: debugArg)! + 1)
        NSLog("[CLICommandHandler] Additional args: %@", Array(additionalArgs).joined(separator: ", "))

        NSLog("[CLICommandHandler] Executing command: %@", command)
        await executeCommand(command, args: Array(additionalArgs))
        NSLog("[CLICommandHandler] Command execution finished")
        return true
    }

    private func executeCommand(_ command: String, args: [String]) async {
        NSLog("[CLICommandHandler] executeCommand: %@", command)

        if command == "help" {
            printHelp()
            exit(0)
            return
        }

        NSLog("[CLICommandHandler] Looking for handler in %d registered commands", commands.count)
        guard let handler = commands[command] else {
            NSLog("[CLICommandHandler] ❌ Unknown command: %@", command)
            print("❌ Unknown debug command: \(command)")
            print("")
            printHelp()
            exit(1)
            return
        }

        NSLog("[CLICommandHandler] Found handler, calling it...")
        await handler(args)
        NSLog("[CLICommandHandler] Handler completed")
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
