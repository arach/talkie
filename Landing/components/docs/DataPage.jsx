"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, FolderOpen, Download, Database, Lock } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'philosophy', title: 'Data Philosophy', level: 2 },
  { id: 'locations', title: 'Where Data Lives', level: 2 },
  { id: 'databases', title: 'Databases', level: 3 },
  { id: 'audio-files', title: 'Audio Files', level: 3 },
  { id: 'models', title: 'Core Data Models', level: 2 },
  { id: 'exports', title: 'Export Options', level: 2 },
  { id: 'sync', title: 'Sync Architecture', level: 2 },
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

const ModelCard = ({ name, description, fields }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
    <h4 className="text-lg font-bold text-zinc-900 dark:text-white mb-2">{name}</h4>
    <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-4">{description}</p>
    <div className="space-y-2">
      {fields.map((field, i) => (
        <div key={i} className="flex items-center gap-2 text-sm">
          <code className="px-2 py-0.5 bg-zinc-100 dark:bg-zinc-800 rounded font-mono text-zinc-700 dark:text-zinc-300">
            {field.name}
          </code>
          <span className="text-zinc-500">{field.type}</span>
        </div>
      ))}
    </div>
  </div>
)

export default function DataPage() {
  return (
    <DocsLayout
      title="Your Data"
      description="Understanding how Talkie stores and manages your data locally. You own your data—it's in readable formats on your disk, and you can export it anytime."
      badge="Data Layer"
      badgeColor="rose"
      sections={sections}
    >
      {/* Philosophy */}
      <h2 id="philosophy">Data Philosophy</h2>
      <p>
        Your voice recordings are personal. They might contain private thoughts, business ideas, or sensitive conversations. Talkie treats this data with the respect it deserves:
      </p>
      <ul>
        <li><strong>Local storage</strong> — Data lives on your Mac, not in someone else's cloud</li>
        <li><strong>Standard formats</strong> — SQLite databases, M4A audio files, plain text exports</li>
        <li><strong>No lock-in</strong> — Export everything with one click</li>
        <li><strong>Optional sync</strong> — iCloud sync is available but never required</li>
      </ul>

      {/* Locations */}
      <h2 id="locations">Where Data Lives</h2>
      <p>
        Talkie stores data in the standard macOS Application Support directory. This makes it easy to back up, migrate, or inspect your data.
      </p>

      <h3 id="databases">Databases</h3>
      <CodeBlock title="Database Locations">
{`~/Library/Application Support/Talkie/
├── talkie_grdb.sqlite      # Memos, settings, workflows
└── live.sqlite             # Live dictation sessions

# These are standard SQLite files. You can inspect them with:
sqlite3 ~/Library/Application\\ Support/Talkie/talkie_grdb.sqlite ".tables"`}
      </CodeBlock>

      <p>
        <strong>Database ownership:</strong> Each database has a single writer process to prevent corruption:
      </p>
      <ul>
        <li><code>talkie_grdb.sqlite</code> — Written by Talkie (main app)</li>
        <li><code>live.sqlite</code> — Written by TalkieLive (helper process)</li>
      </ul>

      <h3 id="audio-files">Audio Files</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <FolderOpen className="w-5 h-5 text-amber-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Audio Storage</span>
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-2">
          Voice recordings are stored as M4A files (AAC codec) for good quality at reasonable file sizes.
        </p>
        <code className="text-xs text-zinc-500 font-mono">
          ~/Library/Application Support/Talkie/Recordings/
        </code>
      </div>

      {/* Core Models */}
      <h2 id="models">Core Data Models</h2>
      <p>
        Understanding the data model helps when building integrations or inspecting your data directly.
      </p>

      <div className="space-y-4 my-6 not-prose">
        <ModelCard
          name="Memo"
          description="A voice recording with transcription and metadata"
          fields={[
            { name: "id", type: "UUID" },
            { name: "title", type: "String?" },
            { name: "transcript", type: "String" },
            { name: "audioPath", type: "String?" },
            { name: "createdAt", type: "Date" },
            { name: "duration", type: "TimeInterval" },
            { name: "isFavorite", type: "Bool" },
          ]}
        />

        <ModelCard
          name="Dictation"
          description="A live dictation session from TalkieLive"
          fields={[
            { name: "id", type: "UUID" },
            { name: "text", type: "String" },
            { name: "appBundleId", type: "String?" },
            { name: "startedAt", type: "Date" },
            { name: "endedAt", type: "Date?" },
          ]}
        />

        <ModelCard
          name="Workflow"
          description="An automation rule with triggers and actions"
          fields={[
            { name: "id", type: "UUID" },
            { name: "name", type: "String" },
            { name: "isEnabled", type: "Bool" },
            { name: "trigger", type: "TriggerConfig" },
            { name: "steps", type: "[WorkflowStep]" },
          ]}
        />
      </div>

      {/* Export Options */}
      <h2 id="exports">Export Options</h2>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Download className="w-5 h-5 text-emerald-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Available Formats</span>
        </div>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-2">
          <li className="flex items-center gap-2">
            <span className="w-16 font-mono text-zinc-500">.txt</span>
            Plain text transcription
          </li>
          <li className="flex items-center gap-2">
            <span className="w-16 font-mono text-zinc-500">.md</span>
            Markdown with frontmatter metadata
          </li>
          <li className="flex items-center gap-2">
            <span className="w-16 font-mono text-zinc-500">.json</span>
            Full data with all metadata fields
          </li>
          <li className="flex items-center gap-2">
            <span className="w-16 font-mono text-zinc-500">.m4a</span>
            Original audio recording
          </li>
        </ul>
      </div>
      <p>
        Export from the memo detail view (Share → Export) or bulk export from Settings → Data → Export All.
      </p>

      {/* Sync Architecture */}
      <h2 id="sync">Sync Architecture</h2>
      <p>
        Talkie uses a <strong>GRDB-primary</strong> architecture. The local SQLite database is always the source of truth. Sync (when enabled) is an additive layer on top.
      </p>

      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Lock className="w-5 h-5 text-blue-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Sync Flow</span>
        </div>
        <ol className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1 list-decimal list-inside">
          <li>App writes to local GRDB database</li>
          <li>Change observer detects new/updated records</li>
          <li>Sync bridge pushes changes to CloudKit (if enabled)</li>
          <li>Remote changes are pulled and merged into GRDB</li>
        </ol>
      </div>
      <p>
        <strong>Key benefit:</strong> The app works perfectly offline. Sync catches up when connectivity returns.
      </p>

      {/* Navigation */}
      <h2 id="navigation">Continue Reading</h2>
      <div className="flex flex-col sm:flex-row gap-4 not-prose">
        <Link
          href="/docs/architecture"
          className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-amber-500 group-hover:-translate-x-1 transition-all" />
          <div>
            <span className="text-xs text-zinc-500">Previous</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">
              Architecture
            </span>
          </div>
        </Link>

        <Link
          href="/docs/workflows"
          className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <div>
            <span className="text-xs text-zinc-500">Next</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-indigo-600 dark:group-hover:text-indigo-400 transition-colors">
              Workflows
            </span>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-indigo-500 group-hover:translate-x-1 transition-all" />
        </Link>
      </div>
    </DocsLayout>
  )
}
