"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Globe, Shield, Smartphone, Laptop, CheckCircle2, AlertCircle, ExternalLink } from 'lucide-react'
import Container from '../Container'

const Step = ({ number, title, children }) => (
  <div className="flex gap-4 md:gap-6">
    <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-500/20 flex items-center justify-center">
      <span className="text-sm font-bold text-blue-600 dark:text-blue-400">{number}</span>
    </div>
    <div className="flex-1 pb-8">
      <h3 className="text-lg font-bold text-zinc-900 dark:text-white mb-3">{title}</h3>
      <div className="text-zinc-600 dark:text-zinc-400 space-y-4">{children}</div>
    </div>
  </div>
)

const InfoBox = ({ type = 'info', children }) => {
  const styles = {
    info: 'bg-blue-50 dark:bg-blue-500/10 border-blue-200 dark:border-blue-500/30 text-blue-800 dark:text-blue-300',
    warning: 'bg-amber-50 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/30 text-amber-800 dark:text-amber-300',
    success: 'bg-emerald-50 dark:bg-emerald-500/10 border-emerald-200 dark:border-emerald-500/30 text-emerald-800 dark:text-emerald-300',
  }
  const icons = {
    info: CheckCircle2,
    warning: AlertCircle,
    success: CheckCircle2,
  }
  const Icon = icons[type]

  return (
    <div className={`flex gap-3 p-4 rounded-lg border ${styles[type]}`}>
      <Icon className="w-5 h-5 flex-shrink-0 mt-0.5" />
      <div className="text-sm">{children}</div>
    </div>
  )
}

export default function TailscalePage() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <Container className="h-14 flex items-center justify-between">
          <Link
            href="/docs"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            DOCS
          </Link>

          <div className="flex items-center gap-2 sm:gap-3">
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">TAILSCALE</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-blue-200 dark:border-blue-500/30 bg-blue-50 dark:bg-blue-500/10 mb-6">
                <Globe className="w-4 h-4 text-blue-600 dark:text-blue-400" />
                <span className="text-xs font-medium text-blue-700 dark:text-blue-400">Network Setup</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                Tailscale Configuration
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                Tailscale creates a secure, private network between your devices. It's how your iPhone finds and connects to your Mac without any port forwarding or cloud relay.
              </p>
            </div>

            {/* Why Tailscale */}
            <section className="mb-12">
              <h2 className="text-2xl font-bold text-zinc-900 dark:text-white mb-4">Why Tailscale?</h2>

              <div className="grid md:grid-cols-2 gap-4 mb-6">
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <Shield className="w-6 h-6 text-blue-500 mb-3" />
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-2">End-to-End Encrypted</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    All traffic between your devices is encrypted. Tailscale can't see your data.
                  </p>
                </div>

                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <Globe className="w-6 h-6 text-emerald-500 mb-3" />
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-2">Works Anywhere</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Connect from any network — home, office, coffee shop, or cellular. No firewall configuration needed.
                  </p>
                </div>
              </div>

              <InfoBox type="info">
                <p>
                  <strong>Privacy Note:</strong> Tailscale coordinates connections but never sees your actual data. Your voice recordings travel directly between your devices.
                </p>
              </InfoBox>
            </section>

            {/* How It Works */}
            <section className="mb-12">
              <h2 className="text-2xl font-bold text-zinc-900 dark:text-white mb-4">How It Works</h2>

              <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6">
                <div className="flex flex-col md:flex-row items-center justify-center gap-8 mb-6">
                  <div className="flex flex-col items-center">
                    <div className="w-16 h-16 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center mb-2">
                      <Laptop className="w-8 h-8 text-zinc-600 dark:text-zinc-400" />
                    </div>
                    <span className="text-sm font-medium text-zinc-900 dark:text-white">Your Mac</span>
                    <span className="text-xs text-zinc-500 font-mono">100.x.x.x</span>
                  </div>

                  <div className="flex flex-col items-center">
                    <div className="w-24 h-px md:w-px md:h-24 bg-gradient-to-r md:bg-gradient-to-b from-blue-500 to-emerald-500"></div>
                    <span className="text-[10px] font-mono text-zinc-400 mt-1">WireGuard tunnel</span>
                  </div>

                  <div className="flex flex-col items-center">
                    <div className="w-16 h-16 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center mb-2">
                      <Smartphone className="w-8 h-8 text-zinc-600 dark:text-zinc-400" />
                    </div>
                    <span className="text-sm font-medium text-zinc-900 dark:text-white">Your iPhone</span>
                    <span className="text-xs text-zinc-500 font-mono">100.x.x.x</span>
                  </div>
                </div>

                <p className="text-sm text-zinc-600 dark:text-zinc-400 text-center">
                  Both devices get a stable IP address on your private Tailscale network. They can always find each other, even when switching networks.
                </p>
              </div>
            </section>

            {/* Setup Steps */}
            <section className="mb-12">
              <h2 className="text-2xl font-bold text-zinc-900 dark:text-white mb-6">Setup Steps</h2>

              <div className="space-y-2">
                <Step number="1" title="Create a Tailscale Account">
                  <p>
                    Go to <a href="https://tailscale.com" target="_blank" rel="noopener noreferrer" className="text-blue-600 dark:text-blue-400 hover:underline inline-flex items-center gap-1">tailscale.com <ExternalLink className="w-3 h-3" /></a> and sign up. You can use Google, Microsoft, GitHub, or email.
                  </p>
                  <InfoBox type="info">
                    Tailscale's free tier supports up to 100 devices — more than enough for personal use.
                  </InfoBox>
                </Step>

                <Step number="2" title="Install Tailscale on Your Mac">
                  <p>Download Tailscale from the Mac App Store or directly from their website:</p>
                  <div className="flex flex-wrap gap-3 mt-3">
                    <a
                      href="https://apps.apple.com/app/tailscale/id1475387142"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 text-sm font-medium hover:opacity-90 transition-opacity"
                    >
                      Mac App Store <ExternalLink className="w-3 h-3" />
                    </a>
                    <a
                      href="https://tailscale.com/download/mac"
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-2 px-4 py-2 rounded-lg border border-zinc-300 dark:border-zinc-700 text-sm font-medium hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
                    >
                      Direct Download <ExternalLink className="w-3 h-3" />
                    </a>
                  </div>
                </Step>

                <Step number="3" title="Sign In on Your Mac">
                  <p>
                    Open Tailscale from your menu bar and sign in with the same account you created. Your Mac will appear in your Tailscale network.
                  </p>
                </Step>

                <Step number="4" title="Install Tailscale on Your iPhone">
                  <p>Download Tailscale from the iOS App Store:</p>
                  <a
                    href="https://apps.apple.com/app/tailscale/id1470499037"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 px-4 py-2 mt-3 rounded-lg bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 text-sm font-medium hover:opacity-90 transition-opacity"
                  >
                    iOS App Store <ExternalLink className="w-3 h-3" />
                  </a>
                </Step>

                <Step number="5" title="Sign In on Your iPhone">
                  <p>
                    Open the Tailscale app and sign in with the same account. Both devices are now on your private network.
                  </p>
                  <InfoBox type="success">
                    <p>
                      <strong>You're connected!</strong> Your Mac and iPhone can now communicate securely over any network.
                    </p>
                  </InfoBox>
                </Step>

                <Step number="6" title="Connect in Talkie">
                  <p>
                    Open Talkie Settings → iPhone and enable iPhone Sync. Talkie will detect Tailscale and display a QR code. Scan it with the Talkie iPhone app to pair.
                  </p>
                </Step>
              </div>
            </section>

            {/* Troubleshooting */}
            <section className="mb-12">
              <h2 className="text-2xl font-bold text-zinc-900 dark:text-white mb-4">Troubleshooting</h2>

              <div className="space-y-4">
                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-2">"Tailscale not running"</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Open the Tailscale app from your menu bar and ensure it shows "Connected". If it says "Disconnected", click to reconnect.
                  </p>
                </div>

                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-2">"No peers found"</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Make sure both devices are signed into the same Tailscale account. Check the Tailscale admin console at <a href="https://login.tailscale.com/admin/machines" className="text-blue-600 dark:text-blue-400 hover:underline">login.tailscale.com/admin</a> to verify both devices appear.
                  </p>
                </div>

                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-2">"Connection timeout"</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Some networks block UDP traffic. Try switching your iPhone to cellular data temporarily to test. If that works, your WiFi network may have restrictions.
                  </p>
                </div>

                <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                  <h3 className="font-bold text-zinc-900 dark:text-white mb-2">"Needs login"</h3>
                  <p className="text-sm text-zinc-600 dark:text-zinc-400">
                    Your Tailscale session has expired. Open Tailscale and re-authenticate. This typically happens after extended periods of inactivity.
                  </p>
                </div>
              </div>
            </section>

            {/* Previous/Next */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row gap-4">
                <Link
                  href="/docs/bridge-setup"
                  className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-emerald-500 group-hover:-translate-x-1 transition-all" />
                  <div>
                    <span className="text-xs text-zinc-500">Previous</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                      TalkieServer Setup
                    </h3>
                  </div>
                </Link>

                <Link
                  href="/"
                  className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <div>
                    <span className="text-xs text-zinc-500">Done?</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
                      Back to Home
                    </h3>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-emerald-500 group-hover:translate-x-1 transition-all" />
                </Link>
              </div>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
