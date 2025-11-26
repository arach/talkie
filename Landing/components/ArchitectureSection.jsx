import React from 'react'
import { Cpu, Cloud, ShieldCheck, Lock, Layers, Wand2, Mic, GitFork, Database } from 'lucide-react'

export default function ArchitectureSection() {
  return (
    <section id="architecture" className="border-t border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-950">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-2xl md:text-3xl font-bold tracking-tight text-zinc-900 dark:text-white">How Talkie Works</h2>
          <p className="mt-3 text-zinc-600 dark:text-zinc-400">A native pipeline for capture → transcript → insight, with local or cloud intelligence.</p>
        </div>

        {/* Diagram */}
        <div className="mt-10 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-zinc-50/50 dark:bg-black p-5">
          <div className="grid gap-3 md:grid-cols-5">
            {[
              { icon: <Mic className="w-4 h-4" />, label: 'Capture (iOS)' },
              { icon: <Cloud className="w-4 h-4" />, label: 'Sync (iCloud)' },
              { icon: <Wand2 className="w-4 h-4" />, label: 'Transcribe' },
              { icon: <Layers className="w-4 h-4" />, label: 'LLM Provider' },
              { icon: <GitFork className="w-4 h-4" />, label: 'Workflows' },
            ].map((s, i) => (
              <div key={i} className="flex items-center justify-center gap-2 rounded-md border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-950 py-3 text-xs font-medium text-zinc-700 dark:text-zinc-300">
                {s.icon}
                <span>{s.label}</span>
              </div>
            ))}
          </div>
          <p className="mt-3 text-center text-[10px] font-mono uppercase tracking-widest text-zinc-500">End‑to‑end on your devices • No glue scripts • No copy/paste</p>
        </div>

        {/* Cards */}
        <div className="mt-10 grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <Card
            icon={<Layers className="w-5 h-5" />}
            title="Provider Layer"
            body="A single interface (LLMProvider) wraps local MLX and cloud APIs (Gemini, OpenAI, Anthropic, Groq). Swap models without changing UI or workflow code."
            footer="Pluggable • Async • Streaming-ready"
          />
          <Card
            icon={<Cpu className="w-5 h-5" />}
            title="Local Intelligence (MLX)"
            body="On Apple Silicon, run 4‑bit quantized models locally for private, fast inference. Download and manage models in-app."
            footer="Qwen / Llama / Mistral / Phi"
          />
          <Card
            icon={<Cloud className="w-5 h-5" />}
            title="Cloud Providers"
            body="When needed, pick best‑in‑class cloud models. Configure keys per provider and choose the right model per workflow."
            footer="Gemini • OpenAI • Anthropic • Groq"
          />
          <Card
            icon={<Wand2 className="w-5 h-5" />}
            title="Workflow Engine"
            body="Reusable, prompt‑driven actions: Summarize, Extract Tasks, Insights, Reminders. Results are saved back to each memo."
            footer="Deterministic prompts • JSON outputs"
          />
          <Card
            icon={<Database className="w-5 h-5" />}
            title="Data & Sync"
            body="Core Data + NSPersistentCloudKitContainer keep memos, transcripts, and outputs consistent across iOS and macOS."
            footer="Automatic iCloud sync"
          />
          <Card
            icon={<ShieldCheck className="w-5 h-5" />}
            title="Privacy & Security"
            body="Local‑first by default. With MLX, your audio and prompts never leave your machine. Cloud calls are explicit and key‑scoped."
            footer="No trackers • HTTPS • App Sandbox"
          />
        </div>

        {/* Details list */}
        <div className="mt-12 grid gap-8 md:grid-cols-2">
          <div className="rounded-lg border border-zinc-200 dark:border-zinc-800 p-5">
            <h3 className="text-sm font-bold uppercase tracking-wider text-zinc-900 dark:text-white">Feature Highlights</h3>
            <ul className="mt-3 list-disc space-y-2 pl-5 text-sm text-zinc-700 dark:text-zinc-300">
              <li>High‑fidelity capture on iOS with immediate iCloud sync</li>
              <li>Readable transcripts with selection and notes</li>
              <li>One‑click workflows: Summary, Tasks, Insights, Reminders</li>
              <li>Local MLX models for private, offline intelligence</li>
              <li>Provider cards for easy API key setup</li>
            </ul>
          </div>
          <div className="rounded-lg border border-zinc-200 dark:border-zinc-800 p-5">
            <h3 className="text-sm font-bold uppercase tracking-wider text-zinc-900 dark:text-white">Tech Stack</h3>
            <ul className="mt-3 space-y-2 text-sm text-zinc-700 dark:text-zinc-300">
              <li><span className="font-medium">Apps:</span> SwiftUI (iOS + macOS), Core Data, CloudKit</li>
              <li><span className="font-medium">Intelligence:</span> MLX (local), Gemini/OpenAI/Anthropic/Groq (cloud)</li>
              <li><span className="font-medium">Workflows:</span> Prompt templates → JSON/text outputs</li>
              <li><span className="font-medium">Landing:</span> Next.js 14, Tailwind CSS, GitHub Pages</li>
            </ul>
          </div>
        </div>
      </div>
    </section>
  )
}

function Card({ icon, title, body, footer }) {
  return (
    <div className="rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white/70 dark:bg-zinc-950/70 backdrop-blur p-5">
      <div className="flex items-center gap-3 text-zinc-900 dark:text-white">
        <div className="flex h-8 w-8 items-center justify-center rounded-md bg-zinc-100 dark:bg-zinc-900 text-zinc-800 dark:text-zinc-200">
          {icon}
        </div>
        <div className="font-semibold">{title}</div>
      </div>
      <p className="mt-2 text-sm text-zinc-700 dark:text-zinc-300">{body}</p>
      {footer && (
        <div className="mt-3 text-[10px] font-mono uppercase tracking-widest text-zinc-500">{footer}</div>
      )}
    </div>
  )
}

