"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Workflow, Zap, Play, FileCode, Settings, Sparkles } from 'lucide-react'
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

const WorkflowCard = ({ icon: Icon, name, description, color }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
    <div className="flex items-start gap-3">
      <div className={`flex-shrink-0 w-10 h-10 rounded-lg ${color} flex items-center justify-center`}>
        <Icon className="w-5 h-5" />
      </div>
      <div>
        <h3 className="font-bold text-zinc-900 dark:text-white mb-1">{name}</h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
      </div>
    </div>
  </div>
)

export default function WorkflowsPage() {
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
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">WORKFLOWS</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-rose-200 dark:border-rose-500/30 bg-rose-50 dark:bg-rose-500/10 mb-6">
                <Workflow className="w-4 h-4 text-rose-600 dark:text-rose-400" />
                <span className="text-xs font-medium text-rose-700 dark:text-rose-400">Automation</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                Workflows
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                Automate your voice-to-action pipeline with workflows. Transform transcriptions
                into structured data, trigger actions, and integrate with other apps.
              </p>
            </div>

            {/* What are Workflows */}
            <Section title="What are Workflows?">
              <p>
                Workflows are automation rules that process your voice recordings after transcription.
                They can extract information, format text, send notifications, or trigger external actions.
              </p>

              <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6 mt-6">
                <div className="flex items-center gap-4">
                  <div className="flex-shrink-0 w-12 h-12 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center">
                    <Zap className="w-6 h-6 text-amber-500" />
                  </div>
                  <div className="flex-1">
                    <div className="text-sm font-medium text-zinc-900 dark:text-white">Voice Input</div>
                    <div className="text-xs text-zinc-500">"Remind me to call John tomorrow at 3pm"</div>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400" />
                  <div className="flex-shrink-0 w-12 h-12 rounded-lg bg-emerald-100 dark:bg-emerald-500/20 flex items-center justify-center">
                    <Sparkles className="w-6 h-6 text-emerald-500" />
                  </div>
                  <div className="flex-1">
                    <div className="text-sm font-medium text-zinc-900 dark:text-white">Action</div>
                    <div className="text-xs text-zinc-500">Create reminder in Reminders.app</div>
                  </div>
                </div>
              </div>

              <Placeholder>
                Coming soon: Detailed workflow concepts, execution model,
                and when workflows run.
              </Placeholder>
            </Section>

            {/* Triggers and Actions */}
            <Section title="Triggers and Actions">
              <div className="grid md:grid-cols-2 gap-4">
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <div className="flex items-center gap-2 mb-3">
                    <Play className="w-5 h-5 text-emerald-500" />
                    <h3 className="font-bold text-zinc-900 dark:text-white">Triggers</h3>
                  </div>
                  <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
                    <li>- After transcription completes</li>
                    <li>- Keyword detection</li>
                    <li>- Time-based (scheduled)</li>
                    <li>- Manual invocation</li>
                  </ul>
                </div>

                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <div className="flex items-center gap-2 mb-3">
                    <Zap className="w-5 h-5 text-amber-500" />
                    <h3 className="font-bold text-zinc-900 dark:text-white">Actions</h3>
                  </div>
                  <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
                    <li>- Transform text</li>
                    <li>- Extract structured data</li>
                    <li>- Send to external service</li>
                    <li>- Create calendar events</li>
                  </ul>
                </div>
              </div>

              <Placeholder>
                Coming soon: Complete trigger and action reference,
                configuration options, and examples.
              </Placeholder>
            </Section>

            {/* Built-in Workflows */}
            <Section title="Built-in Workflows">
              <p>
                Talkie includes several built-in workflows for common tasks.
              </p>

              <div className="space-y-3 mt-6">
                <WorkflowCard
                  icon={Sparkles}
                  name="Smart Summarize"
                  description="Automatically summarize long recordings into key points"
                  color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
                />
                <WorkflowCard
                  icon={FileCode}
                  name="Meeting Notes"
                  description="Extract action items and decisions from meeting recordings"
                  color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
                />
                <WorkflowCard
                  icon={Settings}
                  name="Quick Reminder"
                  description="Parse 'remind me to...' phrases into actual reminders"
                  color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
                />
              </div>

              <Placeholder>
                Coming soon: Full list of built-in workflows with
                configuration guides.
              </Placeholder>
            </Section>

            {/* Custom Workflows */}
            <Section title="Custom Workflows">
              <Placeholder>
                Coming soon: How to create custom workflows,
                available workflow actions, and best practices.
              </Placeholder>
            </Section>

            {/* Workflow File Format */}
            <Section title="Workflow File Format">
              <p>
                Workflows are defined as JSON files. Here's the basic structure:
              </p>

              <CodeBlock title="workflow.json">
{`{
  "id": "my-custom-workflow",
  "name": "My Custom Workflow",
  "trigger": {
    "type": "keyword",
    "keywords": ["summarize", "summary"]
  },
  "actions": [
    {
      "type": "transform",
      "prompt": "Summarize this text..."
    }
  ]
}`}
              </CodeBlock>

              <Placeholder>
                Coming soon: Complete schema documentation, available
                trigger types, action configurations, and variables.
              </Placeholder>
            </Section>

            {/* Navigation */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row gap-4">
                <Link
                  href="/docs/data"
                  className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-cyan-500 group-hover:-translate-x-1 transition-all" />
                  <div>
                    <span className="text-xs text-zinc-500">Previous</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-cyan-600 dark:group-hover:text-cyan-400 transition-colors">
                      Data Layer
                    </h3>
                  </div>
                </Link>

                <Link
                  href="/docs/api"
                  className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <div>
                    <span className="text-xs text-zinc-500">Next</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-orange-600 dark:group-hover:text-orange-400 transition-colors">
                      API Reference
                    </h3>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-orange-500 group-hover:translate-x-1 transition-all" />
                </Link>
              </div>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
