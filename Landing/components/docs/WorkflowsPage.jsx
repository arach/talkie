"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Zap, Play, Sparkles, FileCode, Settings, Clock, Filter } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'what-are-workflows', title: 'What are Workflows?', level: 2 },
  { id: 'anatomy', title: 'Anatomy of a Workflow', level: 2 },
  { id: 'triggers', title: 'Triggers', level: 3 },
  { id: 'conditions', title: 'Conditions', level: 3 },
  { id: 'steps', title: 'Steps', level: 3 },
  { id: 'step-types', title: 'Step Types', level: 2 },
  { id: 'built-in', title: 'Built-in Workflows', level: 2 },
  { id: 'creating', title: 'Creating Workflows', level: 2 },
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

const StepTypeCard = ({ name, description, example }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
    <h4 className="font-bold text-zinc-900 dark:text-white mb-1">{name}</h4>
    <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-2">{description}</p>
    {example && (
      <code className="text-xs text-zinc-500 font-mono">{example}</code>
    )}
  </div>
)

const WorkflowCard = ({ icon: Icon, name, description, color }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
    <div className="flex items-start gap-3">
      <div className={`flex-shrink-0 w-10 h-10 rounded-lg ${color} flex items-center justify-center`}>
        <Icon className="w-5 h-5" />
      </div>
      <div>
        <h4 className="font-bold text-zinc-900 dark:text-white mb-1">{name}</h4>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
      </div>
    </div>
  </div>
)

export default function WorkflowsPage() {
  return (
    <DocsLayout
      title="Workflows"
      description="Automate your voice-to-action pipeline. Transform transcriptions into structured data, trigger actions, and integrate with other apps."
      badge="Automation"
      badgeColor="purple"
      sections={sections}
    >
      {/* What are Workflows */}
      <h2 id="what-are-workflows">What are Workflows?</h2>
      <p>
        Workflows are automation rules that process your voice recordings. When you finish a recording, workflows can automatically extract information, format text, send notifications, or trigger external actions.
      </p>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6 my-6 not-prose">
        <div className="flex flex-col sm:flex-row items-center gap-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center">
              <Zap className="w-6 h-6 text-amber-500" />
            </div>
            <div>
              <div className="text-sm font-medium text-zinc-900 dark:text-white">Voice Input</div>
              <div className="text-xs text-zinc-500">"Remind me to call John at 3pm"</div>
            </div>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 rotate-90 sm:rotate-0" />
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-lg bg-emerald-100 dark:bg-emerald-500/20 flex items-center justify-center">
              <Sparkles className="w-6 h-6 text-emerald-500" />
            </div>
            <div>
              <div className="text-sm font-medium text-zinc-900 dark:text-white">Workflow Action</div>
              <div className="text-xs text-zinc-500">Creates reminder in Reminders.app</div>
            </div>
          </div>
        </div>
      </div>

      <p>
        Think of workflows as recipes: they have a trigger (when to run), conditions (whether to run), and steps (what to do).
      </p>

      {/* Anatomy */}
      <h2 id="anatomy">Anatomy of a Workflow</h2>
      <p>
        Every workflow has three parts:
      </p>

      <h3 id="triggers">Triggers</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Play className="w-5 h-5 text-emerald-500" />
          <span className="font-bold text-zinc-900 dark:text-white">When does it run?</span>
        </div>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
          <li>• <strong>After transcription</strong> — Runs when any memo finishes transcribing</li>
          <li>• <strong>Keyword detection</strong> — Runs when transcript contains specific words</li>
          <li>• <strong>Scheduled</strong> — Runs at specific times (daily digest, etc.)</li>
          <li>• <strong>Manual</strong> — Runs when you invoke it explicitly</li>
        </ul>
      </div>

      <h3 id="conditions">Conditions</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Filter className="w-5 h-5 text-blue-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Should it run?</span>
        </div>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
          <li>• <strong>Length check</strong> — Only memos longer than X seconds</li>
          <li>• <strong>Time of day</strong> — Only during work hours</li>
          <li>• <strong>Content match</strong> — Only if transcript matches pattern</li>
        </ul>
      </div>

      <h3 id="steps">Steps</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Zap className="w-5 h-5 text-amber-500" />
          <span className="font-bold text-zinc-900 dark:text-white">What does it do?</span>
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          Steps are the actions your workflow takes. They run in order, and each step can use output from previous steps.
        </p>
      </div>

      {/* Step Types */}
      <h2 id="step-types">Step Types</h2>
      <p>
        Talkie includes 18 built-in step types. Here are the most commonly used:
      </p>

      <div className="grid md:grid-cols-2 gap-3 my-6 not-prose">
        <StepTypeCard
          name="Transform"
          description="Use AI to transform or reformat text"
          example="Summarize this in 3 bullet points"
        />
        <StepTypeCard
          name="Extract"
          description="Pull structured data from text"
          example="Extract: name, date, action items"
        />
        <StepTypeCard
          name="Notify"
          description="Send a macOS notification"
          example="Show alert with summary"
        />
        <StepTypeCard
          name="Webhook"
          description="POST data to external service"
          example="Send to Zapier, Make, n8n"
        />
        <StepTypeCard
          name="Run Shortcut"
          description="Execute an Apple Shortcut"
          example="Run 'Add to Things' shortcut"
        />
        <StepTypeCard
          name="Copy to Clipboard"
          description="Copy result to clipboard"
          example="Copy formatted output"
        />
        <StepTypeCard
          name="Save to File"
          description="Write output to a file"
          example="Append to ~/notes/daily.md"
        />
        <StepTypeCard
          name="Set Variable"
          description="Store value for later steps"
          example="extractedDate = result.date"
        />
      </div>

      {/* Built-in Workflows */}
      <h2 id="built-in">Built-in Workflows</h2>
      <p>
        Talkie ships with several ready-to-use workflows:
      </p>

      <div className="space-y-3 my-6 not-prose">
        <WorkflowCard
          icon={Sparkles}
          name="Smart Summarize"
          description="Condenses long recordings into key points. Great for meeting notes or voice journals."
          color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
        />
        <WorkflowCard
          icon={FileCode}
          name="Meeting Notes"
          description="Extracts action items, decisions, and attendees from meeting recordings."
          color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
        />
        <WorkflowCard
          icon={Clock}
          name="Quick Reminder"
          description="Parses 'remind me to...' phrases and creates reminders in Reminders.app."
          color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
        />
        <WorkflowCard
          icon={Settings}
          name="Daily Digest"
          description="Scheduled workflow that summarizes all memos from the day at 6pm."
          color="bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400"
        />
      </div>

      {/* Creating Workflows */}
      <h2 id="creating">Creating Workflows</h2>
      <p>
        Workflows are defined as JSON files. You can create them in Settings → Workflows → Create New, or write the JSON directly:
      </p>

      <CodeBlock title="Example: Quick Summary Workflow">
{`{
  "id": "quick-summary",
  "name": "Quick Summary",
  "trigger": {
    "type": "keyword",
    "keywords": ["summarize", "summary", "tldr"]
  },
  "steps": [
    {
      "type": "transform",
      "prompt": "Summarize this in 2-3 bullet points:",
      "input": "{{transcript}}"
    },
    {
      "type": "notify",
      "title": "Summary Ready",
      "body": "{{result}}"
    }
  ]
}`}
      </CodeBlock>

      <p>
        Workflow files are stored in <code>~/Library/Application Support/Talkie/Workflows/</code>. You can share workflows by sharing these JSON files.
      </p>

      {/* Navigation */}
      <h2 id="navigation">Continue Reading</h2>
      <div className="flex flex-col sm:flex-row gap-4 not-prose">
        <Link
          href="/docs/data"
          className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-rose-500 group-hover:-translate-x-1 transition-all" />
          <div>
            <span className="text-xs text-zinc-500">Previous</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-rose-600 dark:group-hover:text-rose-400 transition-colors">
              Your Data
            </span>
          </div>
        </Link>

        <Link
          href="/docs/api"
          className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <div>
            <span className="text-xs text-zinc-500">Next</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-cyan-600 dark:group-hover:text-cyan-400 transition-colors">
              API Reference
            </span>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-cyan-500 group-hover:translate-x-1 transition-all" />
        </Link>
      </div>
    </DocsLayout>
  )
}
