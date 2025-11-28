"use client"
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  Mic,
  Cloud,
  ShieldCheck,
  Smartphone,
  Laptop,
  ArrowRight,
  Fingerprint,
  Cpu,
  Lock,
  Zap,
  Layers,
  Wand2,
  Quote,
  HardDrive,
  Key,
  Eye,
  Ban,
  ExternalLink,
} from 'lucide-react'
import PrimitivesSection from './PrimitivesSection'
import Container from './Container'
import HeroBadge from './HeroBadge'
import PricingSection from './PricingSection'
import ThemeToggle from './ThemeToggle'

export default function LandingPage() {
  const [scrolled, setScrolled] = useState(false)
  const [pricingActive, setPricingActive] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  // Scroll spy for pricing section
  useEffect(() => {
    if (typeof window === 'undefined') return
    const priceEl = document.getElementById('pricing')
    const obs = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.target.id === 'pricing') setPricingActive(e.isIntersecting)
        })
      },
      { rootMargin: '-40% 0px -40% 0px', threshold: 0.1 }
    )
    if (priceEl) obs.observe(priceEl)
    return () => obs.disconnect()
  }, [])

  const handleLaunch = () => {
    if (typeof window !== 'undefined') {
      document.getElementById('get')?.scrollIntoView({ behavior: 'smooth' })
    }
  }
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black text-zinc-900 dark:text-zinc-100 font-sans selection:bg-zinc-900 selection:text-white dark:selection:bg-white dark:selection:text-black">
      {/* Navigation */}
      <a href="#get" className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 btn-ghost">Skip to content</a>
      <nav className={`fixed top-0 left-0 right-0 z-50 border-b transition-colors duration-200 backdrop-blur-md ${
        scrolled
          ? 'bg-white/85 dark:bg-zinc-950/85 border-zinc-200/60 dark:border-zinc-800/60 shadow-[0_4px_12px_rgba(0,0,0,0.05)]'
          : 'bg-white/70 dark:bg-zinc-950/70 border-zinc-200/40 dark:border-zinc-800/40'
      }`}>
        <Container className="h-14 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="flex h-7 w-7 items-center justify-center rounded bg-black dark:bg-white text-white dark:text-black shadow-sm">
              <Mic className="h-3.5 w-3.5" fill="currentColor" />
            </div>
            <span className="font-bold text-base tracking-tight font-mono uppercase">Talkie_OS</span>
          </div>
          <div className="hidden md:flex items-center gap-8 text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500">
            <Link
              href="/features"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Features
            </Link>
            <Link
              href="/manifesto"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Manifesto
            </Link>
            <Link
              href="/security"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Security
            </Link>
            <a
              href="#pricing"
              className={`cursor-pointer transition-colors ${
                pricingActive ? 'text-zinc-900 dark:text-white' : 'hover:text-zinc-800 dark:hover:text-zinc-200'
              }`}
            >
              Pricing
            </a>
          </div>
          <button
            onClick={handleLaunch}
            className="hidden md:flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider bg-zinc-100 dark:bg-zinc-900 hover:bg-zinc-200 dark:hover:bg-zinc-800 px-3 py-1.5 rounded transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-300/60 dark:focus-visible:ring-zinc-600/50"
          >
            Launch Web Demo <ArrowRight className="w-3 h-3" />
          </button>
        </Container>
      </nav>

      {/* Hero Section - Technical Grid Background */}
      <section className="relative pt-28 pb-12 md:pt-32 md:pb-16 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-60 pointer-events-none" />

        <Container className="relative z-10 text-center">
          <div className="mb-8 flex justify-center"><HeroBadge /></div>

          <h1 className="text-5xl md:text-8xl font-bold tracking-tighter text-zinc-900 dark:text-white mb-6 leading-[0.9]">
            VOICE MEMOS<br />
            <span className="text-zinc-400 dark:text-zinc-600">+</span> AI.
          </h1>

          <p className="mx-auto max-w-2xl text-lg text-zinc-600 dark:text-zinc-400 mb-10 leading-relaxed">
            Capture on iPhone. Process on Mac. Synced through your encrypted iCloud — not our servers. Your data never leaves your Apple ecosystem.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <button className="h-12 px-8 rounded bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider hover:scale-105 transition-transform flex items-center gap-2 shadow-xl min-w-[200px] justify-center">
              <Smartphone className="w-4 h-4" />
              <span>Download for iOS</span>
            </button>
            <button className="h-12 px-8 rounded border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white font-bold text-xs uppercase tracking-wider hover:bg-zinc-50 dark:hover:bg-zinc-800 transition-all flex items-center gap-2 min-w-[200px] justify-center">
              <Laptop className="w-4 h-4" />
              <span>Download for Mac</span>
            </button>
          </div>

          <div className="mt-12">
            <button
              onClick={handleLaunch}
              className="text-[10px] font-mono uppercase tracking-widest text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 underline underline-offset-4 decoration-zinc-300 dark:decoration-zinc-700"
            >
              View Interface Design System
            </button>
          </div>
        </Container>
      </section>

      {/* Features Grid */}
      <PrimitivesSection />

      {/* Manifesto Section (Preview) */}
      <section id="manifesto" className="py-12 md:py-16 bg-white dark:bg-zinc-950 border-t border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="max-w-4xl mx-auto space-y-6">

            {/* Header/Intro */}
            <div className="space-y-4">
              <div className="flex items-center gap-3">
                <Quote className="w-3 h-3 text-zinc-400" />
                <h3 className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500">The Manifesto</h3>
              </div>
              <h2 className="text-lg md:text-xl font-bold tracking-tight text-zinc-900 dark:text-white leading-[1.2] uppercase">
                Your best ideas don&apos;t wait for you to sit down.
              </h2>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-2xl">
                Your ideas show up anywhere, at any time. On a walk, between meetings, in the middle of something unrelated. Builders know this rhythm well. Sparks arrive fast, unpolished, and usually at inconvenient times.
              </p>
            </div>

            {/* Divider */}
            <div className="flex items-center justify-center py-2">
              <div className="w-12 h-px bg-zinc-200 dark:bg-zinc-800"></div>
            </div>

            {/* Two Column Block */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
              <div>
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2">001 / DEVICES</span>
                <h3 className="text-sm font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-tight">iPhone + Mac = The Perfect Pair</h3>
                <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs">
                  Your iPhone is the perfect capture device — always on you, always ready. Your Mac is where raw ideas become real output.
                </p>
              </div>
              <div>
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2">002 / APPS</span>
                <h3 className="text-sm font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-tight">Apps, clouds and AI disconnect.</h3>
                <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs">
                  Voice Memos and Notes keep ideas trapped. AI tools pull your ideas into their clouds. Your thoughts get scattered or absorbed into someone else&apos;s system.
                </p>
              </div>
            </div>

            {/* Outro */}
            <div className="text-center pt-4 space-y-4">
              <div className="inline-flex items-center gap-2 px-4 py-2 rounded border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-black/50">
                <div className="w-1.5 h-1.5 bg-emerald-500 rounded-full animate-pulse"></div>
                <p className="text-zinc-900 dark:text-white font-bold text-[10px] uppercase tracking-wide">
                  We believe something essential is missing.
                </p>
              </div>
            </div>

          </div>
        </Container>
      </section>

      {/* Security Architecture Preview Section */}
      <section id="security-preview" className="py-16 md:py-24 bg-zinc-900 border-t border-b border-zinc-800 relative overflow-hidden">
        <div className="absolute inset-0 bg-tactical-grid-dark bg-[size:40px_40px] opacity-20 pointer-events-none" />
        <div className="absolute top-0 right-0 p-24 opacity-5 pointer-events-none">
          <ShieldCheck className="w-96 h-96 text-emerald-500" />
        </div>

        <Container className="relative z-10">
          {/* Header */}
          <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-12">
            <div className="max-w-xl">
              <div className="flex items-center gap-3 mb-4">
                <div className="p-2 bg-emerald-500/10 rounded border border-emerald-500/20">
                  <ShieldCheck className="w-5 h-5 text-emerald-500" />
                </div>
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-500">Security Architecture</span>
              </div>
              <h2 className="text-2xl md:text-3xl font-bold text-white uppercase tracking-tight mb-4 leading-tight">
                Privacy is not a setting.<br/>
                It&apos;s the architecture.
              </h2>
              <p className="text-sm text-zinc-400 leading-relaxed">
                Talkie is built on a &quot;Local-First&quot; doctrine. We do not own servers that store your data. We do not train on your ideas. You own the keys, the database, and the AI models.
              </p>
            </div>
            <Link
              href="/security"
              className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-emerald-500 hover:text-emerald-400 transition-colors shrink-0"
            >
              Full Security Deep Dive <ArrowRight className="w-3 h-3" />
            </Link>
          </div>

          {/* Security Features Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-12">

            <div className="group p-6 bg-zinc-950/50 border border-zinc-800 hover:border-emerald-500/30 transition-all rounded-sm">
              <div className="mb-4 inline-flex items-center justify-center w-10 h-10 rounded bg-zinc-800 text-white group-hover:bg-emerald-500/10 group-hover:text-emerald-400 transition-colors">
                <HardDrive className="w-5 h-5" strokeWidth={1.5} />
              </div>
              <h3 className="text-sm font-bold uppercase tracking-wide text-white mb-1">Local-First Storage</h3>
              <p className="text-[10px] font-mono text-emerald-500 uppercase tracking-wider mb-3">SQLite Database</p>
              <p className="text-xs text-zinc-400 leading-relaxed">
                Your data lives in a local SQLite database on your device&apos;s encrypted disk. Deleting the app deletes the data.
              </p>
            </div>

            <div className="group p-6 bg-zinc-950/50 border border-zinc-800 hover:border-emerald-500/30 transition-all rounded-sm">
              <div className="mb-4 inline-flex items-center justify-center w-10 h-10 rounded bg-zinc-800 text-white group-hover:bg-emerald-500/10 group-hover:text-emerald-400 transition-colors">
                <Cloud className="w-5 h-5" strokeWidth={1.5} />
              </div>
              <h3 className="text-sm font-bold uppercase tracking-wide text-white mb-1">Apple iCloud Sync</h3>
              <p className="text-[10px] font-mono text-emerald-500 uppercase tracking-wider mb-3">Zero-Knowledge Architecture</p>
              <p className="text-xs text-zinc-400 leading-relaxed">
                Data is encrypted with keys managed by your Apple ID. We have no access to these keys and cannot decrypt your data.
              </p>
            </div>

            <div className="group p-6 bg-zinc-950/50 border border-zinc-800 hover:border-emerald-500/30 transition-all rounded-sm">
              <div className="mb-4 inline-flex items-center justify-center w-10 h-10 rounded bg-zinc-800 text-white group-hover:bg-emerald-500/10 group-hover:text-emerald-400 transition-colors">
                <Cpu className="w-5 h-5" strokeWidth={1.5} />
              </div>
              <h3 className="text-sm font-bold uppercase tracking-wide text-white mb-1">On-Device Intelligence</h3>
              <p className="text-[10px] font-mono text-emerald-500 uppercase tracking-wider mb-3">CoreML & MLX</p>
              <p className="text-xs text-zinc-400 leading-relaxed">
                Transcriptions occur 100% on-device. Run local LLMs without a single packet leaving your Mac.
              </p>
            </div>

          </div>

          {/* Condensed Vendor Isolation Banner */}
          <div className="bg-zinc-950 border border-zinc-800 rounded-sm overflow-hidden">
            <div className="grid grid-cols-1 md:grid-cols-3 divide-y md:divide-y-0 md:divide-x divide-zinc-800">

              {/* Vendor */}
              <div className="p-6 text-center bg-red-900/5">
                <div className="inline-flex items-center gap-1.5 text-[10px] font-mono font-bold uppercase text-red-500 bg-red-900/20 px-2 py-1 rounded mb-3">
                  <Ban className="w-3 h-3" /> No Access
                </div>
                <h4 className="text-xs font-bold uppercase tracking-wider text-white mb-1">Talkie Systems</h4>
                <p className="text-[10px] text-zinc-500">Cannot decrypt your data</p>
              </div>

              {/* Wall */}
              <div className="p-6 text-center bg-black/50 flex flex-col items-center justify-center">
                <div className="text-[10px] font-mono font-bold uppercase text-red-500 mb-2">Wall of Separation</div>
                <div className="px-3 py-1 bg-zinc-800 rounded text-[9px] font-mono uppercase text-zinc-400">App Store Binary Only</div>
              </div>

              {/* User */}
              <div className="p-6 text-center bg-emerald-900/5">
                <div className="inline-flex items-center gap-1.5 text-[10px] font-mono font-bold uppercase text-emerald-500 bg-emerald-900/20 px-2 py-1 rounded mb-3">
                  <ShieldCheck className="w-3 h-3" /> Full Custody
                </div>
                <h4 className="text-xs font-bold uppercase tracking-wider text-white mb-1">You & Apple ID</h4>
                <p className="text-[10px] text-zinc-500">Sole data proprietor</p>
              </div>

            </div>
          </div>

        </Container>
      </section>

      <PricingSection />

      {/* Condensed CTA */}
      <section id="get" className="relative py-24 bg-gradient-to-b from-white to-zinc-50 dark:from-zinc-950 dark:to-black border-t border-zinc-200 dark:border-zinc-800">
        <div className="absolute inset-0 pointer-events-none bg-noise" />
        <div className="relative mx-auto max-w-4xl px-6 text-center">
          <Cpu className="w-8 h-8 mx-auto text-zinc-400 mb-6" strokeWidth={1} />
          <h2 className="text-xl md:text-3xl font-bold text-zinc-900 dark:text-white mb-8 tracking-tight uppercase leading-tight">
            Stop uploading your thoughts <br className="hidden md:block" /> to someone else's cloud.
          </h2>
          <div className="flex justify-center">
            <a href="mailto:hello@example.com?subject=Talkie%20Waitlist" className="group relative inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider overflow-hidden rounded">
              <span className="relative z-10">Join the waitlist</span>
              <ArrowRight className="w-4 h-4 relative z-10 group-hover:translate-x-1 transition-transform" />
            </a>
          </div>
          <p className="mt-6 text-[10px] font-mono uppercase text-zinc-400">One‑time license • No subscriptions</p>
        </div>
      </section>

      <footer className="py-12 bg-zinc-100 dark:bg-zinc-950 border-t border-zinc-200 dark:border-zinc-800">
        <Container className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-zinc-900 dark:bg-white rounded-sm"></div>
            <span className="text-sm font-bold uppercase tracking-widest text-zinc-900 dark:text-white">Talkie_OS</span>
          </div>
          <div className="flex gap-8 text-[10px] font-mono uppercase text-zinc-500">
            <a href="https://twitter.com" target="_blank" rel="noopener noreferrer" className="hover:text-black dark:hover:text-white transition-colors">Twitter</a>
            <a href="https://discord.com" target="_blank" rel="noopener noreferrer" className="hover:text-black dark:hover:text-white transition-colors">Discord</a>
            <a href="mailto:hello@talkie.arach.dev" className="hover:text-black dark:hover:text-white transition-colors">Email</a>
          </div>
          <p className="text-[10px] font-mono uppercase text-zinc-400">© {new Date().getFullYear()} Talkie Systems Inc.</p>
        </Container>
      </footer>
      {/* Floating, understated theme toggle */}
      <ThemeToggle />
    </div>
  )
}
