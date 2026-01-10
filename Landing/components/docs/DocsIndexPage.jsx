"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Server, Globe, Book, Lightbulb, Boxes, Database, Workflow, Code2, Puzzle, Route } from 'lucide-react'
import Container from '../Container'

const DocCard = ({ href, icon: Icon, title, description, color }) => (
  <Link
    href={href}
    className="group block p-6 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-all hover:shadow-lg"
  >
    <div className={`inline-flex p-3 rounded-lg ${color} mb-4`}>
      <Icon className="w-6 h-6" />
    </div>
    <h3 className="text-lg font-bold text-zinc-900 dark:text-white mb-2 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
      {title}
    </h3>
    <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-4">
      {description}
    </p>
    <div className="flex items-center gap-1 text-sm font-medium text-emerald-600 dark:text-emerald-400">
      Read guide <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
    </div>
  </Link>
)

export default function DocsIndexPage() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <Container className="h-14 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            BACK
          </Link>

          <div className="flex items-center gap-2 sm:gap-3">
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">DOCS</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          {/* Header */}
          <div className="max-w-2xl mb-16">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 mb-6">
              <Book className="w-4 h-4 text-emerald-500" />
              <span className="text-xs font-medium text-zinc-600 dark:text-zinc-400">Documentation</span>
            </div>

            <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
              Documentation
            </h1>

            <p className="text-lg text-zinc-600 dark:text-zinc-400">
              Learn how Talkie works, from high-level concepts to technical deep dives. Whether you're getting started or building integrations.
            </p>
          </div>

          {/* Start Here */}
          <div className="mb-16">
            <h2 className="text-sm font-bold uppercase tracking-wider text-zinc-500 dark:text-zinc-400 mb-6">
              Start Here
            </h2>
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 max-w-5xl">
              <DocCard
                href="/docs/overview"
                icon={Lightbulb}
                title="Overview"
                description="What makes Talkie different? Local-first design, privacy by default, and a philosophy of ownership."
                color="bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400"
              />

              <DocCard
                href="/docs/architecture"
                icon={Boxes}
                title="Architecture"
                description="Multi-process design explained. How Talkie, TalkieLive, TalkieEngine, and TalkieServer work together."
                color="bg-purple-100 dark:bg-purple-500/20 text-purple-600 dark:text-purple-400"
              />

              <DocCard
                href="/docs/lifecycle"
                icon={Route}
                title="Lifecycle"
                description="The journey from voice to action. Understand each phase and where you can plug in custom logic."
                color="bg-violet-100 dark:bg-violet-500/20 text-violet-600 dark:text-violet-400"
              />

              <DocCard
                href="/docs/data"
                icon={Database}
                title="Your Data"
                description="Where your data lives, how to export it, and what formats we use. Your recordings, your control."
                color="bg-rose-100 dark:bg-rose-500/20 text-rose-600 dark:text-rose-400"
              />
            </div>
          </div>

          {/* Setup Guides */}
          <div className="mb-16">
            <h2 className="text-sm font-bold uppercase tracking-wider text-zinc-500 dark:text-zinc-400 mb-6">
              Setup Guides
            </h2>
            <div className="grid md:grid-cols-2 gap-6 max-w-4xl">
              <DocCard
                href="/docs/bridge-setup"
                icon={Server}
                title="TalkieServer Setup"
                description="Install the local bridge server that enables iPhone connectivity. Learn about Bun, dependencies, and what gets installed."
                color="bg-emerald-100 dark:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400"
              />

              <DocCard
                href="/docs/tailscale"
                icon={Globe}
                title="Tailscale Configuration"
                description="Set up secure, peer-to-peer networking between your Mac and iPhone. No port forwarding or cloud relay needed."
                color="bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
              />
            </div>
          </div>

          {/* Power Users */}
          <div className="mb-16">
            <h2 className="text-sm font-bold uppercase tracking-wider text-zinc-500 dark:text-zinc-400 mb-6">
              Power Users
            </h2>
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 max-w-5xl">
              <DocCard
                href="/docs/workflows"
                icon={Workflow}
                title="Workflows"
                description="Build automated pipelines. Triggers, steps, conditions, and the 18 step types available."
                color="bg-indigo-100 dark:bg-indigo-500/20 text-indigo-600 dark:text-indigo-400"
              />

              <DocCard
                href="/docs/api"
                icon={Code2}
                title="API Reference"
                description="TalkieServer endpoints, URL schemes, and how to integrate with external tools."
                color="bg-cyan-100 dark:bg-cyan-500/20 text-cyan-600 dark:text-cyan-400"
              />

              <DocCard
                href="/docs/extensibility"
                icon={Puzzle}
                title="Extensibility"
                description="Webhooks, custom workflows, and building your own integrations. Talkie is designed to be extended."
                color="bg-orange-100 dark:bg-orange-500/20 text-orange-600 dark:text-orange-400"
              />
            </div>
          </div>
        </Container>
      </main>
    </div>
  )
}
