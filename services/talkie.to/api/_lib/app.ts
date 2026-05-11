import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { put } from '@vercel/blob';
import { createClerkClient, verifyToken } from '@clerk/backend';
import type { Context, Next } from 'hono';

import {
  WorkflowQueueError,
  WorkflowQueueService,
  type ClaimRunResult,
  type CreateWorkflowRunInput,
  type ExecutorHeartbeatInput,
  type ExecutorRegistrationInput,
} from './workflowQueue.js';

const clerk = createClerkClient({
  secretKey: process.env.CLERK_SECRET_KEY,
  publishableKey: process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY,
});

type Plan = 'free' | 'pro' | 'team';
type Feature = 'cloudSync' | 'aiPolish' | 'prioritySupport' | 'betaFeatures';

interface UserEntitlements {
  userId: string;
  email: string | null;
  plan: Plan;
  features: Feature[];
}

type AuthContext = {
  Variables: {
    userId: string;
    user: UserEntitlements;
  };
};

const app = new Hono<AuthContext>();
const workflowQueue = new WorkflowQueueService();

const DEFAULT_MAC_DOWNLOAD_URL = 'https://github.com/arach/usetalkie.com/releases/latest/download/Talkie.dmg';
const DEFAULT_IOS_INSTALL_URL = 'https://apps.apple.com/us/app/talkie-mobile/id6755734109';
const DEFAULT_LANDING_BASE_URL = 'https://talkie.to';
const DEFAULT_API_BASE_URL = 'https://api.talkie.to';
const TALKIE_ICON_URL = 'https://usetalkie.com/talkie-icon.png';
const TALKIE_OG_IMAGE_URL = 'https://usetalkie.com/og-image.png';
const CLI_INSTALL_COMMAND = 'curl -fsSL go.usetalkie.com/install | bash';
const CLI_ONLY_COMMAND = 'bun add -g @talkie/app';

async function authMiddleware(c: Context<AuthContext>, next: Next) {
  const authHeader = c.req.header('Authorization');

  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing or invalid authorization header' }, 401);
  }

  const token = authHeader.slice(7);

  try {
    const payload = await verifyToken(token, {
      secretKey: process.env.CLERK_SECRET_KEY!,
    });

    const userId = payload.sub;
    const clerkUser = await clerk.users.getUser(userId);
    const user: UserEntitlements = {
      userId,
      email: clerkUser.emailAddresses[0]?.emailAddress || null,
      plan: (clerkUser.publicMetadata?.plan as Plan) || 'free',
      features: getFeaturesByPlan((clerkUser.publicMetadata?.plan as Plan) || 'free'),
    };

    c.set('userId', userId);
    c.set('user', user);

    await next();
  } catch (error) {
    console.error('Auth error:', error);
    return c.json({ error: 'Invalid or expired token' }, 401);
  }
}

function getFeaturesByPlan(plan: Plan): Feature[] {
  switch (plan) {
    case 'team':
      return ['cloudSync', 'aiPolish', 'prioritySupport', 'betaFeatures'];
    case 'pro':
      return ['cloudSync', 'aiPolish', 'prioritySupport'];
    case 'free':
    default:
      return [];
  }
}

function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let index = 0; index < Math.max(pa.length, pb.length); index += 1) {
    const left = pa[index] || 0;
    const right = pb[index] || 0;
    if (left > right) return 1;
    if (left < right) return -1;
  }
  return 0;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value != 'object' || value == null || Array.isArray(value)) {
    throw new WorkflowQueueError('Request body must be a JSON object.', 400);
  }
  return value as Record<string, unknown>;
}

function requiredString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value != 'string' || value.trim().length == 0) {
    throw new WorkflowQueueError(`${key} is required.`, 400);
  }
  return value.trim();
}

function optionalString(body: Record<string, unknown>, key: string): string | undefined {
  const value = body[key];
  if (typeof value != 'string') {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function optionalStringRecord(body: Record<string, unknown>, key: string): Record<string, string> | undefined {
  const value = body[key];
  if (value == null) {
    return undefined;
  }

  if (typeof value != 'object' || Array.isArray(value)) {
    throw new WorkflowQueueError(`${key} must be an object.`, 400);
  }

  const record: Record<string, string> = {};
  for (const [entryKey, entryValue] of Object.entries(value)) {
    if (typeof entryValue != 'string') {
      throw new WorkflowQueueError(`${key}.${entryKey} must be a string.`, 400);
    }
    record[entryKey] = entryValue;
  }
  return record;
}

function requiredStringArray(body: Record<string, unknown>, key: string): string[] {
  const value = body[key];
  if (!Array.isArray(value) || value.some((entry) => typeof entry != 'string')) {
    throw new WorkflowQueueError(`${key} must be an array of strings.`, 400);
  }
  return value.map((entry) => entry.trim()).filter(Boolean);
}

function optionalNumber(body: Record<string, unknown>, key: string): number | undefined {
  const value = body[key];
  if (typeof value != 'number' || Number.isNaN(value)) {
    return undefined;
  }
  return value;
}

function handleWorkflowQueueError(c: Context<AuthContext>, error: unknown) {
  if (error instanceof WorkflowQueueError) {
    return c.json({ error: error.message }, error.status as never);
  }

  console.error('Workflow queue error:', error);
  return c.json({ error: 'Workflow queue request failed.' }, 500);
}

function configuredURL(key: string, fallback: string) {
  const candidate = process.env[key]?.trim();
  return candidate && candidate.length > 0 ? candidate : fallback;
}

function landingBaseURL() {
  return configuredURL('TALKIE_LANDING_BASE_URL', DEFAULT_LANDING_BASE_URL);
}

function apiBaseURL() {
  return configuredURL('TALKIE_API_BASE_URL', DEFAULT_API_BASE_URL);
}

function iosInstallURL() {
  return configuredURL('TALKIE_IOS_INSTALL_URL', DEFAULT_IOS_INSTALL_URL);
}

function macDownloadURL() {
  return configuredURL('TALKIE_MAC_DOWNLOAD_URL', DEFAULT_MAC_DOWNLOAD_URL);
}

function requestURL(c: Context<AuthContext>) {
  return new URL(c.req.url);
}

function forwardedHeaderValue(c: Context<AuthContext>, key: string) {
  const value = c.req.header(key)?.split(',')[0]?.trim();
  return value && value.length > 0 ? value : undefined;
}

function hostName(value: string) {
  return value.replace(/:\d+$/, '').toLowerCase();
}

function requestHost(c: Context<AuthContext>) {
  return hostName(forwardedHeaderValue(c, 'x-forwarded-host') ?? c.req.header('host') ?? requestURL(c).host);
}

function requestProtocol(c: Context<AuthContext>) {
  return (forwardedHeaderValue(c, 'x-forwarded-proto') ?? requestURL(c).protocol.replace(':', '')).toLowerCase();
}

function requestOrigin(c: Context<AuthContext>) {
  return `${requestProtocol(c)}://${requestHost(c)}`;
}

function normalizedPathQuery(c: Context<AuthContext>) {
  const url = requestURL(c);
  const forwardedPath = url.searchParams.get('path');
  if (!forwardedPath) {
    return url.search;
  }

  const expectedPath = url.pathname.replace(/^\/api\/?/, '');
  if (forwardedPath.replace(/^\/+/, '') != expectedPath.replace(/^\/+/, '')) {
    return url.search;
  }

  const params = new URLSearchParams(url.search);
  params.delete('path');
  const nextQuery = params.toString();
  return nextQuery.length > 0 ? `?${nextQuery}` : '';
}

function isPreviewOrLocalHost(host: string) {
  return host == 'localhost'
    || host == '127.0.0.1'
    || host.endsWith('.localhost')
    || host.endsWith('.vercel.app');
}

function isLandingHost(host: string) {
  const configuredLandingHost = hostName(new URL(landingBaseURL()).host);
  return host == 'talkie.to' || host == 'www.talkie.to' || host == configuredLandingHost;
}

function isAPIHost(host: string) {
  return host == hostName(new URL(apiBaseURL()).host);
}

function landingBaseURLFor(c: Context<AuthContext>) {
  const host = requestHost(c);
  if (isLandingHost(host) || isPreviewOrLocalHost(host)) {
    return requestOrigin(c);
  }
  return landingBaseURL();
}

function installQRCodeURL(c: Context<AuthContext>) {
  const installLink = new URL('/install', landingBaseURLFor(c)).toString();
  const qrBase = 'https://api.qrserver.com/v1/create-qr-code/';
  const query = new URLSearchParams({
    size: '224x224',
    format: 'png',
    data: installLink,
  });
  return `${qrBase}?${query.toString()}`;
}

function escapeHTML(value: string) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function renderLandingPage(c: Context<AuthContext>) {
  const pageTitle = 'Talkie';
  const pageDescription = 'Voice memos that turn into actions across your phone and Mac.';
  const pageURL = landingBaseURLFor(c);
  const installLink = new URL('/install', pageURL).toString();
  const downloadLink = new URL('/download', pageURL).toString();
  const qrURL = installQRCodeURL(c);

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHTML(pageTitle)}</title>
    <meta name="description" content="${escapeHTML(pageDescription)}" />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="${escapeHTML(pageURL)}" />
    <meta property="og:title" content="${escapeHTML(pageTitle)} — Voice + AI" />
    <meta property="og:description" content="${escapeHTML(pageDescription)}" />
    <meta property="og:image" content="${escapeHTML(TALKIE_OG_IMAGE_URL)}" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${escapeHTML(pageTitle)} — Voice + AI" />
    <meta name="twitter:description" content="${escapeHTML(pageDescription)}" />
    <meta name="twitter:image" content="${escapeHTML(TALKIE_OG_IMAGE_URL)}" />
    <link rel="icon" href="${escapeHTML(TALKIE_ICON_URL)}" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600;700&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet" />
    <style>
      :root {
        color-scheme: light;
        --bg: #f5f5f4;
        --panel: rgba(255, 255, 255, 0.84);
        --panel-strong: rgba(255, 255, 255, 0.95);
        --text: #18181b;
        --muted: #71717a;
        --line: rgba(39, 39, 42, 0.1);
        --accent: #059669;
        --shadow: 0 22px 42px rgba(24, 24, 27, 0.1);
        --shadow-soft: 0 10px 24px rgba(24, 24, 27, 0.05);
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        min-height: 100vh;
        font-family: "Space Grotesk", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: var(--text);
        background: var(--bg);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }

      body::before {
        content: "";
        position: fixed;
        inset: 0;
        pointer-events: none;
        background-image:
          linear-gradient(rgba(113, 113, 122, 0.06) 1px, transparent 1px),
          linear-gradient(90deg, rgba(113, 113, 122, 0.06) 1px, transparent 1px);
        background-size: 34px 34px;
        mask-image: radial-gradient(circle at center, rgba(0, 0, 0, 0.72), transparent 88%);
        opacity: 0.28;
      }

      main {
        width: min(1050px, 100%);
        position: relative;
        z-index: 1;
      }

      .logo-row {
        display: flex;
        justify-content: center;
        align-items: center;
        gap: 12px;
        margin-bottom: 28px;
        text-decoration: none;
        color: inherit;
      }

      .logo-row img {
        width: 48px;
        height: 48px;
        border-radius: 12px;
        display: block;
        box-shadow: var(--shadow-soft);
      }

      .logo-row span {
        font-family: "JetBrains Mono", ui-monospace, monospace;
        font-size: 2rem;
        font-weight: 700;
        letter-spacing: -0.05em;
        text-transform: uppercase;
      }

      .grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 24px;
      }

      .card {
        overflow: hidden;
        border: 1px solid rgba(228, 228, 231, 0.9);
        border-radius: 14px;
        background: var(--panel);
        box-shadow: var(--shadow);
        backdrop-filter: blur(18px);
      }

      .card-head {
        padding: 24px 24px 20px;
        text-align: center;
        background: rgba(250, 250, 249, 0.7);
        border-bottom: 1px solid rgba(228, 228, 231, 0.9);
      }

      .card-head svg {
        width: 32px;
        height: 32px;
        margin: 0 auto 10px;
        display: block;
        color: var(--accent);
      }

      .card-head h2 {
        margin: 0;
        font-family: "JetBrains Mono", ui-monospace, monospace;
        font-size: 1rem;
        font-weight: 700;
        letter-spacing: -0.04em;
        text-transform: uppercase;
      }

      .card-head p {
        margin: 10px 0 0;
        color: var(--muted);
        font: 500 0.84rem/1.45 "JetBrains Mono", ui-monospace, monospace;
      }

      .card-body {
        padding: 24px;
      }

      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 100%;
        min-height: 40px;
        padding: 0 14px;
        border-radius: 8px;
        border: 1px solid transparent;
        text-decoration: none;
        font-family: "JetBrains Mono", ui-monospace, monospace;
        font-size: 0.82rem;
        font-weight: 700;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        transition: transform 120ms ease, box-shadow 120ms ease;
      }

      .button:hover {
        transform: translateY(-1px);
      }

      .button-primary {
        background: var(--accent);
        color: white;
        box-shadow: 0 10px 22px rgba(5, 150, 105, 0.14);
      }

      .stack {
        display: grid;
        gap: 16px;
      }

      .section-title {
        display: flex;
        align-items: center;
        gap: 8px;
        margin: 0 0 8px;
        color: var(--muted);
        font: 700 0.62rem/1 "JetBrains Mono", ui-monospace, monospace;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .section-title::before {
        content: ">";
        color: #a1a1aa;
      }

      .command-wrap {
        display: grid;
        gap: 6px;
      }

      .command {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: center;
        gap: 12px;
        padding: 12px 14px;
        border-radius: 10px;
        border: 1px solid rgba(39, 39, 42, 0.9);
        background: #09090b;
        color: #fafafa;
        font: 500 0.84rem/1.3 "JetBrains Mono", ui-monospace, monospace;
        overflow: hidden;
      }

      .command code {
        color: #fafafa;
        background: transparent;
        padding: 0;
        font-size: 0.84rem;
        white-space: nowrap;
        overflow-x: auto;
      }

      .command-prefix {
        color: #10b981;
        margin-right: 8px;
      }

      .copy-button {
        border: 0;
        background: transparent;
        color: #71717a;
        font: 500 0.68rem/1 "JetBrains Mono", ui-monospace, monospace;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        cursor: pointer;
      }

      .copy-button:hover {
        color: #d4d4d8;
      }

      .hint {
        color: #a1a1aa;
        font: 500 0.72rem/1.45 "JetBrains Mono", ui-monospace, monospace;
      }

      .trust-row {
        display: flex;
        flex-wrap: wrap;
        gap: 14px;
        padding-top: 2px;
        color: #a1a1aa;
        font: 500 0.72rem/1 "JetBrains Mono", ui-monospace, monospace;
        text-transform: uppercase;
      }

      .trust-item {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }

      .trust-item svg {
        width: 12px;
        height: 12px;
        color: #10b981;
      }

      .qr-title {
        margin: 0 0 12px;
        color: var(--muted);
        font: 700 0.62rem/1 "JetBrains Mono", ui-monospace, monospace;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .qr-shell {
        display: flex;
        justify-content: center;
        width: 100%;
      }

      .qr-frame {
        width: min(100%, 240px);
        aspect-ratio: 1;
        padding: 16px;
        display: grid;
        place-items: center;
        border-radius: 14px;
        background: var(--panel-strong);
        border: 1px solid rgba(228, 228, 231, 0.95);
        box-shadow: 0 2px 8px rgba(24, 24, 27, 0.03);
      }

      .qr-frame img {
        width: 100%;
        max-width: 192px;
        height: auto;
        display: block;
        border-radius: 10px;
        image-rendering: -webkit-optimize-contrast;
        image-rendering: crisp-edges;
      }

      .footer-links {
        margin-top: 28px;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: center;
        gap: 12px;
        color: var(--muted);
        font: 500 0.78rem/1 "JetBrains Mono", ui-monospace, monospace;
        text-transform: uppercase;
      }

      .footer-links a {
        color: inherit;
        text-decoration: none;
      }

      .footer-links a:hover {
        color: var(--text);
      }

      .footer-links span {
        color: #d4d4d8;
      }

      footer {
        margin-top: 18px;
        text-align: center;
        color: #a1a1aa;
        font: 500 0.7rem/1 "JetBrains Mono", ui-monospace, monospace;
        text-transform: uppercase;
        letter-spacing: 0.08em;
      }

      @media (max-width: 900px) {
        .grid { grid-template-columns: 1fr; }
      }
    </style>
  </head>
  <body>
    <main>
      <a class="logo-row" href="${escapeHTML(landingBaseURLFor(c))}">
        <img src="${escapeHTML(TALKIE_ICON_URL)}" alt="Talkie" />
        <span>Talkie</span>
      </a>

      <div class="grid">
        <section class="card">
          <div class="card-head">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M4 18h16" />
              <path d="M6 6h12a1 1 0 0 1 1 1v8H5V7a1 1 0 0 1 1-1Z" />
            </svg>
            <h2>Mac</h2>
            <p>macOS 26+ • Apple Silicon</p>
          </div>
          <div class="card-body">
            <div class="stack">
              <div class="command-wrap">
                <p class="section-title">Install via terminal</p>
                <div class="command">
                  <div><span class="command-prefix">&gt;</span><code>${escapeHTML(CLI_ONLY_COMMAND)}</code></div>
                  <button class="copy-button" type="button" data-copy="${escapeHTML(CLI_ONLY_COMMAND)}">Copy</button>
                </div>
                <div class="hint">Installs the app and CLI. Run <code>talkie open</code> to launch.</div>
              </div>

              <a class="button button-primary" href="${escapeHTML(downloadLink)}">Download DMG</a>

              <div class="command-wrap">
                <p class="section-title">CLI only</p>
                <div class="command">
                  <div><span class="command-prefix">&gt;</span><code>bun add -g @talkie/cli</code></div>
                  <button class="copy-button" type="button" data-copy="bun add -g @talkie/cli">Copy</button>
                </div>
                <div class="hint">Query memos, dictations, and workflows from the terminal.</div>
              </div>

              <div class="trust-row">
                <div class="trust-item">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <circle cx="8" cy="8" r="6" />
                    <path d="m5.5 8 1.6 1.6L10.8 6" />
                  </svg>
                  <span>Signed & Notarized</span>
                </div>
                <div class="trust-item">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                    <path d="M8 2.5 12 4v3.2c0 2.4-1.5 4.5-4 6.3-2.5-1.8-4-3.9-4-6.3V4l4-1.5Z" />
                  </svg>
                  <span>Local-first</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section class="card">
          <div class="card-head">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <rect x="8" y="2.75" width="8" height="18.5" rx="1.75" />
              <path d="M11 18h2" />
            </svg>
            <h2>iPhone</h2>
            <p>iOS 26+</p>
          </div>
          <div class="card-body">
            <div class="stack">
              <a class="button button-primary" href="${escapeHTML(installLink)}">App Store</a>

              <div>
                <p class="qr-title">Or scan with your phone</p>
                <div class="qr-shell">
                  <div class="qr-frame">
                    <img src="${escapeHTML(qrURL)}" alt="QR code to install Talkie on iPhone" />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>

      <div class="footer-links">
        <a href="https://usetalkie.com">usetalkie.com</a>
        <span>•</span>
        <a href="https://usetalkie.com/docs">Documentation</a>
        <span>•</span>
        <a href="https://usetalkie.com/security">Security</a>
        <span>•</span>
        <a href="https://usetalkie.com/philosophy">Philosophy</a>
        <span>•</span>
        <a href="mailto:hello@usetalkie.com">Support</a>
      </div>

      <footer>
        Your data stays yours • Local-first • Private by default
      </footer>
    </main>
    <script>
      document.querySelectorAll('.copy-button').forEach((button) => {
        button.addEventListener('click', async () => {
          const text = button.getAttribute('data-copy');
          if (!text) return;
          const original = button.textContent;
          try {
            await navigator.clipboard.writeText(text);
            button.textContent = 'Copied';
          } catch (error) {
            button.textContent = 'Error';
          }
          window.setTimeout(() => {
            button.textContent = original;
          }, 1800);
        });
      });
    </script>
  </body>
</html>`;
}

function renderAPIHomePage() {
  const apiRoot = apiBaseURL();
  const publicRoot = landingBaseURL();

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Talkie API</title>
    <meta name="description" content="Product APIs for Talkie on iPhone and Mac." />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="Talkie API" />
    <meta property="og:description" content="Product APIs for Talkie on iPhone and Mac." />
    <meta property="og:image" content="${escapeHTML(TALKIE_OG_IMAGE_URL)}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:image" content="${escapeHTML(TALKIE_OG_IMAGE_URL)}" />
    <link rel="icon" href="${escapeHTML(TALKIE_ICON_URL)}" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet" />
    <style>
      :root {
        color-scheme: light;
        --bg: #fafaf9;
        --panel: rgba(255, 255, 255, 0.9);
        --text: #18181b;
        --muted: #52525b;
        --line: rgba(39, 39, 42, 0.1);
        --accent: #059669;
      }

      * { box-sizing: border-box; }

      body {
        margin: 0;
        min-height: 100vh;
        background: var(--bg);
        color: var(--text);
        font-family: "Space Grotesk", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      body::before {
        content: "";
        position: fixed;
        inset: 0;
        pointer-events: none;
        background-image:
          linear-gradient(rgba(113, 113, 122, 0.06) 1px, transparent 1px),
          linear-gradient(90deg, rgba(113, 113, 122, 0.06) 1px, transparent 1px);
        background-size: 34px 34px;
        mask-image: radial-gradient(circle at center, rgba(0, 0, 0, 0.72), transparent 88%);
        opacity: 0.2;
      }

      main {
        width: min(920px, calc(100vw - 32px));
        margin: 0 auto;
        padding: 40px 0 56px;
        position: relative;
        z-index: 1;
      }

      .panel {
        border: 1px solid var(--line);
        border-radius: 10px;
        background: var(--panel);
        padding: 24px;
        box-shadow: 0 18px 40px rgba(24, 24, 27, 0.06);
        backdrop-filter: blur(18px);
      }

      .eyebrow {
        color: #047857;
        font: 500 0.66rem/1 "JetBrains Mono", ui-monospace, monospace;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      h1 {
        margin: 12px 0 10px;
        font-size: clamp(2rem, 4.5vw, 3.4rem);
        line-height: 0.95;
        letter-spacing: -0.06em;
        font-weight: 600;
      }

      p {
        margin: 0;
        color: var(--muted);
        font-size: 0.92rem;
        line-height: 1.55;
        font-weight: 400;
      }

      .chips,
      .links {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-top: 20px;
      }

      .chip,
      a {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-height: 38px;
        padding: 0 12px;
        border-radius: 8px;
        border: 1px solid var(--line);
        background: rgba(255, 255, 255, 0.84);
        color: inherit;
        text-decoration: none;
      }

      .chip strong {
        color: var(--accent);
        font: 500 0.63rem/1 "JetBrains Mono", ui-monospace, monospace;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 14px;
        margin-top: 24px;
      }

      .card {
        border: 1px solid var(--line);
        border-radius: 10px;
        background: rgba(255, 255, 255, 0.8);
        padding: 16px;
      }

      .card strong,
      code {
        font-family: "JetBrains Mono", ui-monospace, monospace;
      }

      .card strong {
        display: block;
        margin-bottom: 8px;
        color: #047857;
        font-size: 0.64rem;
        font-weight: 500;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }

      .card p {
        font-size: 0.86rem;
      }

      code {
        font-size: 0.84em;
      }

      @media (max-width: 760px) {
        .grid {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </head>
  <body>
    <main>
      <section class="panel">
        <div class="eyebrow">api.talkie.to</div>
        <h1>Talkie API</h1>
        <p>
          This host powers the app-facing Talkie APIs for iPhone and Mac, including
          flags, authenticated user state, and live workflow execution.
        </p>

        <div class="chips">
          <span class="chip"><strong>API</strong>${escapeHTML(apiRoot)}</span>
          <span class="chip"><strong>Landing</strong>${escapeHTML(publicRoot)}</span>
        </div>

        <div class="links">
          <a href="${escapeHTML(publicRoot)}">Open talkie.to</a>
          <a href="${escapeHTML(new URL('/api/flags', apiRoot).toString())}">View flags</a>
          <a href="${escapeHTML(new URL('/health', apiRoot).toString())}">Health</a>
        </div>

        <div class="grid">
          <div class="card">
            <strong>Public</strong>
            <p><code>GET /api/flags</code> for app feature flags and other unauthenticated client metadata.</p>
          </div>
          <div class="card">
            <strong>User</strong>
            <p><code>GET /api/user</code> and <code>GET /api/user/flags</code> for authenticated app state.</p>
          </div>
          <div class="card">
            <strong>Workflow Runs</strong>
            <p><code>/api/workflow-runs</code> handles live Mac workflow creation, status, and leases.</p>
          </div>
          <div class="card">
            <strong>Executors</strong>
            <p><code>/api/executors/*</code> is the lightweight control plane for signed-in Macs.</p>
          </div>
        </div>
      </section>
    </main>
  </body>
</html>`;
}

function prefersHTML(c: Context<AuthContext>) {
  const accept = c.req.header('Accept') ?? '';
  return accept.includes('text/html') || accept.includes('application/xhtml+xml');
}

app.use('*', logger());
app.use('*', cors());

app.use('/api/*', async (c, next) => {
  const host = requestHost(c);
  if (isLandingHost(host)) {
    const url = requestURL(c);
    const destination = new URL(`${url.pathname}${normalizedPathQuery(c)}`, apiBaseURL());
    return c.redirect(destination.toString(), 307);
  }

  await next();
});

app.get('/', (c) => {
  if (isAPIHost(requestHost(c))) {
    if (prefersHTML(c)) {
      return c.html(renderAPIHomePage());
    }

    return c.json({
      status: 'ok',
      service: 'talkie.to',
      kind: 'api',
      hosts: {
        api: apiBaseURL(),
        landing: landingBaseURL(),
      },
    });
  }

  return c.html(renderLandingPage(c));
});

app.get('/health', (c) =>
  c.json({
    status: 'ok',
    service: 'talkie.to',
    host: requestHost(c),
    role: isAPIHost(requestHost(c)) ? 'api' : 'landing',
  })
);

app.get('/install', (c) => c.redirect(iosInstallURL(), 302));

app.get('/download', (c) => c.redirect(macDownloadURL(), 302));

app.get('/api/flags', (c) => {
  const version = c.req.query('version');
  const build = c.req.query('build');
  const platform = c.req.query('platform');

  const flagConfig: Record<string, { enabled: boolean; minVersion?: string }> = {
    showConnectionCenter: { enabled: false },
    paywallEnabled: { enabled: false },
    showProFeatures: { enabled: false },
    enableCloudSync: { enabled: false },
    showDebugInfo: { enabled: false },
    enableAutoUpdates: { enabled: true },
  };

  const flags: Record<string, boolean> = {};
  for (const [key, config] of Object.entries(flagConfig)) {
    let enabled = config.enabled;
    if (config.minVersion && version) {
      enabled = enabled && compareVersions(version, config.minVersion) >= 0;
    }
    flags[key] = enabled;
  }

  return c.json({
    flags,
    meta: {
      version,
      build,
      platform,
      timestamp: new Date().toISOString(),
    },
  });
});

app.get('/api/user', authMiddleware, async (c) => {
  const user = c.get('user');
  return c.json({
    user,
    timestamp: new Date().toISOString(),
  });
});

app.get('/api/user/flags', authMiddleware, async (c) => {
  const user = c.get('user');
  const version = c.req.query('version');

  return c.json({
    flags: {
      enableAutoUpdates: true,
      enableCloudSync: user.features.includes('cloudSync'),
      enableAiPolish: user.features.includes('aiPolish'),
      showProFeatures: user.plan != 'free',
      showBetaFeatures: user.features.includes('betaFeatures'),
    },
    plan: user.plan,
    features: user.features,
    meta: {
      userId: user.userId,
      version,
      timestamp: new Date().toISOString(),
    },
  });
});

app.post('/api/workflow-runs', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const input: CreateWorkflowRunInput = {
      workflowId: requiredString(body, 'workflowId'),
      workflowName: requiredString(body, 'workflowName'),
      workflowIcon: optionalString(body, 'workflowIcon'),
      memoId: requiredString(body, 'memoId'),
      requestedByDeviceId: optionalString(body, 'requestedByDeviceId'),
    };

    const run = await workflowQueue.createRun(c.get('userId'), input);
    return c.json({ run }, 201);
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.get('/api/workflow-runs/claimable', authMiddleware, async (c) => {
  try {
    const limit = Number.parseInt(c.req.query('limit') ?? '20', 10);
    const runs = await workflowQueue.listClaimableRuns(
      c.get('userId'),
      Number.isFinite(limit) ? Math.max(1, Math.min(limit, 100)) : 20
    );
    return c.json({ runs });
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.get('/api/workflow-runs', authMiddleware, async (c) => {
  try {
    const memoId = c.req.query('memoId')?.trim();
    const runs = await workflowQueue.listRuns(c.get('userId'), memoId || undefined);
    return c.json({ runs });
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.get('/api/workflow-runs/:id', authMiddleware, async (c) => {
  try {
    const details = await workflowQueue.getRunDetails(c.get('userId'), c.req.param('id'));
    if (!details) {
      return c.json({ error: 'Workflow run not found.' }, 404);
    }
    return c.json(details);
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/executors/register', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const input: ExecutorRegistrationInput = {
      deviceId: requiredString(body, 'deviceId'),
      name: requiredString(body, 'name'),
      platform: requiredString(body, 'platform'),
      status: requiredString(body, 'status'),
      priority: optionalNumber(body, 'priority') ?? 100,
      capabilities: requiredStringArray(body, 'capabilities'),
      installId: optionalString(body, 'installId'),
      appVersion: optionalString(body, 'appVersion'),
      tailscaleHostname: optionalString(body, 'tailscaleHostname'),
      metadata: optionalStringRecord(body, 'metadata'),
    };

    const result = await workflowQueue.registerExecutor(c.get('userId'), input);
    return c.json(result);
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/executors/heartbeat', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const input: ExecutorHeartbeatInput = {
      deviceId: requiredString(body, 'deviceId'),
      status: requiredString(body, 'status'),
      claimedRunId: optionalString(body, 'claimedRunId'),
      metadata: optionalStringRecord(body, 'metadata'),
    };

    const result = await workflowQueue.heartbeatExecutor(c.get('userId'), input);
    return c.json(result);
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/workflow-runs/:id/claim', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const result: ClaimRunResult = await workflowQueue.claimRun(
      c.get('userId'),
      c.req.param('id'),
      requiredString(body, 'deviceId'),
      optionalString(body, 'backendId')
    );
    return c.json(result);
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/workflow-runs/:id/start', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    await workflowQueue.startRun(
      c.get('userId'),
      c.req.param('id'),
      requiredString(body, 'deviceId'),
      requiredString(body, 'leaseToken'),
      optionalString(body, 'backendId')
    );
    return c.json({ ok: true });
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/workflow-runs/:id/renew', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const result = await workflowQueue.renewLease(
      c.get('userId'),
      c.req.param('id'),
      requiredString(body, 'deviceId'),
      requiredString(body, 'leaseToken')
    );
    return c.json(result);
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/workflow-runs/:id/release', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    await workflowQueue.releaseRun(
      c.get('userId'),
      c.req.param('id'),
      requiredString(body, 'deviceId'),
      requiredString(body, 'leaseToken'),
      optionalString(body, 'reason')
    );
    return c.json({ ok: true });
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/workflow-runs/:id/complete', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const finalOutputs = optionalStringRecord(body, 'finalOutputs') ?? {};
    const run = await workflowQueue.completeRun(
      c.get('userId'),
      c.req.param('id'),
      requiredString(body, 'deviceId'),
      requiredString(body, 'leaseToken'),
      optionalString(body, 'backendId'),
      finalOutputs,
      optionalString(body, 'output'),
      optionalString(body, 'stepOutputsJSON')
    );
    return c.json({ ok: true, run });
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/workflow-runs/:id/fail', authMiddleware, async (c) => {
  try {
    const body = asRecord(await c.req.json());
    const errorRecord = asRecord(body.error);
    const run = await workflowQueue.failRun(
      c.get('userId'),
      c.req.param('id'),
      requiredString(body, 'deviceId'),
      requiredString(body, 'leaseToken'),
      optionalString(body, 'backendId'),
      requiredString(errorRecord, 'message')
    );
    return c.json({ ok: true, run });
  } catch (error) {
    return handleWorkflowQueueError(c, error);
  }
});

app.post('/api/report', async (c) => {
  try {
    const body = await c.req.json();
    const reportId = body.id || `report-${Date.now()}`;
    const timestamp = new Date().toISOString();
    const report = { ...body, id: reportId, timestamp };

    if (!process.env.BLOB_READ_WRITE_TOKEN) {
      return c.json({ success: false, error: 'Storage not configured' }, 500);
    }

    const blob = await put(`reports/${reportId}.json`, JSON.stringify(report, null, 2), {
      contentType: 'application/json',
      access: 'public',
    });

    return c.json({ success: true, id: reportId, url: blob.url });
  } catch (error) {
    console.error('Report error:', error);
    return c.json(
      {
        success: false,
        error: 'Failed to save report',
        message: error instanceof Error ? error.message : 'Unknown error',
      },
      500
    );
  }
});

export default app;
