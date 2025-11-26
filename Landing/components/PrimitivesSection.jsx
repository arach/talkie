import React from 'react'
import { Zap, Lock, Cloud, Mic, Wand2, Plus } from 'lucide-react'
import Reveal from './Reveal'

export default function PrimitivesSection() {
  return (
    <section className="relative -mt-12 md:-mt-16 lg:-mt-20 xl:-mt-24 bg-zinc-950 text-zinc-100 border-t border-zinc-900">
      <div className="absolute inset-0 bg-tactical-grid-dark opacity-20 pointer-events-none" />
      {/* soft vignette to focus the content */}
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_60%_at_55%_40%,rgba(0,0,0,0.25),transparent)]" />
      <div className="relative mx-auto max-w-5xl px-6 pt-12 pb-16 md:pt-16 md:pb-20">
        <div className="max-w-3xl">
          <h2 className="text-[26px] md:text-[28px] font-extrabold tracking-[0.01em] uppercase text-zinc-100">Powerful Primitives.</h2>
          <p className="mt-2 text-[13px] leading-relaxed text-zinc-400 max-w-[46rem]">
            We&apos;ve rebuilt the recording stack from the ground up. Talkie combines a professional‑grade audio
            engine with a node‑based automation system.
          </p>
        </div>

        <div className="mt-8 md:mt-10 grid gap-5 md:gap-6 xl:gap-8 md:[grid-template-columns:1fr_1fr] lg:[grid-template-columns:2fr_1.25fr_1fr]">
          {/* Big left card (spans 2 cols) */}
          <Reveal className="relative md:col-span-2 lg:col-span-1 overflow-hidden panel panel-hover p-6 xl:p-7 bg-zinc-950/80">
            <div className="flex items-center gap-3">
              <div className="flex h-9 w-9 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-zinc-100">
                <Zap className="w-4 h-4" />
              </div>
              <div className="text-[13px] font-extrabold tracking-[0.22em] uppercase">Local AI Workflows</div>
            </div>
            <p className="mt-3 text-[13px] text-zinc-400">
              Don&apos;t just record. Process. Configure pipelines to automatically summarize meetings, extract action
              items, or reformat ramblings into clear prose.
            </p>

            {/* inner panel ring for code-like pipeline */}
            <div className="mt-6 rounded-[6px] border border-zinc-800/60 p-4 bg-zinc-950/30">
              <div className="pl-4">
                <Row dotClass="bg-zinc-500" connector>Input: Audio Recording (RAW)</Row>
                <Row dotClass="bg-zinc-500" connector>Process: Whisper (Quantized)</Row>
                <Row dotClass="bg-sky-400" connector>LLM: Summarize & Extract Tasks</Row>
                <Row dotClass="bg-emerald-500">
                  Output: <span className="font-semibold">Draft Email</span> / Notion Page
                </Row>
              </div>
            </div>

            {/* faint decorative glyphs */}
            <div className="pointer-events-none absolute right-6 top-8 opacity-5 md:opacity-10">
              <Wand2 className="h-28 w-28 text-zinc-100" />
            </div>
            <div className="pointer-events-none absolute right-16 top-20 opacity-5 md:opacity-10">
              <Plus className="h-10 w-10 text-zinc-100" />
            </div>
          </Reveal>

          {/* On‑device card (tall) */}
          <Reveal delay={80} className="row-span-2 lg:row-span-2 min-h-[280px] xl:min-h-[320px] panel panel-hover p-5 md:p-6 xl:p-7 bg-zinc-950/70">
            <div className="flex items-center gap-3">
              <div className="flex h-6 w-6 items-center justify-center rounded-full bg-zinc-800 text-zinc-100">
                <Lock className="w-3.5 h-3.5" />
              </div>
              <div className="text-sm font-extrabold tracking-wide uppercase">On‑Device Only</div>
            </div>
            <p className="mt-3 text-[13px] text-zinc-400">
              Your voice is your biometric identity. It should never touch a server. We run LLMs locally on the
              Neural Engine.
            </p>
            <div className="mt-6 pt-4 text-[10px] font-mono uppercase tracking-[0.18em] text-zinc-400">
              <div className="hairline" />
              <div className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 items-baseline">
                <span className="whitespace-nowrap">Tracker Count</span>
                <span className="text-right">0</span>
                <span className="whitespace-nowrap">Cloud Processing</span>
                <span className="text-right">Disabled</span>
                <span className="whitespace-nowrap">Offline Mode</span>
                <span className="text-right text-emerald-400 font-medium">Active</span>
              </div>
            </div>
          </Reveal>

          {/* iCloud Sync */}
          <Reveal delay={120} className="panel panel-hover p-5 md:p-6 xl:p-7 bg-zinc-950/70">
            <div className="flex items-center justify-between">
              <Cloud className="w-5 h-5 text-zinc-100" />
              <span className="block h-2 w-2 rounded-full bg-blue-500" />
            </div>
            <div className="mt-3 text-[12px] font-extrabold uppercase tracking-[0.18em]">iCloud Sync</div>
            <p className="mt-1 text-[12px] text-zinc-400 leading-relaxed">
              Start recording on iPhone. Tag it. It appears instantly on your Mac for deep work.
            </p>
          </Reveal>

          {/* Pro Audio */}
          <Reveal delay={160} className="panel panel-hover p-5 md:p-6 xl:p-7 bg-zinc-950/70">
            <div className="flex items-center justify-between">
              <Mic className="w-5 h-5 text-zinc-100" />
              <span className="text-[10px] font-mono uppercase text-zinc-500">Whisper‑V3</span>
            </div>
            <div className="mt-3 text-[12px] font-extrabold uppercase tracking-[0.18em]">Pro Audio</div>
            <p className="mt-1 text-[12px] text-zinc-400 leading-relaxed">
              32‑bit float audio pipeline. Stereo recording. Automatic noise reduction.
            </p>
          </Reveal>
        </div>
      </div>
    </section>
  )
}

function Row({ children, dotClass = 'bg-zinc-500', connector = false }) {
  return (
    <div className="relative pl-4 py-1 text-[12px] font-mono text-zinc-300">
      <span className={`absolute left-[-0.35rem] top-2 h-1.5 w-1.5 rounded-full ${dotClass}`} />
      {children}
      {connector && (
        <span className="absolute left-[-0.14rem] bottom-[-6px] h-[10px] w-px bg-zinc-700/70" />
      )}
    </div>
  )
}
