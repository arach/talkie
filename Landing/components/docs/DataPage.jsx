"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Database, HardDrive, FileText, FolderOpen, Download } from 'lucide-react'
import Container from '../Container'

const Section = ({ title, children }) => (
  <section className="mb-12">
    <h2 className="text-2xl font-bold text-zinc-900 dark:text-white mb-4">{title}</h2>
    <div className="text-zinc-600 dark:text-zinc-400 space-y-4">{children}</div>
  </section>
)

const Placeholder = ({ children }) => (
  <div className="p-6 rounded-lg border border-dashed border-zinc-300 dark:border-zinc-700 bg-zinc-100 dark:bg-zinc-900/50">
    <p className="text-sm text-zinc-500 dark:text-zinc-500 italic">{children}</p>
  </div>
)

const CodeBlock = ({ children, title }) => (
  <div className="rounded-lg border border-zinc-200 dark:border-zinc-800 overflow-hidden">
    {title && (
      <div className="px-4 py-2 bg-zinc-100 dark:bg-zinc-800 border-b border-zinc-200 dark:border-zinc-700">
        <span className="text-xs font-mono text-zinc-500">{title}</span>
      </div>
    )}
    <pre className="p-4 bg-zinc-50 dark:bg-zinc-900 overflow-x-auto">
      <code className="text-sm font-mono text-zinc-800 dark:text-zinc-200">{children}</code>
    </pre>
  </div>
)

const ModelCard = ({ name, description, fields }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
    <h3 className="text-lg font-bold text-zinc-900 dark:text-white mb-2">{name}</h3>
    <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-4">{description}</p>
    <div className="space-y-2">
      {fields.map((field, i) => (
        <div key={i} className="flex items-center gap-2 text-sm">
          <code className="px-2 py-0.5 bg-zinc-100 dark:bg-zinc-800 rounded font-mono text-zinc-700 dark:text-zinc-300">
            {field.name}
          </code>
          <span className="text-zinc-500 dark:text-zinc-500">{field.type}</span>
        </div>
      ))}
    </div>
  </div>
)

export default function DataPage() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <Container className="h-14 flex items-center justify-between">
          <Link
            href="/docs"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            DOCS
          </Link>

          <div className="flex items-center gap-2 sm:gap-3">
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">DATA</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-cyan-200 dark:border-cyan-500/30 bg-cyan-50 dark:bg-cyan-500/10 mb-6">
                <Database className="w-4 h-4 text-cyan-600 dark:text-cyan-400" />
                <span className="text-xs font-medium text-cyan-700 dark:text-cyan-400">Data Layer</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                Data Layer
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                Understanding how Talkie stores and manages your data locally.
                GRDB is the source of truth, with optional CloudKit sync.
              </p>
            </div>

            {/* Database Location */}
            <Section title="Database Location">
              <p>
                Talkie stores its data in the Application Support directory, keeping everything
                local and easily accessible for backup.
              </p>

              <CodeBlock title="Primary Databases">
{`~/Library/Application Support/Talkie/
├── talkie_grdb.sqlite      # Memos, settings
└── live.sqlite             # Live dictation sessions`}
              </CodeBlock>

              <Placeholder>
                Coming soon: Database ownership rules, migration strategy,
                and backup recommendations.
              </Placeholder>
            </Section>

            {/* Core Models */}
            <Section title="Core Models">
              <p>
                These are the primary data types in Talkie's database.
              </p>

              <div className="space-y-4 mt-6">
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
                  name="Transcript"
                  description="Raw transcription output with timing data"
                  fields={[
                    { name: "id", type: "UUID" },
                    { name: "memoId", type: "UUID" },
                    { name: "segments", type: "[Segment]" },
                    { name: "language", type: "String?" },
                  ]}
                />
              </div>

              <Placeholder>
                Coming soon: Complete model documentation with relationships,
                computed properties, and query patterns.
              </Placeholder>
            </Section>

            {/* File Storage */}
            <Section title="File Storage">
              <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                <div className="flex items-center gap-3 mb-3">
                  <FolderOpen className="w-5 h-5 text-amber-500" />
                  <h3 className="font-bold text-zinc-900 dark:text-white">Audio Files</h3>
                </div>
                <p className="text-sm text-zinc-600 dark:text-zinc-400">
                  Voice recordings are stored as M4A files in the Application Support directory,
                  referenced by file path in the database.
                </p>
              </div>

              <Placeholder>
                Coming soon: File naming conventions, cleanup policies,
                and storage optimization strategies.
              </Placeholder>
            </Section>

            {/* Export Formats */}
            <Section title="Export Formats">
              <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                <div className="flex items-center gap-3 mb-3">
                  <Download className="w-5 h-5 text-emerald-500" />
                  <h3 className="font-bold text-zinc-900 dark:text-white">Available Exports</h3>
                </div>
                <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
                  <li>- Plain text (.txt)</li>
                  <li>- Markdown (.md)</li>
                  <li>- JSON with metadata</li>
                  <li>- Audio files (M4A)</li>
                </ul>
              </div>

              <Placeholder>
                Coming soon: Export format specifications, bulk export options,
                and integration with other apps.
              </Placeholder>
            </Section>

            {/* Sync Architecture */}
            <Section title="Sync Architecture">
              <Placeholder>
                Coming soon: How CloudKit sync works, conflict resolution,
                and multi-device considerations.
              </Placeholder>
            </Section>

            {/* Navigation */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row gap-4">
                <Link
                  href="/docs/architecture"
                  className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-amber-500 group-hover:-translate-x-1 transition-all" />
                  <div>
                    <span className="text-xs text-zinc-500">Previous</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">
                      Architecture
                    </h3>
                  </div>
                </Link>

                <Link
                  href="/docs/workflows"
                  className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <div>
                    <span className="text-xs text-zinc-500">Next</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-rose-600 dark:group-hover:text-rose-400 transition-colors">
                      Workflows
                    </h3>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-rose-500 group-hover:translate-x-1 transition-all" />
                </Link>
              </div>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
