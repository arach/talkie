import type { Command } from "../../gunshi-command";

/** Hidden alias: `fresh` delegates to `rebuild --clean`. */
export function registerFreshCommand(parent: Command): void {
  parent
    .command("fresh [service]", { hidden: true })
    .description("Alias for `rebuild --clean`")
    .action((serviceName: string | undefined, _, cmd) => {
      const args = ["rebuild"];
      if (serviceName) args.push(serviceName);
      args.push("--clean");
      cmd.parent?.parse(["node", "talkie-dev", ...args]);
    });
}
