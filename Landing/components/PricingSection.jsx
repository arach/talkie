"use client"
import React, { useState } from 'react'
import { Check } from 'lucide-react'
import Reveal from './Reveal'
import Container from './Container'

export default function PricingSection() {
  const [email, setEmail] = useState('')
  const [status, setStatus] = useState('idle') // idle | sending | success | error
  const [trap, setTrap] = useState('') // honeypot
  const [showForm, setShowForm] = useState(false)
  // Use env var if provided; otherwise default to your Formspree endpoint
  const formspreeId = process.env.NEXT_PUBLIC_FORMSPREE_ID || 'mkgaanoo'

  // Pricing anchors (env-overridable)
  const regular = parseFloat(process.env.NEXT_PUBLIC_REGULAR_PRICE || '29.99')
  const launch = parseFloat(process.env.NEXT_PUBLIC_LAUNCH_PRICE || '2.99')
  const isFree = launch === 0
  const savingPct = Math.max(0, Math.round(((regular - launch) / regular) * 100))

  const requestCoupon = async (e) => {
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
      if (trap) { setStatus('success'); setEmail(''); return } // Honeypot trips as success silently
      setStatus('sending')
      const res = await fetch(`https://formspree.io/f/${formspreeId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ email: em, _subject: 'Introductory Offer – Launch Coupon' }),
      })
      if (res.ok) {
        setStatus('success')
        setEmail('')
      } else {
        setStatus('error')
      }
    } catch {
      setStatus('error')
    }
  }
  return (
    <section id="pricing" className="relative border-t border-zinc-200 dark:border-zinc-800 bg-white dark:bg-black">
      <div className="absolute inset-0 bg-noise pointer-events-none" />
      <Container className="relative py-18 md:py-20 xl:py-24">
        {/* Banner ribbon */}
        <div className="mb-6 md:mb-8 rounded-md border border-emerald-300/40 dark:border-emerald-400/30 bg-emerald-50/70 dark:bg-emerald-900/25 px-4 py-3 text-center shadow-[0_2px_12px_rgba(16,185,129,0.12)]">
          <span className="text-sm font-medium text-emerald-900 dark:text-emerald-200">
            {savingPct > 0 ? `${savingPct}% OFF` : 'LIMITED OFFER'} — Help us shape Talkie and lock in the launch price.
          </span>
        </div>
        <div className="mx-auto max-w-2xl text-center mb-10 md:mb-12">
          <h2 className="text-2xl md:text-3xl font-extrabold tracking-tight text-zinc-900 dark:text-white">Pricing</h2>
          <p className="mt-3 text-[13px] leading-relaxed text-zinc-600 dark:text-zinc-400">
            Simple, transparent, and built for individuals first.
          </p>
        </div>

        <div className="mt-4 flex items-start justify-center">
          {/* Single centered launch card styled like a two-panel offer */}
          <Reveal delay={20} className="relative w-full max-w-[52rem]">
            <div className="panel p-0 grid md:grid-cols-2">
              {/* Left value prop */}
              <div className="p-6 md:p-8">
                <div className="flex items-center gap-2 text-emerald-400 text-[11px] font-mono uppercase tracking-[0.22em]">
                  <span className="block h-1.5 w-1.5 rounded-full bg-emerald-400" />
                  <span>Launch Access</span>
                </div>
                <h3 className="mt-3 text-[26px] font-extrabold tracking-tight uppercase text-zinc-100 leading-[1.05]">
                  Own your
                  <br />
                  intelligence.
                </h3>
                <p className="mt-3 text-[13px] leading-relaxed text-zinc-400 max-w-[28rem]">
                  One‑time purchase. No recurring fees. Stop renting your productivity tools and start owning them.
                </p>
                <ul className="mt-4 space-y-2 text-[13px] text-zinc-300">
                  {[
                    'Native iOS & macOS Apps',
                    'Unlimited Local Transcription',
                    'On‑Device LLM Inference',
                    'iCloud Sync Engine',
                  ].map((f) => (
                    <li key={f} className="flex items-center gap-2">
                      <Check className="h-3.5 w-3.5 text-emerald-400" />
                      <span>{f}</span>
                    </li>
                  ))}
                </ul>
              </div>

              {/* Right price/CTA panel with bracket corners */}
              <div className="relative bg-zinc-950 p-6 md:p-8 bracket">
                <div className="br" />
                <div className="text-[10px] font-mono uppercase tracking-[0.22em] text-zinc-500 text-center">Standard License</div>
                <div className="mt-1 flex items-baseline justify-center gap-3">
                  <span className="line-through text-zinc-500 text-sm opacity-80">${regular.toFixed(2)}</span>
                  <span className="text-[36px] font-extrabold text-zinc-100">{isFree ? '$0' : `$${launch.toFixed(2)}`}</span>
                </div>
                {savingPct > 0 && (
                  <div className="mt-2 text-center">
                    <span className="inline-flex items-center rounded-full border border-emerald-300/60 bg-emerald-50/70 px-3 py-1 text-[10px] font-mono uppercase tracking-[0.22em] text-emerald-700">
                      Limited Intro Offer
                    </span>
                  </div>
                )}

                {!showForm ? (
                  <div className="mt-5 flex flex-col items-center gap-2">
                    <button onClick={() => setShowForm(true)} className="w-full pill">Qualify for Offer</button>
                    <p className="text-[10px] font-mono uppercase tracking-[0.22em] text-zinc-500">We’ll send a secure purchase link</p>
                  </div>
                ) : (
                  <>
                    <form onSubmit={requestCoupon} className="mt-5 space-y-2" aria-label="Launch Offer Form">
                      <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="enter@email.com" className="w-full rounded-sm border border-zinc-700 bg-zinc-900 px-4 py-2.5 text-[13px] text-zinc-100 placeholder-zinc-600 focus:outline-none focus:ring-2 focus:ring-zinc-600 text-center font-mono" required />
                      <input type="text" tabIndex="-1" autoComplete="off" value={trap} onChange={(e) => setTrap(e.target.value)} className="hidden" aria-hidden="true" />
                      <button type="submit" className="w-full rounded-sm bg-zinc-100 text-zinc-950 dark:bg-zinc-100 dark:text-zinc-950 py-2.5 text-[11px] font-bold uppercase tracking-[0.26em] hover:bg-white transition-colors" disabled={status === 'sending' || status === 'success'}>
                        {status === 'sending' ? 'Sending…' : status === 'success' ? 'Sent ✓' : 'Qualify for Offer'}
                      </button>
                    </form>
                    <p className="text-[10px] font-mono uppercase tracking-[0.22em] text-zinc-500 mt-2 text-center">
                      {status === 'success' ? 'We’ll send a secure purchase link to your inbox.' : 'We’ll send a secure purchase link to your inbox.'}
                    </p>
                  </>
                )}
              </div>
            </div>
          </Reveal>
        </div>

        {/* Modal removed in favor of inline panel form */}
      </Container>
    </section>
  )
}
