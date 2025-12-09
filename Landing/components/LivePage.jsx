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
  EyeOff,
  Laptop,
  Download,
  Cpu,
  HardDrive,
  Sparkles,
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

      {/* Hero Section */}
      <section className="relative pt-28 pb-16 md:pt-36 md:pb-24 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-60 pointer-events-none" />

        <Container className="relative z-10">
          <div className="max-w-3xl">
            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-emerald-500/10 border border-emerald-500/20 rounded-full mb-8">
              <Sparkles className="w-3 h-3 text-emerald-500" />
              <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">Free Menu Bar App</span>
            </div>

            <h1 className="text-4xl md:text-6xl font-bold tracking-tighter text-zinc-900 dark:text-white uppercase mb-6 leading-[0.9]">
              Instant<br/>
              <span className="text-emerald-500">voice-to-text</span><br/>
              for Mac.
            </h1>

            <p className="text-lg text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-xl mb-10">
              Hold a hotkey, speak, release. Your words appear wherever you were typing. No context switching. No cloud upload. Just fast, local dictation.
            </p>

            <div className="flex flex-col sm:flex-row items-start gap-4">
              <button className="h-12 px-8 rounded bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider hover:scale-105 transition-transform flex items-center gap-2 shadow-xl">
                <Download className="w-4 h-4" />
                <span>Download for Mac</span>
              </button>
              <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-400 uppercase">
                <Laptop className="w-3 h-3" />
                macOS 13+ required
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* How It Works */}
      <section className="py-16 md:py-24 bg-white dark:bg-zinc-900 border-t border-b border-zinc-200 dark:border-zinc-800">
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
                description="Press and hold your configured key (default: Right Option). Recording starts instantly."
              />
              <div className="w-px h-6 bg-zinc-200 dark:bg-zinc-700 ml-4"></div>
              <FlowStep
                number="2"
                title="Speak"
                description="Talk naturally. A subtle HUD shows you're recording. Your original app stays in focus."
              />
              <div className="w-px h-6 bg-zinc-200 dark:bg-zinc-700 ml-4"></div>
              <FlowStep
                number="3"
                title="Release"
                description="Let go. Transcription happens on-device via Whisper. Takes about a second."
              />
              <div className="w-px h-6 bg-zinc-200 dark:bg-zinc-700 ml-4"></div>
              <FlowStep
                number="4"
                title="Text Appears"
                description="Your transcription is pasted directly where you were typing, or copied to clipboard."
              />
            </div>

            {/* Visual Demo Placeholder */}
            <div className="bg-zinc-100 dark:bg-zinc-950 rounded-lg border border-zinc-200 dark:border-zinc-800 p-8 flex items-center justify-center min-h-[400px]">
              <div className="text-center">
                {/* Simulated HUD */}
                <div className="inline-flex flex-col items-center gap-4">
                  <div className="flex items-center gap-2 px-4 py-2 bg-black/80 backdrop-blur rounded-lg">
                    <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse"></div>
                    <span className="text-white text-sm font-mono">0:03.2</span>
                  </div>
                  <div className="flex gap-1">
                    <div className="w-1 h-4 bg-emerald-500 rounded-full animate-pulse"></div>
                    <div className="w-1 h-6 bg-emerald-500 rounded-full animate-pulse delay-75"></div>
                    <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse delay-150"></div>
                    <div className="w-1 h-5 bg-emerald-500 rounded-full animate-pulse delay-100"></div>
                    <div className="w-1 h-4 bg-emerald-500 rounded-full animate-pulse delay-200"></div>
                  </div>
                  <p className="text-[10px] font-mono text-zinc-500 uppercase tracking-wider mt-4">Recording in progress...</p>
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Features Grid */}
      <section className="py-16 md:py-24 bg-zinc-50 dark:bg-zinc-950">
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
              description="No buttons to click. Hold a hotkey to record, release to transcribe. Muscle memory in minutes."
            />
            <FeatureCard
              icon={MousePointer2}
              title="Return to Origin"
              description="Talkie Live remembers which app you were in. Text gets pasted right back where you were."
            />
            <FeatureCard
              icon={Timer}
              title="Ephemeral Echoes"
              description="Your transcriptions are stored locally for 48 hours. Quick history, no permanent clutter."
            />
            <FeatureCard
              icon={Eye}
              title="Minimal HUD"
              description="A subtle floating pill shows recording state. Expands on hover, disappears when not needed."
            />
            <FeatureCard
              icon={Clipboard}
              title="Smart Routing"
              description="Auto-paste into text fields, or copy to clipboard for non-editable contexts. You choose."
            />
            <FeatureCard
              icon={Clock}
              title="Instant Start"
              description="Lives in your menu bar. Always ready. No app to launch, no window to find."
            />
          </div>
        </Container>
      </section>

      {/* Privacy Section */}
      <section className="py-16 md:py-24 bg-zinc-900 border-t border-b border-zinc-800">
        <Container>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
            <div>
              <div className="flex items-center gap-2 mb-4">
                <HardDrive className="w-4 h-4 text-emerald-500" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-500">100% Local</span>
              </div>
              <h2 className="text-2xl md:text-3xl font-bold text-white uppercase tracking-tight leading-tight mb-6">
                Your voice stays<br/>
                <span className="text-zinc-500">on your Mac.</span>
              </h2>
              <p className="text-zinc-400 leading-relaxed mb-8">
                Talkie Live uses on-device Whisper models for transcription. No audio leaves your computer. No cloud processing. No API keys needed.
              </p>
              <ul className="space-y-3 text-sm text-zinc-300">
                <li className="flex items-center gap-3">
                  <span className="w-1.5 h-1.5 bg-emerald-500 rounded-full"></span>
                  Transcription runs on Apple Silicon Neural Engine
                </li>
                <li className="flex items-center gap-3">
                  <span className="w-1.5 h-1.5 bg-emerald-500 rounded-full"></span>
                  Audio files stored locally, auto-deleted after 48h
                </li>
                <li className="flex items-center gap-3">
                  <span className="w-1.5 h-1.5 bg-emerald-500 rounded-full"></span>
                  No account required, no telemetry
                </li>
              </ul>
            </div>

            <div className="bg-zinc-950 border border-zinc-800 rounded-lg p-8">
              <div className="flex items-center gap-3 mb-6">
                <Cpu className="w-5 h-5 text-emerald-500" />
                <span className="text-xs font-mono font-bold uppercase tracking-widest text-zinc-400">Whisper Engine</span>
              </div>
              <div className="space-y-4">
                <div className="flex justify-between items-center py-3 border-b border-zinc-800">
                  <span className="text-sm text-zinc-400">Model</span>
                  <span className="text-sm text-white font-mono">whisper-large-v3-turbo</span>
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
                  <span className="text-sm text-white font-mono">99+</span>
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Talkie Live vs Talkie */}
      <section className="py-16 md:py-24 bg-white dark:bg-zinc-900">
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
            <div className="border-2 border-emerald-500 rounded-lg p-8 bg-emerald-500/5">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-10 h-10 bg-emerald-500 rounded-lg flex items-center justify-center">
                  <Zap className="w-5 h-5 text-white" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-zinc-900 dark:text-white uppercase">Talkie Live</h3>
                  <span className="text-[10px] font-mono text-emerald-600 dark:text-emerald-400 uppercase">Free</span>
                </div>
              </div>
              <ul className="space-y-3 text-sm text-zinc-600 dark:text-zinc-400">
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-emerald-500 rounded-full"></span>
                  Menu bar presence
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-emerald-500 rounded-full"></span>
                  Global hotkey recording
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-emerald-500 rounded-full"></span>
                  On-device transcription
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-emerald-500 rounded-full"></span>
                  48h echo history
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-emerald-500 rounded-full"></span>
                  Paste-to-origin
                </li>
              </ul>
            </div>

            {/* Full */}
            <div className="border border-zinc-200 dark:border-zinc-700 rounded-lg p-8">
              <div className="flex items-center gap-3 mb-6">
                <div className="w-10 h-10 bg-zinc-900 dark:bg-white rounded-lg flex items-center justify-center">
                  <Mic className="w-5 h-5 text-white dark:text-black" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-zinc-900 dark:text-white uppercase">Talkie</h3>
                  <span className="text-[10px] font-mono text-zinc-500 uppercase">Full App</span>
                </div>
              </div>
              <ul className="space-y-3 text-sm text-zinc-600 dark:text-zinc-400">
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-zinc-400 rounded-full"></span>
                  Everything in Live, plus...
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-zinc-400 rounded-full"></span>
                  Permanent memo library
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-zinc-400 rounded-full"></span>
                  iCloud sync (iPhone + Mac)
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-zinc-400 rounded-full"></span>
                  AI workflows & automation
                </li>
                <li className="flex items-center gap-2">
                  <span className="w-1 h-1 bg-zinc-400 rounded-full"></span>
                  Multi-provider LLM support
                </li>
              </ul>
              <Link
                href="/features"
                className="inline-flex items-center gap-2 mt-6 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors"
              >
                See all features <ArrowRight className="w-3 h-3" />
              </Link>
            </div>
          </div>
        </Container>
      </section>

      {/* CTA */}
      <section className="py-24 bg-gradient-to-b from-zinc-50 to-white dark:from-zinc-950 dark:to-black border-t border-zinc-200 dark:border-zinc-800">
        <Container className="text-center">
          <div className="w-12 h-12 mx-auto mb-6 bg-emerald-500 rounded-xl flex items-center justify-center">
            <Zap className="w-6 h-6 text-white" />
          </div>
          <h2 className="text-2xl md:text-3xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
            Ready to type<br/>with your voice?
          </h2>
          <p className="text-zinc-600 dark:text-zinc-400 mb-8 max-w-md mx-auto">
            Download Talkie Live for free. No account needed, no credit card, no catch.
          </p>
          <button className="h-12 px-8 rounded bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider hover:scale-105 transition-transform flex items-center gap-2 shadow-xl mx-auto">
            <Download className="w-4 h-4" />
            <span>Download for Mac</span>
          </button>
          <p className="mt-6 text-[10px] font-mono uppercase text-zinc-400">macOS 13+ • Apple Silicon optimized</p>
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
