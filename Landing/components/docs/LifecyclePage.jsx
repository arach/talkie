"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Mic, FileAudio, Brain, Type, Database, Zap, Clock, ArrowDown } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'overview', title: 'Overview', level: 2 },
  { id: 'dictation-lifecycle', title: 'Dictation Lifecycle', level: 2 },
  { id: 'phase-capture', title: 'Capture Phase', level: 3 },
  { id: 'phase-transcribe', title: 'Transcription Phase', level: 3 },
  { id: 'phase-route', title: 'Routing Phase', level: 3 },
  { id: 'phase-store', title: 'Storage Phase', level: 3 },
  { id: 'memo-lifecycle', title: 'Memo Lifecycle', level: 2 },
  { id: 'memo-creation', title: 'Creation', level: 3 },
  { id: 'memo-workflows', title: 'Workflow Execution', level: 3 },
  { id: 'extension-points', title: 'Extension Points', level: 2 },
  { id: 'navigation', title: 'Continue Reading', level: 2 },
]

// Lifecycle phase component
const Phase = ({ icon: Icon, name, description, timing, color, children, isLast = false }) => (
  <div className="relative not-prose">
    {/* Connector line */}
    {!isLast && (
      <div className="absolute left-6 top-16 bottom-0 w-px bg-gradient-to-b from-zinc-300 to-zinc-200 dark:from-zinc-700 dark:to-zinc-800" />
    )}

    <div className="flex gap-4">
      {/* Icon */}
      <div className={`flex-shrink-0 w-12 h-12 rounded-xl ${color} flex items-center justify-center shadow-sm border border-white/50 dark:border-zinc-700/50 z-10`}>
        <Icon className="w-6 h-6" />
      </div>

      {/* Content */}
      <div className="flex-1 pb-8">
        <div className="flex items-center gap-3 mb-1">
          <h4 className="text-lg font-display font-semibold text-zinc-900 dark:text-white">{name}</h4>
          {timing && (
            <span className="flex items-center gap-1 text-xs font-mono text-zinc-400">
              <Clock className="w-3 h-3" />
              {timing}
            </span>
          )}
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-3">{description}</p>
        {children}
      </div>
    </div>
  </div>
)

// Step within a phase
const Step = ({ number, label, detail, hookPoint }) => (
  <div className="flex items-start gap-3 py-2">
    <div className="flex-shrink-0 w-6 h-6 rounded-full bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center">
      <span className="text-xs font-bold text-zinc-500 dark:text-zinc-400">{number}</span>
    </div>
    <div className="flex-1">
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-zinc-800 dark:text-zinc-200">{label}</span>
        {hookPoint && (
          <span className="px-1.5 py-0.5 text-[10px] font-mono font-bold uppercase tracking-wider rounded bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400 border border-violet-200 dark:border-violet-500/30">
            Hook
          </span>
        )}
      </div>
      {detail && (
        <span className="text-xs text-zinc-500 dark:text-zinc-500 block mt-0.5">{detail}</span>
      )}
    </div>
  </div>
)

// Hook point callout
const HookPoint = ({ name, description, when }) => (
  <div className="mt-4 p-3 rounded-lg border-2 border-dashed border-violet-300 dark:border-violet-500/40 bg-violet-50/50 dark:bg-violet-500/5">
    <div className="flex items-center gap-2 mb-1">
      <Zap className="w-4 h-4 text-violet-500" />
      <span className="text-sm font-bold text-violet-700 dark:text-violet-400">{name}</span>
    </div>
    <p className="text-xs text-violet-600 dark:text-violet-300/80">{description}</p>
    <p className="text-[10px] font-mono text-violet-500/70 dark:text-violet-400/50 mt-1">When: {when}</p>
  </div>
)

export default function LifecyclePage() {
  return (
    <DocsLayout
      title="Lifecycle"
      description="Understanding the journey from voice to action. Every recording flows through distinct phases, each with natural extension points where you can plug in custom logic."
      badge="Deep Dive"
      badgeColor="purple"
      sections={sections}
    >
      {/* Overview */}
      <h2 id="overview">Overview</h2>
      <p>
        Talkie processes voice in two main flows: <strong>Dictation</strong> (real-time, handled by TalkieLive) and <strong>Memos</strong> (deliberate recordings, handled by the main app). Both share similar phases but differ in timing and intent.
      </p>

      <div className="grid md:grid-cols-2 gap-4 my-6 not-prose">
        <div className="p-4 rounded-lg border border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/50 dark:bg-emerald-500/5">
          <h4 className="font-bold text-emerald-700 dark:text-emerald-400 mb-2">Dictation</h4>
          <p className="text-sm text-emerald-600 dark:text-emerald-300/80">
            Press hotkey, speak, release. Text appears where your cursor is. Fast, in-flow, ephemeral.
          </p>
          <p className="text-xs text-emerald-500/70 mt-2 font-mono">~500ms to paste</p>
        </div>
        <div className="p-4 rounded-lg border border-blue-200 dark:border-blue-500/30 bg-blue-50/50 dark:bg-blue-500/5">
          <h4 className="font-bold text-blue-700 dark:text-blue-400 mb-2">Memo</h4>
          <p className="text-sm text-blue-600 dark:text-blue-300/80">
            Deliberate recording that becomes a searchable note. Triggers workflows for processing, summarizing, extracting.
          </p>
          <p className="text-xs text-blue-500/70 mt-2 font-mono">Permanent, indexed</p>
        </div>
      </div>

      {/* Dictation Lifecycle */}
      <h2 id="dictation-lifecycle">Dictation Lifecycle</h2>
      <p>
        The dictation flow is optimized for speed. From hotkey press to text appearing, every millisecond counts. Here's the complete journey:
      </p>

      <div className="my-8">
        {/* Phase 1: Capture */}
        <Phase
          icon={Mic}
          name="Capture"
          description="Audio flows from microphone to temporary file. Context is captured to know where you were when you started speaking."
          timing="~50ms setup"
          color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
        >
          <div id="phase-capture" className="space-y-0">
            <Step number="1" label="Hotkey detected" detail="Carbon event handler fires immediately" />
            <Step number="2" label="Context captured" detail="Which app, window, selected text" hookPoint />
            <Step number="3" label="Audio capture starts" detail="TalkieLive begins recording via AudioCapture" />
            <Step number="4" label="State broadcast" detail="XPC notifies main app; UI updates" />
          </div>
          <HookPoint
            name="onCaptureStart"
            description="Inspect or modify the capture context. Could auto-route based on which app is active."
            when="After context captured, before audio starts"
          />
        </Phase>

        {/* Phase 2: Transcribe */}
        <Phase
          icon={Brain}
          name="Transcription"
          description="Audio is sent to TalkieEngine for local Whisper transcription. The audio file is saved permanently first—your recording is never lost."
          timing="~300-800ms"
          color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
        >
          <div id="phase-transcribe" className="space-y-0">
            <Step number="5" label="Hotkey released" detail="Stop capture, transition to transcribing" />
            <Step number="6" label="Audio saved" detail="Copied to permanent storage before processing" />
            <Step number="7" label="Transcription request" detail="Sent to TalkieEngine via XPC" hookPoint />
            <Step number="8" label="Text returned" detail="Whisper model returns transcript" hookPoint />
          </div>
          <HookPoint
            name="onTranscriptionComplete"
            description="Transform or validate the transcript. Apply custom corrections, filter content, or route differently based on what was said."
            when="After transcription, before routing"
          />
        </Phase>

        {/* Phase 3: Route */}
        <Phase
          icon={Type}
          name="Routing"
          description="The transcript reaches its destination—pasted into the active app, copied to clipboard, or routed to the scratchpad for editing."
          timing="~50ms"
          color="bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400"
        >
          <div id="phase-route" className="space-y-0">
            <Step number="9" label="Routing decision" detail="Paste, clipboard, or scratchpad" hookPoint />
            <Step number="10" label="Text delivered" detail="Keyboard simulation or clipboard write" />
            <Step number="11" label="Sound feedback" detail="Confirmation that delivery succeeded" />
          </div>
          <HookPoint
            name="beforeRoute"
            description="Intercept before delivery. Could trigger different behavior based on keywords, app context, or custom rules."
            when="After routing decision, before text delivery"
          />
        </Phase>

        {/* Phase 4: Store */}
        <Phase
          icon={Database}
          name="Storage"
          description="The dictation is saved to the local database with full metadata. Available for search, review, and later processing."
          timing="~10ms"
          color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
          isLast
        >
          <div id="phase-store" className="space-y-0">
            <Step number="12" label="Record created" detail="LiveDictation saved to GRDB" hookPoint />
            <Step number="13" label="Context enrichment" detail="Async enhancement with bridge mapping" />
            <Step number="14" label="XPC notification" detail="Main app notified of new dictation" />
            <Step number="15" label="State reset" detail="Ready for next dictation" />
          </div>
          <HookPoint
            name="onDictationStored"
            description="React to completed dictations. Could trigger follow-up actions, sync to external services, or update statistics."
            when="After database write, before state reset"
          />
        </Phase>
      </div>

      {/* Memo Lifecycle */}
      <h2 id="memo-lifecycle">Memo Lifecycle</h2>
      <p>
        Memos are deliberate recordings that persist and get processed. Unlike dictation, memos trigger workflows that can summarize, extract tasks, or integrate with other systems.
      </p>

      <h3 id="memo-creation">Creation</h3>
      <p>
        When you create a memo (via the main Talkie app), the recording follows a similar path but ends differently:
      </p>

      <div className="my-6 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
        <div className="space-y-3">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-violet-100 dark:bg-violet-500/20 flex items-center justify-center">
              <Mic className="w-4 h-4 text-violet-600 dark:text-violet-400" />
            </div>
            <div>
              <span className="text-sm font-medium text-zinc-800 dark:text-zinc-200">Record</span>
              <span className="text-xs text-zinc-500 block">Audio captured via AVAudioRecorder</span>
            </div>
          </div>
          <div className="flex justify-center">
            <ArrowDown className="w-4 h-4 text-zinc-300" />
          </div>
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-blue-100 dark:bg-blue-500/20 flex items-center justify-center">
              <Brain className="w-4 h-4 text-blue-600 dark:text-blue-400" />
            </div>
            <div>
              <span className="text-sm font-medium text-zinc-800 dark:text-zinc-200">Transcribe</span>
              <span className="text-xs text-zinc-500 block">Sent to TalkieEngine via EngineClient</span>
            </div>
          </div>
          <div className="flex justify-center">
            <ArrowDown className="w-4 h-4 text-zinc-300" />
          </div>
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-emerald-100 dark:bg-emerald-500/20 flex items-center justify-center">
              <Database className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
            </div>
            <div>
              <span className="text-sm font-medium text-zinc-800 dark:text-zinc-200">Save as Memo</span>
              <span className="text-xs text-zinc-500 block">Stored in GRDB with audio file reference</span>
            </div>
          </div>
          <div className="flex justify-center">
            <ArrowDown className="w-4 h-4 text-zinc-300" />
          </div>
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center">
              <Zap className="w-4 h-4 text-amber-600 dark:text-amber-400" />
            </div>
            <div>
              <span className="text-sm font-medium text-zinc-800 dark:text-zinc-200">Trigger Workflows</span>
              <span className="text-xs text-zinc-500 block">Auto-run workflows execute in order</span>
            </div>
          </div>
        </div>
      </div>

      <h3 id="memo-workflows">Workflow Execution</h3>
      <p>
        Workflows are multi-step pipelines that process memo content. Each step can transform, extract, or route the content.
      </p>

      <div className="my-6 not-prose">
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="text-xs font-mono text-zinc-500 mb-3">Workflow Execution Flow</div>
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <span className="text-xs font-mono text-zinc-400">1.</span>
              <span className="text-sm text-zinc-700 dark:text-zinc-300">Load workflow definition (JSON)</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-mono text-zinc-400">2.</span>
              <span className="text-sm text-zinc-700 dark:text-zinc-300">Build context from memo (transcript, title, date)</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-mono text-zinc-400">3.</span>
              <span className="text-sm text-zinc-700 dark:text-zinc-300">Execute steps sequentially</span>
              <span className="px-1.5 py-0.5 text-[10px] font-mono font-bold uppercase rounded bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400">Hook</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-mono text-zinc-400">4.</span>
              <span className="text-sm text-zinc-700 dark:text-zinc-300">Each step output becomes available to next step</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs font-mono text-zinc-400">5. </span>
              <span className="text-sm text-zinc-700 dark:text-zinc-300">Save workflow run record with results</span>
            </div>
          </div>
        </div>
      </div>

      <p>
        Step types include <strong>LLM prompts</strong> (transform via AI), <strong>file actions</strong> (save to disk), <strong>clipboard</strong> (copy result), and <strong>webhooks</strong> (POST to external URL).
      </p>

      {/* Extension Points Summary */}
      <h2 id="extension-points">Extension Points</h2>
      <p>
        These are the natural seams in the lifecycle where custom logic could be injected. They represent moments where the flow pauses, a decision is made, or data transforms.
      </p>

      <div className="my-6 overflow-x-auto not-prose">
        <table className="w-full text-sm border border-zinc-200 dark:border-zinc-800 rounded-lg overflow-hidden">
          <thead className="bg-zinc-100 dark:bg-zinc-800">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-zinc-900 dark:text-white">Hook</th>
              <th className="px-4 py-3 text-left font-medium text-zinc-900 dark:text-white">Phase</th>
              <th className="px-4 py-3 text-left font-medium text-zinc-900 dark:text-white">Use Cases</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-200 dark:divide-zinc-800">
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-violet-600 dark:text-violet-400">onCaptureStart</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Capture</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Auto-route based on app, disable in certain contexts</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-violet-600 dark:text-violet-400">onTranscriptionComplete</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Transcription</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Custom corrections, keyword detection, content filtering</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-violet-600 dark:text-violet-400">beforeRoute</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Routing</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Intercept commands ("hey talkie"), transform output</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-violet-600 dark:text-violet-400">onDictationStored</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Storage</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Sync to external service, trigger notifications</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-violet-600 dark:text-violet-400">onMemoCreated</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Memo</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Auto-categorize, trigger custom workflows</td>
            </tr>
            <tr className="bg-white dark:bg-zinc-900">
              <td className="px-4 py-3 font-mono text-violet-600 dark:text-violet-400">beforeWorkflowStep</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Workflow</td>
              <td className="px-4 py-3 text-zinc-600 dark:text-zinc-400">Inject data, modify prompts, skip steps conditionally</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p>
        These extension points aren't implemented yet—this is documenting where they <em>could</em> exist. The lifecycle naturally pauses at these moments, making them ideal for hooks.
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
