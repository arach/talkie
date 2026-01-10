"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowRight, Package, CheckCircle2, AlertCircle, ExternalLink } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'what-is-talkieserver', title: 'What is TalkieServer?', level: 2 },
  { id: 'prerequisites', title: 'Prerequisites', level: 2 },
  { id: 'what-gets-installed', title: 'What Gets Installed', level: 2 },
  { id: 'installation', title: 'Installation Steps', level: 2 },
  { id: 'manual', title: 'Manual Installation', level: 2 },
  { id: 'troubleshooting', title: 'Troubleshooting', level: 2 },
  { id: 'next-steps', title: 'Next Steps', level: 2 },
]

const CodeBlock = ({ children, title }) => (
  <div className="rounded-lg border border-zinc-800 overflow-hidden my-4 not-prose">
    {title && (
      <div className="px-4 py-2 bg-zinc-800 border-b border-zinc-700">
        <span className="text-xs font-mono text-zinc-400">{title}</span>
      </div>
    )}
    <pre className="p-4 bg-zinc-900 overflow-x-auto">
      <code className="text-sm font-mono text-zinc-300">{children}</code>
    </pre>
  </div>
)

const Step = ({ number, title, children }) => (
  <div className="flex gap-4 md:gap-6 not-prose">
    <div className="flex-shrink-0 w-8 h-8 rounded-full bg-emerald-100 dark:bg-emerald-500/20 flex items-center justify-center">
      <span className="text-sm font-bold text-emerald-600 dark:text-emerald-400">{number}</span>
    </div>
    <div className="flex-1 pb-6">
      <h4 className="text-lg font-bold text-zinc-900 dark:text-white mb-2">{title}</h4>
      <div className="text-zinc-600 dark:text-zinc-400 space-y-3">{children}</div>
    </div>
  </div>
)

const InfoBox = ({ type = 'info', children }) => {
  const styles = {
    info: 'bg-blue-50 dark:bg-blue-500/10 border-blue-200 dark:border-blue-500/30 text-blue-800 dark:text-blue-300',
    warning: 'bg-amber-50 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/30 text-amber-800 dark:text-amber-300',
  }
  const Icon = type === 'warning' ? AlertCircle : CheckCircle2

  return (
    <div className={`flex gap-3 p-4 rounded-lg border ${styles[type]} not-prose`}>
      <Icon className="w-5 h-5 flex-shrink-0 mt-0.5" />
      <div className="text-sm">{children}</div>
    </div>
  )
}

export default function BridgeSetupPage() {
  return (
    <DocsLayout
      title="TalkieServer Setup"
      description="TalkieServer is a lightweight local service that enables communication between your Mac and iPhone. It runs on your Mac and handles secure pairing and data sync."
      badge="Setup Guide"
      badgeColor="emerald"
      sections={sections}
    >
      {/* What is TalkieServer */}
      <h2 id="what-is-talkieserver">What is TalkieServer?</h2>
      <p>
        TalkieServer is a TypeScript service that runs locally on your Mac. It acts as a bridge between the Talkie Mac app and the Talkie iPhone app, enabling:
      </p>
      <ul>
        <li><strong>Device Pairing</strong> — Securely connect your iPhone to your Mac</li>
        <li><strong>Voice Sync</strong> — Transfer voice recordings from iPhone to Mac</li>
        <li><strong>Local Processing</strong> — All data stays on your network, never touches external servers</li>
      </ul>

      {/* Prerequisites */}
      <h2 id="prerequisites">Prerequisites</h2>

      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-2">
          <Package className="w-5 h-5 text-orange-500" />
          <h4 className="font-bold text-zinc-900 dark:text-white">Bun Runtime</h4>
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
          Bun is a fast JavaScript runtime that TalkieServer uses. It's similar to Node.js but significantly faster.
        </p>
        <a
          href="https://bun.sh"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-sm font-medium text-emerald-600 dark:text-emerald-400 hover:underline"
        >
          Install Bun <ExternalLink className="w-3 h-3" />
        </a>
      </div>

      <InfoBox type="info">
        Talkie will prompt you to install Bun if it's not detected. You can also install it manually:
        <code className="block mt-2 px-2 py-1 bg-blue-100 dark:bg-blue-900/50 rounded font-mono text-xs">
          curl -fsSL https://bun.sh/install | bash
        </code>
      </InfoBox>

      {/* What Gets Installed */}
      <h2 id="what-gets-installed">What Gets Installed</h2>
      <p>
        When you enable iPhone connectivity, Talkie installs the following packages locally:
      </p>

      <div className="rounded-lg border border-zinc-200 dark:border-zinc-800 overflow-hidden my-4 not-prose">
        <table className="w-full text-sm">
          <thead className="bg-zinc-100 dark:bg-zinc-800">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-zinc-900 dark:text-white">Package</th>
              <th className="px-4 py-3 text-left font-medium text-zinc-900 dark:text-white">Purpose</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-zinc-800 dark:text-zinc-200">elysia</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Fast HTTP server framework</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-zinc-800 dark:text-zinc-200">@elysiajs/cors</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Cross-origin request handling</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-zinc-800 dark:text-zinc-200">tweetnacl</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Cryptographic operations for secure pairing</td>
            </tr>
          </tbody>
        </table>
      </div>

      <InfoBox type="info">
        All packages are installed locally in the TalkieServer directory within the app. They don't affect your system or other projects.
      </InfoBox>

      {/* Installation Steps */}
      <h2 id="installation">Installation Steps</h2>

      <div className="space-y-2 my-6">
        <Step number="1" title="Open Talkie Settings">
          <p>Click the Talkie menu bar icon and select Settings, or press <code className="px-1.5 py-0.5 bg-zinc-200 dark:bg-zinc-800 rounded text-sm font-mono">⌘,</code></p>
        </Step>

        <Step number="2" title="Navigate to iPhone Sync">
          <p>Select the "iPhone" tab in the settings sidebar.</p>
        </Step>

        <Step number="3" title="Enable TalkieServer">
          <p>
            Click "Enable iPhone Sync". Talkie will check for prerequisites and prompt you to install any missing dependencies.
          </p>
          <InfoBox type="warning">
            If Bun is not installed, you'll be prompted to install it first. This requires an internet connection.
          </InfoBox>
        </Step>

        <Step number="4" title="Install Dependencies">
          <p>
            When prompted, click "Install Dependencies" to run <code className="px-1.5 py-0.5 bg-zinc-200 dark:bg-zinc-800 rounded text-sm font-mono">bun install</code>. This downloads the required packages (typically takes a few seconds).
          </p>
        </Step>

        <Step number="5" title="Start the Server">
          <p>
            Once dependencies are installed, TalkieServer will start automatically. You'll see a green status indicator when it's running.
          </p>
        </Step>
      </div>

      {/* Manual Installation */}
      <h2 id="manual">Manual Installation</h2>
      <p>
        If you prefer to install dependencies manually (or need to troubleshoot):
      </p>

      <CodeBlock title="Terminal">
{`# Navigate to TalkieServer directory
cd ~/Library/Application\\ Support/Talkie/TalkieServer

# Install dependencies
bun install

# (Optional) Start server manually
bun run src/server.ts`}
      </CodeBlock>

      {/* Troubleshooting */}
      <h2 id="troubleshooting">Troubleshooting</h2>

      <div className="space-y-4 my-6 not-prose">
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"Bun not found"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Install Bun from <a href="https://bun.sh" className="text-emerald-600 dark:text-emerald-400 hover:underline">bun.sh</a>, then restart Talkie.
          </p>
        </div>

        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"Cannot find package 'elysia'"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Dependencies are missing. Click "Install Dependencies" in settings, or run <code className="px-1 py-0.5 bg-zinc-100 dark:bg-zinc-800 rounded font-mono text-xs">bun install</code> manually.
          </p>
        </div>

        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"Port 8765 already in use"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Another process is using the port. Restart Talkie — it will automatically clean up stray processes.
          </p>
        </div>
      </div>

      {/* Next Steps */}
      <h2 id="next-steps">Next Steps</h2>
      <p>
        TalkieServer is now ready. Next, set up Tailscale to enable secure networking between your Mac and iPhone.
      </p>

      <Link
        href="/docs/tailscale"
        className="group flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-blue-300 dark:hover:border-blue-500/50 transition-colors not-prose"
      >
        <div>
          <span className="font-bold text-zinc-900 dark:text-white group-hover:text-blue-600 dark:group-hover:text-blue-400 transition-colors">
            Configure Tailscale
          </span>
          <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
            Set up secure networking between your Mac and iPhone
          </p>
        </div>
        <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-blue-500 group-hover:translate-x-1 transition-all" />
      </Link>
    </DocsLayout>
  )
}
