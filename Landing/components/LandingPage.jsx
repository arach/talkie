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
  Menu,
  X,
  Layers,
  FileText,
  DollarSign,
  Zap,
  Wand2,
} from 'lucide-react'
import Container from './Container'
import HeroBadge from './HeroBadge'
import PricingSection from './PricingSection'
import ThemeToggle from './ThemeToggle'

export default function LandingPage() {
  const [scrolled, setScrolled] = useState(false)
  const [pricingActive, setPricingActive] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [iosHover, setIosHover] = useState(false)
  const [scrollProgress, setScrollProgress] = useState(0)

  useEffect(() => {
    const onScroll = () => {
      setScrolled(window.scrollY > 8)
      // Fade out iPhone over first 200px of scroll
      const progress = Math.min(window.scrollY / 200, 1)
      setScrollProgress(progress)
    }
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
            <div className="flex h-7 w-7 items-center justify-center rounded bg-gradient-to-br from-emerald-500 to-teal-400 text-white shadow-sm">
              <Mic className="h-3.5 w-3.5" />
            </div>
            <span className="font-bold text-base tracking-tight font-mono uppercase">Talkie</span>
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
          <div className="hidden md:flex items-center gap-3">
            <a
              href="https://github.com/arach/talkie/releases/latest/download/Talkie-for-Mac.zip"
              className="px-3 py-2 rounded text-[10px] font-bold uppercase tracking-wider border border-zinc-300 dark:border-zinc-700 text-zinc-700 dark:text-zinc-300 hover:border-zinc-400 dark:hover:border-zinc-600 hover:text-zinc-900 dark:hover:text-white transition-colors"
            >
              Download Mac
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

      {/* Announcement Banner - below nav */}
      <div className="fixed top-14 left-0 right-0 z-40 bg-gradient-to-r from-emerald-600 via-emerald-500 to-teal-500 border-b border-emerald-400/30 group/banner">
        <Link href="/live" className="block">
          <div className="h-10 flex items-center justify-center text-[11px] px-4">
            {/* Left spacer to counterbalance right reserved area */}
            <div className="w-10" />
            <span className="text-white font-bold">Introducing Talkie Live</span>
            <span className="text-white/40 mx-2">•</span>
            <span className="text-white/90">Voice-to-text that works anywhere on your Mac</span>
            {/* Reserved area for logo + arrow */}
            <div className="w-10 flex items-center ml-0.5">
              <img
                src="/talkie-live-logo.png"
                alt=""
                className="h-5 w-auto transition-all duration-300 ease-out opacity-0 scale-0 group-hover/banner:opacity-100 group-hover/banner:scale-100 -mr-1 -ml-1"
              />
              <ArrowRight className="w-3 h-3 text-white flex-shrink-0 transition-all duration-300 ease-out -translate-x-5 group-hover/banner:translate-x-0" />
            </div>
          </div>
        </Link>
      </div>

      {/* Hero Section - Technical Grid Background */}
      <section className="relative pt-36 pb-12 md:pt-40 md:pb-16 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className={`absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] pointer-events-none transition-opacity duration-300 ease-out ${iosHover ? 'opacity-0' : 'opacity-60'}`} />

        {/* Left hover zone for video reveal */}
        <div
          className="absolute left-0 top-0 w-1/2 h-full hidden sm:block z-20"
          onMouseEnter={() => setIosHover(true)}
          onMouseLeave={() => setIosHover(false)}
        />

        {/* iPhone video - half resolution source, displayed at 330px (2x for retina) */}
        <div
          className={`fixed left-8 md:left-16 top-[52px] w-[330px] pointer-events-none select-none hidden sm:block rounded-[2rem] overflow-hidden bg-black shadow-[0_8px_30px_rgba(0,0,0,0.4)] ${iosHover ? 'z-50' : 'z-20'} transition-opacity duration-150`}
          style={{ isolation: 'isolate', opacity: 1 - scrollProgress }}
        >
          <div className={`rounded-[2rem] border-[3px] border-zinc-700 overflow-hidden transition-opacity duration-300 ease-out ${iosHover ? 'opacity-100' : 'opacity-30'}`}>
            <video
              src="/recording-preview-half.mp4"
              autoPlay
              loop
              muted
              playsInline
              className="w-full h-auto block"
              style={{ marginBottom: '-12px' }}
              aria-hidden="true"
            />
          </div>
        </div>

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
            <a
              href="#pricing"
              className="group/ios h-12 px-8 rounded bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider hover:scale-105 transition-all flex items-center gap-2 shadow-xl hover:shadow-2xl min-w-[200px] justify-center"
              onMouseEnter={() => setIosHover(true)}
              onMouseLeave={() => setIosHover(false)}
            >
              <Smartphone className="w-4 h-4 transition-transform group-hover/ios:-rotate-6" />
              <span>Get iOS Early Access</span>
            </a>
            <a href="https://github.com/arach/talkie/releases/latest/download/Talkie-for-Mac.zip" className="group/mac h-12 px-8 rounded border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white font-bold text-xs uppercase tracking-wider hover:bg-zinc-50 dark:hover:bg-zinc-800 hover:border-zinc-300 dark:hover:border-zinc-600 transition-all flex items-center gap-2 min-w-[200px] justify-center">
              <Laptop className="w-4 h-4 transition-transform group-hover/mac:scale-110" />
              <span>Download for Mac</span>
            </a>
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
      <section className="relative">
        {/* Background layer - below phone */}
        <div className="absolute inset-0 py-8 md:py-16 bg-zinc-100 dark:bg-zinc-900 border-t border-b border-zinc-200 dark:border-zinc-800 overflow-hidden z-10">
          {/* Subtle Background Glows */}
          <div className="absolute top-0 left-1/4 w-[500px] h-[500px] bg-zinc-300/20 dark:bg-zinc-800/20 rounded-full blur-[128px] pointer-events-none mix-blend-multiply dark:mix-blend-screen" />
          <div className="absolute bottom-0 right-1/4 w-[600px] h-[600px] bg-zinc-200/40 dark:bg-zinc-800/10 rounded-full blur-[128px] pointer-events-none mix-blend-multiply dark:mix-blend-screen" />
        </div>

        {/* Content layer - above phone */}
        <div className="relative z-30 py-8 md:py-16 mx-auto max-w-6xl px-6">

          <div className="mb-6 md:mb-10 md:flex items-end justify-between group/primitives-header">
            <div className="max-w-xl">
              <h2 className="text-3xl font-bold text-zinc-900 dark:text-white mb-4 tracking-tight uppercase transition-colors group-hover/primitives-header:text-emerald-600 dark:group-hover/primitives-header:text-emerald-400">Powerful Primitives.</h2>
              <p className="text-zinc-600 dark:text-zinc-400 text-sm leading-relaxed">
                We&apos;ve rebuilt the recording stack from the ground up. Talkie combines a professional‑grade audio engine with a node‑based automation system.
              </p>
            </div>
            <div className="hidden md:block">
              <Layers className="w-6 h-6 text-zinc-300 dark:text-zinc-700 transition-all group-hover/primitives-header:text-emerald-500 group-hover/primitives-header:rotate-12" />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-4 gap-3 md:gap-4 md:auto-rows-fr">

            {/* 1. Local AI Workflows (Large) */}
            <div className="col-span-1 md:col-span-2 md:row-span-2 relative bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 hover:border-emerald-500/30 p-4 md:p-6 flex flex-col md:justify-between group/workflows overflow-hidden rounded-sm shadow-sm hover:shadow-md transition-all duration-500">
              <div className="absolute top-0 right-0 p-6 opacity-5 group-hover/workflows:opacity-10 transition-opacity transform group-hover/workflows:scale-110 duration-700">
                <Wand2 className="w-40 h-40" strokeWidth={0.5} />
              </div>

              <div className="relative z-10">
                <div className="w-9 h-9 rounded-full bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center mb-4 transition-colors group-hover/workflows:bg-emerald-100 dark:group-hover/workflows:bg-emerald-900/30">
                  <Zap className="w-4 h-4 text-zinc-900 dark:text-white transition-all group-hover/workflows:text-emerald-600 dark:group-hover/workflows:text-emerald-400 group-hover/workflows:scale-110" />
                </div>
                <h3 className="text-lg font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-wide transition-colors group-hover/workflows:text-emerald-600 dark:group-hover/workflows:text-emerald-400">Local AI Workflows</h3>
                <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-sm">
                  Don&apos;t just record. Process. Configure pipelines to automatically summarize meetings, extract action items, or reformat ramblings into clear prose.
                </p>
              </div>

              <div className="mt-4 md:mt-8 space-y-1.5 md:space-y-2">
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
            <div className="col-span-1 md:col-span-1 md:row-span-2 bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 hover:border-emerald-500/30 p-4 md:p-5 flex flex-col group/device rounded-sm shadow-sm hover:shadow-md transition-all duration-300">
              <div className="flex items-center gap-2 mb-1.5 md:mb-2">
                <Lock className="w-4 h-4 text-zinc-900 dark:text-white transition-all group-hover/device:text-emerald-500 group-hover/device:scale-110" />
                <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide transition-colors group-hover/device:text-emerald-600 dark:group-hover/device:text-emerald-400">On‑Device Only</h3>
              </div>
              <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed mb-2 md:mb-3">
                Your voice is your biometric identity. It should never touch a server. The only cloud we use is the one you already trust: iCloud.
              </p>
              <div className="mt-auto border-t border-zinc-200 dark:border-zinc-800 pt-2 md:pt-3">
                <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500 mb-1.5 md:mb-2">
                  <span>Tracker Count</span>
                  <span className="text-zinc-300 dark:text-zinc-700">0</span>
                </div>
                <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500 mb-1.5 md:mb-2">
                  <span>Cloud Processing</span>
                  <span className="text-emerald-600 dark:text-emerald-400">Permission Based</span>
                </div>
                <div className="flex items-center justify-between text-[10px] font-mono uppercase text-zinc-500 mb-1.5 md:mb-2">
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
            <div className="col-span-1 bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 hover:border-blue-500/30 p-4 md:p-5 flex flex-col md:justify-between group/icloud rounded-sm shadow-sm hover:shadow-md transition-all duration-300">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <Cloud className="w-4 h-4 text-zinc-900 dark:text-white transition-all group-hover/icloud:text-blue-500 group-hover/icloud:scale-110" />
                    <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide transition-colors group-hover/icloud:text-blue-600 dark:group-hover/icloud:text-blue-400">iCloud Sync</h3>
                  </div>
                  <div className="w-2 h-2 rounded-full bg-blue-500 transition-all group-hover/icloud:scale-125 group-hover/icloud:shadow-[0_0_8px_rgba(59,130,246,0.6)]"></div>
                </div>
                <p className="text-xs text-zinc-600 dark:text-zinc-400">
                  Start recording on iPhone. Tag it. It appears instantly on your Mac for deep work.
                </p>
              </div>
            </div>

            {/* 4. Pro Audio */}
            <div className="col-span-1 bg-white/60 dark:bg-zinc-950/60 backdrop-blur-xl border border-white/20 dark:border-white/10 hover:border-emerald-500/30 p-4 md:p-5 flex flex-col md:justify-between group/audio rounded-sm shadow-sm hover:shadow-md transition-all duration-300">
              <div>
                <div className="flex items-center justify-between mb-1">
                  <div className="flex items-center gap-2">
                    <Mic className="w-4 h-4 text-zinc-900 dark:text-white transition-all group-hover/audio:text-emerald-500 group-hover/audio:scale-110" />
                    <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide transition-colors group-hover/audio:text-emerald-600 dark:group-hover/audio:text-emerald-400">Pro Audio</h3>
                  </div>
                  <span className="text-[10px] font-mono text-zinc-400 transition-colors group-hover/audio:text-emerald-500">WHISPER‑V3</span>
                </div>
                <p className="text-xs text-zinc-600 dark:text-zinc-400">
                  32‑bit float audio pipeline. Stereo recording. Automatic noise reduction.
                </p>
              </div>
            </div>

          </div>
        </div>
      </section>

      {/* Manifesto Section (Preview) */}
      <section id="manifesto" className="py-12 md:py-16 bg-white dark:bg-zinc-950 border-t border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="max-w-4xl mx-auto space-y-6">

            {/* Header/Intro */}
            <div className="space-y-4 group/manifesto-header">
              <div className="flex items-center gap-3">
                <Quote className="w-3 h-3 text-zinc-400 transition-colors group-hover/manifesto-header:text-emerald-500" />
                <h3 className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500 transition-colors group-hover/manifesto-header:text-emerald-500">The Manifesto</h3>
              </div>
              <h2 className="text-lg md:text-xl font-bold tracking-tight text-zinc-900 dark:text-white leading-[1.2] uppercase transition-transform origin-left group-hover/manifesto-header:scale-[1.02]">
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
              <div className="group/devices p-4 -m-4 rounded-lg transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/50">
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2 transition-colors group-hover/devices:text-emerald-500">001 / DEVICES</span>
                <h3 className="text-sm font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-tight transition-colors group-hover/devices:text-emerald-600 dark:group-hover/devices:text-emerald-400">iPhone + Mac = The Perfect Pair</h3>
                <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs">
                  Your iPhone is the perfect capture device — always on you, always ready. Your Mac is where raw ideas become real output.
                </p>
              </div>
              <div className="group/apps p-4 -m-4 rounded-lg transition-colors hover:bg-zinc-50 dark:hover:bg-zinc-900/50">
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2 transition-colors group-hover/apps:text-emerald-500">002 / APPS</span>
                <h3 className="text-sm font-bold text-zinc-900 dark:text-white mb-2 uppercase tracking-tight transition-colors group-hover/apps:text-emerald-600 dark:group-hover/apps:text-emerald-400">Apps, clouds and AI disconnect.</h3>
                <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs">
                  Voice Memos and Notes keep ideas trapped. AI tools pull your ideas into their clouds. Your thoughts get scattered or absorbed into someone else&apos;s system.
                </p>
              </div>
            </div>

            {/* Outro */}
            <div className="text-center pt-4 space-y-4">
              <div className="group/believe inline-flex items-center gap-2 px-4 py-2 rounded border border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-black/50 transition-all hover:border-emerald-500/50 hover:bg-emerald-50 dark:hover:bg-emerald-950/20 cursor-default">
                <div className="w-1.5 h-1.5 bg-emerald-500 rounded-full animate-pulse group-hover/believe:scale-125 transition-transform"></div>
                <p className="text-zinc-900 dark:text-white font-bold text-[10px] uppercase tracking-wide transition-colors group-hover/believe:text-emerald-600 dark:group-hover/believe:text-emerald-400">
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
                Our servers don&apos;t listen.<br/>
                <span className="text-zinc-500">Your voice stays yours.</span>
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
              <div className="p-6 group/local transition-colors hover:bg-zinc-900/50">
                <div className="flex items-center gap-3 mb-3">
                  <HardDrive className="w-4 h-4 text-emerald-500 transition-transform group-hover/local:scale-110" />
                  <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-zinc-400 transition-colors group-hover/local:text-emerald-500">Local-First</span>
                </div>
                <p className="text-xs text-zinc-300 leading-relaxed">
                  Data lives on your device. Delete the app, delete the data. No cloud database we control.
                </p>
              </div>

              {/* iCloud */}
              <div className="p-6 group/icloud transition-colors hover:bg-zinc-900/50">
                <div className="flex items-center gap-3 mb-3">
                  <Cloud className="w-4 h-4 text-emerald-500 transition-transform group-hover/icloud:scale-110" />
                  <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-zinc-400 transition-colors group-hover/icloud:text-emerald-500">Your iCloud</span>
                </div>
                <p className="text-xs text-zinc-300 leading-relaxed">
                  Sync uses Apple&apos;s Private CloudKit. Keys stay with your Apple ID. We never see them.
                </p>
              </div>

              {/* On-Device AI */}
              <div className="p-6 group/ai transition-colors hover:bg-zinc-900/50">
                <div className="flex items-center gap-3 mb-3">
                  <Cpu className="w-4 h-4 text-emerald-500 transition-transform group-hover/ai:scale-110" />
                  <span className="text-[10px] font-mono font-bold uppercase tracking-wider text-zinc-400 transition-colors group-hover/ai:text-emerald-500">On-Device AI</span>
                </div>
                <p className="text-xs text-zinc-300 leading-relaxed">
                  Transcription runs locally on Neural Engine. Use local LLMs for full offline workflows.
                </p>
              </div>

            </div>
          </div>

          {/* Privacy Highlights */}
          <div className="mt-6 flex flex-col md:flex-row items-center justify-center gap-4 md:gap-8 text-[10px] font-mono uppercase">
            <div className="group/highlight1 flex items-center gap-2 cursor-default">
              <Mic className="w-3 h-3 text-emerald-500 transition-transform group-hover/highlight1:scale-125" />
              <span className="text-emerald-400 transition-colors group-hover/highlight1:text-emerald-300">Voice transcribed on-device</span>
            </div>
            <div className="hidden md:block w-px h-4 bg-zinc-700"></div>
            <div className="group/highlight2 flex items-center gap-2 cursor-default">
              <ShieldCheck className="w-3 h-3 text-emerald-500 transition-transform group-hover/highlight2:scale-125" />
              <span className="text-emerald-400 transition-colors group-hover/highlight2:text-emerald-300">Memos stay on your Mac</span>
            </div>
          </div>

        </Container>
      </section>

      <PricingSection />

      {/* Condensed CTA */}
      <section id="get" className="relative py-24 bg-gradient-to-b from-white to-zinc-50 dark:from-zinc-950 dark:to-black border-t border-zinc-200 dark:border-zinc-800 group/cta">
        <div className="absolute inset-0 pointer-events-none bg-noise" />
        <div className="relative mx-auto max-w-4xl px-6 text-center">
          <Cpu className="w-8 h-8 mx-auto text-zinc-400 mb-6 transition-all duration-500 group-hover/cta:text-emerald-500 group-hover/cta:rotate-180" strokeWidth={1} />
          <h2 className="text-xl md:text-3xl font-bold text-zinc-900 dark:text-white mb-8 tracking-tight uppercase leading-tight transition-transform duration-300 group-hover/cta:scale-[1.01]">
            Stop uploading your thoughts <br className="hidden md:block" /> to someone else's cloud.
          </h2>
          <div className="flex justify-center">
            <a href="#pricing" className="group/btn relative inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider overflow-hidden rounded hover:shadow-lg transition-shadow">
              <span className="relative z-10">Get Early Access</span>
              <ArrowRight className="w-4 h-4 relative z-10 group-hover/btn:translate-x-1 transition-transform" />
            </a>
          </div>
          <p className="mt-6 text-[10px] font-mono uppercase text-zinc-400">Your data stays yours • Always</p>
        </div>
      </section>

      <footer className="py-12 bg-zinc-100 dark:bg-zinc-950 border-t border-zinc-200 dark:border-zinc-800">
        <Container className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="group/footer-logo flex items-center gap-2 cursor-default">
            <div className="w-3 h-3 bg-zinc-900 dark:bg-white rounded-sm transition-all group-hover/footer-logo:rotate-45 group-hover/footer-logo:bg-emerald-500 dark:group-hover/footer-logo:bg-emerald-400"></div>
            <span className="text-sm font-bold uppercase tracking-widest text-zinc-900 dark:text-white transition-colors group-hover/footer-logo:text-emerald-600 dark:group-hover/footer-logo:text-emerald-400">Talkie</span>
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
