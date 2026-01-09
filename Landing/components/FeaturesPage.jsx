"use client"
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  Code,
  Layers,
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
  LayoutGrid,
  RefreshCw,
  MessageCircle,
  Smartphone,
  Watch,
  Search,
  Play,
  Hash,
  Bot,
} from 'lucide-react'
import Container from './Container'
import ThemeToggle from './ThemeToggle'
import SubNav from './SubNav'
import { SecurityInfographic } from './SecurityInfographic'
import ScreenshotsSection from './ScreenshotsSection'

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

const ArchitectNode = ({ label, icon: Icon, active, activeClass, iconActiveClass, pingClass = 'bg-emerald-500' }) => (
  <div className={`flex flex-col items-center gap-3 transition-all duration-500 ${active ? 'scale-110' : 'opacity-40 grayscale'}`}>
    <div className={`w-14 h-14 rounded-2xl bg-zinc-950 border border-zinc-800 flex items-center justify-center relative shadow-2xl transition-all ${active ? activeClass : ''}`}>
      <Icon className={`w-6 h-6 ${active ? iconActiveClass : 'text-zinc-600'}`} />
      {active && <div className={`absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full animate-ping ${pingClass}`} />}
    </div>
    <span className="text-[9px] font-mono font-bold uppercase tracking-[0.15em] text-zinc-500">{label}</span>
  </div>
)

export default function FeaturesPage() {
  const [scrolled, setScrolled] = useState(false)
  const [activeStep, setActiveStep] = useState(0)

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  useEffect(() => {
    const timer = setInterval(() => {
      setActiveStep((prev) => (prev + 1) % 3)
    }, 3500)
    return () => clearInterval(timer)
  }, [])

  const statusLabels = [
    'Talkie capture streaming...',
    'Claude Code responding...',
    'Feedback loop synced...',
  ]

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 font-sans selection:bg-zinc-900 selection:text-white dark:selection:bg-white dark:selection:text-black">

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

          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-purple-500 rounded-full animate-pulse"></div>
            <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-900 dark:text-white">Talkie for Agents</span>
          </div>
        </Container>
      </nav>

      {/* Hero */}
      <section className="relative pt-20 pb-16 md:pt-22 md:pb-20 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-grid-fade pointer-events-none opacity-40" />
        <Container className="relative z-10">
          {/* Sub Navigation */}
          <div className="flex justify-center mb-6">
            <SubNav />
          </div>

          <div className="max-w-3xl mx-auto text-center">
            <h1 className="text-5xl md:text-7xl tracking-tighter text-zinc-900 dark:text-white leading-[0.95] mb-6">
              <span className="font-display italic">Voice</span> <span className="text-zinc-400 dark:text-zinc-500">to</span>{' '}
              <span className="font-bold bg-gradient-to-r from-purple-500 to-violet-400 bg-clip-text text-transparent">Agents.</span>
            </h1>

            <p className="text-xl md:text-2xl text-zinc-700 dark:text-zinc-300 leading-snug mb-4 font-display">
              Speak once, run everywhere.
            </p>
            <p className="text-base text-zinc-500 dark:text-zinc-400 leading-relaxed max-w-xl mx-auto mb-10">
              Voice-driven workflows turn your words into documents, tasks, and actions across your Mac — local-first and private.
            </p>

            <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
              <a href="/#pricing" className="h-12 px-8 rounded-lg bg-purple-500 hover:bg-purple-600 text-white font-bold text-sm uppercase tracking-wider hover:scale-105 transition-all flex items-center gap-3 shadow-xl shadow-purple-500/25">
                <Bot className="w-4 h-4" />
                <span>Get Early Access</span>
              </a>
              <div className="flex flex-col gap-1 text-left">
                <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-500 uppercase">
                  <Monitor className="w-3 h-3" />
                  macOS 13+ • Workflow Editor
                </div>
                <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-400 uppercase">
                  <Terminal className="w-3 h-3 text-purple-500" />
                  Claude CLI • Shell Commands
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Agent Orchestrator */}
      <section className="py-16 md:py-20 bg-white dark:bg-black border-t border-zinc-200 dark:border-zinc-800">
        <Container>
            <div className="bg-zinc-950 border border-zinc-800 rounded-2xl p-6 md:p-10 text-white shadow-2xl">
              <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 mb-8">
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-purple-500/10 border border-purple-500/20 rounded-lg">
                    <Layers className="w-4 h-4 text-purple-400" />
                  </div>
                  <div className="flex flex-col">
                    <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400">Talkie Capture → Claude Code → Feedback</span>
                    <span className="text-[11px] text-zinc-500">Auto-paced loop that accelerates collaboration with Claude.</span>
                  </div>
                </div>
                <div className="flex items-center gap-2 px-3 py-1 bg-emerald-500/10 border border-emerald-500/20 rounded-full">
                  <Zap className="w-3 h-3 text-emerald-400" />
                  <span className="text-[9px] font-mono text-emerald-400 uppercase font-bold tracking-widest">Speed: 120ms</span>
                </div>
              </div>

              <div className="bg-zinc-950/80 border border-zinc-800 rounded-xl p-6 md:p-8">
                <div className="flex flex-col md:flex-row items-center gap-6 md:gap-8">
                    <ArchitectNode
                      label="Talkie Capture"
                    icon={Mic}
                    active={activeStep === 0}
                    activeClass="border-emerald-500 bg-zinc-900 shadow-[0_0_25px_rgba(16,185,129,0.35)]"
                    iconActiveClass="text-emerald-400"
                  />

                  <div className="hidden md:block flex-1 h-px border-t border-dashed border-zinc-700" />
                  <div className="md:hidden h-6 w-px border-l border-dashed border-zinc-700" />

                  <ArchitectNode
                    label="Claude Code"
                    icon={Code}
                    active={activeStep === 1}
                    activeClass="border-purple-500 bg-zinc-900 shadow-[0_0_25px_rgba(168,85,247,0.35)]"
                    iconActiveClass="text-purple-400"
                    pingClass="bg-purple-500"
                  />

                  <div className="hidden md:block flex-1 h-px border-t border-dashed border-zinc-700" />
                  <div className="md:hidden h-6 w-px border-l border-dashed border-zinc-700" />

                  <ArchitectNode
                    label="Feedback Loop"
                    icon={RefreshCw}
                    active={activeStep === 2}
                    activeClass="border-emerald-500 bg-zinc-900 shadow-[0_0_25px_rgba(16,185,129,0.35)]"
                    iconActiveClass="text-emerald-400"
                  />
                </div>

                <div className="mt-6 flex flex-col md:flex-row md:items-center md:justify-between gap-3 text-[10px] font-mono">
                  <span className="text-zinc-400 uppercase tracking-widest">{statusLabels[activeStep]}</span>
                  <div className="flex items-center gap-2 text-zinc-600">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                    <span className="text-zinc-500">Auto-paced loop, accelerating collaboration with Claude</span>
                  </div>
                </div>
              </div>
            </div>
        </Container>
      </section>

      {/* Main Content */}
      <main className="py-16 md:py-20 bg-zinc-50 dark:bg-zinc-950">
        <Container>
          {/* 1. Example Workflows - Lead with what you can DO */}
          <section className="mb-24">
             <SectionHeader label="Example Workflows" icon={Workflow} />
             <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <FeatureCard title="Voice → Obsidian" description="Extract insights → enrich with Claude CLI → save to Markdown in your vault." />
                <FeatureCard title="Meeting Notes → Tasks" description="Extract todos → structure JSON → send to Todoist or Linear via API." />
                <FeatureCard title="Daily Journal Builder" description="Summarize daily thoughts → append to daily journal file with timestamp." />
                <FeatureCard title="Quick GitHub Issue" description="Dictate bug report → transform to format → gh issue create." />
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

          {/* 5. Voice Recording */}
          <section className="mb-20">
            <SectionHeader label="Voice Recording & Transcription" icon={Mic} />
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <FeatureCard title="One-Tap Capture" description="Instant recording startup time. No lag. No loading screens." />
                <FeatureCard title="Auto-Transcribe" description="Local, high-accuracy transcription running on-device via Apple's Neural Engine." />
                <FeatureCard title="iCloud Sync" description="Seamless, encrypted synchronization across iPhone, iPad, and Mac." />
                <FeatureCard title="Smart Library" description="Organize with Recent, Processed, Archived, and custom Smart Folders." />
              </div>
              <div className="bg-zinc-100 dark:bg-zinc-900 rounded border border-zinc-200 dark:border-zinc-800">
                <ScreenshotsSection />
              </div>
            </div>
          </section>

          {/* 6. Widgets */}
          <section className="mb-20">
            <SectionHeader label="Widgets & Quick Access" icon={LayoutGrid} />
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
              <div>
                <h3 className="text-2xl font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-6">Record From Anywhere</h3>
                <p className="text-zinc-600 dark:text-zinc-400 mb-8 max-w-xl">
                  Add Talkie widgets to your Home Screen, Lock Screen, or Control Center for instant voice capture — no need to open the app.
                </p>
                <div className="grid grid-cols-2 gap-4">
                  <FeatureCard title="Home Screen Widget" description="Small or medium widget with quick record button and memo count." />
                  <FeatureCard title="Lock Screen Widget" description="Circular widget for instant capture without unlocking." />
                  <FeatureCard title="Control Center" description="iOS 18+ toggle for one-tap recording from anywhere." />
                  <FeatureCard title="Deep Links" description="Widget taps open directly to recording view." />
                </div>
              </div>

              {/* Widget Preview */}
              <div className="flex items-center justify-center">
                <div className="relative">
                  {/* Phone frame mockup */}
                  <div className="w-64 h-[420px] bg-zinc-900 rounded-[2.5rem] p-3 shadow-2xl">
                    <div className="w-full h-full bg-zinc-800 rounded-[2rem] p-4 flex flex-col">
                      {/* Status bar */}
                      <div className="flex justify-between text-[10px] text-zinc-400 mb-4">
                        <span>9:41</span>
                        <div className="flex gap-1">
                          <span>5G</span>
                          <span>100%</span>
                        </div>
                      </div>

                      {/* Widget preview */}
                      <div className="bg-black rounded-2xl p-4 mb-4">
                        <div className="flex flex-col items-center">
                          <div className="w-14 h-14 bg-gradient-to-br from-red-500 to-red-600 rounded-full flex items-center justify-center mb-2 shadow-lg shadow-red-500/30">
                            <Mic className="w-6 h-6 text-white" />
                          </div>
                          <span className="text-[10px] font-mono font-bold tracking-widest text-zinc-400 uppercase">Record</span>
                          <span className="text-[9px] text-zinc-600 mt-1">12 memos</span>
                        </div>
                      </div>

                      {/* App icons placeholder */}
                      <div className="grid grid-cols-4 gap-3 mt-auto">
                        {[...Array(8)].map((_, i) => (
                          <div key={i} className="w-10 h-10 bg-zinc-700 rounded-xl" />
                        ))}
                      </div>
                    </div>
                  </div>

                  {/* Floating badge */}
                  <div className="absolute -right-4 top-20 bg-emerald-500 text-white text-[10px] font-bold uppercase tracking-wider px-3 py-1.5 rounded-full shadow-lg">
                    iOS 16+
                  </div>
                </div>
              </div>
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
        </Container>
      </main>

      <ThemeToggle />
    </div>
  )
}
