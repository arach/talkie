#!/usr/bin/env bun

import { createProgram } from "./cli";
import { registerDevCommand } from "./commands/dev";
import { registerStatusCommand } from "./commands/dev/status";
import { registerCleanCommand } from "./commands/dev/clean";
import { registerStopCommand } from "./commands/dev/stop";
import { registerStartCommand } from "./commands/dev/start";
import { registerRestartCommand } from "./commands/dev/restart";
import { registerBuildCommand } from "./commands/dev/build";
import { registerRebuildCommand } from "./commands/dev/rebuild";
import { registerLogsCommand } from "./commands/dev/logs";
import { registerDbCommand } from "./commands/dev/db";
import { registerPerfCommand } from "./commands/dev/perf";
import { registerSimCommand } from "./commands/dev/sim";
import { registerSyncCommand as registerIncrementalCommand } from "./commands/dev/sync";
import { registerFreshCommand } from "./commands/dev/fresh";
import { registerFlagsCommand } from "./commands/dev/flags";
import { registerBootoutCommand } from "./commands/dev/bootout";
import { registerWipeCommand } from "./commands/dev/wipe";

const program = createProgram();
program.name("talkie-dev");
program.description(
  "Dev workflow tools for Talkie services.\n\n" +
  "Manages the lifecycle of Talkie, TalkieAgent, and TalkieRunner.\n" +
  "Covers building, launching, stopping, restarting, log tailing, DerivedData cleanup,\n" +
  "and database inspection.\n\n" +
  "Quick start:\n" +
  "  talkie-dev status              Show what's running and build state\n" +
  "  talkie-dev rebuild agent       Build + restart TalkieAgent\n" +
  "  talkie-dev logs agent          Tail TalkieAgent logs\n" +
  "  talkie-dev clean --dry-run     Preview stale DerivedData cleanup"
);

// Top-level dev commands (the primary interface)
registerStatusCommand(program);
registerCleanCommand(program);
registerStopCommand(program);
registerStartCommand(program);
registerRestartCommand(program);
registerBuildCommand(program);
registerRebuildCommand(program);
registerLogsCommand(program);
registerDbCommand(program);
registerPerfCommand(program);
registerSimCommand(program);
registerIncrementalCommand(program);
registerFreshCommand(program);
registerFlagsCommand(program);
registerBootoutCommand(program);
registerWipeCommand(program);

// Hidden `dev` subgroup for backwards compat
registerDevCommand(program);

await program.parse();
