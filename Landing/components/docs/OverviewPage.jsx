"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Lightbulb, Shield, Cpu, Network, Eye } from 'lucide-react'
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

const FeatureCard = ({ icon: Icon, title, description, color }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
    <Icon className={`w-6 h-6 ${color} mb-3`} />
    <h3 className="font-bold text-zinc-900 dark:text-white mb-2">{title}</h3>
    <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
  </div>
)

export default function OverviewPage() {
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
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">OVERVIEW</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-violet-200 dark:border-violet-500/30 bg-violet-50 dark:bg-violet-500/10 mb-6">
                <Lightbulb className="w-4 h-4 text-violet-600 dark:text-violet-400" />
                <span className="text-xs font-medium text-violet-700 dark:text-violet-400">Introduction</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                Overview
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                Talkie is a voice-first productivity suite for macOS. Built with privacy at its core,
                it processes everything locally while maintaining a seamless experience across devices.
              </p>
            </div>

            {/* Philosophy */}
            <Section title="Philosophy">
              <p>
                Talkie is designed around three core principles that guide every architectural decision.
              </p>

              <div className="grid md:grid-cols-3 gap-4 mt-6">
                <FeatureCard
                  icon={Shield}
                  title="Local-First"
                  description="Your voice data never leaves your devices. All transcription happens on your Mac."
                  color="text-emerald-500"
                />
                <FeatureCard
                  icon={Cpu}
                  title="Privacy by Design"
                  description="No cloud processing required. No accounts needed. Your data is yours."
                  color="text-blue-500"
                />
                <FeatureCard
                  icon={Eye}
                  title="Transparent"
                  description="See exactly what's happening. No black boxes or hidden processes."
                  color="text-violet-500"
                />
              </div>
            </Section>

            {/* Local-First Design */}
            <Section title="Local-First Design">
              <Placeholder>
                Coming soon: Detailed explanation of local-first principles in Talkie.
                How data stays on device, offline-first capabilities, and sync strategies.
              </Placeholder>
            </Section>

            {/* Multi-Process Architecture */}
            <Section title="Multi-Process Architecture">
              <p>
                Talkie splits responsibilities across multiple processes for reliability and performance.
                If one component has an issue, the others keep running.
              </p>

              <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6 mt-6">
                <pre className="text-xs md:text-sm font-mono text-zinc-600 dark:text-zinc-400 overflow-x-auto">
{`┌─────────────────────────────────────────────────────────────┐
│                    Talkie (Mac App)                         │
│              UI • Workflows • Data • Orchestration          │
└────────────────┬────────────────┬────────────────┬──────────┘
                 │ XPC            │ XPC            │ HTTP
                 ▼                ▼                ▼
        ┌────────────────┐ ┌─────────────┐ ┌──────────────────┐
        │  TalkieLive    │ │ TalkieEngine│ │  TalkieServer    │
        │    (Swift)     │ │   (Swift)   │ │   (TypeScript)   │
        │  Ears & Hands  │ │ Local Brain │ │   iOS Bridge     │
        └────────────────┘ └─────────────┘ └──────────────────┘`}
                </pre>
              </div>

              <Placeholder>
                Coming soon: Detailed breakdown of each process, when they start,
                and how they communicate.
              </Placeholder>
            </Section>

            {/* Communication Patterns */}
            <Section title="How Components Communicate">
              <div className="space-y-4">
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <div className="flex items-center gap-3 mb-2">
                    <Network className="w-5 h-5 text-blue-500" />
                    <h3 className="font-bold text-zinc-900 dark:text-white">XPC (Inter-Process Communication)</h3>
                  </div>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Talkie communicates with TalkieLive and TalkieEngine via XPC,
                    Apple's secure inter-process communication mechanism.
                  </p>
                </div>

                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <div className="flex items-center gap-3 mb-2">
                    <Network className="w-5 h-5 text-emerald-500" />
                    <h3 className="font-bold text-zinc-900 dark:text-white">HTTP (Local Server)</h3>
                  </div>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    TalkieServer exposes HTTP endpoints for iOS connectivity.
                    Communication happens over Tailscale's encrypted tunnel.
                  </p>
                </div>
              </div>

              <Placeholder>
                Coming soon: Message flow diagrams, security considerations,
                and error handling patterns.
              </Placeholder>
            </Section>

            {/* Next Steps */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <h2 className="text-xl font-bold text-zinc-900 dark:text-white mb-4">Continue Reading</h2>

              <Link
                href="/docs/architecture"
                className="group flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-violet-300 dark:hover:border-violet-500/50 transition-colors"
              >
                <div>
                  <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-violet-600 dark:group-hover:text-violet-400 transition-colors">
                    Architecture Deep Dive
                  </h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Detailed look at each component and how they work together
                  </p>
                </div>
                <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-violet-500 group-hover:translate-x-1 transition-all" />
              </Link>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
