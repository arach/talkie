const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

// Read the logo as base64 for embedding
const logoPath = path.join(__dirname, '..', 'public', 'talkie-live-logo.png');
const logoBase64 = fs.readFileSync(logoPath).toString('base64');
const logoDataUrl = `data:image/png;base64,${logoBase64}`;

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
      background: linear-gradient(180deg, #0a0a0c 0%, #0d0d10 100%);
      position: relative;
      overflow: hidden;
    }
    .grid {
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background-image:
        linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px);
      background-size: 40px 40px;
      opacity: 0.6;
    }
    .corner { position: absolute; width: 20px; height: 20px; }
    .corner-tl { top: 32px; left: 32px; border-top: 2px solid #3f3f46; border-left: 2px solid #3f3f46; }
    .corner-tr { top: 32px; right: 32px; border-top: 2px solid #3f3f46; border-right: 2px solid #3f3f46; }
    .corner-bl { bottom: 32px; left: 32px; border-bottom: 2px solid #3f3f46; border-left: 2px solid #3f3f46; }
    .corner-br { bottom: 32px; right: 32px; border-bottom: 2px solid #3f3f46; border-right: 2px solid #3f3f46; }
    .content {
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      z-index: 1;
      padding: 0 60px;
    }
    .bottom-section {
      position: absolute;
      bottom: 28px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 4px;
    }
    .bottom-logo {
      filter: drop-shadow(0 2px 8px rgba(0, 0, 0, 0.4));
    }
    .bottom-logo img {
      width: 90px;
      height: auto;
    }
    .bottom-url {
      font-size: 11px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 500;
      color: #52525b;
      letter-spacing: 0.02em;
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
      background-color: #10b981;
      box-shadow: 0 0 8px rgba(16, 185, 129, 0.6);
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
      font-size: 82px;
      font-weight: 900;
      color: #fafafa;
      letter-spacing: -0.04em;
      text-transform: uppercase;
      line-height: 0.95;
    }
    h1 .highlight {
      color: #10b981;
    }
    h1 .arrow {
      color: #10b981;
      margin: 0 -8px;
    }
    .tagline {
      font-size: 18px;
      color: #a1a1aa;
      margin-top: 32px;
      font-weight: 500;
      max-width: 700px;
      line-height: 1.6;
    }
    .tagline strong {
      color: #fafafa;
    }
    .features {
      display: flex;
      align-items: center;
      gap: 24px;
      margin-top: 28px;
    }
    .feature {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 500;
      color: #71717a;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .feature-check {
      color: #10b981;
      font-size: 14px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="grid"></div>
    <div class="corner corner-tl"></div>
    <div class="corner corner-tr"></div>
    <div class="corner corner-bl"></div>
    <div class="corner corner-br"></div>
    <div class="content">
      <div class="hero-badge">
        <div class="hero-badge-dot"></div>
        <span class="hero-badge-text">Talkie Live</span>
      </div>
      <h1>THOUGHTS<span class="arrow">→</span>TEXT.<br/><span class="highlight">INSTANTLY.</span></h1>
      <p class="tagline">Hold a hotkey, speak, release. <strong>Your words appear at the cursor.</strong></p>
      <div class="features">
        <div class="feature"><span class="feature-check">✓</span> 100% Local</div>
        <div class="feature"><span class="feature-check">✓</span> No Account</div>
        <div class="feature"><span class="feature-check">✓</span> macOS Menu Bar</div>
      </div>
    </div>
    <div class="bottom-section">
      <span class="bottom-url">usetalkie.com/live</span>
      <div class="bottom-logo">
        <img src="${logoDataUrl}" alt="Talkie Live" />
      </div>
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

  const outputPath = path.join(__dirname, '..', 'public', 'og-live.png');
  await page.screenshot({ path: outputPath, type: 'png' });

  console.log(`Generated: ${outputPath}`);
  await browser.close();
})();
