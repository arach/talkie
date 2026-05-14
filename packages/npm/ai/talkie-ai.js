#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createCipheriv, createECDH, hkdfSync, randomBytes, randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { networkInterfaces } from "node:os";
import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const RED = "\x1b[31m";

const AI_SETUP_PROTOCOL = "talkie-ai-setup-v1";
const CLAIM_PROTOCOL = "talkie-ai-setup-claim-v1";
const RESPONSE_PROTOCOL = "talkie-ai-setup-response-v1";
const COMPLETE_PROTOCOL = "talkie-ai-setup-complete-v1";
const CREDENTIAL_PROTOCOL = "talkie-ai-credentials-v1";

const PROVIDERS = {
  openai: {
    id: "openai",
    name: "OpenAI",
    env: "OPENAI_API_KEY",
    keyUrl: "https://platform.openai.com/api-keys",
    defaultModel: "gpt-5.2-chat-latest",
  },
  groq: {
    id: "groq",
    name: "Groq",
    env: "GROQ_API_KEY",
    keyUrl: "https://console.groq.com/keys",
    defaultModel: "llama-3.3-70b-versatile",
  },
};

const DEFAULT_ASSISTANT_PROMPT =
  "You are Talkie's Apple Watch voice assistant. Answer directly, briefly, and naturally.";

function parseArgs(argv) {
  const args = [...argv];
  const command = args[0]?.startsWith("--") ? "help" : args.shift();
  const opts = { command };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const [rawName, inlineValue] = arg.slice(2).split("=", 2);
    const name = rawName.replace(/-([a-z])/g, (_, char) => char.toUpperCase());
    const takesValue = !["help", "noQr", "json", "link", "openKeyUrl", "keyUrl"].includes(name);
    const value = inlineValue ?? (takesValue ? args[++index] : "true");
    if (takesValue && (value == null || value.startsWith("--"))) {
      throw new Error(`Missing value for --${rawName}`);
    }

    opts[name] = value;
  }

  return opts;
}

function printHelp() {
  console.log(`${BOLD}Talkie AI setup${RESET}

Usage:
  npx @talkie/ai qr [options]

Options:
  --provider <openai|groq>   AI provider to send to iPhone
  --model <id>               Model to save with the provider
  --key <key>                API key to share over the encrypted transaction
  --host <ip-or-host>        Hostname/IP your iPhone can reach over local Wi-Fi
  --port <port>              Local port to listen on (default: random)
  --timeout <seconds>        How long the one-time setup stays open (default: 180)
  --prompt <text>            Assistant system prompt saved on iPhone
  --open-key-url             Open the provider API-key page before prompting
  --key-url                  Print the provider API-key page URL and exit
  --credential-source <name>  browser, paste, 1password, keychain, or auto
  --op-item <name|ref>        1Password item name or op:// reference
  --op-field <field>          1Password field label/id (default: credential)
  --keychain-service <name>   macOS Keychain generic password service name
  --keychain-account <name>   macOS Keychain generic password account name
  --link                     Print a talkie:// setup link instead of a QR
  --no-qr                    Skip QR rendering and print the raw setup payload
  --json                     JSON output for scripts

Examples:
  npx @talkie/ai qr
  OPENAI_API_KEY=sk-... npx @talkie/ai qr --provider openai
  npx @talkie/ai qr --provider groq --open-key-url
  npx @talkie/ai qr --op-item "OpenAI API key" --op-field credential
  npx @talkie/ai qr --credential-source keychain
`);
}

function normalizeProvider(value) {
  const normalized = value?.trim().toLowerCase();
  if (!normalized) return null;
  if (normalized === "open-ai") return "openai";
  if (PROVIDERS[normalized]) return normalized;
  throw new Error(`Unsupported provider: ${value}. Expected openai or groq.`);
}

function defaultHost() {
  const interfaces = networkInterfaces();
  const candidates = [];

  for (const [name, addresses] of Object.entries(interfaces)) {
    for (const address of addresses ?? []) {
      if (address.family !== "IPv4" || address.internal) continue;
      if (address.address.startsWith("169.254.")) continue;

      const isRFC1918 =
        address.address.startsWith("10.") ||
        address.address.startsWith("192.168.") ||
        /^172\.(1[6-9]|2\d|3[0-1])\./.test(address.address);

      candidates.push({
        name,
        address: address.address,
        score: (name === "en0" ? 10 : 0) + (isRFC1918 ? 5 : 0),
      });
    }
  }

  candidates.sort((a, b) => b.score - a.score);
  return candidates[0]?.address ?? null;
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let length = 0;

    request.on("data", (chunk) => {
      length += chunk.length;
      if (length > 64 * 1024) {
        reject(new Error("Request body is too large"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function sendJson(response, statusCode, body) {
  const encoded = JSON.stringify(body);
  response.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(encoded),
    "Cache-Control": "no-store",
  });
  response.end(encoded);
}

function openUrl(url) {
  return spawnSync("open", [url], { stdio: "ignore" }).status === 0;
}

function commandExists(command) {
  return spawnSync("sh", ["-c", `command -v ${shellQuote(command)}`], {
    stdio: "ignore",
  }).status === 0;
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function validateApiKey(provider, apiKey) {
  if (apiKey.includes("*") || apiKey.includes("•")) {
    throw new Error(`${provider.name} API key appears to be masked. Paste the newly-created secret key value, not a redacted display.`);
  }

  if (!apiKey || apiKey.length < 20) {
    throw new Error(`${provider.name} API key looks too short. Paste the full secret key, not a label.`);
  }

  if (provider.id === "openai" && !apiKey.startsWith("sk-")) {
    console.log(`  ${YELLOW}!${RESET} OpenAI keys usually start with ${CYAN}sk-${RESET}; continuing with the value you provided.`);
  }

  if (provider.id === "groq" && !apiKey.startsWith("gsk_")) {
    console.log(`  ${YELLOW}!${RESET} Groq keys usually start with ${CYAN}gsk_${RESET}; continuing with the value you provided.`);
  }
}

function encryptCredentialPayload({ ecdh, sessionId, clientPublicKey, credentialPayload }) {
  const sharedSecret = ecdh.computeSecret(Buffer.from(clientPublicKey, "base64"));
  const key = Buffer.from(
    hkdfSync(
      "sha256",
      sharedSecret,
      Buffer.from(sessionId, "utf8"),
      Buffer.from(AI_SETUP_PROTOCOL, "utf8"),
      32
    )
  );
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(credentialPayload), "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return Buffer.concat([nonce, ciphertext, tag]).toString("base64");
}

function startTransactionServer({ ecdh, sessionId, credentialPayload, port, timeoutMs }) {
  let claimed = false;
  let completed = false;
  let resolveDone;
  let rejectDone;
  let server;
  const done = new Promise((resolve, reject) => {
    resolveDone = resolve;
    rejectDone = reject;
  });

  const timeout = setTimeout(() => {
    server?.close();
    rejectDone(new Error(
      claimed
        ? "Timed out waiting for the iPhone to validate and save the AI credentials."
        : "Timed out waiting for the iPhone to scan the setup code."
    ));
  }, timeoutMs);

  server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url ?? "/", "http://localhost");
      if (request.method === "GET" && url.pathname === "/") {
        sendJson(response, 200, { ok: true, protocol: AI_SETUP_PROTOCOL });
        return;
      }

      if (request.method === "POST" && url.pathname === "/talkie-ai/complete") {
        if (!claimed) {
          sendJson(response, 409, { error: "not_claimed" });
          return;
        }

        if (completed) {
          sendJson(response, 410, { error: "already_completed" });
          return;
        }

        const body = JSON.parse(await readBody(request));
        if (
          body.protocol !== COMPLETE_PROTOCOL ||
          body.sessionId !== sessionId ||
          (body.status !== "ok" && body.status !== "failed")
        ) {
          sendJson(response, 400, { error: "invalid_completion" });
          return;
        }

        completed = true;
        clearTimeout(timeout);
        sendJson(response, 200, { ok: true });
        setTimeout(() => {
          server.close();
          if (body.status === "ok") {
            resolveDone();
          } else {
            rejectDone(new Error(body.message || "iPhone rejected the AI credential setup."));
          }
        }, 200);
        return;
      }

      if (request.method !== "POST" || url.pathname !== "/talkie-ai/claim") {
        sendJson(response, 404, { error: "not_found" });
        return;
      }

      if (claimed) {
        sendJson(response, 410, { error: "already_claimed" });
        return;
      }

      const body = JSON.parse(await readBody(request));
      if (
        body.protocol !== CLAIM_PROTOCOL ||
        body.sessionId !== sessionId ||
        typeof body.clientPublicKey !== "string"
      ) {
        sendJson(response, 400, { error: "invalid_claim" });
        return;
      }

      const ciphertext = encryptCredentialPayload({
        ecdh,
        sessionId,
        clientPublicKey: body.clientPublicKey,
        credentialPayload,
      });

      claimed = true;
      sendJson(response, 200, {
        protocol: RESPONSE_PROTOCOL,
        ciphertext,
      });
    } catch (error) {
      sendJson(response, 500, {
        error: "transaction_failed",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  });

  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "0.0.0.0", () => {
      server.off("error", reject);
      resolve({
        port: server.address().port,
        done,
        close: () => {
          clearTimeout(timeout);
          server.close();
        },
      });
    });
  });
}

async function renderQr(value) {
  try {
    const qrcode = await import("qrcode-terminal");
    const renderer = qrcode.default ?? qrcode;
    await new Promise((resolve) => {
      renderer.generate(value, { small: true }, (qr) => {
        console.log(qr);
        resolve();
      });
    });
    return true;
  } catch {
    const result = spawnSync("qrencode", ["-t", "ANSIUTF8", value], {
      encoding: "utf8",
    });
    if (result.status === 0 && result.stdout) {
      console.log(result.stdout.trimEnd());
      return true;
    }
  }

  return false;
}

async function promptLine(readline, label, defaultValue = "") {
  const suffix = defaultValue ? ` ${DIM}[${defaultValue}]${RESET}` : "";
  const answer = (await readline.question(`${label}${suffix}: `)).trim();
  return answer || defaultValue;
}

function isNo(answer) {
  return answer.toLowerCase() === "n" || answer.toLowerCase() === "no";
}

function normalizeCredentialSource(value) {
  const normalized = value?.trim().toLowerCase();
  if (!normalized) return null;
  if (["browser", "paste", "1password", "op", "keychain", "apple-passwords", "passwords", "auto"].includes(normalized)) {
    return normalized === "op" ? "1password" : normalized;
  }
  throw new Error(`Unsupported credential source: ${value}. Expected browser, paste, 1password, keychain, or auto.`);
}

async function promptSecret(label) {
  if (!input.isTTY || !output.isTTY || typeof input.setRawMode !== "function") {
    return "";
  }

  return new Promise((resolve) => {
    let value = "";
    output.write(`${label}: `);
    input.setRawMode(true);
    input.resume();
    input.setEncoding("utf8");

    const cleanup = () => {
      input.setRawMode(false);
      input.pause();
      input.off("data", onData);
      output.write("\n");
    };

    const onData = (chunk) => {
      for (const char of chunk) {
        if (char === "\u0003") {
          cleanup();
          process.exit(130);
        }
        if (char === "\r" || char === "\n") {
          cleanup();
          resolve(value.trim());
          return;
        }
        if (char === "\u007f" || char === "\b") {
          if (value.length > 0) {
            value = value.slice(0, -1);
            output.write("\b \b");
          }
          continue;
        }
        if (char >= " ") {
          value += char;
          output.write("*");
        }
      }
    };

    input.on("data", onData);
  });
}

async function chooseProvider(readline, requestedProvider) {
  const normalized = normalizeProvider(requestedProvider);
  if (normalized) return PROVIDERS[normalized];

  console.log(`${BOLD}Provider${RESET}`);
  console.log(`  1. OpenAI ${process.env.OPENAI_API_KEY ? DIM + "(OPENAI_API_KEY found)" + RESET : ""}`);
  console.log(`  2. Groq   ${process.env.GROQ_API_KEY ? DIM + "(GROQ_API_KEY found)" + RESET : ""}`);
  const answer = await promptLine(readline, "Choose provider", "1");
  if (answer === "2" || answer.toLowerCase() === "groq") return PROVIDERS.groq;
  return PROVIDERS.openai;
}

async function promptForSecret(readline, provider) {
  try {
    readline.close();
  } catch {
    // Already closed by a previous prompt path.
  }
  const key = await promptSecret(`${provider.name} API key`);
  if (!key) {
    throw new Error(`No ${provider.name} API key provided. Use --key or set ${provider.env}.`);
  }
  validateApiKey(provider, key);
  return key;
}

async function browserCredentialFlow({ readline, provider }) {
  console.log();
  console.log(`${BOLD}${provider.name} API key${RESET}`);
  console.log(`  1. Open ${CYAN}${provider.keyUrl}${RESET}`);
  console.log(`  2. Create a new secret key or copy an existing unredacted key.`);
  console.log(`  3. Return here and paste it. Input is hidden.`);
  const shouldOpen = await promptLine(readline, "Open this page now", "Y");
  if (!isNo(shouldOpen)) {
    if (openUrl(provider.keyUrl)) {
      console.log(`  ${GREEN}✓${RESET} Opened ${provider.name} API key page.`);
    } else {
      console.log(`  ${YELLOW}!${RESET} Could not open browser automatically. Open the URL above.`);
    }
  }
  return promptForSecret(readline, provider);
}

async function pasteCredentialFlow({ readline, provider }) {
  console.log();
  console.log(`${BOLD}Manual paste${RESET}`);
  console.log(`  ${DIM}Paste the full secret value. Masked or redacted keys will be rejected. Input is hidden.${RESET}`);
  return promptForSecret(readline, provider);
}

function readFrom1Password({ provider, item, field }) {
  if (!commandExists("op")) {
    throw new Error("1Password CLI is not installed. Install `op`, or choose manual paste.");
  }

  const fieldName = field || "credential";
  const attempts = item?.startsWith("op://")
    ? [["read", item]]
    : [
        ["item", "get", item, "--fields", `label=${fieldName}`, "--reveal"],
        ["item", "get", item, "--fields", fieldName, "--reveal"],
        ["item", "get", item, "--fields", "password", "--reveal"],
      ];

  const failures = [];
  for (const args of attempts) {
    const result = spawnSync("op", args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    const value = result.stdout?.trim();
    if (result.status === 0 && value) {
      validateApiKey(provider, value);
      return value;
    }
    failures.push(result.stderr?.trim() || result.stdout?.trim());
  }

  const reason = failures.find(Boolean) || "No value returned.";
  throw new Error(`Could not read ${provider.name} key from 1Password. ${reason} Run \`op signin\` if the CLI is not signed in.`);
}

async function onePasswordCredentialFlow({ readline, provider, opts }) {
  if (!commandExists("op")) {
    throw new Error("1Password CLI is not installed. Install `op`, or choose manual paste.");
  }

  const envPrefix = provider.id.toUpperCase();
  const item =
    opts.opItem?.trim() ||
    process.env[`TALKIE_AI_${envPrefix}_OP_ITEM`]?.trim() ||
    process.env.TALKIE_AI_OP_ITEM?.trim() ||
    await promptLine(readline, "1Password item name or op:// reference");
  if (!item) {
    throw new Error("No 1Password item selected.");
  }

  const field =
    opts.opField?.trim() ||
    process.env[`TALKIE_AI_${envPrefix}_OP_FIELD`]?.trim() ||
    process.env.TALKIE_AI_OP_FIELD?.trim() ||
    await promptLine(readline, "1Password field label/id", "credential");

  return readFrom1Password({ provider, item, field });
}

function defaultKeychainService(provider) {
  return `Talkie ${provider.name} API Key`;
}

function readFromKeychain({ provider, service, account }) {
  if (process.platform !== "darwin") {
    throw new Error("Apple Passwords/Keychain lookup is only available on macOS.");
  }
  if (!commandExists("security")) {
    throw new Error("macOS `security` tool was not found. Choose manual paste instead.");
  }

  const args = ["find-generic-password"];
  if (account) args.push("-a", account);
  args.push("-s", service, "-w");
  const result = spawnSync("security", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  const value = result.stdout?.trim();
  if (result.status === 0 && value) {
    validateApiKey(provider, value);
    return value;
  }

  const lookup = account ? `service ${shellQuote(service)} and account ${shellQuote(account)}` : `service ${shellQuote(service)}`;
  const saveHint = `security add-generic-password -U -s ${shellQuote(service)}${account ? ` -a ${shellQuote(account)}` : ""} -w '<api-key>'`;
  throw new Error(
    `No ${provider.name} key found in Keychain for ${lookup}. ` +
    `Save one with \`${saveHint}\`, choose manual paste, or open the Passwords app and copy the key.`
  );
}

async function keychainCredentialFlow({ readline, provider, opts }) {
  const envPrefix = provider.id.toUpperCase();
  const service =
    opts.keychainService?.trim() ||
    process.env[`TALKIE_AI_${envPrefix}_KEYCHAIN_SERVICE`]?.trim() ||
    process.env.TALKIE_AI_KEYCHAIN_SERVICE?.trim() ||
    await promptLine(readline, "Keychain service", defaultKeychainService(provider));
  const account =
    opts.keychainAccount?.trim() ||
    process.env[`TALKIE_AI_${envPrefix}_KEYCHAIN_ACCOUNT`]?.trim() ||
    process.env.TALKIE_AI_KEYCHAIN_ACCOUNT?.trim() ||
    await promptLine(readline, "Keychain account", provider.env);

  try {
    return readFromKeychain({ provider, service, account });
  } catch (error) {
    console.log(`  ${YELLOW}!${RESET} ${error instanceof Error ? error.message : String(error)}`);
    const shouldOpen = await promptLine(readline, "Open Apple Passwords now", "N");
    if (!isNo(shouldOpen)) {
      if (!openUrl("x-apple.systempreferences:com.apple.Passwords-Settings.extension")) {
        spawnSync("open", ["-a", "Passwords"], { stdio: "ignore" });
      }
      console.log(`  ${DIM}Copy the saved ${provider.name} key from Passwords, then choose manual paste next time.${RESET}`);
    }
    throw new Error(`No ${provider.name} API key loaded from Apple Passwords/Keychain.`);
  }
}

async function chooseCredentialSource(readline, provider, requestedSource) {
  const source = normalizeCredentialSource(requestedSource);
  if (source && source !== "auto") return source;

  console.log();
  console.log(`${BOLD}${provider.name} credential source${RESET}`);
  console.log(`  1. Browser setup ${DIM}(open key page, then paste)${RESET}`);
  console.log("  2. I've got this, let me paste");
  console.log(`  3. 1Password CLI ${commandExists("op") ? DIM + "(op found)" + RESET : DIM + "(op not found)" + RESET}`);
  console.log("  4. Apple Passwords / Keychain");
  const answer = await promptLine(readline, "Choose source", "1");
  if (answer === "2" || answer.toLowerCase() === "paste") return "paste";
  if (answer === "3" || ["1password", "op"].includes(answer.toLowerCase())) return "1password";
  if (answer === "4" || ["keychain", "passwords", "apple-passwords"].includes(answer.toLowerCase())) return "keychain";
  return "browser";
}

async function resolveKey({ readline, provider, providedKey, opts }) {
  if (providedKey?.trim()) {
    const key = providedKey.trim();
    validateApiKey(provider, key);
    return key;
  }

  const envKey = process.env[provider.env]?.trim();
  if (envKey) {
    const answer = await promptLine(readline, `Use ${provider.env} from this shell`, "Y");
    if (!isNo(answer)) {
      validateApiKey(provider, envKey);
      return envKey;
    }
  }

  const source =
    opts.opItem?.trim() ? "1password" :
    (opts.keychainService?.trim() || opts.keychainAccount?.trim()) ? "keychain" :
    await chooseCredentialSource(readline, provider, opts.credentialSource);
  if (source === "paste") {
    return pasteCredentialFlow({ readline, provider });
  }
  if (source === "1password") {
    return onePasswordCredentialFlow({ readline, provider, opts });
  }
  if (source === "keychain") {
    return keychainCredentialFlow({ readline, provider, opts });
  }
  return browserCredentialFlow({ readline, provider });
}

async function runQr(opts) {
  const readline = createInterface({ input, output });
  try {
    const provider = await chooseProvider(readline, opts.provider);
    if (opts.keyUrl === "true") {
      console.log(provider.keyUrl);
      return;
    }
    if (opts.openKeyUrl === "true") {
      if (!openUrl(provider.keyUrl)) {
        console.log(provider.keyUrl);
      }
    }
    const model = opts.model?.trim() || await promptLine(readline, "Model", provider.defaultModel);
    const apiKey = await resolveKey({ readline, provider, providedKey: opts.key, opts });
    const host = opts.host?.trim() || defaultHost();
    const port = opts.port ? Number.parseInt(opts.port, 10) : 0;
    const timeoutSeconds = opts.timeout ? Number.parseInt(opts.timeout, 10) : 180;
    const assistantPrompt = opts.prompt?.trim() || DEFAULT_ASSISTANT_PROMPT;

    if (!host) {
      throw new Error("Could not find a local Wi-Fi IP address. Re-run with --host <ip>.");
    }
    if (Number.isNaN(port) || port < 0 || port > 65535) {
      throw new Error("--port must be a valid TCP port.");
    }
    if (Number.isNaN(timeoutSeconds) || timeoutSeconds < 15) {
      throw new Error("--timeout must be at least 15 seconds.");
    }

    const sessionId = randomUUID();
    const ecdh = createECDH("prime256v1");
    ecdh.generateKeys();

    const credentialPayload = {
      protocol: CREDENTIAL_PROTOCOL,
      providerId: provider.id,
      providerName: provider.name,
      modelId: model,
      apiKey,
      assistantPrompt,
    };

    const server = await startTransactionServer({
      ecdh,
      sessionId,
      credentialPayload,
      port,
      timeoutMs: timeoutSeconds * 1000,
    });

    const invite = {
      protocol: AI_SETUP_PROTOCOL,
      url: `http://${host}:${server.port}`,
      sessionId,
      serverPublicKey: ecdh.getPublicKey("base64", "uncompressed"),
      providerId: provider.id,
      modelId: model,
    };
    const invitePayload = JSON.stringify(invite);
    const setupLink = `talkie://ai/setup?${new URLSearchParams({ payload: invitePayload }).toString()}`;

    process.once("SIGINT", () => {
      server.close();
      console.log("\nSetup cancelled.");
      process.exit(130);
    });

    if (opts.json === "true") {
      console.log(JSON.stringify({
        invite,
        setupLink,
        provider: provider.id,
        model,
        expiresInSeconds: timeoutSeconds,
      }, null, 2));
    } else {
      console.log(`\n${BOLD}Talkie AI setup${RESET} ${DIM}(local Wi-Fi, one-time)${RESET}`);
      console.log(`${DIM}Scan this in Talkie on iPhone. The QR is only an invite; the API key is sent encrypted after the phone claims it.${RESET}\n`);

      if (opts.link === "true") {
        console.log(setupLink);
      } else if (opts.noQr === "true") {
        console.log(invitePayload);
      } else {
        const rendered = await renderQr(invitePayload);
        if (!rendered) {
          console.log(`${YELLOW}!${RESET} QR renderer unavailable. Install package dependencies with ${CYAN}npm install${RESET}, or install ${CYAN}qrencode${RESET}.`);
          console.log(`${DIM}Setup link:${RESET}\n${setupLink}`);
        }
      }

      console.log();
      console.log(`  provider: ${CYAN}${provider.name}${RESET}`);
      console.log(`  model:    ${CYAN}${model}${RESET}`);
      console.log(`  local:    ${CYAN}${invite.url}${RESET}`);
      console.log(`  expires:  ${CYAN}${timeoutSeconds}s${RESET}`);
      console.log();
      console.log(`${DIM}Waiting for iPhone to scan, validate, and save...${RESET}`);
    }

    await server.done;

    if (opts.json === "true") {
      console.log(JSON.stringify({ ok: true, claimed: true }, null, 2));
    } else {
      console.log(`${GREEN}✓${RESET} iPhone validated and saved ${provider.name} credentials. Transaction closed.`);
    }
  } finally {
    try {
      readline.close();
    } catch {
      // The hidden API-key prompt closes the readline interface before taking over stdin.
    }
  }
}

async function main() {
  try {
    const opts = parseArgs(process.argv.slice(2));
    if (!opts.command || opts.command === "help" || opts.help === "true") {
      printHelp();
      return;
    }

    if (opts.command !== "qr") {
      throw new Error(`Unknown command: ${opts.command}`);
    }

    await runQr(opts);
  } catch (error) {
    console.error(`${RED}error:${RESET} ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

await main();
