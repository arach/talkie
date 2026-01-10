"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowRight, Shield, Cpu, Eye, Network } from 'lucide-react'
import DocsLayout from './DocsLayout'
import { SimpleArchitectureDiagram } from './ArchitectureDiagram'

// Sections for the right-side table of contents
const sections = [
  { id: 'philosophy', title: 'Philosophy', level: 2 },
  { id: 'design-principles', title: 'Design Principles', level: 2 },
  { id: 'local-first', title: 'Local-First Design', level: 2 },
  { id: 'multi-process', title: 'Multi-Process Architecture', level: 2 },
  { id: 'communication', title: 'How Components Communicate', level: 2 },
  { id: 'xpc', title: 'XPC', level: 3 },
  { id: 'http', title: 'HTTP', level: 3 },
  { id: 'next-steps', title: 'Continue Reading', level: 2 },
]

const FeatureCard = ({ icon: Icon, title, description, color }) => (
  <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 not-prose">
    <Icon className={`w-6 h-6 ${color} mb-3`} />
    <h4 className="font-bold text-zinc-900 dark:text-white mb-2">{title}</h4>
    <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
  </div>
)

export default function OverviewPage() {
  return (
    <DocsLayout
      title="Overview"
      description="Talkie is a voice-first productivity suite for macOS. Built with privacy at its core, it processes everything locally while maintaining a seamless experience across devices."
      badge="Introduction"
      badgeColor="purple"
      sections={sections}
    >
      {/* Philosophy */}
      <h2 id="philosophy">Philosophy</h2>
      <p>
        Talkie is designed around three core principles that guide every architectural decision.
        These aren't just marketing—they fundamentally shape how the app works.
      </p>

      <div className="grid md:grid-cols-3 gap-4 my-6 not-prose">
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

      {/* Design Principles */}
      <h2 id="design-principles">Design Principles</h2>
      <p>
        We treat every user as a potential developer. These principles guide how we build Talkie,
        giving you visibility and control over everything—with smart defaults so you don't have to think about it.
      </p>

      <div className="my-6 space-y-4 not-prose">
        <div className="flex gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400 font-bold text-sm">1</div>
          <div>
            <h4 className="font-bold text-zinc-900 dark:text-white">Everything is a file</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
              Your data lives in readable formats on disk. SQLite databases, JSON exports, audio files—all accessible and portable.
            </p>
          </div>
        </div>

        <div className="flex gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400 font-bold text-sm">2</div>
          <div>
            <h4 className="font-bold text-zinc-900 dark:text-white">Small, focused data stores</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
              Instead of one monolithic database, each component owns its data. Memos in one place, live dictations in another. Clear boundaries, easy to reason about.
            </p>
          </div>
        </div>

        <div className="flex gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400 font-bold text-sm">3</div>
          <div>
            <h4 className="font-bold text-zinc-900 dark:text-white">Data stores exposed by default</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
              We don't hide your data in opaque containers. Browse your recordings, query your databases, export anything. Your data, your access.
            </p>
          </div>
        </div>

        <div className="flex gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400 font-bold text-sm">4</div>
          <div>
            <h4 className="font-bold text-zinc-900 dark:text-white">Well-defined lifecycles</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
              Every recording flows through clear phases: capture → transcription → routing → storage. Each phase has hooks where you can plug in custom logic.
            </p>
          </div>
        </div>

        <div className="flex gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400 font-bold text-sm">5</div>
          <div>
            <h4 className="font-bold text-zinc-900 dark:text-white">Protect the critical path</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
              Recording and transcription are sacred. Nothing should block them—not sync, not workflows, not UI rendering. The happy path is always fast.
            </p>
          </div>
        </div>

        <div className="flex gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <div className="flex-shrink-0 w-8 h-8 rounded-full bg-amber-100 dark:bg-amber-500/20 flex items-center justify-center text-amber-600 dark:text-amber-400 font-bold text-sm">6</div>
          <div>
            <h4 className="font-bold text-zinc-900 dark:text-white">Smart defaults, full control</h4>
            <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
              Talkie works great out of the box. But when you want to customize—workflows, shortcuts, data locations, export formats—everything is configurable.
            </p>
          </div>
        </div>
      </div>

      {/* Local-First Design */}
      <h2 id="local-first">Local-First Design</h2>
      <p>
        "Local-first" means your data lives on your device first, always. The cloud is optional,
        not required. This has real implications:
      </p>
      <ul>
        <li><strong>Works offline</strong> — Record, transcribe, and create memos without internet</li>
        <li><strong>Instant startup</strong> — No waiting for cloud connections or sync</li>
        <li><strong>You own your data</strong> — It's in readable formats on your disk</li>
        <li><strong>No accounts required</strong> — Start using Talkie immediately</li>
      </ul>
      <p>
        When you do enable sync (like iCloud), it's additive. The app works perfectly without it,
        and sync just keeps your devices in harmony.
      </p>

      {/* Multi-Process Architecture */}
      <h2 id="multi-process">Multi-Process Architecture</h2>
      <p>
        Unlike most apps that run as a single process, Talkie splits responsibilities across
        multiple specialized processes. This design provides reliability, security, and performance
        benefits.
      </p>

      <SimpleArchitectureDiagram />

      <p>
        <strong>Why multiple processes?</strong>
      </p>
      <ul>
        <li><strong>Fault isolation</strong> — If one component crashes, others keep running</li>
        <li><strong>Security boundaries</strong> — Each process has only the permissions it needs</li>
        <li><strong>Resource management</strong> — Heavy transcription work doesn't block the UI</li>
        <li><strong>Independent updates</strong> — Components can evolve separately</li>
      </ul>

      {/* Communication */}
      <h2 id="communication">How Components Communicate</h2>
      <p>
        The processes talk to each other using two main methods, each chosen for specific reasons.
      </p>

      <h3 id="xpc">XPC (Inter-Process Communication)</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-2">
          <Network className="w-5 h-5 text-blue-500" />
          <span className="font-bold text-zinc-900 dark:text-white">Talkie ↔ TalkieLive ↔ TalkieEngine</span>
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          XPC is Apple's secure inter-process communication mechanism. It provides automatic
          process lifecycle management, type-safe messaging, and sandboxing support.
          All native macOS components use XPC.
        </p>
      </div>

      <h3 id="http">HTTP (Local Server)</h3>
      <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 my-4 not-prose">
        <div className="flex items-center gap-3 mb-2">
          <Network className="w-5 h-5 text-emerald-500" />
          <span className="font-bold text-zinc-900 dark:text-white">TalkieServer ↔ iPhone</span>
        </div>
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          TalkieServer exposes HTTP endpoints that the iPhone app connects to.
          All traffic flows over Tailscale's encrypted WireGuard tunnel.
          This enables cross-device sync without any cloud intermediary.
        </p>
      </div>

      {/* Next Steps */}
      <h2 id="next-steps">Continue Reading</h2>
      <p>
        Ready to go deeper? The architecture docs explain each component in detail.
      </p>

      <Link
        href="/docs/architecture"
        className="group flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-violet-300 dark:hover:border-violet-500/50 transition-colors not-prose"
      >
        <div>
          <span className="font-bold text-zinc-900 dark:text-white group-hover:text-violet-600 dark:group-hover:text-violet-400 transition-colors">
            Architecture Deep Dive
          </span>
          <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">
            Detailed look at each component and how they work together
          </p>
        </div>
        <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-violet-500 group-hover:translate-x-1 transition-all" />
      </Link>
    </DocsLayout>
  )
}
