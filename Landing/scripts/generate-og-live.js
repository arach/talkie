const puppeteer = require('puppeteer');
const path = require('path');

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
      overflow: hidden;
    }
    .gradient {
      position: absolute;
      top: -200px;
      left: 50%;
      transform: translateX(-50%);
      width: 800px;
      height: 800px;
      background: radial-gradient(circle, rgba(16, 185, 129, 0.15) 0%, transparent 70%);
      pointer-events: none;
    }
    .grid {
      position: absolute;
      top: 0; left: 0; right: 0; bottom: 0;
      background-image:
        linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px);
      background-size: 40px 40px;
      opacity: 0.8;
    }
    .corner { position: absolute; width: 20px; height: 20px; }
    .corner-tl { top: 32px; left: 32px; border-top: 2px solid #10b981; border-left: 2px solid #10b981; }
    .corner-tr { top: 32px; right: 32px; border-top: 2px solid #10b981; border-right: 2px solid #10b981; }
    .corner-bl { bottom: 32px; left: 32px; border-bottom: 2px solid #10b981; border-left: 2px solid #10b981; }
    .corner-br { bottom: 32px; right: 32px; border-bottom: 2px solid #10b981; border-right: 2px solid #10b981; }
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
      background: rgba(16, 185, 129, 0.1);
      border: 1px solid rgba(16, 185, 129, 0.3);
      border-radius: 100px;
      padding: 10px 20px;
      margin-bottom: 40px;
    }
    .hero-badge-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: #10b981;
      box-shadow: 0 0 12px rgba(16, 185, 129, 0.8);
    }
    .hero-badge-text {
      font-size: 11px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 700;
      letter-spacing: 0.2em;
      color: #10b981;
      text-transform: uppercase;
    }
    h1 {
      font-size: 88px;
      font-weight: 900;
      color: #fafafa;
      letter-spacing: -0.04em;
      text-transform: uppercase;
      line-height: 0.85;
      margin-bottom: 16px;
    }
    h1 .emerald {
      color: #10b981;
    }
    h1 .muted {
      color: #52525b;
    }
    .tagline {
      font-size: 20px;
      color: #a1a1aa;
      margin-top: 32px;
      font-weight: 500;
      max-width: 700px;
      line-height: 1.5;
    }
    .tagline strong {
      color: #fafafa;
    }
    .features {
      display: flex;
      align-items: center;
      gap: 32px;
      margin-top: 40px;
    }
    .feature {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 13px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 500;
      color: #71717a;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .feature .check {
      width: 16px;
      height: 16px;
      color: #10b981;
    }
    .badge {
      position: absolute;
      top: 50px;
      right: 70px;
      background: #10b981;
      padding: 10px 20px;
      border-radius: 8px;
      transform: rotate(3deg);
      box-shadow: 0 4px 20px rgba(16, 185, 129, 0.4);
    }
    .badge span {
      font-size: 14px;
      font-weight: 800;
      font-family: 'JetBrains Mono', monospace;
      color: #000;
      letter-spacing: 0.05em;
      text-transform: uppercase;
    }
    .bottom {
      position: absolute;
      bottom: 36px;
      display: flex;
      align-items: center;
      gap: 16px;
    }
    .bottom span {
      font-size: 13px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 500;
      color: #52525b;
      letter-spacing: 0.05em;
    }
    .bottom .sep { color: #3f3f46; }
  </style>
</head>
<body>
  <div class="container">
    <div class="gradient"></div>
    <div class="grid"></div>
    <div class="corner corner-tl"></div>
    <div class="corner corner-tr"></div>
    <div class="corner corner-bl"></div>
    <div class="corner corner-br"></div>
    <div class="badge"><span>Free</span></div>
    <div class="content">
      <div class="hero-badge">
        <div class="hero-badge-dot"></div>
        <span class="hero-badge-text">Talkie Live</span>
      </div>
      <h1>CAPTURE IDEAS<br/><span class="emerald">BEFORE THEY</span><br/><span class="muted">DISAPPEAR.</span></h1>
      <p class="tagline">Hold a hotkey, speak, release. <strong>Your words appear instantly.</strong></p>
      <div class="features">
        <div class="feature">
          <svg class="check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M20 6L9 17l-5-5"/></svg>
          <span>100% Local</span>
        </div>
        <div class="feature">
          <svg class="check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M20 6L9 17l-5-5"/></svg>
          <span>No Account</span>
        </div>
        <div class="feature">
          <svg class="check" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M20 6L9 17l-5-5"/></svg>
          <span>macOS Menu Bar</span>
        </div>
      </div>
    </div>
    <div class="bottom">
      <span>Voice-to-Text in ~2 seconds</span>
      <span class="sep">|</span>
      <span>talkie.live</span>
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
