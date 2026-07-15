import {
  cli,
  define,
  type ArgSchema,
  type Command as GunshiCommand,
  type CommandContext,
  type SubCommandable,
} from "gunshi";

type ActionHandler = (...args: any[]) => unknown;
type HookHandler = () => unknown;

interface CommandOptions {
  hidden?: boolean;
}

interface OptionDefinition {
  key: string;
  schema: ArgSchema;
  takesValue: boolean;
  optionalValueDefault?: string;
}

interface PositionalDefinition {
  key: string;
  required: boolean;
}

interface ParsedOption {
  key: string;
  schema: ArgSchema;
  takesValue: boolean;
  optionalValueDefault?: string;
}

const BUILTIN_PRINTED_ERROR_NAMES = new Set([
  "AggregateError",
  "ArgsValidationError",
  "CommandNotFoundError",
]);

export class Command {
  public parent?: Command;

  private commandName?: string;
  private commandDescription?: string;
  private commandVersion?: string;
  private hidden = false;
  private readonly optionDefinitions: OptionDefinition[] = [];
  private readonly positionalDefinitions: PositionalDefinition[] = [];
  private readonly childCommands = new Map<string, Command>();
  private actionHandler?: ActionHandler;
  private readonly postActionHooks: HookHandler[] = [];
  private lastOptions: Record<string, unknown> = {};

  constructor(spec?: string, options: CommandOptions = {}) {
    if (spec) {
      const parsed = parseCommandSpec(spec);
      this.commandName = parsed.name;
      this.positionalDefinitions.push(...parsed.positionals);
    }
    this.hidden = options.hidden ?? false;
  }

  name(): string | undefined;
  name(value: string): this;
  name(value?: string): string | undefined | this {
    if (value === undefined) return this.commandName;
    this.commandName = value;
    return this;
  }

  description(value: string): this {
    this.commandDescription = value;
    return this;
  }

  version(value: string): this {
    this.commandVersion = value;
    return this;
  }

  option(flags: string, description?: string): this;
  option<T>(
    flags: string,
    description: string,
    parser: (value: string) => T,
    defaultValue?: T
  ): this;
  option(flags: string, description: string, defaultValue: string | boolean | number): this;
  option(
    flags: string,
    description?: string,
    parserOrDefault?: ((value: string) => unknown) | unknown,
    defaultValue?: unknown
  ): this {
    this.optionDefinitions.push(parseOption(flags, description, parserOrDefault, defaultValue));
    return this;
  }

  command(spec: string, options: CommandOptions = {}): Command {
    const command = new Command(spec, options);
    command.parent = this;
    if (!command.commandName) {
      throw new Error(`Invalid command spec: ${spec}`);
    }
    this.childCommands.set(command.commandName, command);
    return command;
  }

  alias(name: string): this {
    if (!this.parent) return this;
    this.parent.childCommands.set(name, this);
    return this;
  }

  aliases(names: string[]): this {
    for (const name of names) this.alias(name);
    return this;
  }

  action(handler: ActionHandler): this {
    this.actionHandler = handler;
    return this;
  }

  hook(name: "postAction", handler: HookHandler): this {
    if (name === "postAction") {
      this.root().postActionHooks.push(handler);
    }
    return this;
  }

  opts(): Record<string, any> {
    return { ...this.lastOptions };
  }

  optsWithGlobals(): Record<string, any> {
    const chain: Command[] = [];
    let current: Command | undefined = this;
    while (current) {
      chain.push(current);
      current = current.parent;
    }

    return chain
      .reverse()
      .reduce<Record<string, unknown>>((result, command) => {
        Object.assign(result, command.lastOptions);
        return result;
      }, {});
  }

  async parse(argv: string[] = process.argv.slice(2)): Promise<void> {
    const normalizedArgv = normalizeArgv(argv, this.collectOptionValueSettings());
    const rootCommand = this.toGunshiCommand();
    const subCommands = this.toGunshiSubCommands();

    try {
      await cli(normalizedArgv, rootCommand, {
        name: this.commandName,
        version: this.commandVersion,
        description: this.commandDescription,
        subCommands,
        strict: true,
        renderHeader: null,
        onAfterCommand: async () => {
          await this.runPostActionHooks();
        },
        onErrorCommand: async () => {
          await this.runPostActionHooks();
        },
      });
    } catch (error) {
      if (!isGunshiPrintedError(error)) {
        console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
      }
      process.exitCode = 1;
    }
  }

  private toGunshiCommand(nameOverride?: string): GunshiCommand {
    const command = define({
      name: nameOverride ?? this.commandName,
      description: this.commandDescription,
      args: this.gunshiArgs(),
      internal: this.hidden,
      run: this.actionHandler
        ? async (ctx: Readonly<CommandContext>) => {
            await this.invokeAction(ctx);
          }
        : undefined,
      subCommands: this.childCommands.size > 0 ? this.toGunshiSubCommands() : undefined,
    });

    return command as GunshiCommand;
  }

  private toGunshiSubCommands(): Map<string, SubCommandable> | undefined {
    if (this.childCommands.size === 0) return undefined;

    const subCommands = new Map<string, SubCommandable>();
    for (const [name, command] of this.childCommands) {
      subCommands.set(name, command.toGunshiCommand(name));
    }
    return subCommands;
  }

  private gunshiArgs(): Record<string, ArgSchema> {
    const args: Record<string, ArgSchema> = {};

    for (const option of this.root().optionDefinitions) {
      args[option.key] = option.schema;
    }
    for (const option of this.optionDefinitions) {
      args[option.key] = option.schema;
    }
    for (const positional of this.positionalDefinitions) {
      args[positional.key] = {
        type: "positional",
        required: positional.required,
      };
    }

    return args;
  }

  private async invokeAction(ctx: Readonly<CommandContext>): Promise<void> {
    const values = ctx.values as Record<string, unknown>;
    const chain = this.ancestorChain();

    for (const command of chain) {
      command.lastOptions = pickOptionValues(values, command.optionDefinitions);
    }

    const localOptions = this.lastOptions;
    const positionals = this.positionalDefinitions.map((positional) => values[positional.key]);

    if (this.positionalDefinitions.length > 0) {
      await this.actionHandler?.(...positionals, localOptions, this);
    } else {
      await this.actionHandler?.(localOptions, this);
    }
  }

  private ancestorChain(): Command[] {
    const chain: Command[] = [];
    let current: Command | undefined = this;
    while (current) {
      chain.push(current);
      current = current.parent;
    }
    return chain.reverse();
  }

  private root(): Command {
    let current: Command = this;
    while (current.parent) current = current.parent;
    return current;
  }

  private async runPostActionHooks(): Promise<void> {
    for (const hook of this.postActionHooks) {
      await hook();
    }
  }

  private collectOptionValueSettings(): Map<string, { takesValue: boolean; optionalValueDefault?: string }> {
    const options = new Map<string, { takesValue: boolean; optionalValueDefault?: string }>();
    this.collectOptionValueSettingsInto(options);
    return options;
  }

  private collectOptionValueSettingsInto(
    options: Map<string, { takesValue: boolean; optionalValueDefault?: string }>
  ): void {
    for (const option of this.optionDefinitions) {
      if (option.takesValue) {
        options.set(`--${kebabCase(option.key)}`, {
          takesValue: true,
          optionalValueDefault: option.optionalValueDefault,
        });
        if (option.schema.short) {
          options.set(`-${option.schema.short}`, {
            takesValue: true,
            optionalValueDefault: option.optionalValueDefault,
          });
        }
      }
    }
    for (const command of new Set(this.childCommands.values())) {
      command.collectOptionValueSettingsInto(options);
    }
  }
}

function parseCommandSpec(spec: string): { name: string; positionals: PositionalDefinition[] } {
  const tokens = spec.trim().split(/\s+/).filter(Boolean);
  const [name, ...rest] = tokens;
  const positionals = rest
    .map((token): PositionalDefinition | null => {
      const match = token.match(/^([<[{])([^>\]}]+)([>\]}])$/);
      if (!match) return null;
      return {
        key: camelCase(match[2]),
        required: match[1] === "<",
      };
    })
    .filter((value): value is PositionalDefinition => value != null);

  return { name, positionals };
}

function parseOption(
  flags: string,
  description?: string,
  parserOrDefault?: ((value: string) => unknown) | unknown,
  defaultValue?: unknown
): ParsedOption {
  const tokens = flags
    .split(/[,\s|]+/)
    .map((token) => token.trim())
    .filter(Boolean);

  const longFlag = tokens.find((token) => token.startsWith("--"));
  if (!longFlag) {
    throw new Error(`Option is missing a long flag: ${flags}`);
  }

  const shortFlag = tokens.find((token) => /^-[^-]$/.test(token));
  const valueToken = tokens.find((token) => /^<[^>]+>$/.test(token) || /^\[[^\]]+\]$/.test(token));
  const hasValue = valueToken != null;
  const optionalValue = valueToken?.startsWith("[") ?? false;
  const parser = typeof parserOrDefault === "function"
    ? (parserOrDefault as (value: string) => unknown)
    : undefined;
  const defaultFromThirdArg = parser ? undefined : parserOrDefault;
  const schemaDefault = defaultValue ?? defaultFromThirdArg;
  const negatable = longFlag.startsWith("--no-");
  const optionName = negatable ? longFlag.slice("--no-".length) : longFlag.slice("--".length);
  const key = camelCase(optionName);
  const schema: ArgSchema = {
    type: "boolean",
    description,
  };

  if (shortFlag) schema.short = shortFlag.slice(1);
  if (optionName.includes("-")) schema.toKebab = true;

  if (negatable) {
    schema.type = "boolean";
    schema.negatable = true;
    schema.default = schemaDefault !== undefined ? Boolean(schemaDefault) : true;
    return { key, schema, takesValue: false };
  }

  if (hasValue) {
    if (parser) {
      schema.type = "custom";
      schema.parse = parser;
      schema.metavar = valueToken?.slice(1, -1);
    } else {
      schema.type = "string";
    }

    if (schemaDefault !== undefined && isSchemaDefault(schemaDefault)) {
      schema.default = schemaDefault;
    }

    const optionalValueDefault = optionalValue
      ? inferOptionalValueDefault(parser, schemaDefault)
      : undefined;

    return { key, schema, takesValue: true, optionalValueDefault };
  }

  schema.type = "boolean";
  if (schemaDefault !== undefined && isSchemaDefault(schemaDefault)) {
    schema.default = schemaDefault;
  }

  return { key, schema, takesValue: false };
}

function pickOptionValues(
  values: Record<string, unknown>,
  definitions: OptionDefinition[]
): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const definition of definitions) {
    if (Object.prototype.hasOwnProperty.call(values, definition.key)) {
      result[definition.key] = values[definition.key];
    }
  }
  return result;
}

function inferOptionalValueDefault(
  parser: ((value: string) => unknown) | undefined,
  defaultValue: unknown
): string {
  if (defaultValue !== undefined) return String(defaultValue);
  if (parser) {
    try {
      const parsed = parser(undefined as unknown as string);
      if (parsed !== undefined && parsed !== null) return String(parsed);
    } catch {}
  }
  return "true";
}

function normalizeArgv(
  argv: string[],
  optionValueSettings: Map<string, { takesValue: boolean; optionalValueDefault?: string }>
): string[] {
  const normalized: string[] = [];

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "-V") {
      normalized.push("--version");
      continue;
    }

    const [flag, inlineValue] = arg.split("=", 2);
    const setting = optionValueSettings.get(flag);
    if (!setting || inlineValue !== undefined) {
      normalized.push(arg);
      continue;
    }

    const next = argv[index + 1];
    if (next !== undefined && !next.startsWith("-")) {
      normalized.push(`${arg}=${next}`);
      index += 1;
      continue;
    }

    if (setting.optionalValueDefault !== undefined) {
      normalized.push(`${arg}=${setting.optionalValueDefault}`);
    } else {
      normalized.push(arg);
    }
  }

  return normalized;
}

function isGunshiPrintedError(error: unknown): boolean {
  if (error instanceof Error && BUILTIN_PRINTED_ERROR_NAMES.has(error.name)) {
    return true;
  }
  return error instanceof AggregateError;
}

function isSchemaDefault(value: unknown): value is string | boolean | number {
  return ["string", "boolean", "number"].includes(typeof value);
}

function camelCase(value: string): string {
  return value.replace(/-([a-zA-Z0-9])/g, (_, char: string) => char.toUpperCase());
}

function kebabCase(value: string): string {
  return value.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`);
}
