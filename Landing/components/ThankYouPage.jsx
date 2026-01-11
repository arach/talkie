"use client"
import React from 'react'
import Link from 'next/link'
import { Check, ArrowRight, Mail, Sparkles } from 'lucide-react'

export default function ThankYouPage() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black text-zinc-900 dark:text-zinc-100 font-sans selection:bg-zinc-900 selection:text-white dark:selection:bg-white dark:selection:text-black">
      {/* Background Grid */}
      <div className="fixed inset-0 z-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:60px_60px] opacity-20 dark:opacity-10 pointer-events-none" />

      <main className="relative z-10 min-h-screen flex items-center justify-center px-6 py-24">
        <div className="w-full max-w-sm">
          <div className="bg-white/80 dark:bg-zinc-900/80 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 p-8 relative">
            {/* Corner Accents */}
            <div className="absolute top-0 left-0 w-3 h-3 border-t-2 border-l-2 border-emerald-500" />
            <div className="absolute top-0 right-0 w-3 h-3 border-t-2 border-r-2 border-emerald-500" />
            <div className="absolute bottom-0 left-0 w-3 h-3 border-b-2 border-l-2 border-emerald-500" />
            <div className="absolute bottom-0 right-0 w-3 h-3 border-b-2 border-r-2 border-emerald-500" />

            {/* Success Icon */}
            <div className="flex justify-center mb-8">
              <div className="w-16 h-16 bg-emerald-100 dark:bg-emerald-900/30 rounded-full flex items-center justify-center animate-in zoom-in duration-500">
                <Check className="w-8 h-8 text-emerald-600 dark:text-emerald-400" strokeWidth={3} />
              </div>
            </div>

            {/* Header */}
            <div className="text-center mb-8">
              <div className="flex items-center justify-center gap-2 mb-4">
                <div className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse" />
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">
                  Confirmed
                </span>
              </div>
              <h1 className="text-2xl md:text-3xl font-bold text-zinc-900 dark:text-white uppercase tracking-tight mb-3">
                You&apos;re on the list.
              </h1>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-md mx-auto">
                Thanks for your interest in Talkie. We&apos;re building something special and you&apos;ll be among the first to experience it.
              </p>
            </div>

            {/* What to Expect */}
            <div className="border-t border-zinc-200 dark:border-zinc-800 pt-6 mb-6">
              <h2 className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500 mb-5 text-center">
                &gt; What happens next
              </h2>
              <div className="space-y-4 text-center">
                <div className="group">
                  <div className="inline-flex items-center justify-center w-8 h-8 bg-zinc-100 dark:bg-zinc-800 rounded mb-2 group-hover:bg-emerald-100 dark:group-hover:bg-emerald-900/30 transition-colors">
                    <Mail className="w-4 h-4 text-zinc-500 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors" />
                  </div>
                  <p className="text-xs font-bold text-zinc-900 dark:text-white">Check your inbox</p>
                  <p className="text-[11px] text-zinc-500 dark:text-zinc-400">Confirmation email incoming.</p>
                </div>
                <div className="group">
                  <div className="inline-flex items-center justify-center w-8 h-8 bg-zinc-100 dark:bg-zinc-800 rounded mb-2 group-hover:bg-emerald-100 dark:group-hover:bg-emerald-900/30 transition-colors">
                    <Sparkles className="w-4 h-4 text-zinc-500 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors" />
                  </div>
                  <p className="text-xs font-bold text-zinc-900 dark:text-white">Early access + launch discount</p>
                  <p className="text-[11px] text-zinc-500 dark:text-zinc-400">We&apos;ll invite you before public launch.</p>
                </div>
              </div>
            </div>

            {/* CTA */}
            <div className="text-center">
              <Link
                href="/"
                className="inline-flex items-center gap-2 text-xs font-mono font-bold uppercase tracking-widest text-zinc-500 hover:text-zinc-900 dark:hover:text-white transition-colors group"
              >
                Back to Home
                <ArrowRight className="w-3 h-3 transition-transform group-hover:translate-x-1" />
              </Link>
            </div>
          </div>

          {/* Footer note */}
          <p className="text-center text-[10px] font-mono text-zinc-400 mt-6 uppercase tracking-wider">
            Questions? Reach out anytime.
          </p>
        </div>
      </main>
    </div>
  )
}
