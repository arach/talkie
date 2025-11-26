"use client"
import React, { useEffect, useState } from 'react'
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
} from 'lucide-react'
import PrimitivesSection from './PrimitivesSection'
import Container from './Container'
import HeroBadge from './HeroBadge'
import PricingSection from './PricingSection'

export default function LandingPage() {
  const [scrolled, setScrolled] = useState(false)
  const [getActive, setGetActive] = useState(false)
  const [pricingActive, setPricingActive] = useState(false)
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  // Scroll spy for CTA section
  useEffect(() => {
    if (typeof window === 'undefined') return
    const getEl = document.getElementById('get')
    const priceEl = document.getElementById('pricing')
    const obs = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.target.id === 'get') setGetActive(e.isIntersecting)
          if (e.target.id === 'pricing') setPricingActive(e.isIntersecting)
        })
      },
      { rootMargin: '-40% 0px -40% 0px', threshold: 0.1 }
    )
    if (getEl) obs.observe(getEl)
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
          <div className="hidden md:flex items-center gap-8 text-[10px] font-mono font-bold uppercase tracking-[0.22em]">
            <a
              href="#get"
              className={`relative cursor-pointer transition-colors ${
                getActive ? 'text-zinc-900 dark:text-white' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'
              }`}
            >
              Get
              <span
                className={`absolute -bottom-1 left-0 h-[2px] w-full origin-left transform rounded bg-zinc-900 dark:bg-zinc-200 transition-scale ${
                  getActive ? 'scale-x-100 opacity-100' : 'scale-x-0 opacity-0'
                }`}
                aria-hidden
              />
            </a>
            <a
              href="#pricing"
              className={`relative cursor-pointer transition-colors ${
                pricingActive ? 'text-zinc-900 dark:text-white' : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'
              }`}
            >
              Pricing
              <span
                className={`absolute -bottom-1 left-0 h-[2px] w-full origin-left transform rounded bg-zinc-900 dark:bg-zinc-200 transition-scale ${
                  pricingActive ? 'scale-x-100 opacity-100' : 'scale-x-0 opacity-0'
                }`}
                aria-hidden
              />
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
      <section className="relative pt-32 pb-10 md:pt-40 md:pb-14 xl:pt-48 xl:pb-16 overflow-hidden bg-white dark:bg-zinc-950">
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-90 pointer-events-none" />
        <div className="absolute inset-0 z-0 bg-hero-gradient" />
        <div className="absolute inset-0 z-0 bg-noise" />

        <Container className="relative z-10 text-center">
          <div className="mb-7 md:mb-8 flex justify-center"><HeroBadge /></div>

          <h1 className="text-6xl md:text-7xl lg:text-8xl xl:text-[6.5rem] 2xl:text-[7rem] font-extrabold tracking-tight text-zinc-900 dark:text-white mb-5 md:mb-6 leading-[0.88]">
            VOICE MEMOS<br />
            <span className="text-zinc-400 dark:text-zinc-600">+</span> AI.
          </h1>

          <p className="mx-auto max-w-[44rem] xl:max-w-[48rem] text-[15px] md:text-base text-zinc-600 dark:text-zinc-400 mb-8 md:mb-9 leading-relaxed">
            Your private audio workspace. Capture high‑fidelity recordings, apply <span className="text-zinc-900 dark:text-white font-medium">local AI workflows</span>, and turn thoughts into structured notes, tasks, and reminders — without leaving your device.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
            <button className="pill flex items-center gap-2">
              <Smartphone className="w-4 h-4" />
              <span>Download for iOS</span>
            </button>
            <button className="pill flex items-center gap-2">
              <Laptop className="w-4 h-4" />
              <span>Download for Mac</span>
            </button>
          </div>

          {/* Value bullets */}
          <div className="mt-4 text-[11px] font-mono uppercase tracking-[0.22em] text-zinc-500 flex items-center justify-center gap-3">
            <span>Local MLX</span>
            <span className="opacity-40">•</span>
            <span>iCloud Sync</span>
            <span className="opacity-40">•</span>
            <span>JSON Workflows</span>
          </div>

          <div className="mt-10 md:mt-12">
            <button
              onClick={handleLaunch}
              className="text-[10px] font-mono uppercase tracking-widest text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 underline underline-offset-4 decoration-zinc-300 dark:decoration-zinc-700"
            >
              View Interface Design System
            </button>
          </div>
        </Container>
      </section>

      {/* Feature explanation matching the design */}
      <PrimitivesSection />

      {/* (Architecture section temporarily removed) */}

      <PricingSection />

      {/* Condensed CTA */}
      <section id="get" className="relative py-24 bg-gradient-to-b from-white to-zinc-50 dark:from-zinc-950 dark:to-black border-t border-zinc-200 dark:border-zinc-800">
        <div className="absolute inset-0 pointer-events-none bg-noise" />
        <div className="relative mx-auto max-w-4xl px-6 text-center">
          <Cpu className="w-8 h-8 mx-auto text-zinc-400 mb-6" strokeWidth={1} />
          <h2 className="text-2xl md:text-4xl font-bold text-zinc-900 dark:text-white mb-8 tracking-tight uppercase leading-tight">
            Stop uploading your thoughts <br className="hidden md:block" /> to someone else's cloud.
          </h2>
          <div className="flex justify-center">
            <a href="mailto:hello@example.com?subject=Talkie%20Waitlist" className="group relative inline-flex items-center gap-3 px-8 py-4 bg-zinc-900 dark:bg-white text-white dark:text-black font-bold text-sm uppercase tracking-widest overflow-hidden rounded">
              <span className="relative z-10">Join the waitlist</span>
              <ArrowRight className="w-4 h-4 relative z-10 group-hover:translate-x-1 transition-transform" />
            </a>
          </div>
          <p className="mt-6 text-[10px] font-mono uppercase text-zinc-400">One‑time license • No subscriptions</p>
        </div>
      </section>

      <footer className="py-12 bg-zinc-50 dark:bg-zinc-950 border-t border-zinc-200 dark:border-zinc-800">
        <Container className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-zinc-900 dark:bg-white rounded-sm"></div>
            <span className="text-sm font-bold uppercase tracking-widest text-zinc-900 dark:text-white">Talkie_OS</span>
          </div>
          <div className="flex items-center gap-8 text-[10px] font-mono uppercase tracking-[0.22em] text-zinc-500">
            <a href="#" className="hover:text-black dark:hover:text-white">Privacy</a>
            <a href="#" className="hover:text-black dark:hover:text-white">Terms</a>
            <a href="mailto:hello@example.com" className="hover:text-black dark:hover:text-white">Contact</a>
          </div>
          <p className="text-[10px] font-mono uppercase tracking-[0.22em] text-zinc-400">© {new Date().getFullYear()} Talkie Systems Inc.</p>
        </Container>
      </footer>
    </div>
  )
}
