"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Terminal } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'talkieserver', title: 'TalkieServer Endpoints', level: 2 },
  { id: 'health', title: 'Health Check', level: 3 },
  { id: 'pair', title: 'Pairing', level: 3 },
  { id: 'memos', title: 'Memos', level: 3 },
  { id: 'url-schemes', title: 'URL Schemes', level: 2 },
  { id: 'applescript', title: 'AppleScript', level: 2 },
  { id: 'shortcuts', title: 'Shortcuts', level: 2 },
  { id: 'navigation', title: 'Continue Reading', level: 2 },
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

const EndpointCard = ({ method, path, description, response }) => {
  const methodColors = {
    GET: 'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-700 dark:text-emerald-400',
    POST: 'bg-blue-100 dark:bg-blue-500/20 text-blue-700 dark:text-blue-400',
    PUT: 'bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-400',
    DELETE: 'bg-red-100 dark:bg-red-500/20 text-red-700 dark:text-red-400',
  }

  return (
    <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
      <div className="flex items-center gap-3 mb-2">
        <span className={`px-2 py-0.5 text-xs font-bold rounded ${methodColors[method]}`}>
          {method}
        </span>
        <code className="text-sm font-mono text-zinc-800 dark:text-zinc-200">{path}</code>
      </div>
      <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-2">{description}</p>
      {response && (
        <pre className="mt-2 p-2 bg-zinc-100 dark:bg-zinc-800 rounded text-xs font-mono text-zinc-600 dark:text-zinc-400 overflow-x-auto">
          {response}
        </pre>
      )}
    </div>
  )
}

export default function ApiPage() {
  return (
    <DocsLayout
      title="API Reference"
      description="Integration points for developers. HTTP endpoints, URL schemes, and programmatic access to Talkie."
      badge="Reference"
      badgeColor="amber"
      sections={sections}
    >
      {/* TalkieServer HTTP Endpoints */}
      <h2 id="talkieserver">TalkieServer HTTP Endpoints</h2>
      <p>
        TalkieServer runs locally on your Mac and exposes HTTP endpoints for iOS connectivity and local integrations. By default, it listens on <code>localhost:8765</code>.
      </p>
      <p>
        When paired with Tailscale, the same endpoints are accessible from your iPhone using your Mac's Tailscale IP address.
      </p>

      <h3 id="health">Health Check</h3>
      <div className="space-y-3 my-4">
        <EndpointCard
          method="GET"
          path="/health"
          description="Check if TalkieServer is running and get version info."
          response={`{ "status": "ok", "version": "1.0.0" }`}
        />
      </div>

      <h3 id="pair">Pairing</h3>
      <div className="space-y-3 my-4">
        <EndpointCard
          method="GET"
          path="/pair"
          description="Returns pairing information displayed as a QR code in Talkie settings."
          response={`{ "publicKey": "...", "ip": "100.x.x.x", "port": 8765 }`}
        />
        <EndpointCard
          method="POST"
          path="/pair/confirm"
          description="Confirms pairing from iOS device. Requires the shared secret from QR code."
        />
      </div>

      <h3 id="memos">Memos</h3>
      <div className="space-y-3 my-4">
        <EndpointCard
          method="POST"
          path="/memos"
          description="Upload a voice memo from iOS. Accepts multipart form data with audio file."
        />
        <EndpointCard
          method="GET"
          path="/memos"
          description="List recent memos for iOS sync. Returns last 50 memos by default."
          response={`{ "memos": [{ "id": "...", "title": "...", "createdAt": "..." }] }`}
        />
        <EndpointCard
          method="GET"
          path="/memos/:id"
          description="Get a specific memo by ID, including transcript and audio URL."
        />
      </div>

      {/* URL Schemes */}
      <h2 id="url-schemes">URL Schemes</h2>
      <p>
        Talkie registers URL schemes for deep linking and automation. Use these from Shortcuts, Alfred, Raycast, or any app that supports opening URLs.
      </p>

      <CodeBlock title="Supported URL Schemes">
{`talkie://                       # Open Talkie
talkie://record                 # Start recording immediately
talkie://stop                   # Stop current recording
talkie://memo/{id}              # Open a specific memo
talkie://settings               # Open settings window
talkie://settings/iphone        # Open iPhone sync settings
talkie://workflow/{id}          # Run a workflow manually`}
      </CodeBlock>

      <p>
        <strong>Example from Terminal:</strong>
      </p>
      <CodeBlock>
{`# Start a recording
open "talkie://record"

# Open a specific memo
open "talkie://memo/abc-123-def"`}
      </CodeBlock>

      {/* AppleScript */}
      <h2 id="applescript">AppleScript</h2>
      <p>
        Talkie is fully scriptable via AppleScript. This enables integration with Alfred, Keyboard Maestro, Raycast, and other automation tools.
      </p>

      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Terminal className="w-5 h-5 text-violet-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Available Commands</span>
        </div>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
          <li>• <code>start recording</code> — Begin a new voice recording</li>
          <li>• <code>stop recording</code> — Stop and save current recording</li>
          <li>• <code>get memos</code> — Returns list of recent memos</li>
          <li>• <code>get transcript of memo id "..."</code> — Get transcript text</li>
        </ul>
      </div>

      <CodeBlock title="Example: Record for 10 seconds">
{`tell application "Talkie"
    start recording
    delay 10
    stop recording
end tell`}
      </CodeBlock>

      <CodeBlock title="Example: Get latest transcript">
{`tell application "Talkie"
    set recentMemos to get memos
    set latestMemo to item 1 of recentMemos
    set transcriptText to transcript of latestMemo
    return transcriptText
end tell`}
      </CodeBlock>

      {/* Shortcuts */}
      <h2 id="shortcuts">Shortcuts Integration</h2>
      <p>
        Talkie exposes actions to the Shortcuts app for building voice-driven automations.
      </p>

      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <span className="font-bold text-zinc-900 dark:text-white block mb-3">Available Shortcut Actions</span>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-2">
          <li className="flex items-center gap-2">
            <span className="w-32 text-zinc-500">Start Recording</span>
            Begin a new voice recording
          </li>
          <li className="flex items-center gap-2">
            <span className="w-32 text-zinc-500">Stop Recording</span>
            Stop and process current recording
          </li>
          <li className="flex items-center gap-2">
            <span className="w-32 text-zinc-500">Get Recent Memos</span>
            Returns list of recent memos
          </li>
          <li className="flex items-center gap-2">
            <span className="w-32 text-zinc-500">Run Workflow</span>
            Execute a workflow by name
          </li>
        </ul>
      </div>

      <p>
        Combine with Siri: "Hey Siri, run my 'Quick Note' shortcut" to trigger voice recording hands-free.
      </p>

      {/* Navigation */}
      <h2 id="navigation">Continue Reading</h2>
      <div className="flex flex-col sm:flex-row gap-4 not-prose">
        <Link
          href="/docs/workflows"
          className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-indigo-500 group-hover:-translate-x-1 transition-all" />
          <div>
            <span className="text-xs text-zinc-500">Previous</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-indigo-600 dark:group-hover:text-indigo-400 transition-colors">
              Workflows
            </span>
          </div>
        </Link>

        <Link
          href="/docs/extensibility"
          className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <div>
            <span className="text-xs text-zinc-500">Next</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-orange-600 dark:group-hover:text-orange-400 transition-colors">
              Extensibility
            </span>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-orange-500 group-hover:translate-x-1 transition-all" />
        </Link>
      </div>
    </DocsLayout>
  )
}
