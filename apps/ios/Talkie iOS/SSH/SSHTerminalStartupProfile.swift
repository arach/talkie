//
//  SSHTerminalStartupProfile.swift
//  Talkie iOS
//
//  Connection-level startup modes for the SSH terminal.
//

import Foundation

enum SSHTerminalStartupProfile: String, Codable, CaseIterable, Sendable {
    case standardShell = "standardShell"
    case talkieShell = "cleanShell"
    case talkieSession = "persistentContext"

    var title: String {
        switch self {
        case .standardShell:
            "Native"
        case .talkieShell:
            "T Shell"
        case .talkieSession:
            "Tmux"
        }
    }

    var shortTitle: String {
        switch self {
        case .standardShell:
            "Native"
        case .talkieShell:
            "T Shell"
        case .talkieSession:
            "Tmux"
        }
    }

    var summary: String {
        switch self {
        case .standardShell:
            "Uses the host's native login shell. Best for cloud boxes, random SSH hosts, or any machine Talkie does not manage."
        case .talkieShell:
            "Starts Talkie's managed shell without tmux. Best when you want Talkie's setup in a fresh shell."
        case .talkieSession:
            "Attaches to Talkie's persistent tmux session so your shell and tools survive reconnects."
        }
    }

    var startupCommand: String {
        switch self {
        case .standardShell:
            ""
        case .talkieShell:
            Self.cleanShellCommand
        case .talkieSession:
            Self.persistentContextCommand
        }
    }

    static func pairedHomeLauncherCommand() -> String {
        remoteHelperCommand(
            helperName: "talkie-enter",
            fallbackMessage: "[Talkie] Remote entry helper is missing on this Mac. Opening a plain shell."
        )
    }

    static func nativeLauncherCommand() -> String {
        nativePersistentShellCommand
    }

    static func bridgeLogTailCommand() -> String {
        #"""
/bin/zsh -lc 'export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
clear;
printf "[Talkie] Bridge + agent log tail\n";
printf "Press Ctrl-C to stop.\n\n";
today="$(date +%F)";
log_candidates=(
  "/tmp/talkie-bridge-hyper-scan.log"
  "/tmp/talkie-bridge-dev.log"
  "/tmp/talkie-bridge.log"
  "$HOME/Library/Logs/TalkieBridge/bridge-dev.log"
  "$HOME/Library/Logs/TalkieBridge/bridge.log"
  "$HOME/Library/Application Support/Talkie/Bridge/bridge.log"
  "$HOME/Library/Application Support/Talkie/Bridge/bridge.dev.log"
  "$HOME/Library/Application Support/Talkie/logs/talkie-$today.log"
  "$HOME/Library/Application Support/TalkieAgent/logs/talkie-$today.log"
  "/tmp/talkie-agent-debug.log"
  "/tmp/to.talkie.app.agent.dev.stdout.log"
  "/tmp/to.talkie.app.agent.dev.stderr.log"
  "/tmp/to.talkie.app.agent.xpc.dev.stdout.log"
  "/tmp/to.talkie.app.agent.xpc.dev.stderr.log"
);
existing=();
for file in "${log_candidates[@]}"; do
  [[ -f "$file" ]] && existing+=("$file");
done;
if (( ${#existing[@]} > 0 )); then
  printf "Tailing logs:\n";
  printf "  %s\n" "${existing[@]}";
  printf "\n";
  exec tail -n 80 -F "${existing[@]}";
fi;
printf "No Talkie bridge or agent log found yet.\nChecked:\n";
printf "  %s\n" "${log_candidates[@]}";
printf "\nWaiting for a bridge log to appear...\n";
while true; do
  for file in "${log_candidates[@]}"; do
    if [[ -f "$file" ]]; then
      printf "\nTailing logs from first available file: %s\n\n" "$file";
      exec tail -n 120 -F "$file";
    fi;
  done;
  sleep 2;
done'
"""#
    }

    static func normalizedStartupCommandOverride(
        _ command: String?,
        for profile: SSHTerminalStartupProfile
    ) -> String? {
        let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCommand.isEmpty else {
            return nil
        }

        if currentDefaultCommands(for: profile).contains(trimmedCommand) {
            return nil
        }

        if isLegacyHelperWrapper(trimmedCommand, for: profile) {
            return nil
        }

        if isPairedHomeLauncherCommand(trimmedCommand) {
            return nil
        }

        if isNativeLauncherCommand(trimmedCommand) {
            return nil
        }

        if isLegacyRawStartupScript(trimmedCommand) {
            return nil
        }

        return trimmedCommand
    }

    static func inferredProfile(from command: String) -> SSHTerminalStartupProfile {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand.isEmpty {
            return .standardShell
        }

        if currentDefaultCommands(for: .standardShell).contains(trimmedCommand) {
            return .standardShell
        }

        if currentDefaultCommands(for: .talkieShell).contains(trimmedCommand) {
            return .talkieShell
        }

        if trimmedCommand == pairedHomeLauncherCommand().trimmingCharacters(in: .whitespacesAndNewlines) {
            return .talkieShell
        }

        if isNativeLauncherCommand(trimmedCommand) {
            return .standardShell
        }

        if isLegacyHelperWrapper(trimmedCommand, for: .talkieShell) {
            return .talkieShell
        }

        if isLegacyCleanShellCommand(trimmedCommand) {
            return .talkieShell
        }

        if currentDefaultCommands(for: .talkieSession).contains(trimmedCommand)
            || isLegacyHelperWrapper(trimmedCommand, for: .talkieSession) {
            return .talkieSession
        }

        return .standardShell
    }

    private static var cleanShellCommand: String {
        remoteHelperCommand(
            helperName: "talkie-shell",
            fallbackMessage: "[Talkie] Talkie shell helper is missing on this Mac. Opening a plain shell."
        )
    }

    private static var persistentContextCommand: String {
        remoteHelperCommand(
            helperName: "talkie-session",
            fallbackMessage: "[Talkie] Talkie session helper is missing on this Mac. Opening a plain shell."
        )
    }

    private static var legacyCleanShellCommand: String {
        remoteHelperCommand(
            helperName: "talkie-clean",
            fallbackMessage: "[Talkie] Talkie shell helper is missing on this Mac. Opening a plain shell."
        )
    }

    private static var legacyPersistentContextCommand: String {
        remoteHelperCommand(
            helperName: "talkie-context",
            fallbackMessage: "[Talkie] Talkie session helper is missing on this Mac. Opening a plain shell."
        )
    }

    private static var nativePersistentShellCommand: String {
        #"""
/bin/zsh -fc 'export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"; SESSION_NAME="${TALKIE_NATIVE_SESSION:-talkie-native-${TALKIE_SURFACE:-phone}}"; SHELL_BIN="${SHELL:-}"; if [[ -z "$SHELL_BIN" || ! -x "$SHELL_BIN" ]]; then SHELL_BIN="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | sed "s/^UserShell: //")"; fi; if [[ -z "$SHELL_BIN" || ! -x "$SHELL_BIN" ]]; then SHELL_BIN="$(command -v zsh || printf /bin/zsh)"; fi; TMUX_BIN="$(command -v tmux || true)"; if [[ -n "$TMUX_BIN" ]]; then TMUX_SHELL_COMMAND="exec \"$SHELL_BIN\" -il"; "$TMUX_BIN" has-session -t "$SESSION_NAME" 2>/dev/null || "$TMUX_BIN" new-session -d -s "$SESSION_NAME" -c "$HOME" "$TMUX_SHELL_COMMAND"; "$TMUX_BIN" set-option -t "$SESSION_NAME" status off >/dev/null 2>&1 || true; exec "$TMUX_BIN" attach -t "$SESSION_NAME"; fi; exec "$SHELL_BIN" -il'
"""#
    }

    private static func remoteHelperCommand(helperName: String, fallbackMessage: String) -> String {
        let escapedFallbackMessage = fallbackMessage
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")

        return #"""
/bin/zsh -fc 'export PATH="$HOME/.talkie-shell/bin:$HOME/.talkie-shell/runtime/bin:$HOME/bin:$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"; helper="$HOME/.talkie-shell/bin/\#(helperName)"; if [[ -x "$helper" ]]; then exec "$helper"; fi; printf "\r\n\#(escapedFallbackMessage)\r\n"; export PROMPT="${PROMPT:-%n@%m:%~ %# }"; cd "$HOME" 2>/dev/null || true; exec "$(command -v zsh || printf /bin/zsh)" -f -i'
"""#
    }

    private static func isLegacyCleanShellCommand(_ command: String) -> Bool {
        isLegacyRawStartupScript(command) && !command.contains(#"TMUX_BIN="$(command -v tmux || true)""#)
    }

    private static func isLegacyHelperWrapper(
        _ command: String,
        for profile: SSHTerminalStartupProfile
    ) -> Bool {
        let helperNames: [String]
        switch profile {
        case .standardShell:
            helperNames = []
        case .talkieShell:
            helperNames = ["talkie-shell", "talkie-clean"]
        case .talkieSession:
            helperNames = ["talkie-session", "talkie-context", "talkie-enter"]
        }

        return helperNames.contains { helperName in
            command.contains(#"HELPER="$HOME/.talkie-shell/bin/\#(helperName)";"#)
                && command.contains(#"exec "$HELPER";"#)
        }
    }

    private static func currentDefaultCommands(for profile: SSHTerminalStartupProfile) -> Set<String> {
        let commands: [String]
        switch profile {
        case .standardShell:
            commands = [""]
        case .talkieShell:
            commands = [
                cleanShellCommand,
                legacyCleanShellCommand,
            ]
        case .talkieSession:
            commands = [
                persistentContextCommand,
                legacyPersistentContextCommand,
            ]
        }

        return commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .reduce(into: Set<String>()) { result, value in
            result.insert(value)
            }
    }

    private static func isPairedHomeLauncherCommand(_ command: String) -> Bool {
        command.contains(#"helper="$HOME/.talkie-shell/bin/talkie-enter""#)
            || command.contains(#"HELPER="$HOME/.talkie-shell/bin/talkie-enter""#)
    }

    private static func isNativeLauncherCommand(_ command: String) -> Bool {
        command.contains("TALKIE_NATIVE_SESSION")
            || command.contains("talkie-native-${TALKIE_SURFACE:-phone}")
    }

    private static func isLegacyRawStartupScript(_ command: String) -> Bool {
        command.contains(#"cat > "$TALKIE_ZDOTDIR/.zshenv" <<'EOF'"#)
            || command.contains(#"cat > "$TALKIE_ZDOTDIR/.zshrc" <<'EOF'"#)
            || command.contains(#"export TALKIE_ZDOTDIR="$HOME/.talkie-shell";"#)
            || command.contains(#"_talkie_script="$(printf '%s'"#)
            || command.contains(#"base64 -D 2>/dev/null || base64 -d 2>/dev/null"#)
    }
}
