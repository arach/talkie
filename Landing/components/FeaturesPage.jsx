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
  Monitor,
  Zap,
  Calendar,
  Mail,
  Bell,
  Copy,
  Globe,
} from 'lucide-react'
import Container from './Container'
import ThemeToggle from './ThemeToggle'
import { SecurityInfographic } from './SecurityInfographic'

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
