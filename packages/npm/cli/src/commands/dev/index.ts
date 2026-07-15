import type { Command } from "../../gunshi-command";
import { registerStatusCommand } from "./status";
import { registerCleanCommand } from "./clean";
import { registerStopCommand } from "./stop";
import { registerStartCommand } from "./start";
import { registerRestartCommand } from "./restart";
import { registerBuildCommand } from "./build";
import { registerRebuildCommand } from "./rebuild";
import { registerLogsCommand } from "./logs";
import { registerDbCommand } from "./db";
import { registerPerfCommand } from "./perf";
import { registerSimCommand } from "./sim";
import { registerSyncCommand } from "./sync";
import { registerFreshCommand } from "./fresh";
import { registerFlagsCommand } from "./flags";
import { registerWipeCommand } from "./wipe";

/** Hidden backwards-compat alias: `talkie-dev dev <cmd>` still works. */
export function registerDevCommand(program: Command): void {
  const devCmd = program
    .command("dev", { hidden: true })
    .description("Dev workflow tools (use top-level commands instead)");

  registerStatusCommand(devCmd);
  registerCleanCommand(devCmd);
  registerStopCommand(devCmd);
  registerStartCommand(devCmd);
  registerRestartCommand(devCmd);
  registerBuildCommand(devCmd);
  registerRebuildCommand(devCmd);
  registerLogsCommand(devCmd);
  registerDbCommand(devCmd);
  registerPerfCommand(devCmd);
  registerSimCommand(devCmd);
  registerSyncCommand(devCmd);
  registerFreshCommand(devCmd);
  registerFlagsCommand(devCmd);
  registerWipeCommand(devCmd);
}
