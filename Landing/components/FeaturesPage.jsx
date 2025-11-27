"use client"
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  Mic,
  Workflow,
  Terminal,
  FolderTree,
  FileOutput,
  Cpu,
  ShieldCheck,
  Monitor,
  Smartphone,
  Zap,
  Calendar,
  Mail,
  Bell,
  Copy,
  Globe,
  Lock,
  Server,
  FileJson,
  CheckCircle2,
  AlertTriangle,
  ArrowRight,
  Cloud,
  Brain,
  Database,
  Layers,
  Filter,
  Network,
} from 'lucide-react'
import Container from './Container'
import ThemeToggle from './ThemeToggle'

const SectionHeader = ({ label, icon: Icon }) => (
  <div className="flex items-center gap-3 mb-8 pt-8 border-t border-zinc-200 dark:border-zinc-800">
    {Icon && <Icon className="w-4 h-4 text-emerald-500" />}
    <h2 className="text-sm font-mono font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-400">
      {label}
    </h2>
  </div>
)

const FeatureCard = ({ title, description, children }) => (
  <div className="group border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900/50 p-6 hover:border-zinc-400 dark:hover:border-zinc-600 transition-colors">
    <h3 className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">{title}</h3>
    <p className="text-sm text-zinc-600 dark:text-zinc-400 leading-relaxed mb-4">{description}</p>
    {children}
  </div>
)

const WorkflowStepRow = ({ icon: Icon, label, desc }) => (
  <div className="flex items-start gap-4 p-3 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0">
    <div className="mt-0.5 p-1.5 bg-zinc-100 dark:bg-zinc-800 rounded text-zinc-900 dark:text-white">
      <Icon className="w-3.5 h-3.5" />
    </div>
    <div>
      <span className="text-xs font-bold uppercase tracking-wider text-zinc-900 dark:text-white block">{label}</span>
      <span className="text-xs text-zinc-500 dark:text-zinc-400">{desc}</span>
    </div>
  </div>
)

const ServiceBadge = ({ label, icon: Icon, imgSrc, color = "text-zinc-400" }) => (
  <div className="flex items-center gap-2.5 bg-zinc-950 border border-zinc-800 px-3 py-2.5 rounded shadow-sm hover:border-zinc-700 hover:bg-zinc-900 transition-all cursor-default group">
    {imgSrc ? (
       <img src={imgSrc} alt={label} className="w-3.5 h-3.5 object-contain opacity-70 group-hover:opacity-100 transition-all grayscale group-hover:grayscale-0" />
    ) : (
       Icon && <Icon className={`w-3.5 h-3.5 ${color}`} />
    )}
    <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-400 group-hover:text-zinc-300 transition-colors">{label}</span>
  </div>
)

const SecurityInfographic = () => {
  return (
    <div className="bg-zinc-950 border border-zinc-800 p-6 md:p-12 relative overflow-visible rounded-sm select-none">
      <div className="absolute inset-0 bg-tactical-grid-dark opacity-20 pointer-events-none" />

      <div className="relative z-10">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-12">
            <div className="flex items-center gap-3">
            <ShieldCheck className="w-6 h-6 text-emerald-500" />
            <div className="flex flex-col">
                <h2 className="text-xl font-bold text-white uppercase tracking-wide leading-none">Security Architecture</h2>
                <span className="text-[10px] font-mono text-zinc-500 uppercase mt-1">Data Sovereignty Model v1.2</span>
            </div>
            </div>
             <div className="flex items-center gap-4 text-[10px] font-mono uppercase text-zinc-500">
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.5)]"></div>
                    <span>Trusted</span>
                </div>
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-indigo-500"></div>
                    <span>Runtime</span>
                </div>
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-amber-500"></div>
                    <span>External</span>
                </div>
            </div>
        </div>

        {/* 3-Part Grid Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-12 border border-zinc-800 rounded-sm overflow-visible bg-zinc-950/50">

          {/* LEFT: TRUSTED ZONE (5 cols) - Green Hover */}
          <div className="lg:col-span-5 relative bg-zinc-900/30 p-8 flex flex-col justify-between border-b lg:border-b-0 lg:border-r border-zinc-800 group/trusted hover:bg-emerald-900/10 transition-colors duration-500">
             {/* Header */}
             <div className="flex items-center justify-between mb-8 lg:mb-0">
                <div className="flex items-center gap-2">
                    <Lock className="w-3 h-3 text-emerald-500" />
                    <span className="text-xs font-mono font-bold uppercase text-emerald-500 tracking-widest group-hover/trusted:text-emerald-400 transition-colors">Extended Trusted Zone</span>
                </div>
             </div>

             {/* Content: Vertical Stack with Custom Spacing */}
             <div className="flex flex-col gap-6 relative mt-4">
                {/* Connecting Line (Vertical) */}
                <div className="absolute left-6 top-6 bottom-6 w-px bg-zinc-800 z-0 border-l border-dashed border-zinc-700/50 group-hover/trusted:border-emerald-500/30 transition-colors"></div>

                {/* iPhone Card */}
                <div className="w-full flex items-start gap-4 bg-zinc-950 p-4 border border-zinc-800 rounded-sm z-10 relative group hover:border-emerald-500/50 transition-colors">
                   <div className="p-2 bg-zinc-900 rounded-sm text-white border border-zinc-800 group-hover:border-emerald-500/50 transition-colors">
                      <Smartphone className="w-4 h-4 group-hover:text-emerald-400 transition-colors" />
                   </div>
                   <div className="flex-1">
                      <h4 className="text-xs font-bold text-white uppercase tracking-wider mb-2">iPhone</h4>
                      <ul className="space-y-1.5">
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-400">
                            <span className="w-1 h-1 bg-zinc-600 rounded-full group-hover:bg-emerald-500 transition-colors"></span> Voice Input
                         </li>
                      </ul>
                   </div>
                </div>

                {/* iCloud Card */}
                <div className="w-full flex items-start gap-4 bg-zinc-950 p-4 border border-zinc-800 rounded-sm z-10 relative group hover:border-emerald-500/50 transition-colors">
                   <div className="p-2 bg-zinc-900 rounded-sm text-zinc-400 border border-zinc-800 group-hover:border-emerald-500/50 transition-colors">
                      <Cloud className="w-4 h-4 group-hover:text-emerald-400 transition-colors" />
                   </div>
                   <div className="flex-1">
                      <h4 className="text-xs font-bold text-zinc-300 uppercase tracking-wider mb-2">iCloud</h4>
                      <ul className="space-y-1.5">
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-500">
                            <span className="w-1 h-1 bg-zinc-700 rounded-full group-hover:bg-emerald-500 transition-colors"></span> Encrypted Sync
                         </li>
                      </ul>
                   </div>
                </div>

                {/* Mac Card - Bottom Aligned */}
                <div className="w-full flex items-start gap-4 bg-zinc-950 p-4 border border-zinc-800 rounded-sm z-10 relative group hover:border-emerald-500/50 transition-colors">
                   <div className="p-2 bg-zinc-900 rounded-sm text-white border border-zinc-800 group-hover:border-emerald-500/50 transition-colors">
                      <Monitor className="w-4 h-4 group-hover:text-emerald-400 transition-colors" />
                   </div>
                   <div className="flex-1">
                      <h4 className="text-xs font-bold text-white uppercase tracking-wider mb-2">Mac</h4>
                      <ul className="space-y-1.5">
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-400">
                            <span className="w-1 h-1 bg-zinc-600 rounded-full group-hover:bg-emerald-500 transition-colors"></span> File System
                         </li>
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-400">
                            <span className="w-1 h-1 bg-zinc-600 rounded-full group-hover:bg-emerald-500 transition-colors"></span> Neural Engine
                         </li>
                      </ul>
                   </div>

                   {/* Connector to Talkie (Horizontal Pipe) */}
                   <div className="absolute -right-8 top-1/2 -translate-y-1/2 z-30 hidden lg:block w-8 h-10 overflow-visible pointer-events-none">
                      <div className="absolute top-1/2 left-0 w-full h-[2px] bg-zinc-800 group-hover:bg-emerald-500/50 transition-colors"></div>
                   </div>
                </div>

             </div>

             {/* Background tint */}
             <div className="absolute inset-0 bg-emerald-500/0 group-hover/trusted:bg-emerald-500/5 pointer-events-none transition-colors duration-500" />
          </div>

          {/* MIDDLE: TALKIE ENGINE (3 cols) - Indigo Hover */}
          <div className="lg:col-span-3 relative bg-zinc-900/10 flex flex-col justify-end border-b lg:border-b-0 lg:border-r border-zinc-800 group/engine hover:bg-indigo-500/5 transition-colors duration-500">
             <div className="absolute inset-0 bg-tactical-grid-dark opacity-10 pointer-events-none" />

             {/* Header */}
             <div className="absolute top-0 left-0 right-0 p-8 text-center border-b border-zinc-800/50 group-hover/engine:border-indigo-500/20 transition-colors">
                <div className="flex items-center justify-center gap-2 mb-2">
                    <Network className="w-3 h-3 text-zinc-500 group-hover/engine:text-indigo-400 transition-colors" />
                    <span className="text-xs font-mono font-bold uppercase text-zinc-500 tracking-widest group-hover/engine:text-indigo-400 transition-colors">Talkie Engine</span>
                </div>
                <span className="text-[9px] font-mono text-zinc-600 uppercase">Local Runtime</span>
             </div>

             {/* Workflow Conduit - Bottom Aligned with Mac */}
             <div className="flex flex-col items-center justify-end p-4 pb-8 relative z-20">

                {/* Connector Entry Point Overlay (Left) */}
                <div className="absolute left-0 top-1/2 w-4 h-[2px] bg-zinc-800 group-hover/engine:bg-indigo-500/50 transition-colors -translate-y-1/2 hidden lg:block"></div>

                {/* Conduit Card */}
                <div className="relative w-full p-5 flex flex-col items-center justify-center bg-zinc-950 border border-zinc-700 rounded-sm shadow-xl group-hover/engine:border-indigo-500/50 transition-all duration-300">
                   {/* Animated Pulse BG */}
                   <div className="absolute inset-0 bg-zinc-800/20 group-hover/engine:bg-indigo-900/20 transition-colors"></div>

                   <div className="mb-3 p-2 bg-black border border-zinc-800 rounded group-hover/engine:border-indigo-500/50 transition-colors">
                       <Workflow className="w-5 h-5 text-indigo-500" />
                   </div>
                   <span className="text-[10px] font-bold text-white uppercase tracking-wider text-center mb-4">Workflow Conduit</span>

                   {/* Mini Steps */}
                   <div className="w-full space-y-1.5">
                      <div className="flex items-center gap-2 text-[9px] font-mono text-zinc-400 bg-zinc-900/80 px-2 py-1.5 rounded border border-zinc-800/50">
                        <span className="w-1 h-1 bg-zinc-600 rounded-full"></span> 1. Assemble
                      </div>
                      <div className="flex items-center gap-2 text-[9px] font-mono text-zinc-400 bg-zinc-900/80 px-2 py-1.5 rounded border border-zinc-800/50">
                        <span className="w-1 h-1 bg-indigo-500 rounded-full"></span> 2. Sanitize
                      </div>
                      <div className="flex items-center gap-2 text-[9px] font-mono text-zinc-400 bg-zinc-900/80 px-2 py-1.5 rounded border border-zinc-800/50">
                         <span className="w-1 h-1 bg-zinc-600 rounded-full"></span> 3. Dispatch
                      </div>
                   </div>
                </div>

                {/* Exit Arrow - Layered Above Border */}
                <div className="absolute -right-3 top-1/2 -translate-y-1/2 z-30 hidden lg:block">
                   <div className="w-6 h-6 bg-zinc-900 border border-amber-500/50 rounded-full flex items-center justify-center shadow-[0_0_10px_rgba(245,158,11,0.2)] hover:scale-110 transition-transform">
                      <ArrowRight className="w-3 h-3 text-amber-500" />
                   </div>
                </div>
             </div>
          </div>

          {/* RIGHT: EXTERNAL WORLD (4 cols) - Amber Hover */}
          <div className="lg:col-span-4 relative bg-zinc-950 p-8 flex flex-col z-10 group/external hover:bg-amber-900/10 transition-colors duration-500">

             {/* Header */}
             <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-2">
                    <Globe className="w-3 h-3 text-amber-500" />
                    <span className="text-xs font-mono font-bold uppercase text-amber-500 tracking-widest group-hover/external:text-amber-400 transition-colors">External World</span>
                </div>
             </div>

             {/* Content */}
             <div className="flex-1 flex flex-col justify-center items-center gap-8">
                 <div className="grid grid-cols-2 gap-3 w-full max-w-[280px]">
                    <ServiceBadge label="OpenAI" imgSrc="https://cdn.simpleicons.org/openai/white" />
                    <ServiceBadge label="Anthropic" imgSrc="https://cdn.simpleicons.org/anthropic/white" />
                    <ServiceBadge label="Google" imgSrc="https://cdn.simpleicons.org/google" />
                    <ServiceBadge label="Notion" imgSrc="https://cdn.simpleicons.org/notion/white" />
                    <ServiceBadge label="Zapier" imgSrc="https://cdn.simpleicons.org/zapier/FF4F00" />
                    <ServiceBadge label="Linear" imgSrc="https://cdn.simpleicons.org/linear/5E6AD2" />
                 </div>

                 <div className="w-full max-w-[200px] border-t border-dashed border-zinc-800 mt-2 group-hover/external:border-amber-500/30 transition-colors"></div>

                 <div className="group relative">
                    <p className="text-[10px] text-zinc-500 text-center max-w-[250px] leading-relaxed cursor-help border-b border-dotted border-zinc-700/50 inline-block pb-0.5 hover:text-zinc-400 transition-colors">
                      Outbound: <span className="text-zinc-400 font-bold group-hover/external:text-amber-500 transition-colors">Text-Only Stream</span>
                    </p>

                    {/* Tooltip */}
                    <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-3 w-48 p-3 bg-zinc-900 border border-zinc-700 rounded shadow-xl opacity-0 group-hover:opacity-100 transition-all duration-200 pointer-events-none z-50">
                       <p className="text-[9px] text-zinc-300 text-center leading-relaxed">
                         Strict Sanitization: Audio remains local. Only text prompts are transmitted.
                       </p>
                       <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 w-2 h-2 bg-zinc-900 border-b border-r border-zinc-700 rotate-45"></div>
                    </div>
                 </div>
             </div>
          </div>

        </div>
      </div>
    </div>
  )
}

export default function FeaturesPage() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 font-sans selection:bg-zinc-900 selection:text-white dark:selection:bg-white dark:selection:text-black">

      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <div className="mx-auto max-w-5xl px-6 h-14 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            BACK
          </Link>

          <div className="flex items-center gap-3">
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">FEATURES &amp; SPECS</span>
          </div>
        </div>
      </nav>

      <main className="pt-32 pb-32 px-6">
        <div className="mx-auto max-w-5xl">

          {/* Hero */}
          <div className="max-w-3xl mb-24">
            <h1 className="text-4xl md:text-6xl font-bold tracking-tighter text-zinc-900 dark:text-white uppercase mb-6 leading-[0.9]">
              Voice memos, <br/>
              <span className="text-emerald-500">supercharged</span> with <br/>
              AI workflows.
            </h1>
            <p className="text-lg text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-2xl border-l-2 border-emerald-500 pl-6">
              Talkie turns your spoken thoughts into structured, automated output — all on your devices, powered by iCloud, and designed for builders who want speed, sovereignty, and flow.
            </p>
          </div>

          {/* 1. Voice Recording */}
          <section className="mb-20">
            <SectionHeader label="Voice Recording & Transcription" icon={Mic} />
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <FeatureCard title="One-Tap Capture" description="Instant recording startup time. No lag. No loading screens." />
              <FeatureCard title="Auto-Transcribe" description="Local, high-accuracy transcription running on-device via Apple's Neural Engine." />
              <FeatureCard title="iCloud Sync" description="Seamless, encrypted synchronization across iPhone, iPad, and Mac." />
              <FeatureCard title="Smart Library" description="Organize with Recent, Processed, Archived, and custom Smart Folders." />
            </div>
          </section>

          {/* 2. AI Workflows */}
          <section className="mb-20">
            <SectionHeader label="AI-Powered Workflows" icon={Workflow} />
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
              <div className="lg:col-span-2">
                <h3 className="text-2xl font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-6">Modular Pipelines</h3>
                <p className="text-zinc-600 dark:text-zinc-400 mb-8 max-w-xl">
                  Build modular pipelines that process your voice memos through multiple steps. Use our drag-and-drop editor to chain LLMs, scripts, and file operations.
                </p>
                <div className="grid grid-cols-2 gap-4">
                  <div className="bg-zinc-100 dark:bg-zinc-900 p-4 border border-zinc-200 dark:border-zinc-800">
                    <span className="text-xs font-mono text-zinc-500 block mb-1">SUPPORTED MODELS</span>
                    <p className="text-sm font-bold text-zinc-900 dark:text-white">Gemini, OpenAI, Anthropic, Groq, Local MLX</p>
                  </div>
                  <div className="bg-zinc-100 dark:bg-zinc-900 p-4 border border-zinc-200 dark:border-zinc-800">
                    <span className="text-xs font-mono text-zinc-500 block mb-1">VARIABLES</span>
                    <p className="text-sm font-bold text-zinc-900 dark:text-white">{'{{TRANSCRIPT}}, {{TITLE}}, {{DATE}}'}</p>
                  </div>
                </div>
              </div>

              {/* Workflow Step Types Table */}
              <div className="bg-white dark:bg-black border border-zinc-200 dark:border-zinc-800">
                <div className="p-3 bg-zinc-50 dark:bg-zinc-900 border-b border-zinc-200 dark:border-zinc-800">
                  <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500">Available Step Types</span>
                </div>
                <div>
                  <WorkflowStepRow icon={Cpu} label="LLM" desc="Summaries, extraction, restructuring" />
                  <WorkflowStepRow icon={Terminal} label="Shell Command" desc="Run CLI tools (claude, gh, jq)" />
                  <WorkflowStepRow icon={FileOutput} label="Save to File" desc="Write results to disk with aliases" />
                  <WorkflowStepRow icon={Globe} label="Webhook" desc="Send JSON/Text to any endpoint" />
                  <WorkflowStepRow icon={Mail} label="Email" desc="Send results via Mail.app" />
                  <WorkflowStepRow icon={Calendar} label="Calendar" desc="Create events from transcript" />
                  <WorkflowStepRow icon={Copy} label="Clipboard" desc="Copy results to system clipboard" />
                  <WorkflowStepRow icon={Bell} label="Notification" desc="Native macOS alerts" />
                </div>
              </div>
            </div>
          </section>

          {/* 3. Shell Integration */}
          <section className="mb-20">
            <SectionHeader label="Shell Command Integration" icon={Terminal} />
            <div className="bg-zinc-900 text-zinc-100 p-8 rounded-sm font-mono text-sm border border-zinc-800 relative overflow-hidden">
               <div className="absolute top-0 right-0 p-4 opacity-20">
                 <Terminal className="w-24 h-24" />
               </div>
               <div className="relative z-10 grid grid-cols-1 md:grid-cols-2 gap-12">
                 <div>
                   <h3 className="text-emerald-400 font-bold uppercase tracking-wider mb-4">Run Unix Tools Directly</h3>
                   <ul className="space-y-3 text-zinc-400">
                     <li className="flex items-center gap-2"><span className="text-emerald-500">➜</span> Executable allowlist for safety</li>
                     <li className="flex items-center gap-2"><span className="text-emerald-500">➜</span> Claude CLI integration (MCP)</li>
                     <li className="flex items-center gap-2"><span className="text-emerald-500">➜</span> Multi-line templates</li>
                     <li className="flex items-center gap-2"><span className="text-emerald-500">➜</span> Respectful PATH merging (brew, node, bun)</li>
                   </ul>
                 </div>
                 <div className="flex flex-col justify-center">
                    <div className="bg-black/50 p-4 rounded border border-zinc-700">
                      <p className="text-zinc-500 mb-2"># Example: Create GitHub Issue</p>
                      <p className="text-white">
                        <span className="text-purple-400">gh</span> issue create <br/>
                        <span className="pl-4">--title</span> <span className="text-green-400">{'"{{TITLE}}"'}</span> <br/>
                        <span className="pl-4">--body</span> <span className="text-green-400">{'"{{TRANSCRIPT}}"'}</span> <br/>
                        <span className="pl-4">--label</span> <span className="text-green-400">&quot;voice-memo&quot;</span>
                      </p>
                    </div>
                 </div>
               </div>
            </div>
          </section>

          {/* 4. Aliases & Output */}
          <section className="mb-20">
             <div className="grid grid-cols-1 md:grid-cols-2 gap-12">
               <div>
                  <SectionHeader label="Path Aliases" icon={FolderTree} />
                  <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-6">Shortcuts for your most important directories.</p>
                  <ul className="space-y-2 font-mono text-xs">
                    <li className="flex items-center gap-2 bg-zinc-100 dark:bg-zinc-900 p-2 border border-zinc-200 dark:border-zinc-800">
                      <span className="text-emerald-600 dark:text-emerald-500 font-bold">@Notes</span>
                      <span className="text-zinc-400">→</span>
                      <span className="text-zinc-500">~/Documents/Obsidian/Vault</span>
                    </li>
                    <li className="flex items-center gap-2 bg-zinc-100 dark:bg-zinc-900 p-2 border border-zinc-200 dark:border-zinc-800">
                      <span className="text-emerald-600 dark:text-emerald-500 font-bold">@Projects</span>
                      <span className="text-zinc-400">→</span>
                      <span className="text-zinc-500">~/Dev/Current</span>
                    </li>
                  </ul>
               </div>
               <div>
                  <SectionHeader label="Smart File Output" icon={FileOutput} />
                  <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-6">Save workflow results exactly where you want.</p>
                  <ul className="space-y-2 text-xs text-zinc-600 dark:text-zinc-400">
                     <li className="flex items-center gap-2">
                       <Zap className="w-3 h-3 text-zinc-400" /> Template filenames with date/time
                     </li>
                     <li className="flex items-center gap-2">
                       <Zap className="w-3 h-3 text-zinc-400" /> Auto-directory creation
                     </li>
                     <li className="flex items-center gap-2">
                       <Zap className="w-3 h-3 text-zinc-400" /> Append mode for logs &amp; journals
                     </li>
                  </ul>
               </div>
             </div>
          </section>

          {/* 5. Example Workflows */}
          <section className="mb-24">
             <SectionHeader label="Example Workflows" icon={Workflow} />
             <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <FeatureCard title="Voice → Obsidian" description="Extract insights → enrich with Claude CLI → save to Markdown in your vault." />
                <FeatureCard title="Meeting Notes → Tasks" description="Extract todos → structure JSON → send to Todoist or Linear via API." />
                <FeatureCard title="Daily Journal Builder" description="Summarize daily thoughts → append to daily journal file with timestamp." />
                <FeatureCard title="Quick GitHub Issue" description="Dictate bug report → transform to format → gh issue create." />
             </div>
          </section>

          {/* 6. Security Infographic */}
          <section className="mb-24">
            <SecurityInfographic />
          </section>

          {/* Footer Lists */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-12 border-t border-zinc-200 dark:border-zinc-800 pt-12">

             {/* Platform */}
             <div>
               <h4 className="flex items-center gap-2 text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-4">
                 <Monitor className="w-4 h-4" /> Platform Support
               </h4>
               <ul className="space-y-2 text-xs text-zinc-600 dark:text-zinc-400">
                 <li className="flex items-center gap-2"><span className="w-1.5 h-1.5 bg-green-500 rounded-full"></span> macOS (Primary App)</li>
                 <li className="flex items-center gap-2"><span className="w-1.5 h-1.5 bg-green-500 rounded-full"></span> iOS (Companion App)</li>
                 <li className="flex items-center gap-2"><span className="w-1.5 h-1.5 bg-blue-500 rounded-full"></span> iCloud Sync</li>
               </ul>
             </div>

             {/* Config */}
             <div>
               <h4 className="flex items-center gap-2 text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-4">
                 <Cpu className="w-4 h-4" /> Configuration
               </h4>
               <ul className="space-y-2 text-xs text-zinc-600 dark:text-zinc-400">
                 <li>Workflow Manager</li>
                 <li>Activity Log</li>
                 <li>Model Library</li>
                 <li>API Key Management</li>
               </ul>
             </div>

          </div>

        </div>
      </main>

      <ThemeToggle />
    </div>
  )
}
