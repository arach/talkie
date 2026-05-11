import { Command } from "commander";
import { closeDb } from "./db";
import { registerMemosCommand } from "./commands/memos";
import { registerDictationsCommand } from "./commands/dictations";
import { registerSearchCommand } from "./commands/search";
import { registerWorkflowsCommand } from "./commands/workflows";
import { registerStatsCommand } from "./commands/stats";
import { registerInstallCommand } from "./commands/install";
import { registerSyncCommand } from "./commands/sync";
import { registerDataCommand } from "./commands/data";
import { registerAppCommand } from "./commands/app";
import { registerTerminalCommand } from "./commands/terminal";

export function createProgram(): Command {
  const program = new Command();

  program
    .name("talkie")
    .description(
      `Voice-first productivity for macOS

  Query your voice memos, dictations, and workflows from the terminal.
  Requires Talkie.app — install it with: talkie install

  Quick start:
    talkie open               open Talkie.app
    talkie doctor             check app, CLI, and companion setup
    talkie companion          show App Store QR for iPhone/iPad
    talkie pair               show Mac Bridge pairing QR (iOS app companion)
    talkie terminal pair      add iOS SSH terminal access (--ios-only)
    talkie memos              list recent voice memos
    talkie search <query>     full-text search across everything
    talkie stats              usage overview
    talkie install            download & install Talkie.app
    talkie upgrade            check for & install app updates`
    )
    .version("0.4.3")
    .option("--db <path>", "override database path")
    .option("--json", "force JSON output (default when piped)")
    .option("--pretty", "force human-readable output (default in terminal)");

  registerMemosCommand(program);
  registerDictationsCommand(program);
  registerSearchCommand(program);
  registerWorkflowsCommand(program);
  registerStatsCommand(program);
  registerInstallCommand(program);
  registerSyncCommand(program);
  registerDataCommand(program);
  registerAppCommand(program);
  registerTerminalCommand(program);

  program.hook("postAction", () => closeDb());

  return program;
}
