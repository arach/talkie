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
  Keyboard,
  Circle,
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
      <section className="relative pt-28 pb-20 md:pt-40 md:pb-32 overflow-hidden bg-zinc-100 dark:bg-zinc-950 group/hero">
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-60 pointer-events-none" />

        <Container className="relative z-10">
          <div>
            <div className="max-w-4xl">
              {/* Badge */}
              <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-emerald-500/10 border border-emerald-500/20 rounded-full mb-8">
                <Sparkles className="w-3 h-3 text-emerald-500" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">Start Free • No Account Required • 100% Local</span>
              </div>

              <div className="flex items-center gap-6 md:gap-10 mb-6 group/headline">
                <h1 className="text-5xl md:text-7xl lg:text-8xl font-bold tracking-tighter text-zinc-900 dark:text-white uppercase leading-none whitespace-nowrap">
                  <span>Thoughts</span> <span className="text-zinc-400 dark:text-zinc-500">→</span> <span className="transition-colors duration-300 group-hover/headline:text-emerald-500">Action</span>
                </h1>
                {/* Logo - inline with headline */}
                <div className="hidden lg:flex items-center justify-center relative group/icon flex-shrink-0 w-40 h-28">
                  <div className="absolute inset-0 m-auto w-48 h-36 bg-emerald-500/5 rounded-full blur-2xl transition-all duration-500 group-hover/icon:bg-emerald-500/20 group-hover/icon:scale-125 group-hover/headline:bg-emerald-500/15 pointer-events-none" />
                  <img
                    src="/talkie-live-logo.png"
                    alt="Talkie Live"
                    className="w-36 md:w-40 relative z-10 opacity-90 transition-all duration-300 group-hover/icon:opacity-100 group-hover/icon:scale-105 group-hover/icon:rotate-1 group-hover/headline:opacity-100 group-hover/headline:rotate-1"
                  />
                </div>
              </div>

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
          </div>
        </Container>
      </section>

      {/* Quick Start - Two Ways to Record */}
      <section className="py-16 md:py-20 bg-white dark:bg-zinc-900 border-t border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="text-center mb-10">
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500">Two Ways to Record</span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-3xl mx-auto">
            {/* Keyboard Shortcut */}
            <div className="group border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950 p-8 rounded-xl hover:border-emerald-500/50 transition-all text-center">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-zinc-100 dark:bg-zinc-800 rounded-2xl mb-5 group-hover:bg-emerald-500/10 transition-colors">
                <Keyboard className="w-7 h-7 text-zinc-600 dark:text-zinc-400 group-hover:text-emerald-500 transition-colors" />
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Keyboard</h3>
              <div className="inline-flex items-center gap-1.5 px-4 py-2 bg-zinc-200 dark:bg-zinc-800 rounded-lg mb-4">
                <span className="text-xs font-mono font-bold text-zinc-700 dark:text-zinc-300">⌥</span>
                <span className="text-xs font-mono text-zinc-400">+</span>
                <span className="text-xs font-mono font-bold text-zinc-700 dark:text-zinc-300">⌘</span>
                <span className="text-xs font-mono text-zinc-400">+</span>
                <span className="text-xs font-mono font-bold text-zinc-700 dark:text-zinc-300">L</span>
              </div>
              <p className="text-xs text-zinc-500 dark:text-zinc-400">Press anywhere to record</p>
            </div>

            {/* Menu Bar Pill */}
            <div className="group border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950 p-8 rounded-xl hover:border-emerald-500/50 transition-all text-center">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-zinc-100 dark:bg-zinc-800 rounded-2xl mb-5 group-hover:bg-emerald-500/10 transition-colors">
                <div className="flex items-center gap-1">
                  <Circle className="w-2.5 h-2.5 text-emerald-500 fill-emerald-500" />
                  <div className="w-8 h-2.5 bg-zinc-300 dark:bg-zinc-600 rounded-full group-hover:bg-emerald-500/50 transition-colors"></div>
                </div>
              </div>
              <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-2">Menu Bar</h3>
              <div className="inline-flex items-center gap-2 px-4 py-2 bg-zinc-200 dark:bg-zinc-800 rounded-lg mb-4">
                <div className="w-2 h-2 bg-emerald-500 rounded-full"></div>
                <span className="text-xs font-mono text-zinc-600 dark:text-zinc-400">Always-on pill</span>
              </div>
              <p className="text-xs text-zinc-500 dark:text-zinc-400">Click to start talking</p>
            </div>
          </div>

          <p className="text-center text-xs text-zinc-400 mt-8 max-w-md mx-auto">
            Text appears exactly where your cursor was. No copy-paste needed.
          </p>
        </Container>
      </section>

      {/* Why Voice - Benefits */}
      <section className="py-20 md:py-28 bg-white dark:bg-zinc-900 border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="text-center mb-16">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-emerald-500/10 border border-emerald-500/20 rounded-full mb-6">
              <Zap className="w-3 h-3 text-emerald-500" />
              <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">Why Voice?</span>
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-6">
              Execute at the<br/>
              <span className="text-emerald-500">speed of thought.</span>
            </h2>
            <p className="text-zinc-600 dark:text-zinc-400 max-w-2xl mx-auto leading-relaxed">
              Speaking is the most natural way to express complex thoughts. Talkie Live turns your voice into text instantly, so you can capture ideas at the speed you think them.
            </p>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-3 gap-8 max-w-2xl mx-auto mb-16">
            <StatCard value="~40" label="Keyboard WPM" />
            <StatCard value="200+" label="Talkie Live WPM" />
            <StatCard value="5x" label="Faster" />
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
                  Every dictation is a live log of how you work: how you break down goals, sequence steps, and make decisions.
                </p>
                <p>
                  Today that stream feeds other platforms: chat, CRMs, ticketing systems, code hosts, AI coding tools. They learn. They improve. You pay.
                </p>
                <p>
                  Talkie keeps that stream in one place, under your control, as training data for your own models and scripts.
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

      {/* Powerful AI Models - Feature Section */}
      <section className="py-16 md:py-20 bg-zinc-950 border-t border-b border-zinc-800">
        <Container>
          <div className="text-center mb-10">
            <div className="inline-flex items-center justify-center w-12 h-12 bg-emerald-500/10 border border-emerald-500/20 rounded-xl mb-4">
              <Cpu className="w-6 h-6 text-emerald-500" />
            </div>
            <h2 className="text-2xl md:text-3xl font-bold text-white uppercase tracking-tight mb-3">
              Powerful AI Models
            </h2>
            <p className="text-sm text-zinc-400 max-w-md mx-auto">
              Your voice stays on your Mac. Choose the model that fits your workflow.
            </p>
          </div>

          {/* Model Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl mx-auto">
            {/* Parakeet Card */}
            <div className="relative bg-zinc-900 border-2 border-emerald-500 rounded-xl p-5">
              <div className="absolute -top-2.5 left-4">
                <span className="px-2 py-0.5 bg-emerald-500 text-[9px] font-mono font-bold uppercase tracking-wider text-white rounded">Recommended</span>
              </div>
              <div className="flex items-center gap-2.5 mt-1 mb-4">
                <div className="w-9 h-9 bg-emerald-500/20 rounded-lg flex items-center justify-center p-1.5">
                  <img src="/nvidia-logo.png" alt="NVIDIA" className="w-full h-full object-contain" />
                </div>
                <div>
                  <span className="text-base text-white font-bold">Parakeet</span>
                  <span className="text-zinc-500 text-sm ml-1">v3</span>
                </div>
              </div>
              <div className="space-y-2 text-xs">
                <div className="flex justify-between">
                  <span className="text-zinc-500">Size</span>
                  <span className="text-zinc-300 font-mono">~200 MB</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500">Speed</span>
                  <span className="text-emerald-400 font-mono">Ultra-fast</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500">Languages</span>
                  <span className="text-zinc-300 font-mono">English</span>
                </div>
              </div>
            </div>

            {/* Whisper Card */}
            <div className="relative bg-zinc-900 border border-zinc-700 rounded-xl p-5 hover:border-zinc-600 transition-colors">
              <div className="absolute -top-2.5 left-4">
                <span className="px-2 py-0.5 bg-cyan-600 text-[9px] font-mono font-bold uppercase tracking-wider text-white rounded">Multilingual</span>
              </div>
              <div className="flex items-center gap-2.5 mt-1 mb-4">
                <div className="w-9 h-9 bg-zinc-800 rounded-lg flex items-center justify-center p-1.5">
                  <img src="/openai-logo.png" alt="OpenAI" className="w-full h-full object-contain opacity-70" />
                </div>
                <div>
                  <span className="text-base text-white font-bold">Whisper</span>
                  <span className="text-zinc-500 text-sm ml-1">large-v3</span>
                </div>
              </div>
              <div className="space-y-2 text-xs">
                <div className="flex justify-between">
                  <span className="text-zinc-500">Size</span>
                  <span className="text-zinc-300 font-mono">~1.5 GB</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500">Speed</span>
                  <span className="text-zinc-300 font-mono">Fast</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500">Languages</span>
                  <span className="text-zinc-300 font-mono">99+</span>
                </div>
              </div>
            </div>
          </div>

          <p className="text-center text-[10px] text-zinc-500 mt-6">
            Both run locally via MLX on Apple Silicon • No internet required • Switch anytime
          </p>
        </Container>
      </section>

      {/* Privacy Section */}
      <section className="py-20 md:py-28 bg-zinc-900">
        <Container>
          <div className="max-w-3xl mx-auto text-center">
            <div className="flex items-center justify-center gap-2 mb-6">
              <HardDrive className="w-5 h-5 text-emerald-500" />
              <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-500">100% Local Processing</span>
            </div>
            <h2 className="text-3xl md:text-4xl font-bold text-white uppercase tracking-tight leading-tight mb-6">
              Your voice stays on your Mac.
            </h2>
            <p className="text-zinc-400 leading-relaxed mb-10 max-w-xl mx-auto">
              No audio leaves your computer. No cloud processing. No API keys. No account required.
            </p>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4">
                <CheckCircle2 className="w-5 h-5 text-emerald-500 mx-auto mb-2" />
                <p className="text-xs text-zinc-400">Neural Engine<br/>Processing</p>
              </div>
              <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4">
                <CheckCircle2 className="w-5 h-5 text-emerald-500 mx-auto mb-2" />
                <p className="text-xs text-zinc-400">48h Auto<br/>Cleanup</p>
              </div>
              <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4">
                <CheckCircle2 className="w-5 h-5 text-emerald-500 mx-auto mb-2" />
                <p className="text-xs text-zinc-400">Zero<br/>Telemetry</p>
              </div>
              <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4">
                <CheckCircle2 className="w-5 h-5 text-emerald-500 mx-auto mb-2" />
                <p className="text-xs text-zinc-400">Works<br/>Offline</p>
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

      {/* Ecosystem Bar */}
      <section className="py-8 bg-zinc-100 dark:bg-zinc-900 border-t border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 sm:gap-8">
            <span className="text-[10px] font-mono uppercase tracking-widest text-zinc-400">Talkie Ecosystem</span>
            <div className="flex items-center gap-6">
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-purple-500 rounded-sm"></div>
                <span className="text-[10px] font-mono uppercase text-zinc-500">Engine</span>
                <span className="text-[10px] text-zinc-400 hidden sm:inline">powers transcription</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-emerald-500 rounded-full"></div>
                <span className="text-[10px] font-mono uppercase text-emerald-600 dark:text-emerald-400 font-bold">Live</span>
                <span className="text-[10px] text-zinc-400 hidden sm:inline">you&apos;re here</span>
              </div>
              <Link href="/features" className="flex items-center gap-2 group">
                <div className="w-2 h-2 bg-orange-500 rounded-sm"></div>
                <span className="text-[10px] font-mono uppercase text-zinc-500 group-hover:text-orange-500 transition-colors">Talkie</span>
                <span className="text-[10px] text-zinc-400 hidden sm:inline group-hover:text-zinc-600 dark:group-hover:text-zinc-300 transition-colors">full app →</span>
              </Link>
            </div>
          </div>
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
