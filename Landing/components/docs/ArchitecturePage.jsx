"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Layers, Monitor, Mic, Cpu, Server, MessageSquare } from 'lucide-react'
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

const ComponentCard = ({ icon: Icon, name, subtitle, responsibilities, color }) => (
  <div className="p-6 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
    <div className="flex items-start gap-4">
      <div className={`flex-shrink-0 w-12 h-12 rounded-lg ${color} flex items-center justify-center`}>
        <Icon className="w-6 h-6" />
      </div>
      <div className="flex-1">
        <h3 className="text-lg font-bold text-zinc-900 dark:text-white">{name}</h3>
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
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">ARCHITECTURE</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-amber-200 dark:border-amber-500/30 bg-amber-50 dark:bg-amber-500/10 mb-6">
                <Layers className="w-4 h-4 text-amber-600 dark:text-amber-400" />
                <span className="text-xs font-medium text-amber-700 dark:text-amber-400">Technical</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                Architecture
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                A deep dive into Talkie's multi-process architecture. Each component has a single responsibility,
                making the system reliable and maintainable.
              </p>
            </div>

            {/* Architecture Diagram */}
            <Section title="System Overview">
              <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6">
                <pre className="text-xs md:text-sm font-mono text-zinc-600 dark:text-zinc-400 overflow-x-auto">
{`┌─────────────────────────────────────────────────────────────┐
│                    Talkie (Swift)                           │
│              UI • Workflows • Data • Orchestration          │
└────────────────┬────────────────┬────────────────┬──────────┘
                 │ XPC            │ XPC            │ HTTP
                 ▼                ▼                ▼
        ┌────────────────┐ ┌─────────────┐ ┌──────────────────┐
        │  TalkieLive    │ │ TalkieEngine│ │  TalkieServer    │
        │    (Swift)     │ │   (Swift)   │ │   (TypeScript)   │
        │  Ears & Hands  │ │ Local Brain │ │   iOS Bridge     │
        └────────────────┘ └─────────────┘ └────────┬─────────┘
                                                    │ Tailscale
                                                    ▼
                                           ┌──────────────────┐
                                           │  Talkie (iPhone) │
                                           │   Voice Capture  │
                                           └──────────────────┘`}
                </pre>
              </div>
            </Section>

            {/* Components */}
            <Section title="Components">
              <div className="space-y-4">
                <ComponentCard
                  icon={Monitor}
                  name="Talkie"
                  subtitle="Main Application (Swift/SwiftUI)"
                  responsibilities={[
                    "User interface and settings",
                    "Workflow orchestration",
                    "Data management (GRDB)",
                    "Process lifecycle management",
                  ]}
                  color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
                />

                <ComponentCard
                  icon={Mic}
                  name="TalkieLive"
                  subtitle="Dictation Service (Swift)"
                  responsibilities={[
                    "Microphone capture and audio processing",
                    "Live dictation mode",
                    "Keyboard simulation for text insertion",
                    "Audio level monitoring",
                  ]}
                  color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
                />

                <ComponentCard
                  icon={Cpu}
                  name="TalkieEngine"
                  subtitle="Transcription Engine (Swift)"
                  responsibilities={[
                    "Local Whisper model management",
                    "Audio-to-text transcription",
                    "Model downloading and caching",
                    "GPU acceleration (when available)",
                  ]}
                  color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
                />

                <ComponentCard
                  icon={Server}
                  name="TalkieServer"
                  subtitle="iOS Bridge (TypeScript/Bun)"
                  responsibilities={[
                    "HTTP API for iOS app communication",
                    "Device pairing and authentication",
                    "Voice recording sync from iPhone",
                    "Tailscale integration",
                  ]}
                  color="bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400"
                />
              </div>
            </Section>

            {/* XPC Communication */}
            <Section title="XPC Communication Patterns">
              <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                <div className="flex items-center gap-3 mb-3">
                  <MessageSquare className="w-5 h-5 text-blue-500" />
                  <h3 className="font-bold text-zinc-900 dark:text-white">Inter-Process Communication</h3>
                </div>
                <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-4">
                  Talkie uses XPC (Cross-Process Communication) to talk to TalkieLive and TalkieEngine.
                  This provides security boundaries and crash isolation.
                </p>
              </div>

              <Placeholder>
                Coming soon: XPC protocol definitions, message flow diagrams,
                error handling strategies, and reconnection logic.
              </Placeholder>
            </Section>

            {/* Process Lifecycle */}
            <Section title="Process Lifecycle">
              <Placeholder>
                Coming soon: How processes start and stop, launchd integration,
                crash recovery, and resource management.
              </Placeholder>
            </Section>

            {/* Design Decisions */}
            <Section title="Design Decisions">
              <Placeholder>
                Coming soon: Why multi-process instead of monolithic,
                trade-offs considered, and evolution of the architecture.
              </Placeholder>
            </Section>

            {/* Navigation */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row gap-4">
                <Link
                  href="/docs/overview"
                  className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-violet-500 group-hover:-translate-x-1 transition-all" />
                  <div>
                    <span className="text-xs text-zinc-500">Previous</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-violet-600 dark:group-hover:text-violet-400 transition-colors">
                      Overview
                    </h3>
                  </div>
                </Link>

                <Link
                  href="/docs/data"
                  className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <div>
                    <span className="text-xs text-zinc-500">Next</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">
                      Data Layer
                    </h3>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-amber-500 group-hover:translate-x-1 transition-all" />
                </Link>
              </div>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
