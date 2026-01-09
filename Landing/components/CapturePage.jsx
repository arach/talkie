"use client"
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  ArrowRight,
  Smartphone,
  Watch,
  Cloud,
  Laptop,
  Mic,
  Zap,
  Sparkles,
  MapPin,
  CheckCircle2,
  History,
  Activity,
  Waves,
  Brain,
  Car,
} from 'lucide-react'
import Container from './Container'
import ThemeToggle from './ThemeToggle'
import SubNav from './SubNav'

const CaptureCard = ({ icon: Icon, title, description }) => (
  <div className="group border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900/50 p-6 rounded-xl hover:border-blue-500/50 transition-colors">
    <div className="flex items-center gap-3 mb-3">
      <div className="p-2 bg-blue-500/10 rounded-lg">
        <Icon className="w-4 h-4 text-blue-500" />
      </div>
      <h3 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide">{title}</h3>
    </div>
    <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">{description}</p>
  </div>
)

const FlowStep = ({ icon: Icon, title, description }) => (
  <div className="flex items-start gap-4">
    <div className="mt-1 w-8 h-8 rounded-full bg-blue-500 text-white flex items-center justify-center">
      <Icon className="w-4 h-4" />
    </div>
    <div>
      <h4 className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide mb-1">{title}</h4>
      <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">{description}</p>
    </div>
  </div>
)

const CaptureFeedItem = ({ time, text, location, icon: Icon }) => (
  <div className="flex gap-4 p-5 border-b border-zinc-100 dark:border-zinc-800/50 last:border-0 group">
    <div className="flex flex-col items-center gap-2">
      <div className="w-10 h-10 rounded-full bg-blue-500/10 flex items-center justify-center text-blue-500 border border-blue-500/20">
        <Icon className="w-5 h-5" />
      </div>
      <div className="w-px flex-1 bg-zinc-100 dark:bg-zinc-800 group-last:hidden"></div>
    </div>
    <div className="flex-1 pb-4">
      <div className="flex justify-between items-center mb-2">
        <span className="text-[10px] font-mono font-bold text-zinc-400 uppercase tracking-[0.2em]">{time}</span>
        <span className="text-[9px] font-mono text-zinc-400 uppercase flex items-center gap-1.5">
          <MapPin className="w-2.5 h-2.5" /> {location}
        </span>
      </div>
      <p className="text-sm text-zinc-800 dark:text-zinc-200 font-medium leading-relaxed transition-colors group-hover:text-blue-600 dark:group-hover:text-blue-400">
        "{text}"
      </p>
    </div>
  </div>
)

export default function CapturePage() {
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
        <Container className="h-14 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            BACK
          </Link>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-blue-500 rounded-full animate-pulse"></div>
            <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-900 dark:text-white">Talkie for Mobile</span>
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
              <span className="font-bold bg-gradient-to-r from-blue-500 to-cyan-400 bg-clip-text text-transparent">Capture.</span>
            </h1>

            <p className="text-xl md:text-2xl text-zinc-700 dark:text-zinc-300 leading-snug mb-4 font-display">
              Your best ideas don&apos;t wait for you to sit down.
            </p>
            <p className="text-base text-zinc-500 dark:text-zinc-400 leading-relaxed max-w-xl mx-auto mb-10">
              Speak on iPhone or Apple Watch. Keep moving. Find the transcript waiting on your Mac, ready for the next step.
            </p>

            <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
              <a href="/#pricing" className="h-12 px-8 rounded-lg bg-blue-500 hover:bg-blue-600 text-white font-bold text-sm uppercase tracking-wider hover:scale-105 transition-all flex items-center gap-3 shadow-xl shadow-blue-500/25">
                <Smartphone className="w-4 h-4" />
                <span>Get Early Access</span>
              </a>
              <div className="flex flex-col gap-1 text-left">
                <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-500 uppercase">
                  <Smartphone className="w-3 h-3" />
                  iOS 17+ • watchOS 10+
                </div>
                <div className="flex items-center gap-2 text-[10px] font-mono text-zinc-400 uppercase">
                  <CheckCircle2 className="w-3 h-3 text-blue-500" />
                  iCloud Sync to Mac
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* Capture Modes */}
      <section className="py-16 md:py-20 bg-white dark:bg-black border-t border-zinc-200 dark:border-zinc-800">
        <Container>
          <div className="text-center max-w-3xl mx-auto mb-12">
            <h2 className="text-3xl md:text-4xl text-zinc-900 dark:text-white tracking-tight">
              <span className="font-display italic">Capture,</span> <span className="font-bold">no friction.</span>
            </h2>
            <p className="mt-3 text-zinc-600 dark:text-zinc-400 leading-relaxed">
              Choose the fastest path in the moment, then let Talkie bring it home.
            </p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <CaptureCard
              icon={Smartphone}
              title="iPhone App"
              description="Open, speak, done. Designed for quick capture with clean, readable transcripts."
            />
            <CaptureCard
              icon={Watch}
              title="Apple Watch"
              description="Tap the wrist, speak a thought, and keep moving. Perfect for walks and commutes."
            />
            <CaptureCard
              icon={Zap}
              title="Widgets + Shortcuts"
              description="Launch capture from your Home Screen, Lock Screen, or a shortcut gesture."
            />
          </div>
        </Container>
      </section>

      {/* Flow */}
      <section className="py-16 md:py-24 bg-zinc-900 border-t border-b border-zinc-800 relative overflow-hidden">
        <div className="absolute inset-0 bg-tactical-grid-dark bg-[size:40px_40px] opacity-30 pointer-events-none" />
        <Container className="relative z-10">
          <div className="max-w-3xl mx-auto text-center mb-12">
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-blue-500">One continuous thread</span>
            <h2 className="mt-4 text-3xl md:text-4xl font-bold text-white uppercase tracking-tight">
              Capture anywhere, continue on Mac.
            </h2>
            <p className="mt-3 text-zinc-400 leading-relaxed">
              Capture on the go, then continue on your Mac with dictation and workflows ready to go.
            </p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-4xl mx-auto">
            <FlowStep
              icon={MapPin}
              title="Capture"
              description="Speak an idea the moment it appears, without opening a laptop."
            />
            <FlowStep
              icon={Cloud}
              title="Sync"
              description="Encrypted iCloud sync moves your transcript to the Mac you already use."
            />
            <FlowStep
              icon={Laptop}
              title="Act"
              description="Turn it into tasks, summaries, or documents with one click."
            />
          </div>
        </Container>
      </section>

      {/* Use Cases */}
      <section className="py-16 md:py-20 bg-white dark:bg-black">
        <Container>
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 items-start">
            <div className="lg:col-span-5">
              <h3 className="text-2xl md:text-3xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
                Real-world capture.
              </h3>
              <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed mb-6">
                Talkie is built for the in-between moments where ideas tend to disappear.
              </p>
              <ul className="space-y-3 text-sm text-zinc-600 dark:text-zinc-400">
                {[
                  'Walking between meetings',
                  'Sketching a feature on a commute',
                  'Recording feedback right after a call',
                  'Capturing a fix while hands are busy',
                ].map((item) => (
                  <li key={item} className="flex items-center gap-2">
                    <CheckCircle2 className="w-4 h-4 text-blue-500" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>
            <div className="lg:col-span-7">
              <div className="bg-white dark:bg-zinc-950 border border-zinc-200 dark:border-zinc-800 rounded-2xl overflow-hidden shadow-2xl">
                <div className="p-6 border-b border-zinc-100 dark:border-zinc-800 flex justify-between items-center bg-zinc-50/50 dark:bg-zinc-900/50">
                  <div className="flex items-center gap-3">
                    <History className="w-4 h-4 text-zinc-400" />
                    <span className="text-[10px] font-mono font-bold uppercase tracking-[0.2em] text-zinc-500">Recent Stream</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-blue-500" />
                    <span className="text-[10px] font-mono text-zinc-400 uppercase">Synchronized</span>
                  </div>
                </div>
                <div className="max-h-[420px] overflow-y-auto">
                  <CaptureFeedItem
                    time="09:12 AM"
                    location="Mission St."
                    text="The architecture of the new hub should be local-first. We need to focus on MLX optimization."
                    icon={Brain}
                  />
                  <CaptureFeedItem
                    time="11:45 AM"
                    location="Home Node"
                    text="Met Sarah for coffee. She mentioned the vector database issue—it's likely a circular dependency in the middleware."
                    icon={Activity}
                  />
                  <CaptureFeedItem
                    time="02:30 PM"
                    location="Transit"
                    text="Idea for the landing page: use a tactical grid with high-contrast emerald accents."
                    icon={Waves}
                  />
                  <CaptureFeedItem
                    time="05:20 PM"
                    location="Downtown"
                    text="Reminder: need to buy the organic milk and dino nuggets for the weekend."
                    icon={Car}
                  />
                </div>
                <div className="p-6 border-t border-zinc-100 dark:border-zinc-800 text-center">
                  <Link
                    href="/dictation"
                    className="text-[10px] font-bold uppercase tracking-widest text-blue-500 hover:text-blue-600 transition-colors inline-flex items-center gap-2"
                  >
                    Continue on Mac <ArrowRight className="w-3 h-3" />
                  </Link>
                </div>
              </div>
            </div>
          </div>
        </Container>
      </section>

      {/* CTA */}
      <section className="py-20 bg-gradient-to-b from-zinc-50 to-white dark:from-zinc-950 dark:to-black border-t border-zinc-200 dark:border-zinc-800">
        <Container className="text-center">
          <div className="w-14 h-14 mx-auto mb-6 bg-blue-500 rounded-2xl flex items-center justify-center shadow-xl shadow-blue-500/25">
            <Mic className="w-7 h-7 text-white" />
          </div>
          <h2 className="text-2xl md:text-3xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-4">
            Capture now, build later.
          </h2>
          <p className="text-zinc-600 dark:text-zinc-400 mb-8 max-w-lg mx-auto">
            Join early access and keep every idea connected to your Mac.
          </p>
          <a href="/#pricing" className="inline-flex h-12 px-8 rounded bg-blue-600 hover:bg-blue-700 text-white font-bold text-xs uppercase tracking-widest transition-colors items-center gap-2">
            <Mic className="w-4 h-4" />
            <span>Get Early Access</span>
          </a>
        </Container>
      </section>

      <footer className="py-12 bg-zinc-100 dark:bg-zinc-950 border-t border-zinc-200 dark:border-zinc-800">
        <Container className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-blue-500 rounded-sm"></div>
            <span className="text-sm font-bold uppercase tracking-widest text-zinc-900 dark:text-white">Talkie</span>
          </div>
          <div className="flex gap-8 text-[10px] font-mono uppercase text-zinc-500">
            <Link href="/" className="hover:text-black dark:hover:text-white transition-colors">Home</Link>
            <Link href="/dictation" className="hover:text-black dark:hover:text-white transition-colors">Dictation</Link>
            <Link href="/workflows" className="hover:text-black dark:hover:text-white transition-colors">Workflows</Link>
            <Link href="/security" className="hover:text-black dark:hover:text-white transition-colors">Security</Link>
          </div>
          <p className="text-[10px] font-mono uppercase text-zinc-400">&copy; {new Date().getFullYear()} Talkie Systems Inc.</p>
        </Container>
      </footer>

      <ThemeToggle />
    </div>
  )
}
