const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

const html = `
<!DOCTYPE html>
<html>
<head>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      width: 1200px;
      height: 630px;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
    }
    .container {
      height: 100%;
      width: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background-color: #09090b;
      position: relative;
    }
    .grid {
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background-image:
        linear-gradient(rgba(255,255,255,0.04) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.04) 1px, transparent 1px);
      background-size: 40px 40px;
      opacity: 0.6;
    }
    .corner { position: absolute; width: 20px; height: 20px; }
    .corner-tl { top: 32px; left: 32px; border-top: 2px solid #52525b; border-left: 2px solid #52525b; }
    .corner-tr { top: 32px; right: 32px; border-top: 2px solid #52525b; border-right: 2px solid #52525b; }
    .corner-bl { bottom: 32px; left: 32px; border-bottom: 2px solid #52525b; border-left: 2px solid #52525b; }
    .corner-br { bottom: 32px; right: 32px; border-bottom: 2px solid #52525b; border-right: 2px solid #52525b; }
    .content {
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      z-index: 1;
      padding: 0 60px;
    }
    .hero-badge {
      display: flex;
      align-items: center;
      gap: 8px;
      background: rgba(24, 24, 27, 0.9);
      border: 1px solid rgba(63, 63, 70, 0.7);
      border-radius: 10px;
      padding: 8px 16px;
      margin-bottom: 32px;
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.1);
    }
    .hero-badge-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background-color: #22c55e;
      box-shadow: 0 0 8px rgba(34, 197, 94, 0.6);
    }
    .hero-badge-text {
      font-size: 10px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 700;
      letter-spacing: 0.22em;
      color: #d4d4d8;
      text-transform: uppercase;
    }
    h1 {
      font-size: 100px;
      font-weight: 900;
      color: #fafafa;
      letter-spacing: -0.04em;
      text-transform: uppercase;
      line-height: 0.9;
    }
    h1 .plus {
      color: #52525b;
    }
    h1 .ai {
      color: #22c55e;
    }
    .tagline {
      font-size: 15px;
      color: #a1a1aa;
      margin-top: 36px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 500;
      max-width: 900px;
      line-height: 1.8;
      text-transform: uppercase;
      letter-spacing: 0.1em;
    }
    .tagline .sep {
      color: #3f3f46;
      margin: 0 8px;
    }
    .tagline-sub {
      font-size: 13px;
      color: #71717a;
      margin-top: 16px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 400;
      letter-spacing: 0.08em;
    }
    .tagline-sub .highlight {
      color: #a1a1aa;
    }
    .lock-icon {
      width: 14px;
      height: 14px;
      vertical-align: middle;
      margin-right: 6px;
      color: #71717a;
    }
    .lock-icon.lock-right {
      margin-right: 0;
      margin-left: 6px;
    }
    .badge {
      position: absolute;
      top: 60px;
      right: 80px;
      border: 2px solid #fafafa;
      background: #09090b;
      padding: 8px 16px;
      box-shadow: 4px 4px 0px 0px #10b981;
      transform: rotate(3deg);
    }
    .badge span {
      font-size: 18px;
      font-weight: 700;
      font-family: 'JetBrains Mono', monospace;
      color: #fafafa;
      letter-spacing: -0.02em;
    }
    .bottom {
      position: absolute;
      bottom: 36px;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .bottom span {
      font-size: 12px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 500;
      color: #52525b;
    }
    .bottom .sep { color: #3f3f46; }
  </style>
</head>
<body>
  <div class="container">
    <div class="grid"></div>
    <div class="corner corner-tl"></div>
    <div class="corner corner-tr"></div>
    <div class="corner corner-bl"></div>
    <div class="corner corner-br"></div>
    <div class="badge"><span>;) Talkie</span></div>
    <div class="content">
      <div class="hero-badge">
        <div class="hero-badge-dot"></div>
        <span class="hero-badge-text">Native on iOS & macOS</span>
      </div>
      <h1>VOICE MEMOS<br/><span class="plus">+</span> <span class="ai">AI.</span></h1>
      <p class="tagline">Capture on iPhone <span class="sep">|</span> Process on Mac</p>
      <p class="tagline-sub"><svg class="lock-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/></svg> synced via <span class="highlight">your</span> iCloud <svg class="lock-icon lock-right" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/></svg></p>
    </div>
    <div class="bottom">
      <span style="letter-spacing: 0.1em;">iOS + macOS</span>
      <span class="sep">•</span>
      <span>usetalkie.com</span>
    </div>
  </div>
</body>
</html>
`;

(async () => {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 630, deviceScaleFactor: 2 });
  await page.setContent(html, { waitUntil: 'networkidle0' });

  // Wait for fonts to load
  await page.evaluate(() => document.fonts.ready);
  await new Promise(r => setTimeout(r, 500));

  const outputPath = path.join(__dirname, '..', 'public', 'og-image.png');
  await page.screenshot({ path: outputPath, type: 'png' });

  console.log(`Generated: ${outputPath}`);
  await browser.close();
})();
