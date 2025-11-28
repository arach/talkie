"use client"
import React, { useState, useEffect } from 'react'
import { Check, Clock } from 'lucide-react'

export default function PricingSection() {
  const [email, setEmail] = useState('')
  const [isSubmitted, setIsSubmitted] = useState(false)
  const [status, setStatus] = useState('idle') // idle | sending | success | error
  const [trap, setTrap] = useState('') // honeypot
  const [timeLeft, setTimeLeft] = useState({ days: 0, hours: 0, minutes: 0, seconds: 0 })

  // Use env var if provided; otherwise default to your Formspree endpoint
  const formspreeId = process.env.NEXT_PUBLIC_FORMSPREE_ID || 'mkgaanoo'

  // Pricing anchors (env-overridable)
  const regular = parseFloat(process.env.NEXT_PUBLIC_REGULAR_PRICE || '29.99')
  const launch = parseFloat(process.env.NEXT_PUBLIC_LAUNCH_PRICE || '0')
  const isFree = launch === 0

  // Countdown to end of year
  useEffect(() => {
    const endOfYear = new Date('2026-01-01T00:00:00')

    const updateCountdown = () => {
      const now = new Date()
      const diff = endOfYear - now

      if (diff <= 0) {
        setTimeLeft({ days: 0, hours: 0, minutes: 0, seconds: 0 })
        return
      }

      setTimeLeft({
        days: Math.floor(diff / (1000 * 60 * 60 * 24)),
        hours: Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)),
        minutes: Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60)),
        seconds: Math.floor((diff % (1000 * 60)) / 1000)
      })
    }

    updateCountdown()
    const interval = setInterval(updateCountdown, 1000)
    return () => clearInterval(interval)
  }, [])

  const handleEmailSubmit = async (e) => {
    e.preventDefault()
    const em = email.trim()
    if (!em || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(em)) return

    if (!formspreeId) {
      // graceful fallback to mailto if not configured
      const subject = encodeURIComponent('Introductory Offer – Launch Coupon')
      const body = encodeURIComponent(`Please send a launch coupon to: ${em}`)
      window.location.href = `mailto:hello@example.com?subject=${subject}&body=${body}`
      return
    }

    try {
      if (trap) { setIsSubmitted(true); setEmail(''); return } // Honeypot trips as success silently
      setStatus('sending')
      const res = await fetch(`https://formspree.io/f/${formspreeId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ email: em, _subject: 'Introductory Offer – Launch Coupon' }),
      })
      if (res.ok) {
        setStatus('success')
        setIsSubmitted(true)
        setEmail('')
      } else {
        setStatus('error')
      }
    } catch {
      setStatus('error')
    }
  }

  return (
    <section id="pricing" className="py-24 bg-zinc-50 dark:bg-black relative">
      <div className="absolute inset-0 bg-tactical-grid dark:bg-tactical-grid-dark bg-[size:40px_40px] opacity-50 pointer-events-none" />

      <div className="relative z-10 mx-auto max-w-4xl px-6">
        <div className="bg-white/80 dark:bg-zinc-900/80 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 p-8 md:p-12 rounded-sm shadow-sm">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-12 items-center">

            {/* Left: Value Prop */}
            <div>
              <div className="flex items-center gap-2 mb-6">
                <div className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse"></div>
                <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-emerald-600 dark:text-emerald-400">Launch Access</span>
              </div>
              <h2 className="text-3xl font-bold text-zinc-900 dark:text-white mb-4 tracking-tight uppercase">
                You own <br/> the tool.
              </h2>
              <p className="text-sm text-zinc-600 dark:text-zinc-400 mb-6 leading-relaxed">
                No subscription. Buy once. Your recordings, your workflows, your devices.
              </p>

              <ul className="space-y-3">
                {[
                  "Native iOS & macOS Apps",
                  "Encrypted iCloud Sync",
                  "Unlimited Local Transcription",
                  "Zero Vendor Lock-in"
                ].map((item, i) => (
                  <li key={i} className="flex items-center gap-3 text-xs font-mono text-zinc-700 dark:text-zinc-300">
                    <Check className="w-3 h-3 text-zinc-400" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>

            {/* Right: Pricing Card */}
            <div className="bg-zinc-50 dark:bg-black border border-zinc-200 dark:border-zinc-800 p-6 relative group">
              {/* Corner Accents */}
              <div className="absolute top-0 left-0 w-2 h-2 border-t border-l border-zinc-900 dark:border-white transition-opacity" />
              <div className="absolute top-0 right-0 w-2 h-2 border-t border-r border-zinc-900 dark:border-white transition-opacity" />
              <div className="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-zinc-900 dark:border-white transition-opacity" />
              <div className="absolute bottom-0 right-0 w-2 h-2 border-b border-r border-zinc-900 dark:border-white transition-opacity" />

              <div className="text-center mb-6">
                <p className="text-[10px] font-mono uppercase text-zinc-400 mb-2">Lifetime License</p>
                <div className="flex items-center justify-center gap-3 mb-2">
                  <span className="text-lg font-mono text-zinc-400 line-through decoration-zinc-400">${regular.toFixed(2)}</span>
                  <span className="text-4xl font-bold text-emerald-600 dark:text-emerald-400">{isFree ? 'FREE' : `$${launch.toFixed(2)}`}</span>
                </div>
                <p className="text-[10px] font-mono uppercase text-emerald-600 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-900/20 inline-block px-2 py-1 rounded mb-4">
                  Limited Time Only
                </p>

                {/* Countdown Timer */}
                <div className="flex items-center justify-center gap-1 text-[10px] font-mono text-zinc-500 dark:text-zinc-400">
                  <Clock className="w-3 h-3" />
                  <span>Ends in</span>
                  <span className="text-zinc-900 dark:text-white font-bold">{timeLeft.days}d</span>
                  <span className="text-zinc-900 dark:text-white font-bold">{timeLeft.hours}h</span>
                  <span className="text-zinc-900 dark:text-white font-bold">{timeLeft.minutes}m</span>
                  <span className="text-zinc-900 dark:text-white font-bold">{timeLeft.seconds}s</span>
                </div>
              </div>

              {!isSubmitted ? (
                <form onSubmit={handleEmailSubmit} className="space-y-3">
                  <input
                    type="email"
                    required
                    placeholder="enter@email.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="w-full bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 px-4 py-3 text-sm font-mono text-center text-zinc-900 dark:text-white placeholder-zinc-400 focus:outline-none focus:border-zinc-400 dark:focus:border-zinc-600 transition-colors"
                  />
                  <input type="text" tabIndex="-1" autoComplete="off" value={trap} onChange={(e) => setTrap(e.target.value)} className="hidden" aria-hidden="true" />
                  <button
                    type="submit"
                    className="w-full bg-emerald-600 hover:bg-emerald-700 dark:bg-emerald-500 dark:hover:bg-emerald-600 text-white py-3 text-xs font-bold uppercase tracking-widest transition-colors"
                    disabled={status === 'sending'}
                  >
                    {status === 'sending' ? 'Sending…' : 'Get Free Access'}
                  </button>
                  <p className="text-[10px] text-center text-zinc-400 mt-2">
                    We&apos;ll send your free download link to your inbox.
                  </p>
                </form>
              ) : (
                <div className="text-center py-6 animate-in fade-in zoom-in duration-300">
                  <div className="w-12 h-12 bg-emerald-100 dark:bg-emerald-900/30 rounded-full flex items-center justify-center mx-auto mb-3">
                    <Check className="w-6 h-6 text-emerald-600 dark:text-emerald-400" />
                  </div>
                  <p className="text-sm font-bold text-zinc-900 dark:text-white uppercase tracking-wide">You&apos;re on the list.</p>
                  <p className="text-xs text-zinc-500 mt-1">Check your inbox shortly for the link.</p>
                </div>
              )}
            </div>

          </div>
        </div>
      </div>
    </section>
  )
}
