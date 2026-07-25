#!/usr/bin/env bun

import { copyFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const ROOT = path.resolve(import.meta.dirname, "..");
const args = process.argv.slice(2);

function option(name, fallback) {
  const index = args.indexOf(`--${name}`);
  if (index === -1) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`--${name} requires a value`);
  return value;
}

const theme = option("theme");
if (!theme || !["dark", "light"].includes(theme)) throw new Error("Use --theme dark or --theme light");

const sourceRoot = path.resolve(option("source", path.join(ROOT, "artifacts/talkie-videos/prepared", theme, "raw")));
const outputRoot = path.resolve(option("output", path.join(ROOT, "artifacts/talkie-videos/hyperframes", `talkie-${theme}-screen-library`)));
const assetsRoot = path.join(outputRoot, "assets");
const id = `talkie-${theme}-screen-library`;

const screens = [
  ["home", "Home", "Your day, held like an instrument panel."],
  ["agent", "Agent", "Live voice and local activity in one operating view."],
  ["library", "Library", "Every memo, capture, and recording stays close."],
  ["compose", "Compose", "Start with a thought. Shape it without losing its source."],
  ["captures", "Capture Library", "Screenshots and recordings remain browseable in context."],
  ["workflows", "Workflows", "Turn speech into a repeatable system."],
  ["console", "Console", "Bring the tools already in your loop into Talkie."],
  ["stats", "Learn", "Discover how Talkie works, then jump into the real surface."],
  ["models", "Models", "Choose local and hosted intelligence in one place."],
  ["context", "Context", "Decide what Talkie can see, remember, and use."],
  ["settings", "Appearance", "One product language, tuned for dark and light."],
];

await mkdir(assetsRoot, { recursive: true });
await Promise.all(screens.map(([slug]) => copyFile(path.join(sourceRoot, `${slug}.mp4`), path.join(assetsRoot, `${slug}.mp4`))));

const palette = theme === "dark" ? {
  canvas: "#1a1020",
  ink: "#f5ecdf",
  dim: "#c7b9c7",
  accent: "#f1a84b",
  panel: "rgba(38, 23, 43, 0.78)",
  rule: "rgba(255, 238, 214, 0.22)",
  shadow: "rgba(7, 4, 11, 0.58)",
  background: "radial-gradient(circle at 16% 22%, rgba(232, 126, 71, .42), transparent 32%), radial-gradient(circle at 82% 18%, rgba(67, 151, 154, .34), transparent 35%), radial-gradient(circle at 72% 86%, rgba(120, 72, 156, .42), transparent 42%), linear-gradient(135deg, #27152d 0%, #171522 48%, #102429 100%)",
} : {
  canvas: "#eadfce",
  ink: "#2b2025",
  dim: "#655b60",
  accent: "#6f2f16",
  panel: "rgba(255, 248, 237, 0.78)",
  rule: "rgba(67, 48, 52, 0.20)",
  shadow: "rgba(83, 60, 47, 0.28)",
  background: "radial-gradient(circle at 14% 20%, rgba(224, 119, 73, .38), transparent 32%), radial-gradient(circle at 82% 16%, rgba(91, 155, 164, .34), transparent 35%), radial-gradient(circle at 72% 90%, rgba(166, 118, 178, .32), transparent 42%), linear-gradient(135deg, #f4dfc8 0%, #e8e1d6 50%, #cfe0dc 100%)",
};

const sceneDuration = 3.8;
const mediaDuration = 3.7;
const introDuration = 2.2;
const outroStart = introDuration + screens.length * sceneDuration;
const totalDuration = outroStart + 3;

const scenesMarkup = screens.map(([slug, title, description], index) => {
  const start = Number((introDuration + index * sceneDuration).toFixed(1));
  const number = String(index + 1).padStart(2, "0");
  return `
      <section id="scene-${slug}" class="scene">
        <div class="orbit orbit-a" data-layout-allow-overflow></div><div class="orbit orbit-b" data-layout-allow-overflow></div>
        <div class="product-wrap">
          <video id="video-${slug}" class="screen clip" data-start="${start}" data-duration="${mediaDuration}" data-track-index="2" data-media-start="0.1" src="assets/${slug}.mp4" muted playsinline preload="auto"></video>
        </div>
        <div class="caption">
          <div class="eyebrow">${number} / ${theme.toUpperCase()} PASS</div>
          <h1>${title}</h1>
          <p>${description}</p>
        </div>
      </section>`;
}).join("\n");

const sceneIds = screens.map(([slug]) => `"#scene-${slug}"`).join(", ");
const starts = screens.map((_, index) => (introDuration + index * sceneDuration).toFixed(1)).join(", ");

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1920, height=1080" />
  <script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
  <style>
    :root { --canvas:${palette.canvas}; --ink:${palette.ink}; --dim:${palette.dim}; --accent:${palette.accent}; --panel:${palette.panel}; --rule:${palette.rule}; --shadow:${palette.shadow}; }
    * { box-sizing:border-box; margin:0; padding:0; }
    html,body { width:1920px; height:1080px; overflow:hidden; background:var(--canvas); color:var(--ink); }
    body { font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
    #root { position:relative; width:1920px; height:1080px; overflow:hidden; background:${palette.background}; }
    #root::before { content:""; position:absolute; inset:0; opacity:.18; background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 180 180' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.55'/%3E%3C/svg%3E"); mix-blend-mode:soft-light; pointer-events:none; }
    .scene { position:absolute; inset:0; opacity:0; overflow:hidden; }
    .orbit { position:absolute; border:1px solid var(--rule); border-radius:50%; }
    .orbit-a { width:980px; height:980px; left:-360px; top:-420px; }
    .orbit-b { width:760px; height:760px; right:-220px; bottom:-340px; }
    .product-wrap { position:absolute; width:1188px; height:876px; left:94px; top:102px; display:flex; align-items:center; justify-content:center; }
    .screen { display:block; width:auto; height:840px; max-width:1180px; border:1px solid var(--rule); border-radius:18px; box-shadow:0 42px 120px var(--shadow), 0 2px 0 rgba(255,255,255,.12) inset; }
    .caption { position:absolute; z-index:5; right:84px; bottom:108px; width:500px; padding:34px 36px 38px; border:1px solid var(--rule); border-radius:22px; background:var(--panel); backdrop-filter:blur(26px); box-shadow:0 28px 80px var(--shadow); }
    .eyebrow { color:var(--accent); font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:14px; letter-spacing:.22em; }
    h1 { margin-top:20px; font-family:Georgia,"Times New Roman",serif; font-size:68px; line-height:.96; font-weight:400; letter-spacing:-.045em; }
    .caption p { margin-top:20px; max-width:410px; color:var(--dim); font-size:21px; line-height:1.48; }
    .intro,.outro { position:absolute; inset:0; z-index:10; display:grid; place-items:center; text-align:center; }
    .intro-inner,.outro-inner { padding:50px 62px; border:1px solid var(--rule); border-radius:26px; background:var(--panel); backdrop-filter:blur(28px); box-shadow:0 36px 110px var(--shadow); }
    .mode { color:var(--accent); font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:15px; letter-spacing:.25em; text-transform:uppercase; }
    .wordmark { margin-top:18px; font-family:Georgia,"Times New Roman",serif; font-size:112px; line-height:.9; letter-spacing:-.06em; }
    .intro p,.outro p { margin-top:22px; color:var(--dim); font-size:24px; }
    .rail { position:absolute; z-index:20; right:84px; bottom:50px; left:84px; height:2px; background:var(--rule); }
    .rail-fill { width:0; height:100%; background:var(--accent); }
  </style>
</head>
<body>
  <main id="root" data-composition-id="main" data-start="0" data-duration="${totalDuration}" data-width="1920" data-height="1080">
    <div id="intro" class="intro clip" data-start="0" data-duration="${introDuration}" data-track-index="4"><div class="intro-inner"><div class="mode">Talkie / ${theme} mode</div><div class="wordmark">Every screen.</div><p>One coherent product language from capture to output.</p></div></div>
${scenesMarkup}
    <div id="outro" class="outro clip" data-start="${outroStart}" data-duration="3" data-track-index="4"><div class="outro-inner"><div class="mode">Talkie for Mac</div><div class="wordmark">Say it once.</div><p>Use it everywhere.</p></div></div>
    <div id="progress-rail" class="rail clip" data-start="0" data-duration="${totalDuration}" data-track-index="5"><div id="rail-fill" class="rail-fill"></div></div>
  </main>
  <script>
    window.__timelines = window.__timelines || {};
    const tl = gsap.timeline({ paused:true });
    tl.fromTo("#intro .intro-inner", {opacity:0,y:12}, {opacity:1,y:0,duration:.35}, 0).to("#intro .intro-inner", {opacity:0,duration:.28}, ${introDuration - 0.28});
    tl.set("#intro .intro-inner", {opacity:0,visibility:"hidden"}, ${introDuration});
    const scenes = [${sceneIds}];
    const starts = [${starts}];
    scenes.forEach((scene,index) => {
      const start = starts[index];
      tl.fromTo(scene,{opacity:0},{opacity:1,duration:.28},start);
      tl.fromTo(scene + " .product-wrap",{opacity:0,y:18,scale:.994},{opacity:1,y:0,scale:1,duration:.52,ease:"power2.out"},start+.06);
      tl.fromTo(scene + " .caption",{opacity:0,y:20},{opacity:1,y:0,duration:.5,ease:"power2.out"},start+.18);
      tl.to(scene,{opacity:0,duration:.24},start+${sceneDuration - 0.24});
      tl.set(scene,{opacity:0,visibility:"hidden"},start+${sceneDuration});
    });
    tl.fromTo("#outro .outro-inner",{opacity:0,y:12},{opacity:1,y:0,duration:.35},${outroStart});
    tl.to("#rail-fill",{width:"100%",duration:${totalDuration},ease:"none"},0);
    window.__timelines.main = tl;
  </script>
</body>
</html>`;

const packageJson = {
  name: id,
  private: true,
  type: "module",
  scripts: {
    dev: "npx --yes hyperframes@0.5.3 preview",
    check: "npx --yes hyperframes@0.5.3 lint && npx --yes hyperframes@0.5.3 validate && npx --yes hyperframes@0.5.3 inspect",
    render: "npx --yes hyperframes@0.5.3 render",
  },
};

await Promise.all([
  writeFile(path.join(outputRoot, "index.html"), html),
  writeFile(path.join(outputRoot, "package.json"), `${JSON.stringify(packageJson, null, 2)}\n`),
  writeFile(path.join(outputRoot, "meta.json"), `${JSON.stringify({ id, name: `Talkie ${theme} screen library`, description: `Every current Talkie screen presented in ${theme} mode.` }, null, 2)}\n`),
  writeFile(path.join(outputRoot, "hyperframes.json"), `${JSON.stringify({ $schema: "https://hyperframes.heygen.com/schema/hyperframes.json", registry: "https://raw.githubusercontent.com/heygen-com/hyperframes/main/registry", paths: { blocks: "compositions", components: "compositions/components", assets: "assets" } }, null, 2)}\n`),
  writeFile(path.join(outputRoot, "DESIGN.md"), `# Talkie ${theme} screen library\n\nA ${totalDuration}-second pass through all eleven current Talkie surfaces. Exact-window Action captures float over an editorial ${theme === "dark" ? "aubergine, mineral teal, and amber" : "parchment, mineral blue, and terracotta"} background. Green-backed preprocessing plates live beside the source library for downstream keying.\n`),
]);

console.log(JSON.stringify({ theme, outputRoot, duration: totalDuration, screenCount: screens.length }, null, 2));
