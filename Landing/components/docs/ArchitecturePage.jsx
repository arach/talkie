"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowRight, ArrowLeft, Monitor, Mic, Cpu, Server, MessageSquare } from 'lucide-react'
import DocsLayout from './DocsLayout'
import ArcDiagram from './ArcDiagram'
import architectureDiagram from './diagrams/architecture.diagram'

const sections = [
  { id: 'system-overview', title: 'System Overview', level: 2 },
  { id: 'components', title: 'Components', level: 2 },
  { id: 'talkie', title: 'Talkie', level: 3 },
  { id: 'talkielive', title: 'TalkieLive', level: 3 },
  { id: 'talkieengine', title: 'TalkieEngine', level: 3 },
  { id: 'talkieserver', title: 'TalkieServer', level: 3 },
  { id: 'xpc', title: 'XPC Communication', level: 2 },
  { id: 'lifecycle', title: 'Process Lifecycle', level: 2 },
  { id: 'navigation', title: 'Continue Reading', level: 2 },
]

const ComponentCard = ({ id, icon: Icon, name, subtitle, responsibilities, color }) => (
  <div id={id} className="p-6 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose scroll-mt-20">
    <div className="flex items-start gap-4">
      <div className={`flex-shrink-0 w-12 h-12 rounded-lg ${color} flex items-center justify-center`}>
        <Icon className="w-6 h-6" />
      </div>
      <div className="flex-1">
        <h4 className="text-lg font-bold text-zinc-900 dark:text-white">{name}</h4>
        <p className="text-sm text-zinc-500 dark:text-zinc-400 mb-3">{subtitle}</p>
        <ul className="space-y-1">
          {responsibilities.map((item, i) => (
            <li key={i} className="text-sm text-zinc-600 dark:text-zinc-400 flex items-start gap-2">
              <span className="text-zinc-400 dark:text-zinc-600">-</span>
              {item}
            </li>
          ))}
        </ul>
      </div>
    </div>
  </div>
)

export default function ArchitecturePage() {
  return (
    <DocsLayout
      title="Architecture"
      description="A deep dive into Talkie's multi-process architecture. Each component has a single responsibility, making the system reliable and maintainable."
      badge="Technical"
      badgeColor="amber"
      sections={sections}
    >
      {/* System Overview */}
      <h2 id="system-overview">System Overview</h2>
      <p>
        Talkie's architecture separates concerns across multiple processes. This isn't complexity for complexity's sake—it provides real benefits: fault isolation, security boundaries, and the ability to evolve components independently.
      </p>

      <ArcDiagram data={architectureDiagram} className="my-8" />

      <p>
        The main Talkie app is the orchestrator—it manages the UI, workflows, and data. The helper processes (TalkieLive, TalkieEngine, TalkieServer) handle specific tasks that benefit from isolation.
      </p>

      {/* Components */}
      <h2 id="components">Components</h2>
      <p>
        Each component has a clear responsibility and communicates through well-defined interfaces.
      </p>

      <div className="space-y-4 my-6 not-prose">
        <ComponentCard
          id="talkie"
          icon={Monitor}
          name="Talkie"
          subtitle="Main Application (Swift/SwiftUI)"
          responsibilities={[
            "User interface and settings",
            "Workflow orchestration and execution",
            "Data management (GRDB database)",
            "Process lifecycle management for helpers",
          ]}
          color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
        />

        <ComponentCard
          id="talkielive"
          icon={Mic}
          name="TalkieLive"
          subtitle="Dictation Service (Swift)"
          responsibilities={[
            "Microphone capture and audio processing",
            "Live dictation mode with real-time feedback",
            "Keyboard simulation for text insertion",
            "Audio level monitoring and silence detection",
          ]}
          color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
        />

        <ComponentCard
          id="talkieengine"
          icon={Cpu}
          name="TalkieEngine"
          subtitle="Transcription Engine (Swift)"
          responsibilities={[
            "Local Whisper model management",
            "Audio-to-text transcription",
            "Model downloading and caching",
            "GPU acceleration via Metal (when available)",
          ]}
          color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
        />

        <ComponentCard
          id="talkieserver"
          icon={Server}
          name="TalkieServer"
          subtitle="iOS Bridge (TypeScript/Bun)"
          responsibilities={[
            "HTTP API for iOS app communication",
            "Device pairing and authentication",
            "Voice recording sync from iPhone/Apple Watch",
            "Tailscale network integration",
          ]}
          color="bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400"
        />
      </div>

      {/* XPC Communication */}
      <h2 id="xpc">XPC Communication</h2>
      <p>
        XPC (Cross-Process Communication) is Apple's secure mechanism for processes to talk to each other. Talkie uses XPC to communicate with TalkieLive and TalkieEngine.
      </p>

      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-3">
          <MessageSquare className="w-5 h-5 text-blue-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Why XPC?</span>
        </div>
        <ul className="text-sm text-zinc-600 dark:text-zinc-400 space-y-1">
          <li>• <strong>Security</strong> — Each process runs with minimal permissions</li>
          <li>• <strong>Crash isolation</strong> — A helper crash doesn't take down the main app</li>
          <li>• <strong>Lifecycle management</strong> — macOS handles process start/stop</li>
          <li>• <strong>Type safety</strong> — Protocol-based communication with compile-time checks</li>
        </ul>
      </div>

      <p>
        When you start a dictation, Talkie sends an XPC message to TalkieLive. TalkieLive captures audio, sends it to TalkieEngine for transcription, and simulates keyboard input with the results—all without the main app needing microphone or accessibility permissions.
      </p>

      {/* Process Lifecycle */}
      <h2 id="lifecycle">Process Lifecycle</h2>
      <p>
        Helper processes are managed by launchd, macOS's service manager. This means:
      </p>
      <ul>
        <li><strong>On-demand start</strong> — Helpers launch when needed, not at login</li>
        <li><strong>Automatic restart</strong> — If a helper crashes, launchd restarts it</li>
        <li><strong>Resource efficiency</strong> — Idle helpers use minimal resources</li>
        <li><strong>Clean shutdown</strong> — Helpers terminate when Talkie quits</li>
      </ul>
      <p>
        You can see the helper processes in Activity Monitor: look for TalkieLive, TalkieEngine, and TalkieServer (when iPhone sync is enabled).
      </p>

      {/* Navigation */}
      <h2 id="navigation">Continue Reading</h2>
      <div className="flex flex-col sm:flex-row gap-4 not-prose">
        <Link
          href="/docs/overview"
          className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-violet-500 group-hover:-translate-x-1 transition-all" />
          <div>
            <span className="text-xs text-zinc-500">Previous</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-violet-600 dark:group-hover:text-violet-400 transition-colors">
              Overview
            </span>
          </div>
        </Link>

        <Link
          href="/docs/data"
          className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <div>
            <span className="text-xs text-zinc-500">Next</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-rose-600 dark:group-hover:text-rose-400 transition-colors">
              Your Data
            </span>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-rose-500 group-hover:translate-x-1 transition-all" />
        </Link>
      </div>
    </DocsLayout>
  )
}
