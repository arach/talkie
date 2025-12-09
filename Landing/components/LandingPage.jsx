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
  Cpu,
  Lock,
  Quote,
  HardDrive,
  Ban,
  Menu,
  X,
  Layers,
  FileText,
  DollarSign,
} from 'lucide-react'
import PrimitivesSection from './PrimitivesSection'
import Container from './Container'
import HeroBadge from './HeroBadge'
import PricingSection from './PricingSection'
import ThemeToggle from './ThemeToggle'

export default function LandingPage() {
  const [scrolled, setScrolled] = useState(false)
  const [pricingActive, setPricingActive] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

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
          {/* Mobile menu button */}
          <button
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            className="md:hidden p-2 -mr-2 text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white transition-colors"
            aria-label="Toggle menu"
          >
            {mobileMenuOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </Container>
        {/* Mobile menu */}
        {mobileMenuOpen && (
          <div className="md:hidden border-t border-zinc-200 dark:border-zinc-800 bg-white/95 dark:bg-zinc-950/95 backdrop-blur-md">
            <Container className="py-4 flex flex-col gap-3">
              <Link
                href="/features"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <Layers className="w-4 h-4" />
                Features
              </Link>
              <Link
                href="/manifesto"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <FileText className="w-4 h-4" />
                Manifesto
              </Link>
              <Link
                href="/security"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <ShieldCheck className="w-4 h-4" />
                Security
              </Link>
              <a
                href="#pricing"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <DollarSign className="w-4 h-4" />
                Pricing
              </a>
            </Container>
          </div>
        )}
      </nav>

      {/* Hero Section - Technical Grid Background */}
      <section className="relative pt-28 pb-12 md:pt-32 md:pb-16 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-60 pointer-events-none" />

        <Container className="relative z-10 text-center">
          <div className="mb-8 flex justify-center"><HeroBadge /></div>

          <h1 className="text-5xl md:text-8xl font-bold tracking-tighter text-zinc-900 dark:text-white mb-6 leading-[0.9] group cursor-default">
            <span className="transition-all duration-300 group-hover:drop-shadow-[0_0_30px_rgba(255,255,255,0.4)] dark:group-hover:drop-shadow-[0_0_30px_rgba(255,255,255,0.3)]">VOICE MEMOS</span><br />
            <span className="text-zinc-400 dark:text-zinc-600 font-normal">+</span>{' '}
            <span className="transition-all duration-300 group-hover:text-emerald-400">AI.</span>
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

        <Container className="relative z-10">
          {/* Header */}
          <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-10">
            <div className="max-w-lg">
              <div className="flex items-center gap-2 mb-3">
                <Lock className="w-4 h-4 text-emerald-500" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-500">Data Sovereignty</span>
              </div>
              <h2 className="text-2xl md:text-3xl font-bold text-white uppercase tracking-tight leading-tight">
                We can&apos;t see your data.<br/>
                <span className="text-zinc-500">By design.</span>
              </h2>
            </div>
            <Link
              href="/security"
              className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-emerald-500 hover:text-emerald-400 transition-colors shrink-0"
            >
              Security Deep Dive <ArrowRight className="w-3 h-3" />
            </Link>
          </div>

          {/* Condensed 3-column stance */}
          <div className="bg-zinc-950 border border-zinc-800 rounded-sm overflow-hidden">
            <div className="grid grid-cols-1 md:grid-cols-3 divide-y md:divide-y-0 md:divide-x divide-zinc-800">

              {/* Local Storage */}
              <div className="p-6">
                <div className="flex items-center gap-3 mb-3">
                  <HardDrive className="w-4 h-4 text-emerald-500" />
                  <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-zinc-400">Local-First</span>
                </div>
                <p className="text-xs text-zinc-300 leading-relaxed">
                  Data lives on your device. Delete the app, delete the data. No cloud database we control.
                </p>
              </div>

              {/* iCloud */}
              <div className="p-6">
                <div className="flex items-center gap-3 mb-3">
                  <Cloud className="w-4 h-4 text-emerald-500" />
                  <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-zinc-400">Your iCloud</span>
                </div>
                <p className="text-xs text-zinc-300 leading-relaxed">
                  Sync uses Apple&apos;s Private CloudKit. Keys stay with your Apple ID. We never see them.
                </p>
              </div>

              {/* On-Device AI */}
              <div className="p-6">
                <div className="flex items-center gap-3 mb-3">
                  <Cpu className="w-4 h-4 text-emerald-500" />
                  <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-zinc-400">On-Device AI</span>
                </div>
                <p className="text-xs text-zinc-300 leading-relaxed">
                  Transcription runs locally on Neural Engine. Use local LLMs for full offline workflows.
                </p>
              </div>

            </div>
          </div>

          {/* Vendor Isolation One-liner */}
          <div className="mt-6 flex flex-col md:flex-row items-center justify-center gap-4 md:gap-8 text-[10px] font-mono uppercase">
            <div className="flex items-center gap-2">
              <Ban className="w-3 h-3 text-red-500" />
              <span className="text-red-400">Talkie: No data access</span>
            </div>
            <div className="hidden md:block w-px h-4 bg-zinc-700"></div>
            <div className="flex items-center gap-2">
              <ShieldCheck className="w-3 h-3 text-emerald-500" />
              <span className="text-emerald-400">You: Full ownership</span>
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
            <a href="/privacypolicy" className="hover:text-black dark:hover:text-white transition-colors">Privacy</a>
          </div>
          <p className="text-[10px] font-mono uppercase text-zinc-400">© {new Date().getFullYear()} Talkie Systems Inc.</p>
        </Container>
      </footer>
      {/* Floating, understated theme toggle */}
      <ThemeToggle />
    </div>
  )
}
