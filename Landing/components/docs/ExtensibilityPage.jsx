"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Webhook, Workflow, Plug, GitBranch, Box } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'integration-points', title: 'Integration Points', level: 2 },
  { id: 'webhooks', title: 'Webhooks', level: 2 },
  { id: 'events', title: 'Available Events', level: 3 },
  { id: 'payload', title: 'Payload Format', level: 3 },
  { id: 'custom-workflows', title: 'Custom Workflows', level: 2 },
  { id: 'integrations', title: 'Third-Party Integrations', level: 2 },
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

const IntegrationCard = ({ icon: Icon, name, description, color }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
    <div className="flex items-start gap-3">
      <div className={`flex-shrink-0 w-10 h-10 rounded-lg ${color} flex items-center justify-center`}>
        <Icon className="w-5 h-5" />
      </div>
      <div className="flex-1">
        <h4 className="font-bold text-zinc-900 dark:text-white mb-1">{name}</h4>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
      </div>
    </div>
  </div>
)

export default function ExtensibilityPage() {
  return (
    <DocsLayout
      title="Extensibility"
      description="Build on top of Talkie. Create custom workflows, integrate with external services, and extend functionality through hooks and webhooks."
      badge="Developers"
      badgeColor="purple"
      sections={sections}
    >
      {/* Integration Points */}
      <h2 id="integration-points">Integration Points</h2>
      <p>
        Talkie is designed to be extended. Whether you want to send transcripts to another app, trigger external services, or build your own automation—there's a way to do it.
      </p>

      <div className="space-y-3 my-6 not-prose">
        <IntegrationCard
          icon={Webhook}
          name="Webhooks"
          description="POST transcription data to any URL when events occur. Works with Zapier, Make, n8n, or your own services."
          color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
        />
        <IntegrationCard
          icon={Workflow}
          name="Custom Workflows"
          description="Create your own automation workflows with triggers, conditions, and actions. Full JSON schema available."
          color="bg-rose-100 dark:bg-rose-500/20 text-rose-600 dark:text-rose-400"
        />
        <IntegrationCard
          icon={Plug}
          name="URL Schemes"
          description="Deep link into Talkie from other apps, scripts, or Shortcuts. Control recording and access memos."
          color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
        />
        <IntegrationCard
          icon={GitBranch}
          name="AppleScript"
          description="Full AppleScript dictionary for controlling Talkie programmatically from Alfred, Keyboard Maestro, etc."
          color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
        />
      </div>

      {/* Webhooks */}
      <h2 id="webhooks">Webhooks</h2>
      <p>
        Webhooks let you push data to external services when things happen in Talkie. Configure them in Settings → Workflows → Webhooks.
      </p>

      <h3 id="events">Available Events</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-2">
          <li className="flex items-start gap-3">
            <code className="text-xs bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded font-mono">memo.created</code>
            <span>Fires when a new memo is saved with transcription</span>
          </li>
          <li className="flex items-start gap-3">
            <code className="text-xs bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded font-mono">memo.updated</code>
            <span>Fires when a memo is edited or metadata changes</span>
          </li>
          <li className="flex items-start gap-3">
            <code className="text-xs bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded font-mono">workflow.completed</code>
            <span>Fires when a workflow finishes executing</span>
          </li>
          <li className="flex items-start gap-3">
            <code className="text-xs bg-zinc-100 dark:bg-zinc-800 px-2 py-0.5 rounded font-mono">dictation.ended</code>
            <span>Fires when a live dictation session ends</span>
          </li>
        </ul>
      </div>

      <h3 id="payload">Payload Format</h3>
      <p>
        Webhook payloads are JSON with a consistent structure:
      </p>

      <CodeBlock title="Webhook Payload Example">
{`{
  "event": "memo.created",
  "timestamp": "2024-01-15T10:30:00Z",
  "data": {
    "id": "abc-123-def",
    "title": "Meeting Notes",
    "transcript": "Today we discussed the Q1 roadmap...",
    "duration": 45.2,
    "language": "en",
    "createdAt": "2024-01-15T10:29:15Z"
  }
}`}
      </CodeBlock>

      <p>
        Webhooks include an <code>X-Talkie-Signature</code> header for verification. Use your webhook secret to validate incoming requests.
      </p>

      {/* Custom Workflows */}
      <h2 id="custom-workflows">Custom Workflows</h2>
      <p>
        Beyond the built-in workflows, you can create your own. Workflows are JSON files stored in your Application Support directory.
      </p>

      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <Box className="w-5 h-5 text-amber-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Workflow Location</span>
        </div>
        <code className="block text-sm font-mono bg-zinc-100 dark:bg-zinc-800 px-3 py-2 rounded text-zinc-700 dark:text-zinc-300">
          ~/Library/Application Support/Talkie/Workflows/
        </code>
      </div>

      <CodeBlock title="Custom Workflow Example">
{`{
  "id": "send-to-notion",
  "name": "Send to Notion",
  "trigger": {
    "type": "keyword",
    "keywords": ["note", "notion"]
  },
  "steps": [
    {
      "type": "transform",
      "prompt": "Format as a clean note with bullet points:"
    },
    {
      "type": "webhook",
      "url": "https://api.notion.com/v1/pages",
      "headers": {
        "Authorization": "Bearer {{secrets.NOTION_TOKEN}}"
      },
      "body": {
        "parent": { "database_id": "{{secrets.NOTION_DB}}" },
        "properties": {
          "title": { "title": [{ "text": { "content": "{{title}}" } }] }
        },
        "children": [{ "paragraph": { "text": "{{result}}" } }]
      }
    }
  ]
}`}
      </CodeBlock>

      <p>
        Share workflows by sharing the JSON file. Import by dropping into the Workflows directory.
      </p>

      {/* Third-Party Integrations */}
      <h2 id="integrations">Third-Party Integrations</h2>
      <p>
        Popular services Talkie users integrate with:
      </p>

      <div className="grid md:grid-cols-2 gap-3 my-6 not-prose">
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-1">Notion</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Send transcriptions to Notion databases via webhook action
          </p>
        </div>
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-1">Obsidian</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Create notes in your vault using the "Save to File" action
          </p>
        </div>
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-1">Slack</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Post summaries to channels via Slack webhooks
          </p>
        </div>
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-1">Raycast</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Quick access via URL schemes and AppleScript
          </p>
        </div>
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-1">Things / Todoist</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Create tasks from voice notes via URL schemes or webhooks
          </p>
        </div>
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-1">Zapier / Make / n8n</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Connect to 1000+ services via workflow automation platforms
          </p>
        </div>
      </div>

      {/* Navigation */}
      <h2 id="navigation">Continue Reading</h2>
      <div className="flex flex-col sm:flex-row gap-4 not-prose">
        <Link
          href="/docs/api"
          className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-amber-500 group-hover:-translate-x-1 transition-all" />
          <div>
            <span className="text-xs text-zinc-500">Previous</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">
              API Reference
            </span>
          </div>
        </Link>

        <Link
          href="/docs"
          className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <div>
            <span className="text-xs text-zinc-500">Back to</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
              Documentation Index
            </span>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-emerald-500 group-hover:translate-x-1 transition-all" />
        </Link>
      </div>
    </DocsLayout>
  )
}
