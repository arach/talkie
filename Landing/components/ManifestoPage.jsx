"use client"
import React, { useEffect, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, Mic } from 'lucide-react'
import Container from './Container'

const ConsoleHeader = ({ label, color = "text-zinc-500" }) => (
  <div className="mb-6 mt-4 select-none">
    <h2 className={`text-xs font-mono font-bold uppercase ${color}`}>&gt; {label}</h2>
    <div className={`w-full border-b border-solid mt-2 ${color.includes('emerald') ? 'border-emerald-500/30' : 'border-zinc-300 dark:border-zinc-700'}`}></div>
  </div>
)

export default function ManifestoPage() {
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

          <div className="flex items-center gap-2 sm:gap-3">
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">PHILOSOPHY</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6 relative overflow-hidden">
        {/* Background Grid */}
        <div className="absolute inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:60px_60px] opacity-20 dark:opacity-10 pointer-events-none" />

        <article className="relative z-10 mx-auto max-w-3xl">

          {/* CONTEXT */}
          <div className="mb-10">
            <ConsoleHeader label="CONTEXT" />

            <h1 className="text-xl md:text-3xl font-bold tracking-tight text-zinc-900 dark:text-white leading-tight uppercase mb-4">
              Your best ideas don&apos;t wait <br className="hidden md:block" /> for you to sit down.
            </h1>

            <p className="text-sm text-zinc-600 dark:text-zinc-400 leading-relaxed font-medium max-w-2xl">
              Your ideas show up anywhere, at any time. On a walk, between meetings, in the middle of something unrelated. Builders know this rhythm well. Sparks arrive fast, unpolished, and usually at inconvenient times. And without a way to catch them in the moment, they slip away just as quickly.
            </p>
          </div>

          {/* OBSERVATIONS */}
          <div className="mb-12">
            <ConsoleHeader label="OBSERVATIONS" />

            <div className="grid grid-cols-1 md:grid-cols-2 gap-8 md:gap-12 mb-8">
               {/* 001 / DEVICES */}
               <div>
                  <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2">001 / DEVICES</span>
                  <h3 className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-2">iPhone + Mac = ✨</h3>
                  <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs">
                    Your iPhone is the perfect capture device - always on you, always ready. Your Mac is where raw ideas become real output.
                  </p>
               </div>

               {/* 002 / SILOS */}
               <div>
                  <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2">002 / SILOS</span>
                  <span className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-2">Apps, Clouds &amp; AI Disconnect.</span>
                  <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs">
                    Voice Memos trap ideas. AI clouds absorb them. Your thoughts get scattered, siloed, and locked in someone else&apos;s system.
                  </p>
               </div>
            </div>

            {/* 003 / MISSING LINK + INTERSTITIAL */}
            <div className="border-t border-dashed border-zinc-200 dark:border-zinc-800 pt-8 mt-8">
               <div className="grid grid-cols-1 md:grid-cols-2 gap-8 items-center">
                 <div>
                   <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-400 block mb-2">003 / MISSING LINK</span>
                   <h3 className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-2">Something essential is missing.</h3>
                   <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs max-w-sm">
                     A private, continuous flow between your voice and your tools.
                   </p>
                 </div>

                 {/* Interstitial */}
                 <div className="flex justify-start md:justify-start md:pl-8">
                    <div className="border-2 border-zinc-900 dark:border-white bg-white dark:bg-black px-6 py-3 shadow-[4px_4px_0px_0px_rgba(16,185,129,1)] -rotate-2 hover:rotate-0 hover:shadow-[2px_2px_0px_0px_rgba(16,185,129,1)] transition-all select-none cursor-default">
                      <span className="text-xl font-bold font-mono text-zinc-900 dark:text-white tracking-tight">;) Talkie</span>
                    </div>
                 </div>
               </div>
            </div>
          </div>

          {/* PRINCIPLES */}
          <div className="mb-16">
            <ConsoleHeader label="PRINCIPLES" color="text-emerald-600 dark:text-emerald-500" />

            <div className="space-y-10">
              {/* 004 / MINIMALISM */}
               <div className="grid grid-cols-1 md:grid-cols-[120px_1fr] gap-4 md:gap-8 group">
                 <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-500 pt-1 group-hover:underline">004 / MINIMALISM</span>
                 <div>
                   <h3 className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-2 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">Tools should stay out of the way.</h3>
                   <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs max-w-xl">
                     Talkie is intentionally minimal. No inboxes. No dashboards. No proprietary workflow. Just a clear, quiet path from what you say to what you build.
                   </p>
                 </div>
              </div>

              {/* 005 / OWNERSHIP */}
               <div className="grid grid-cols-1 md:grid-cols-[120px_1fr] gap-4 md:gap-8 group">
                 <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-500 pt-1 group-hover:underline">005 / OWNERSHIP</span>
                 <div>
                   <h3 className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-2 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">Own your voice, own your workflow.</h3>
                   <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs max-w-xl">
                    Own your thoughts. Own your tools. Privacy is the architecture of sovereignty. Your intellectual property belongs to you, not a training set.
                   </p>
                 </div>
              </div>

              {/* 006 / AGENCY */}
               <div className="grid grid-cols-1 md:grid-cols-[120px_1fr] gap-4 md:gap-8 group">
                 <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-500 pt-1 group-hover:underline">006 / AGENCY</span>
                 <div>
                   <h3 className="text-base font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-2 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">Orchestrate your own tools.</h3>
                   <p className="text-zinc-600 dark:text-zinc-400 leading-relaxed text-xs max-w-xl">
                     We provide powerful building blocks so you can shape your own workflow. Your data. Your tools. Your rules.
                   </p>
                 </div>
              </div>
            </div>

          </div>

          {/* Footer Statement */}
          <footer className="mt-24 pb-12 text-center">
            <div className="flex justify-center mb-8">
               <div className="w-px h-16 bg-zinc-200 dark:bg-zinc-800"></div>
            </div>

            <h2 className="text-5xl md:text-7xl font-bold text-zinc-900 dark:text-white tracking-tighter uppercase mb-8">
              This is Talkie.
            </h2>

            <div className="flex flex-col items-center gap-6">
               <Link
                 href="/"
                 className="group relative px-10 py-4 bg-zinc-900 dark:bg-white text-white dark:text-black text-sm font-bold uppercase tracking-widest hover:scale-105 transition-transform overflow-hidden shadow-xl rounded-sm"
               >
                 <span className="relative z-10 flex items-center gap-3">
                   Start Your Flow <ArrowLeft className="w-4 h-4 rotate-180" />
                 </span>
                 <div className="absolute inset-0 bg-emerald-500/0 group-hover:bg-emerald-500/10 transition-colors duration-300"></div>
               </Link>

               <div className="flex items-center justify-center gap-4 text-[10px] font-mono uppercase tracking-widest text-zinc-400 dark:text-zinc-600 mt-4">
                  <span>VELOCITY</span>
                  <span className="text-emerald-500">•</span>
                  <span>SOVEREIGNTY</span>
                  <span className="text-emerald-500">•</span>
                  <span>FLOW</span>
               </div>
            </div>
          </footer>

        </article>
      </main>
    </div>
  )
}
