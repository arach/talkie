#!/usr/bin/env bun
/**
 * mic-probe — Quick diagnostic for Talkie audio input state.
 *
 * Usage: bun scripts/mic-probe.ts
 *
 * Shows:
 *  - System audio input devices
 *  - TalkieAgent bridge status (port 19823)
 *  - TalkieMic helper status (port 19824)
 */

const PORTS = {
  agent: 19823,
  mic: 19824,
} as const;

// ── System audio devices ──────────────────────────────────────────────

async function listAudioDevices() {
  const proc = Bun.spawn(["system_profiler", "SPAudioDataType", "-json"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const text = await new Response(proc.stdout).text();
  try {
    const data = JSON.parse(text);
    const items = data?.SPAudioDataType ?? [];
    const inputs: { name: string; manufacturer: string; channels: number; defaultInput: boolean }[] = [];
    for (const item of items) {
      const devices = item?._items ?? [];
      for (const dev of devices) {
        if (dev?.coreaudio_input_source) {
          inputs.push({
            name: dev._name ?? "Unknown",
            manufacturer: dev.coreaudio_device_manufacturer ?? "Unknown",
            channels: parseInt(dev.coreaudio_device_input ?? "0"),
            defaultInput: dev.coreaudio_default_audio_input_device === "yes",
          });
        }
      }
    }
    return inputs;
  } catch {
    return [];
  }
}

// ── Bridge ping ───────────────────────────────────────────────────────

function pingBridge(
  port: number,
  label: string,
  method = "ping"
): Promise<{ label: string; ok: boolean; result?: Record<string, unknown>; error?: string }> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      resolve({ label, ok: false, error: "timeout (3s)" });
    }, 3000);

    try {
      const ws = new WebSocket(`ws://127.0.0.1:${port}`);

      ws.onopen = () => {
        ws.send(JSON.stringify({ id: "probe", method }));
      };

      ws.onmessage = (event) => {
        clearTimeout(timer);
        try {
          const data = JSON.parse(String(event.data));
          resolve({ label, ok: true, result: data.result ?? data });
        } catch {
          resolve({ label, ok: true, result: {} });
        }
        ws.close();
      };

      ws.onerror = () => {
        clearTimeout(timer);
        resolve({ label, ok: false, error: "not running" });
      };

      ws.onclose = () => {
        clearTimeout(timer);
      };
    } catch (e) {
      clearTimeout(timer);
      resolve({ label, ok: false, error: String(e) });
    }
  });
}

// ── Main ──────────────────────────────────────────────────────────────

async function main() {
  console.log("\n🎤 Talkie Mic Probe\n");

  // System devices
  const devices = await listAudioDevices();
  console.log("── Audio Input Devices ──");
  if (devices.length === 0) {
    console.log("  (none found)");
  } else {
    for (const d of devices) {
      const tag = d.defaultInput ? " ← DEFAULT" : "";
      console.log(`  ${d.name} (${d.channels}ch, ${d.manufacturer})${tag}`);
    }
  }

  // Running processes
  console.log("\n── Processes ──");
  const psAgent = Bun.spawnSync(["pgrep", "-fl", "TalkieAgent"]);
  const psMic = Bun.spawnSync(["pgrep", "-fl", "TalkieMic"]);
  console.log(`  TalkieAgent: ${psAgent.exitCode === 0 ? psAgent.stdout.toString().trim() : "not running"}`);
  console.log(`  TalkieMic:   ${psMic.exitCode === 0 ? psMic.stdout.toString().trim() : "not running (launches on demand)"}`);

  // Bridge status
  console.log("\n── Service Bridges ──");
  const [agent, mic] = await Promise.all([
    pingBridge(PORTS.agent, "TalkieAgent", "ping"),
    pingBridge(PORTS.mic, "TalkieMic", "status"),
  ]);

  for (const svc of [agent, mic]) {
    const portKey = svc.label === "TalkieAgent" ? "agent" : "mic";
    if (svc.ok) {
      console.log(`  ${svc.label} (port ${PORTS[portKey]}): ✅ online`);
      if (svc.result) {
        const { sessions, ...rest } = svc.result as Record<string, unknown>;
        for (const [k, v] of Object.entries(rest)) {
          console.log(`    ${k}: ${JSON.stringify(v)}`);
        }
        if (Array.isArray(sessions) && sessions.length > 0) {
          console.log(`    sessions:`);
          for (const s of sessions) {
            const sess = s as Record<string, unknown>;
            const dur = typeof sess.duration === "number" ? sess.duration.toFixed(1) : "?";
            const bytes = typeof sess.bytesWritten === "number" ? `${(sess.bytesWritten as number / 1024).toFixed(0)}KB` : "?";
            const label = sess.label ? ` [${sess.label}]` : "";
            console.log(`      ${sess.clientId}${label} — ${dur}s, ${bytes}`);
          }
        }
      }
    } else {
      console.log(`  ${svc.label} (port ${PORTS[portKey]}): ⬚ ${svc.error}`);
    }
  }

  console.log("");
}

main();
