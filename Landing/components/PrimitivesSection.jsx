"use client"
import React from 'react'
import { Zap, Lock, Cloud, Mic, Wand2, Plus, Layers, Network, Database, Smartphone } from 'lucide-react'

export default function PrimitivesSection() {
  return (
    <section className="py-16 bg-zinc-100 dark:bg-zinc-900 border-t border-b border-zinc-200 dark:border-zinc-800 relative overflow-hidden">

      {/* Subtle Background Glows */}
      <div className="absolute top-0 left-1/4 w-[500px] h-[500px] bg-zinc-300/20 dark:bg-zinc-800/20 rounded-full blur-[128px] pointer-events-none mix-blend-multiply dark:mix-blend-screen" />
      <div className="absolute bottom-0 right-1/4 w-[600px] h-[600px] bg-zinc-200/40 dark:bg-zinc-800/10 rounded-full blur-[128px] pointer-events-none mix-blend-multiply dark:mix-blend-screen" />

      <div className="relative z-10 mx-auto max-w-6xl px-6">

        <div className="mb-10 md:flex items-end justify-between">
           <div className="max-w-xl">
             <h2 className="text-3xl font-bold text-zinc-900 dark:text-white mb-4 tracking-tight uppercase">Powerful Primitives.</h2>
             <p className="text-zinc-600 dark:text-zinc-400 text-sm leading-relaxed">
               We&apos;ve rebuilt the recording stack from the ground up. Talkie combines a professional‑grade audio engine with a node‑based automation system.
             </p>
           </div>
           <div className="hidden md:block">
             <Layers className="w-6 h-6 text-zinc-300 dark:text-zinc-700" />
           </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 auto-rows-fr">

          {/* 1. Local AI Workflows (Large) */}
          <div className="col-span-1 md:col-span-2 row-span-2 relative bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 p-6 flex flex-col justify-between group overflow-hidden rounded-sm shadow-sm hover:shadow-md transition-all duration-500">
            <div className="absolute top-0 right-0 p-6 opacity-5 group-hover:opacity-10 transition-opacity transform group-hover:scale-110 duration-700">
              <Wand2 className="w-40 h-40" strokeWidth={0.5} />
            </div>

            <div className="relative z-10">
              <div className="w-9 h-9 rounded-full bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center mb-4">
                <Zap className="w-4 h-4 text-zinc-900 dark:text-white" />
              </div>
              <h3 className="text-lg font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-wide">Local AI Workflows</h3>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-sm">
                Don&apos;t just record. Process. Configure pipelines to automatically summarize meetings, extract action items, or reformat ramblings into clear prose.
              </p>
            </div>

            <div className="mt-8 space-y-2">
               <div className="flex items-center gap-3 text-xs font-mono text-zinc-500">
                  <div className="w-1.5 h-1.5 bg-zinc-400 rounded-full"></div>
                  <span>Input: Audio Recording (RAW)</span>
               </div>
               <div className="w-px h-3 bg-zinc-300 dark:bg-zinc-700 ml-[2.5px]"></div>
               <div className="flex items-center gap-3 text-xs font-mono text-zinc-500">
                  <div className="w-1.5 h-1.5 bg-zinc-400 rounded-full"></div>
                  <span>Process: Whisper (Quantized)</span>
               </div>
               <div className="w-px h-3 bg-zinc-300 dark:bg-zinc-700 ml-[2.5px]"></div>
               <div className="flex items-center gap-3 text-xs font-mono text-blue-500">
                  <div className="w-1.5 h-1.5 bg-blue-500 rounded-full"></div>
                  <span>LLM: Summarize &amp; Extract Tasks</span>
               </div>
               <div className="w-px h-3 bg-zinc-300 dark:bg-zinc-700 ml-[2.5px]"></div>
               <div className="flex items-center gap-3 text-xs font-mono text-zinc-900 dark:text-white font-bold">
                  <div className="w-1.5 h-1.5 bg-emerald-500 rounded-full shadow-[0_0_8px_rgba(34,197,94,0.6)]"></div>
                  <span>Output: Draft Email / Notion Page</span>
               </div>
            </div>
          </div>

          {/* 2. On-Device Only (Tall) */}
          <div className="col-span-1 md:col-span-1 row-span-2 bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 p-5 flex flex-col group rounded-sm shadow-sm hover:shadow-md transition-all duration-300">
            <div className="w-9 h-9 rounded-full bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center mb-4">
               <Lock className="w-4 h-4 text-zinc-900 dark:text-white" />
            </div>
            <h3 className="text-base font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-wide">On‑Device Only</h3>
            <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed mb-6">
              Your voice is your biometric identity. It should never touch a server. The only cloud we use is the one you already trust: iCloud.
            </p>
            <div className="mt-auto border-t border-zinc-200 dark:border-zinc-800 pt-3">
               <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500 mb-2">
                 <span>Tracker Count</span>
                 <span className="text-zinc-300 dark:text-zinc-700">0</span>
               </div>
               <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500 mb-2">
                 <span>Cloud Processing</span>
                 <span className="text-emerald-600 dark:text-emerald-400">Permission Based</span>
               </div>
               <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500 mb-2">
                 <span>Offline Mode</span>
                 <span className="text-emerald-600 dark:text-emerald-400">Active</span>
               </div>
               <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500">
                 <span>Storage</span>
                 <span className="text-blue-500">Apple iCloud</span>
               </div>
            </div>
          </div>

          {/* 3. iCloud Sync */}
          <div className="col-span-1 bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 p-5 flex flex-col justify-between group rounded-sm shadow-sm hover:shadow-md transition-all duration-300">
             <div>
               <div className="flex items-center justify-between mb-3">
                  <Cloud className="w-4 h-4 text-zinc-900 dark:text-white" />
                  <div className="w-2 h-2 rounded-full bg-blue-500"></div>
               </div>
               <h3 className="text-sm font-bold text-zinc-900 dark:text-white mb-1 uppercase tracking-wide">iCloud Sync</h3>
               <p className="text-xs text-zinc-600 dark:text-zinc-400">
                 Start recording on iPhone. Tag it. It appears instantly on your Mac for deep work.
               </p>
             </div>
          </div>

          {/* 4. Pro Audio */}
          <div className="col-span-1 bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 p-5 flex flex-col justify-between group rounded-sm shadow-sm hover:shadow-md transition-all duration-300">
             <div>
               <div className="flex items-center justify-between mb-3">
                  <Mic className="w-4 h-4 text-zinc-900 dark:text-white" />
                  <span className="text-[10px] font-mono text-zinc-400">WHISPER‑V3</span>
               </div>
               <h3 className="text-sm font-bold text-zinc-900 dark:text-white mb-1 uppercase tracking-wide">Pro Audio</h3>
               <p className="text-xs text-zinc-600 dark:text-zinc-400">
                 32‑bit float audio pipeline. Stereo recording. Automatic noise reduction.
               </p>
             </div>
          </div>

        </div>
      </div>
    </section>
  )
}
