"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Puzzle, Webhook, Workflow, Plug, GitBranch, Box } from 'lucide-react'
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

const IntegrationCard = ({ icon: Icon, name, description, status, color }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
    <div className="flex items-start gap-3">
      <div className={`flex-shrink-0 w-10 h-10 rounded-lg ${color} flex items-center justify-center`}>
        <Icon className="w-5 h-5" />
      </div>
      <div className="flex-1">
        <div className="flex items-center gap-2 mb-1">
          <h3 className="font-bold text-zinc-900 dark:text-white">{name}</h3>
          {status && (
            <span className="px-2 py-0.5 text-[10px] font-medium bg-zinc-100 dark:bg-zinc-800 text-zinc-500 rounded">
              {status}
            </span>
          )}
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
      </div>
    </div>
  </div>
)

export default function ExtensibilityPage() {
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
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">EXTENSIBILITY</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-indigo-200 dark:border-indigo-500/30 bg-indigo-50 dark:bg-indigo-500/10 mb-6">
                <Puzzle className="w-4 h-4 text-indigo-600 dark:text-indigo-400" />
                <span className="text-xs font-medium text-indigo-700 dark:text-indigo-400">Developers</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                Extensibility
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                Build on top of Talkie. Create custom workflows, integrate with external services,
                and extend functionality through hooks and webhooks.
              </p>
            </div>

            {/* Integration Points */}
            <Section title="Integration Points">
              <p>
                Talkie provides multiple ways to extend and integrate with external systems.
              </p>

              <div className="space-y-3 mt-6">
                <IntegrationCard
                  icon={Webhook}
                  name="Webhooks"
                  description="Send transcription data to external URLs when events occur"
                  status="Coming Soon"
                  color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
                />
                <IntegrationCard
                  icon={Workflow}
                  name="Custom Workflows"
                  description="Create your own automation workflows with triggers and actions"
                  color="bg-rose-100 dark:bg-rose-500/20 text-rose-600 dark:text-rose-400"
                />
                <IntegrationCard
                  icon={Plug}
                  name="URL Schemes"
                  description="Deep link into Talkie from other apps and scripts"
                  color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
                />
                <IntegrationCard
                  icon={GitBranch}
                  name="AppleScript"
                  description="Control Talkie programmatically from macOS automation tools"
                  color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
                />
              </div>
            </Section>

            {/* Hooks and Webhooks */}
            <Section title="Hooks and Webhooks">
              <p>
                Configure webhooks to receive notifications when events occur in Talkie.
              </p>

              <CodeBlock title="Webhook Payload Example">
{`{
  "event": "memo.created",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "id": "abc-123",
    "transcript": "Meeting notes for...",
    "duration": 45.2,
    "language": "en"
  }
}`}
              </CodeBlock>

              <Placeholder>
                Coming soon: Available webhook events, payload schemas,
                authentication options, and retry policies.
              </Placeholder>
            </Section>

            {/* Custom Workflows */}
            <Section title="Custom Workflows">
              <p>
                Create workflows that run your own logic on transcriptions.
              </p>

              <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                <div className="flex items-center gap-3 mb-3">
                  <Box className="w-5 h-5 text-amber-500" />
                  <h3 className="font-bold text-zinc-900 dark:text-white">Workflow Directory</h3>
                </div>
                <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">
                  Custom workflows are stored in the Application Support directory:
                </p>
                <code className="block text-sm font-mono bg-zinc-100 dark:bg-zinc-800 px-3 py-2 rounded text-zinc-700 dark:text-zinc-300">
                  ~/Library/Application Support/Talkie/Workflows/
                </code>
              </div>

              <Placeholder>
                Coming soon: Workflow development guide, available actions,
                testing workflows, and sharing workflows.
              </Placeholder>
            </Section>

            {/* Third-Party Integrations */}
            <Section title="Third-Party Integrations">
              <p>
                Examples of integrating Talkie with popular services.
              </p>

              <div className="grid md:grid-cols-2 gap-3 mt-6">
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-1">Notion</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Send transcriptions to Notion databases
                  </p>
                </div>
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-1">Obsidian</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Create notes in your Obsidian vault
                  </p>
                </div>
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-1">Slack</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Post summaries to Slack channels
                  </p>
                </div>
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-1">Raycast</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Quick access via Raycast extensions
                  </p>
                </div>
              </div>

              <Placeholder>
                Coming soon: Step-by-step integration guides for each service.
              </Placeholder>
            </Section>

            {/* Developer Resources */}
            <Section title="Developer Resources">
              <Placeholder>
                Coming soon: SDK documentation, example projects,
                community plugins, and contribution guidelines.
              </Placeholder>
            </Section>

            {/* Navigation */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row gap-4">
                <Link
                  href="/docs/api"
                  className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-orange-500 group-hover:-translate-x-1 transition-all" />
                  <div>
                    <span className="text-xs text-zinc-500">Previous</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-orange-600 dark:group-hover:text-orange-400 transition-colors">
                      API Reference
                    </h3>
                  </div>
                </Link>

                <Link
                  href="/docs"
                  className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <div>
                    <span className="text-xs text-zinc-500">Back to</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                      Documentation Index
                    </h3>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-emerald-500 group-hover:translate-x-1 transition-all" />
                </Link>
              </div>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
