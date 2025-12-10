"use client"
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  ArrowRight,
  Mic,
  Command,
  Clock,
  Clipboard,
  MousePointer2,
  Zap,
  Timer,
  Eye,
  Laptop,
  Download,
  Cpu,
  HardDrive,
  Sparkles,
  Lightbulb,
  Target,
  Rocket,
  CheckCircle2,
  Code2,
  Mail,
  PenLine,
  FileText,
  Palette,
  RefreshCw,
} from 'lucide-react'
import Container from './Container'
import ThemeToggle from './ThemeToggle'

const FeatureCard = ({ icon: Icon, title, description }) => (
  <div className="group border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900/50 p-6 hover:border-emerald-500/50 dark:hover:border-emerald-500/50 transition-colors">
    <div className="flex items-center gap-3 mb-3">
      <div className="p-2 bg-emerald-500/10 rounded">
        <Icon className="w-4 h-4 text-emerald-500" />
      </div>
      <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide">{title}</h3>
    </div>
    <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">{description}</p>
  </div>
)

const FlowStep = ({ number, title, description }) => (
  <div className="flex gap-4">
    <div className="flex-shrink-0 w-8 h-8 bg-emerald-500 text-white rounded-full flex items-center justify-center text-sm font-bold">
      {number}
    </div>
    <div>
      <h4 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-1">{title}</h4>
      <p className="text-xs text-zinc-500 dark:text-zinc-400">{description}</p>
    </div>
  </div>
)

const BenefitCard = ({ icon: Icon, title, description, highlight }) => (
  <div className="border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900/50 p-6 rounded-xl hover:border-emerald-500/50 transition-colors">
    <div className="flex items-start gap-4">
      <div className="p-3 bg-emerald-500/10 rounded-xl flex-shrink-0">
        <Icon className="w-5 h-5 text-emerald-500" />
      </div>
      <div>
        <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">{title}</h3>
        <p className="text-sm text-zinc-600 dark:text-zinc-400 leading-relaxed">{description}</p>
        {highlight && (
          <p className="text-xs font-mono text-emerald-600 dark:text-emerald-400 mt-3 uppercase tracking-wide">{highlight}</p>
        )}
      </div>
    </div>
  </div>
)

const StatCard = ({ value, label }) => (
  <div className="text-center">
    <div className="text-3xl md:text-4xl font-bold text-emerald-500 mb-1">{value}</div>
    <div className="text-[10px] font-mono uppercase tracking-wider text-zinc-500">{label}</div>
  </div>
)

export default function LivePage() {
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
        <div className="mx-auto max-w-5xl px-4 sm:px-6 h-14 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            BACK
          </Link>

          <div className="flex items-center gap-2 sm:gap-3">
            <div className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">TALKIE LIVE</span>
          </div>
        </div>
      </nav>

      {/* Hero Section - More Dramatic */}
      <section className="relative pt-28 pb-20 md:pt-40 md:pb-32 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-60 pointer-events-none" />

        {/* Gradient accent */}
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[600px] h-[600px] bg-emerald-500/10 rounded-full blur-3xl pointer-events-none" />

        <Container className="relative z-10">
          <div className="max-w-3xl">
            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-emerald-500/10 border border-emerald-500/20 rounded-full mb-8">
              <Sparkles className="w-3 h-3 text-emerald-500" />
              <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">Free • No Account Required • 100% Local</span>
            </div>

            <h1 className="text-4xl md:text-6xl lg:text-7xl font-bold tracking-tighter text-zinc-900 dark:text-white uppercase mb-6 leading-[0.85]">
              Fastest way to<br/>
              <span className="text-emerald-500">convert thoughts</span><br/>
              <span className="text-zinc-400 dark:text-zinc-600">to action.</span>
            </h1>

            <p className="text-lg md:text-xl text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-xl mb-10">
              Speaking is the most natural way to express complex thoughts. Talkie Live turns your voice into text instantly, so you can capture ideas at the speed you think them.
            </p>

            <div className="flex flex-col sm:flex-row items-start gap-4">
              <a href="https://github.com/arach/talkie/releases/latest/download/Talkie-Live.zip" className="h-14 px-10 rounded-lg bg-emerald-500 hover:bg-emerald-600 text-white font-bold text-sm uppercase tracking-wider hover:scale-105 transition-all flex items-center gap-3 shadow-xl shadow-emerald-500/25">
                <Download className="w-5 h-5" />
                <span>Download for Mac</span>
              </a>
              <div className="flex flex-col gap-1">
                <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-500 uppercase">
                  <Laptop className="w-3 h-3" />
                  macOS 13+ • Apple Silicon
                </div>
                <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-400 uppercase">
                  <CheckCircle2 className="w-3 h-3 text-emerald-500" />
                  Signed & Notarized by Apple
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Why Voice - Benefits */}
      <section className="py-20 md:py-28 bg-white dark:bg-zinc-900 border-t border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="text-center mb-16">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-emerald-500/10 border border-emerald-500/20 rounded-full mb-6">
              <Zap className="w-3 h-3 text-emerald-500" />
              <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">Why Voice?</span>
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-6">
              Think faster.<br/>
              <span className="text-emerald-500">Type less.</span>
            </h2>
            <p className="text-zinc-600 dark:text-zinc-400 max-w-2xl mx-auto leading-relaxed">
              Speaking is the most natural way to express complex thoughts. Talkie Live turns your voice into text instantly, so you can capture ideas at the speed you think them.
            </p>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-3 gap-8 max-w-2xl mx-auto mb-16">
            <StatCard value="4x" label="Faster than typing" />
            <StatCard value="~2s" label="Idea to text" />
            <StatCard value="0" label="Apps to open" />
          </div>

          {/* Benefits */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <BenefitCard
              icon={Zap}
              title="Speed"
              description="We speak at 150 words per minute but type at 40. Voice capture lets you get thoughts out before they evolve or fade."
              highlight="4x faster capture"
            />
            <BenefitCard
              icon={Eye}
              title="Rest Your Eyes"
              description="Look away from the screen while you speak. Mid-length thoughts flow better when you're not staring at a cursor waiting for words."
              highlight="Natural expression"
            />
            <BenefitCard
              icon={Rocket}
              title="Ecosystem"
              description="Start with a quick capture in Talkie Live. Continue with AI workflows in Talkie for Mac. Your ideas grow with the same tools."
              highlight="Memo → Workflow → Action"
            />
          </div>

          {/* + AI Teaser */}
          <div className="mt-16 pt-16 border-t border-zinc-200 dark:border-zinc-800">
            <div className="max-w-3xl mx-auto text-center">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-zinc-100 dark:bg-zinc-800 rounded-full mb-6">
                <Sparkles className="w-3 h-3 text-emerald-500" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500">+ AI</span>
              </div>
              <h3 className="text-xl md:text-2xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
                Your workflow, in high resolution.
              </h3>
              <div className="space-y-4 text-zinc-600 dark:text-zinc-400 leading-relaxed text-left max-w-2xl mx-auto">
                <p>
                  Your dictations are a live stream of your workflow. They capture how you break big goals into steps, make decisions, and move work forward, moment by moment.
                </p>
                <p>
                  Today that kind of data mostly feeds other platforms: chat, CRMs, ticketing systems, code hosts, AI coding tools. They improve. Your bill goes up.
                </p>
                <p>
                  With Talkie, that stream stays in one place. A high resolution record of how you work, ready for your own models, scripts, and tools to learn from, replay, and reuse.
                </p>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* The Philosophy */}
      <section className="py-20 md:py-28 bg-zinc-950 text-white">
        <Container>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
            <div>
              <div className="flex items-center gap-2 mb-6">
                <Lightbulb className="w-5 h-5 text-emerald-400" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-400">Philosophy</span>
              </div>
              <h2 className="text-3xl md:text-4xl font-bold uppercase tracking-tight mb-6 leading-tight">
                Work is changing fast,<br/>
                <span className="text-emerald-400">and we're leaning</span><br/>
                into it.
              </h2>
              <div className="space-y-6 text-zinc-400 leading-relaxed">
                <p>
                  For the first time in our careers, we can turn ideas into action at the speed of the tools around us.
                </p>
                <p>
                  <span className="text-white font-medium">It's the age of AI.</span> Typing every idea by hand is no longer required.
                </p>
                <p>
                  You get to talk, move faster, and actually enjoy the upgrade.
                </p>
              </div>
            </div>

            {/* Visual: Idea → Action Flow */}
            <div className="relative">
              <div className="absolute inset-0 bg-emerald-500/5 rounded-2xl blur-xl"></div>
              <div className="relative bg-zinc-900 border border-zinc-800 rounded-2xl p-8">
                <div className="space-y-6">
                  {/* Step 1 */}
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-amber-500/20 rounded-xl flex items-center justify-center flex-shrink-0">
                      <Lightbulb className="w-6 h-6 text-amber-400" />
                    </div>
                    <div>
                      <div className="text-xs font-mono uppercase text-zinc-500 mb-1">Moment 0</div>
                      <div className="text-white font-bold">Idea arrives</div>
                    </div>
                  </div>

                  <div className="w-px h-4 bg-zinc-800 ml-6"></div>

                  {/* Step 2 */}
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-emerald-500/20 rounded-xl flex items-center justify-center flex-shrink-0">
                      <Mic className="w-6 h-6 text-emerald-400" />
                    </div>
                    <div>
                      <div className="text-xs font-mono uppercase text-zinc-500 mb-1">+0.3 seconds</div>
                      <div className="text-white font-bold">Hold key, speak</div>
                    </div>
                  </div>

                  <div className="w-px h-4 bg-zinc-800 ml-6"></div>

                  {/* Step 3 */}
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-blue-500/20 rounded-xl flex items-center justify-center flex-shrink-0">
                      <Cpu className="w-6 h-6 text-blue-400" />
                    </div>
                    <div>
                      <div className="text-xs font-mono uppercase text-zinc-500 mb-1">+1.2 seconds</div>
                      <div className="text-white font-bold">Transcribed locally</div>
                    </div>
                  </div>

                  <div className="w-px h-4 bg-zinc-800 ml-6"></div>

                  {/* Step 4 */}
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-purple-500/20 rounded-xl flex items-center justify-center flex-shrink-0">
                      <Target className="w-6 h-6 text-purple-400" />
                    </div>
                    <div>
                      <div className="text-xs font-mono uppercase text-zinc-500 mb-1">+1.5 seconds</div>
                      <div className="text-white font-bold">Text appears exactly where you need it</div>
                    </div>
                  </div>
                </div>

                <div className="mt-8 pt-6 border-t border-zinc-800">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-mono uppercase text-zinc-500">Total time</span>
                    <span className="text-2xl font-bold text-emerald-400">~2 seconds</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* How It Works */}
      <section className="py-20 md:py-28 bg-white dark:bg-zinc-900 border-t border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="flex items-center gap-3 mb-12">
            <Zap className="w-4 h-4 text-emerald-500" />
            <h2 className="text-sm font-mono font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-400">
              How It Works
            </h2>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            {/* Flow Steps */}
            <div className="space-y-8">
              <FlowStep
                number="1"
                title="Hold the Hotkey"
                description="Press and hold your configured key (default: Right Option). Recording starts instantly. No click, no menu."
              />
              <div className="w-px h-6 bg-zinc-200 dark:bg-zinc-700 ml-4"></div>
              <FlowStep
                number="2"
                title="Speak Your Mind"
                description="Talk naturally. A subtle HUD appears. Your original app stays in focus. You never leave what you were doing."
              />
              <div className="w-px h-6 bg-zinc-200 dark:bg-zinc-700 ml-4"></div>
              <FlowStep
                number="3"
                title="Release to Transcribe"
                description="Let go of the key. On-device AI transcribes your speech in about a second. Nothing leaves your Mac."
              />
              <div className="w-px h-6 bg-zinc-200 dark:bg-zinc-700 ml-4"></div>
              <FlowStep
                number="4"
                title="Text Appears"
                description="Your transcription is pasted directly where your cursor was, or copied to clipboard. You're already back to work."
              />
            </div>

            {/* Visual Demo */}
            <div className="bg-zinc-100 dark:bg-zinc-950 rounded-2xl border border-zinc-200 dark:border-zinc-800 p-8 flex items-center justify-center min-h-[450px]">
              <div className="text-center">
                {/* Simulated HUD */}
                <div className="inline-flex flex-col items-center gap-6">
                  <div className="flex items-center gap-3 px-6 py-3 bg-black/90 backdrop-blur-lg rounded-2xl shadow-2xl">
                    <div className="w-3 h-3 bg-red-500 rounded-full animate-pulse shadow-lg shadow-red-500/50"></div>
                    <span className="text-white text-lg font-mono font-medium">0:03.2</span>
                  </div>
                  <div className="flex gap-1.5">
                    {[4, 7, 3, 6, 4, 8, 5, 3, 6, 4].map((h, i) => (
                      <div
                        key={i}
                        className="w-1.5 bg-emerald-500 rounded-full animate-pulse shadow-sm shadow-emerald-500/50"
                        style={{
                          height: `${h * 4}px`,
                          animationDelay: `${i * 50}ms`
                        }}
                      ></div>
                    ))}
                  </div>
                  <div className="flex items-center gap-2 px-4 py-2 bg-zinc-200 dark:bg-zinc-800 rounded-lg">
                    <Command className="w-3 h-3 text-zinc-500" />
                    <span className="text-xs font-mono text-zinc-500">Right Option</span>
                  </div>
                  <p className="text-xs font-mono text-zinc-400 uppercase tracking-wider mt-2">Release to transcribe</p>
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Use Cases */}
      <section className="py-20 md:py-28 bg-zinc-50 dark:bg-zinc-950">
        <Container>
          <div className="text-center mb-16">
            <div className="flex items-center justify-center gap-2 mb-6">
              <Rocket className="w-4 h-4 text-emerald-500" />
              <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500">Real World Uses</span>
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
              Ideas → Action
            </h2>
            <p className="text-zinc-600 dark:text-zinc-400 max-w-xl mx-auto">
              Every bit of friction between thought and capture is a chance for an idea to vanish. Here are a few ways Talkie Live gets used in real work.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center mb-4">
                <Code2 className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">While Coding</h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 italic leading-relaxed mb-2">
                "Alright, thinking out loud: first fix the auth flow, then clean up these tests, then rename this module…"
              </p>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
                Keep a running stream of code notes without leaving your editor.
              </p>
              <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800">
                <span className="text-[10px] font-mono text-emerald-500 uppercase">→ Paste into TODO comment or issue</span>
              </div>
            </div>

            <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center mb-4">
                <Mail className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Email Drafts</h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 italic leading-relaxed mb-2">
                "Hey Sarah, quick update on the launch. We're on track for Friday, but we need a final sign-off on pricing…"
              </p>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
                Dictate the rough draft, then tweak tone instead of typing from scratch.
              </p>
              <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800">
                <span className="text-[10px] font-mono text-emerald-500 uppercase">→ Paste into your email field</span>
              </div>
            </div>

            <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center mb-4">
                <FileText className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Meeting Notes</h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 italic leading-relaxed mb-2">
                "Key decisions: ship v1 as-is, move analytics to next sprint. Action items: John owns rollout, I own bug triage…"
              </p>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
                Capture the debrief right after the call while it's still fresh.
              </p>
              <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800">
                <span className="text-[10px] font-mono text-emerald-500 uppercase">→ Paste into Notion, Obsidian, or your notes app</span>
              </div>
            </div>

            <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center mb-4">
                <RefreshCw className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Context Switching</h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 italic leading-relaxed mb-2">
                "Where I left off: debugging the memory leak in the worker pool, next step is to isolate the new job type…"
              </p>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
                Leave yourself a breadcrumb so you can drop back into deep work fast.
              </p>
              <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800">
                <span className="text-[10px] font-mono text-emerald-500 uppercase">→ Paste into your task tracker</span>
              </div>
            </div>

            <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center mb-4">
                <PenLine className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Draft a Blog Post</h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 italic leading-relaxed mb-2">
                "Title idea: Why I stopped writing specs by hand. Intro: I used to… now I just…"
              </p>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
                Talk through the messy first draft instead of staring at a blank page.
              </p>
              <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800">
                <span className="text-[10px] font-mono text-emerald-500 uppercase">→ Paste into your editor</span>
              </div>
            </div>

            <div className="bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 p-6 rounded-xl">
              <div className="w-10 h-10 bg-zinc-100 dark:bg-zinc-800 rounded-lg flex items-center justify-center mb-4">
                <Palette className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Creative Briefs</h3>
              <p className="text-xs text-zinc-500 dark:text-zinc-500 italic leading-relaxed mb-2">
                "Visual direction: dark background, single accent color, feels like a focused tool not a dashboard. References: Linear, Raycast…"
              </p>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
                Capture nuance and small details before they slip away.
              </p>
              <div className="mt-4 pt-4 border-t border-zinc-100 dark:border-zinc-800">
                <span className="text-[10px] font-mono text-emerald-500 uppercase">→ Paste into your design doc</span>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Features Grid */}
      <section className="py-20 md:py-28 bg-white dark:bg-zinc-900 border-t border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="flex items-center gap-3 mb-12">
            <Command className="w-4 h-4 text-emerald-500" />
            <h2 className="text-sm font-mono font-bold uppercase tracking-widest text-zinc-500 dark:text-zinc-400">
              Features
            </h2>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <FeatureCard
              icon={Mic}
              title="Hold-to-Talk"
              description="No buttons to click. Hold a hotkey to record, release to transcribe. Builds muscle memory in minutes."
            />
            <FeatureCard
              icon={MousePointer2}
              title="Return to Origin"
              description="Talkie Live remembers which app and text field you were in. Text gets pasted right back where you were working."
            />
            <FeatureCard
              icon={Timer}
              title="48-Hour Echoes"
              description="Your transcriptions are stored locally for 48 hours. Quick access to recent captures, no permanent clutter."
            />
            <FeatureCard
              icon={Eye}
              title="Minimal HUD"
              description="A subtle floating pill shows recording state. Expands on hover for details, disappears when not needed."
            />
            <FeatureCard
              icon={Clipboard}
              title="Smart Routing"
              description="Auto-paste into text fields, or copy to clipboard for non-editable contexts. Intelligently adapts."
            />
            <FeatureCard
              icon={Clock}
              title="Always Ready"
              description="Lives silently in your menu bar. No app to launch, no window to find. Ready the instant you need it."
            />
          </div>
        </Container>
      </section>

      {/* Privacy Section */}
      <section className="py-20 md:py-28 bg-zinc-900">
        <Container>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            <div>
              <div className="flex items-center gap-2 mb-6">
                <HardDrive className="w-5 h-5 text-emerald-500" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-500">100% Local Processing</span>
              </div>
              <h2 className="text-3xl md:text-4xl font-bold text-white uppercase tracking-tight leading-tight mb-6">
                Your voice stays<br/>
                <span className="text-zinc-500">on your Mac.</span>
              </h2>
              <p className="text-zinc-400 leading-relaxed mb-8">
                Talkie Live uses on-device transcription with Whisper and Parakeet models. No audio leaves your computer. No cloud processing. No API keys needed. No account required.
              </p>
              <ul className="space-y-4 text-sm text-zinc-300">
                <li className="flex items-center gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  Transcription runs on Apple Silicon Neural Engine
                </li>
                <li className="flex items-center gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  Audio files stored locally, auto-deleted after 48h
                </li>
                <li className="flex items-center gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  No account required, no telemetry, no analytics
                </li>
                <li className="flex items-center gap-3">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                  Works offline. No internet connection needed
                </li>
              </ul>
            </div>

            <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-8">
              <div className="flex items-center gap-3 mb-6">
                <Cpu className="w-5 h-5 text-emerald-500" />
                <span className="text-xs font-mono font-bold uppercase tracking-widest text-zinc-400">Transcription Engines</span>
              </div>
              <div className="space-y-4">
                <div className="flex justify-between items-center py-3 border-b border-zinc-800">
                  <span className="text-sm text-zinc-400">Models</span>
                  <div className="flex flex-col items-end gap-1">
                    <span className="text-sm text-white font-mono">whisper-large-v3-turbo</span>
                    <span className="text-sm text-emerald-400 font-mono">parakeet-v3</span>
                  </div>
                </div>
                <div className="flex justify-between items-center py-3 border-b border-zinc-800">
                  <span className="text-sm text-zinc-400">Runtime</span>
                  <span className="text-sm text-white font-mono">MLX (Apple Silicon)</span>
                </div>
                <div className="flex justify-between items-center py-3 border-b border-zinc-800">
                  <span className="text-sm text-zinc-400">Latency</span>
                  <span className="text-sm text-emerald-400 font-mono">~1s for 10s audio</span>
                </div>
                <div className="flex justify-between items-center py-3">
                  <span className="text-sm text-zinc-400">Languages</span>
                  <span className="text-sm text-white font-mono">99+ (Whisper) • English (Parakeet)</span>
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Talkie Live vs Talkie */}
      <section className="py-20 md:py-28 bg-white dark:bg-zinc-900">
        <Container>
          <div className="text-center mb-12">
            <h2 className="text-2xl md:text-3xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
              Live vs Full Talkie
            </h2>
            <p className="text-zinc-600 dark:text-zinc-400 max-w-xl mx-auto">
              Talkie Live is for instant capture. The full Talkie app is for organizing and processing your voice memos with AI workflows.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto">
            {/* Live */}
            <div className="border-2 border-emerald-500 rounded-xl p-8 bg-emerald-500/5">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-12 h-12 bg-emerald-500 rounded-xl flex items-center justify-center">
                  <Zap className="w-6 h-6 text-white" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-zinc-900 dark:text-white uppercase">Talkie Live</h3>
                  <span className="text-xs font-mono text-emerald-600 dark:text-emerald-400 uppercase">Free Forever</span>
                </div>
              </div>
              <ul className="space-y-3 text-sm text-zinc-600 dark:text-zinc-400">
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                  Menu bar presence
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                  Global hotkey recording
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                  On-device transcription
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                  48h echo history
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                  Paste-to-origin
                </li>
              </ul>
            </div>

            {/* Full */}
            <div className="border border-zinc-200 dark:border-zinc-700 rounded-xl p-8">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-12 h-12 bg-zinc-900 dark:bg-white rounded-xl flex items-center justify-center">
                  <Mic className="w-6 h-6 text-white dark:text-black" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-zinc-900 dark:text-white uppercase">Talkie</h3>
                  <span className="text-xs font-mono text-zinc-500 uppercase">Full App</span>
                </div>
              </div>
              <ul className="space-y-3 text-sm text-zinc-600 dark:text-zinc-400">
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-zinc-400" />
                  Everything in Live, plus...
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-zinc-400" />
                  Permanent memo library
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-zinc-400" />
                  iCloud sync (iPhone + Mac)
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-zinc-400" />
                  AI workflows & automation
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4 text-zinc-400" />
                  Multi-provider LLM support
                </li>
              </ul>
              <Link
                href="/features"
                className="inline-flex items-center gap-2 mt-6 text-xs font-bold uppercase tracking-wider text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors"
              >
                See all features <ArrowRight className="w-3 h-3" />
              </Link>
            </div>
          </div>
        </Container>
      </section>

      {/* CTA */}
      <section className="py-28 bg-gradient-to-b from-zinc-50 to-white dark:from-zinc-950 dark:to-black border-t border-zinc-200 dark:border-zinc-800">
        <Container className="text-center">
          <div className="w-16 h-16 mx-auto mb-8 bg-emerald-500 rounded-2xl flex items-center justify-center shadow-xl shadow-emerald-500/25">
            <Zap className="w-8 h-8 text-white" />
          </div>
          <h2 className="text-3xl md:text-4xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
            Accelerate thoughts<br/>to action.
          </h2>
          <p className="text-lg text-zinc-600 dark:text-zinc-400 mb-10 max-w-lg mx-auto">
            Download Talkie Live for free. No account needed, no credit card, no catch. Just faster thinking.
          </p>
          <a href="https://github.com/arach/talkie/releases/latest/download/Talkie-Live.zip" className="inline-flex h-14 px-10 rounded-lg bg-emerald-500 hover:bg-emerald-600 text-white font-bold text-sm uppercase tracking-wider hover:scale-105 transition-all items-center gap-3 shadow-xl shadow-emerald-500/25">
            <Download className="w-5 h-5" />
            <span>Download for Mac</span>
          </a>
          <p className="mt-8 text-xs font-mono uppercase text-zinc-400">macOS 13+ • Apple Silicon optimized • Signed & Notarized</p>
        </Container>
      </section>

      {/* Footer */}
      <footer className="py-12 bg-zinc-100 dark:bg-zinc-950 border-t border-zinc-200 dark:border-zinc-800">
        <Container className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-emerald-500 rounded-sm"></div>
            <span className="text-sm font-bold uppercase tracking-widest text-zinc-900 dark:text-white">Talkie Live</span>
          </div>
          <div className="flex gap-8 text-[10px] font-mono uppercase text-zinc-500">
            <Link href="/" className="hover:text-black dark:hover:text-white transition-colors">Home</Link>
            <Link href="/features" className="hover:text-black dark:hover:text-white transition-colors">Full App</Link>
            <Link href="/security" className="hover:text-black dark:hover:text-white transition-colors">Security</Link>
            <Link href="/privacypolicy" className="hover:text-black dark:hover:text-white transition-colors">Privacy</Link>
          </div>
          <p className="text-[10px] font-mono uppercase text-zinc-400">&copy; {new Date().getFullYear()} Talkie Systems Inc.</p>
        </Container>
      </footer>

      <ThemeToggle />
    </div>
  )
}
