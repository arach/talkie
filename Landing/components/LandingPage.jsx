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
  Bot,
  DollarSign,
  Zap,
  Sparkles,
  Wand2,
  Book,
  Terminal,
} from 'lucide-react'
import Container from './Container'
import HeroBadge from './HeroBadge'
import PricingSection from './PricingSection'
import ThemeToggle from './ThemeToggle'

export default function LandingPage() {
  const [scrolled, setScrolled] = useState(false)
  const [pricingActive, setPricingActive] = useState(false)
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [featureTab, setFeatureTab] = useState('mac')

  useEffect(() => {
    const onScroll = () => {
      setScrolled(window.scrollY > 8)
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

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black text-zinc-900 dark:text-zinc-100 font-sans selection:bg-zinc-900 selection:text-white dark:selection:bg-white dark:selection:text-black">
      {/* Navigation */}
      <a href="#get" className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 btn-ghost">Skip to content</a>
      <nav className={`fixed top-0 left-0 right-0 z-50 border-b transition-all duration-300 backdrop-blur-md ${
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
              href="/dictation"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Talkie for Mac
            </Link>
            <Link
              href="/capture"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Talkie for Mobile
            </Link>
            <Link
              href="/workflows"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Talkie for Agents
            </Link>
            <Link
              href="/philosophy"
              className="cursor-pointer hover:text-black dark:hover:text-white transition-colors"
            >
              Philosophy
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
                href="/dictation"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <Laptop className="w-4 h-4" />
                Talkie for Mac
              </Link>
              <Link
                href="/capture"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <Smartphone className="w-4 h-4" />
                Talkie for Mobile
              </Link>
              <Link
                href="/workflows"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <Layers className="w-4 h-4" />
                Automation
              </Link>
              <Link
                href="/philosophy"
                onClick={() => setMobileMenuOpen(false)}
                className="flex items-center gap-2.5 text-sm font-mono font-medium uppercase tracking-wider text-zinc-900 dark:text-zinc-100 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <Quote className="w-4 h-4" />
                Philosophy
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
      <div className="fixed top-14 left-0 right-0 z-40 bg-gradient-to-r from-emerald-600 via-emerald-500 to-teal-500 border-b border-emerald-400/30 group/banner transition-opacity duration-300">
        <Link href="/dictation" className="block">
          <div className="h-10 flex items-center justify-center text-[11px] px-4">
            {/* Left spacer to counterbalance right reserved area */}
            <div className="w-10" />
            <span className="text-white font-bold">Talkie for Mac</span>
            <span className="text-white/40 mx-2">•</span>
            <span className="text-white/90">Dictation plus workflows, with iPhone &amp; Watch capture</span>
            {/* Reserved area for arrow */}
            <div className="w-10 flex items-center ml-0.5">
              <ArrowRight className="w-3 h-3 text-white flex-shrink-0 transition-all duration-300 ease-out -translate-x-2 group-hover/banner:translate-x-0" />
            </div>
          </div>
        </Link>
      </div>

      {/* Hero Section - Technical Grid Background */}
      <section className="relative pt-36 pb-12 md:pt-40 md:pb-16 overflow-hidden bg-zinc-100 dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-grid-fade pointer-events-none opacity-40" />



        <Container className="relative z-10 text-center">
          <h1 className="text-5xl md:text-8xl font-bold tracking-tighter text-zinc-900 dark:text-white mb-6 leading-[0.9] group cursor-default">
            <span className="font-display italic font-medium transition-all duration-300 group-hover:drop-shadow-[0_0_30px_rgba(16,185,129,0.35)]">Voice</span>{' '}
            <span className="text-zinc-400 dark:text-zinc-600 font-normal">to</span>{' '}
            <span className="relative inline-flex items-center">
              <span className="bg-gradient-to-r from-emerald-500 to-teal-400 bg-clip-text text-transparent">Action.</span>
              <Sparkles className="absolute -top-5 -right-7 h-5 w-5 text-emerald-400/80" />
            </span>
          </h1>

          <p className="mx-auto max-w-xl text-xl md:text-2xl text-zinc-700 dark:text-zinc-300 mb-4 leading-snug font-display">
            Your unified voice system.
          </p>
          <p className="mx-auto max-w-2xl text-base text-zinc-500 dark:text-zinc-400 mb-10 leading-relaxed">
            Drive all your Mac apps when you&apos;re working. Capture memos on iPhone and Watch when you&apos;re on the go.
          </p>

          <div className="mt-8 grid grid-cols-1 sm:grid-cols-3 gap-4 text-left">
            <div className="group/triad rounded-xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white/70 dark:bg-zinc-900/60 p-4 backdrop-blur-xl transition-all duration-300 hover:backdrop-blur-2xl hover:bg-white/80 dark:hover:bg-zinc-900/70 hover:border-emerald-400/70 hover:shadow-[0_0_0_1px_rgba(16,185,129,0.25),0_12px_30px_rgba(16,185,129,0.16)]">
              <div className="flex items-center gap-2 mb-2">
                <Laptop className="w-4 h-4 text-emerald-500" />
                <span className="text-[11px] font-mono font-bold uppercase tracking-widest text-zinc-600 dark:text-zinc-400">Talkie for Mac</span>
              </div>
              <p className="text-sm text-zinc-700 dark:text-zinc-300">
                Voice to action with dictation and workflows.
              </p>
            </div>
            <div className="group/triad rounded-xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white/70 dark:bg-zinc-900/60 p-4 backdrop-blur-xl transition-all duration-300 hover:backdrop-blur-2xl hover:bg-white/80 dark:hover:bg-zinc-900/70 hover:border-emerald-400/70 hover:shadow-[0_0_0_1px_rgba(16,185,129,0.25),0_12px_30px_rgba(16,185,129,0.16)]">
              <div className="flex items-center gap-2 mb-2">
                <Smartphone className="w-4 h-4 text-emerald-500" />
                <span className="text-[11px] font-mono font-bold uppercase tracking-widest text-zinc-600 dark:text-zinc-400">Talkie for Mobile</span>
              </div>
              <p className="text-sm text-zinc-700 dark:text-zinc-300">
                Capture on iPhone and Watch, synced to Mac.
              </p>
            </div>
            <div className="group/triad rounded-xl border border-zinc-200/80 dark:border-zinc-800/80 bg-white/70 dark:bg-zinc-900/60 p-4 backdrop-blur-xl transition-all duration-300 hover:backdrop-blur-2xl hover:bg-white/80 dark:hover:bg-zinc-900/70 hover:border-emerald-400/70 hover:shadow-[0_0_0_1px_rgba(16,185,129,0.25),0_12px_30px_rgba(16,185,129,0.16)]">
              <div className="flex items-center gap-2 mb-2">
                <Bot className="w-4 h-4 text-emerald-500" />
                <span className="text-[11px] font-mono font-bold uppercase tracking-widest text-zinc-600 dark:text-zinc-400">Talkie for Agents</span>
              </div>
              <p className="text-sm text-zinc-700 dark:text-zinc-300">
                Voice-initiated workflows for tasks and documents.
              </p>
            </div>
          </div>

          <div className="mt-8 flex justify-center">
            <Link
              href="/dictation"
              className="h-12 px-8 rounded bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider hover:scale-105 transition-all flex items-center gap-2 shadow-xl hover:shadow-2xl"
            >
              <Laptop className="w-4 h-4" />
              <span>Download Talkie for Mac</span>
            </Link>
          </div>
        </Container>
      </section>

      {/* Features Section */}
      <section className="relative py-16 md:py-24 bg-white dark:bg-black border-y border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="text-center mb-8">
            <h2 className="text-4xl md:text-5xl font-bold tracking-tighter text-zinc-900 dark:text-white leading-tight">
              <span className="font-display italic font-medium">Voice</span> to Everything, <span className="bg-gradient-to-r from-emerald-500 to-teal-400 bg-clip-text text-transparent">Instantly.</span>
            </h2>
            <p className="mt-4 text-lg text-zinc-600 dark:text-zinc-400 max-w-2xl mx-auto">
              Talkie is the connective tissue — driving your favorite tools with the right context, then pinging you when it's done.
            </p>
          </div>

          <div className="rounded-2xl border border-zinc-200/70 dark:border-zinc-800/70 bg-white/60 dark:bg-zinc-900/50 backdrop-blur-2xl overflow-hidden">
            <div className="p-2">
              <div className="flex flex-wrap justify-center gap-2 rounded-lg bg-white/80 dark:bg-zinc-950/60 px-2.5 py-1.5 backdrop-blur-2xl">
                {[
                  { id: 'mac', label: 'Talkie for Mac', icon: Laptop },
                  { id: 'go', label: 'Talkie for Mobile', icon: Smartphone },
                  { id: 'agents', label: 'Talkie for Agents', icon: Bot },
                ].map(({ id, label, icon: Icon }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => setFeatureTab(id)}
                  className={`group inline-flex items-center gap-2 rounded-lg px-3 py-1.5 text-[10px] font-mono font-bold uppercase tracking-widest transition-all ${
                    featureTab === id
                      ? 'bg-zinc-900 text-white dark:bg-white dark:text-black shadow-[0_10px_30px_rgba(0,0,0,0.18)]'
                      : 'bg-white/70 text-zinc-600 dark:bg-zinc-900/70 dark:text-zinc-400 hover:backdrop-blur-2xl hover:text-zinc-900 dark:hover:text-white'
                    }`}
                    aria-pressed={featureTab === id}
                  >
                    <Icon className={`h-3.5 w-3.5 ${featureTab === id ? 'text-emerald-400' : 'text-emerald-500'}`} />
                    {label}
                  </button>
                ))}
              </div>
            </div>

            <div className="p-5 md:p-6">
              {featureTab === 'mac' && (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 text-center">
                  {[
                    {
                      icon: Terminal,
                      title: 'Universal Voice Input',
                      body: 'Dictate into any app. Talkie types wherever your cursor is, no plugins required.',
                    },
                    {
                      icon: Wand2,
                      title: 'Blazing-Fast & Accurate',
                      body: 'Real-time transcription that keeps up with your thoughts, powered by a state-of-the-art audio engine.',
                    },
                    {
                      icon: Book,
                      title: 'Teach It Your Language',
                      body: 'Ensure near-perfect accuracy for your specific jargon with Personal Dictionaries.',
                    },
                    {
                      icon: Cpu,
                      title: 'Local-First Engine',
                      body: 'Process speech on-device by default, with privacy built into every step.',
                    },
                  ].map(({ icon: Icon, title, body }) => (
                    <div key={title} className="rounded-lg border border-zinc-200/70 dark:border-zinc-800/60 bg-white/80 dark:bg-zinc-950/50 p-5 backdrop-blur-lg transition-all hover:backdrop-blur-2xl hover:border-emerald-400/70 hover:shadow-[0_10px_30px_rgba(16,185,129,0.14)]">
                      <Icon className="w-6 h-6 mx-auto text-emerald-500 mb-3" />
                      <h4 className="font-bold text-zinc-800 dark:text-zinc-200">{title}</h4>
                      <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">{body}</p>
                    </div>
                  ))}
                </div>
              )}

              {featureTab === 'go' && (
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-center">
                  {[
                    {
                      icon: Zap,
                      title: 'Instant Capture',
                      body: 'Open, speak, done. Capture ideas anywhere with iPhone or Apple Watch.',
                    },
                    {
                      icon: ShieldCheck,
                      title: 'On-Device Transcription',
                      body: 'Get a high-quality, private transcript immediately - no internet required.',
                    },
                    {
                      icon: Cloud,
                      title: 'Seamless iCloud Sync',
                      body: 'Your notes show up on your Mac moments later, ready for the next step.',
                    },
                  ].map(({ icon: Icon, title, body }) => (
                    <div key={title} className="rounded-lg border border-zinc-200/70 dark:border-zinc-800/60 bg-white/80 dark:bg-zinc-950/50 p-5 backdrop-blur-lg transition-all hover:backdrop-blur-2xl hover:border-emerald-400/70 hover:shadow-[0_10px_30px_rgba(16,185,129,0.14)]">
                      <Icon className="w-6 h-6 mx-auto text-emerald-500 mb-3" />
                      <h4 className="font-bold text-zinc-800 dark:text-zinc-200">{title}</h4>
                      <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">{body}</p>
                    </div>
                  ))}
                </div>
              )}

              {featureTab === 'agents' && (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 text-center">
                  {[
                    {
                      icon: Layers,
                      title: 'Agent Pipelines',
                      body: 'Chain steps that transform raw speech into structured output.',
                    },
                    {
                      icon: Wand2,
                      title: 'LLM Steps',
                      body: 'Summaries, extraction, and transformations tuned for your workflows.',
                    },
                    {
                      icon: Terminal,
                      title: 'Tool Actions',
                      body: 'Trigger scripts, export files, and route results where you work.',
                    },
                    {
                      icon: Book,
                      title: 'Personal Knowledge',
                      body: 'Keep outputs consistent with your language, style, and taxonomy.',
                    },
                  ].map(({ icon: Icon, title, body }) => (
                    <div key={title} className="rounded-lg border border-zinc-200/70 dark:border-zinc-800/60 bg-white/80 dark:bg-zinc-950/50 p-5 backdrop-blur-lg transition-all hover:backdrop-blur-2xl hover:border-emerald-400/70 hover:shadow-[0_10px_30px_rgba(16,185,129,0.14)]">
                      <Icon className="w-6 h-6 mx-auto text-emerald-500 mb-3" />
                      <h4 className="font-bold text-zinc-800 dark:text-zinc-200">{title}</h4>
                      <p className="text-sm text-zinc-600 dark:text-zinc-400 mt-1">{body}</p>
                    </div>
                  ))}
                </div>
              )}

              <div className="mt-6 text-center">
                {featureTab === 'mac' && (
                  <Link
                    href="/dictation"
                    className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors"
                  >
                    Explore Talkie for Mac <ArrowRight className="w-3 h-3" />
                  </Link>
                )}
                {featureTab === 'go' && (
                  <Link
                    href="/capture"
                    className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors"
                  >
                    Explore Talkie for Mobile <ArrowRight className="w-3 h-3" />
                  </Link>
                )}
                {featureTab === 'agents' && (
                  <Link
                    href="/workflows"
                    className="inline-flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors"
                  >
                    Explore Automation <ArrowRight className="w-3 h-3" />
                  </Link>
                )}
              </div>
            </div>
          </div>

        </Container>
      </section>

      {/* Manifesto Section (Preview) */}
      <section id="philosophy" className="py-12 md:py-16 bg-white dark:bg-zinc-950 border-t border-b border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="max-w-4xl mx-auto space-y-6">

            {/* Header/Intro */}
            <div className="space-y-4 group/philosophy-header">
              <div className="flex items-center gap-3">
                <Quote className="w-3 h-3 text-zinc-400 transition-colors group-hover/philosophy-header:text-emerald-500" />
                <h3 className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500 transition-colors group-hover/philosophy-header:text-emerald-500">Our Philosophy</h3>
              </div>
              <h2 className="text-xl md:text-2xl tracking-tight text-zinc-900 dark:text-white leading-[1.2] transition-transform origin-left group-hover/philosophy-header:scale-[1.02]">
                <span className="font-display italic">Your best ideas</span> <span className="font-bold">don&apos;t wait for you to sit down.</span>
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
        <div className="absolute inset-0 bg-tactical-grid-dark opacity-15 pointer-events-none" />

        <Container className="relative z-10">
          {/* Header */}
          <div className="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-10">
            <div className="max-w-lg">
              <div className="flex items-center gap-2 mb-3">
                <Lock className="w-4 h-4 text-emerald-500" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-500">Data Sovereignty</span>
              </div>
              <h2 className="text-2xl md:text-3xl text-white tracking-tight leading-tight">
                <span className="font-display italic">Our servers don&apos;t listen.</span><br/>
                <span className="text-zinc-500 font-bold">Your voice stays yours.</span>
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
          <h2 className="text-xl md:text-3xl text-zinc-900 dark:text-white mb-8 tracking-tight leading-tight transition-transform duration-300 group-hover/cta:scale-[1.01]">
            <span className="font-display italic">Stop uploading your thoughts</span> <br className="hidden md:block" /> <span className="font-bold">to someone else&apos;s cloud.</span>
          </h2>
          <div className="flex justify-center">
            <a href="#pricing" className="group/btn relative inline-flex items-center gap-2 px-6 py-3 bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-xs uppercase tracking-wider overflow-hidden rounded hover:shadow-lg transition-shadow">
              <span className="relative z-10">Request Early Access</span>
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
            <a href="/philosophy" className="hover:text-black dark:hover:text-white transition-colors">Philosophy</a>
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
