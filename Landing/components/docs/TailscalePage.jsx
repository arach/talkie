"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Shield, Globe, Smartphone, Laptop, CheckCircle2, AlertCircle, ExternalLink } from 'lucide-react'
import DocsLayout from './DocsLayout'

const sections = [
  { id: 'why-tailscale', title: 'Why Tailscale?', level: 2 },
  { id: 'how-it-works', title: 'How It Works', level: 2 },
  { id: 'setup', title: 'Setup Steps', level: 2 },
  { id: 'step-1', title: '1. Create Account', level: 3 },
  { id: 'step-2', title: '2. Install on Mac', level: 3 },
  { id: 'step-3', title: '3. Install on iPhone', level: 3 },
  { id: 'step-4', title: '4. Connect in Talkie', level: 3 },
  { id: 'troubleshooting', title: 'Troubleshooting', level: 2 },
  { id: 'navigation', title: 'Next Steps', level: 2 },
]

const Step = ({ number, title, children }) => (
  <div id={`step-${number}`} className="flex gap-4 md:gap-6 not-prose scroll-mt-20">
    <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-100 dark:bg-blue-500/20 flex items-center justify-center">
      <span className="text-sm font-bold text-blue-600 dark:text-blue-400">{number}</span>
    </div>
    <div className="flex-1 pb-6">
      <h4 className="text-lg font-bold text-zinc-900 dark:text-white mb-2">{title}</h4>
      <div className="text-zinc-600 dark:text-zinc-400 space-y-3">{children}</div>
    </div>
  </div>
)

const InfoBox = ({ type = 'info', children }) => {
  const styles = {
    info: 'bg-blue-50 dark:bg-blue-500/10 border-blue-200 dark:border-blue-500/30 text-blue-800 dark:text-blue-300',
    warning: 'bg-amber-50 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/30 text-amber-800 dark:text-amber-300',
    success: 'bg-emerald-50 dark:bg-emerald-500/10 border-emerald-200 dark:border-emerald-500/30 text-emerald-800 dark:text-emerald-300',
  }
  const icons = { info: CheckCircle2, warning: AlertCircle, success: CheckCircle2 }
  const Icon = icons[type]

  return (
    <div className={`flex gap-3 p-4 rounded-lg border ${styles[type]} not-prose`}>
      <Icon className="w-5 h-5 flex-shrink-0 mt-0.5" />
      <div className="text-sm">{children}</div>
    </div>
  )
}

export default function TailscalePage() {
  return (
    <DocsLayout
      title="Tailscale Configuration"
      description="Tailscale creates a secure, private network between your devices. It's how your iPhone finds and connects to your Mac without any port forwarding or cloud relay."
      badge="Network Setup"
      badgeColor="blue"
      sections={sections}
    >
      {/* Why Tailscale */}
      <h2 id="why-tailscale">Why Tailscale?</h2>
      <p>
        Your Mac and iPhone need a way to talk to each other securely, even when they're on different networks. Tailscale solves this elegantly.
      </p>

      <div className="grid md:grid-cols-2 gap-4 my-6 not-prose">
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <Shield className="w-6 h-6 text-blue-500 mb-3" />
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">End-to-End Encrypted</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            All traffic between your devices is encrypted. Tailscale can't see your data.
          </p>
        </div>

        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <Globe className="w-6 h-6 text-emerald-500 mb-3" />
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">Works Anywhere</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Connect from any network — home, office, coffee shop, or cellular. No firewall configuration needed.
          </p>
        </div>
      </div>

      <InfoBox type="info">
        <strong>Privacy Note:</strong> Tailscale coordinates connections but never sees your actual data. Your voice recordings travel directly between your devices.
      </InfoBox>

      {/* How It Works */}
      <h2 id="how-it-works">How It Works</h2>
      <p>
        Tailscale gives each of your devices a stable IP address on a private network. They can always find each other, even when switching between WiFi and cellular.
      </p>

      <div className="bg-white dark:bg-zinc-900 rounded-xl border border-zinc-200 dark:border-zinc-800 p-6 my-6 not-prose">
        <div className="flex flex-col md:flex-row items-center justify-center gap-8">
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
      </div>

      {/* Setup Steps */}
      <h2 id="setup">Setup Steps</h2>

      <div className="space-y-2 my-6">
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
          </div>
          <p className="mt-3">
            Sign in with the same account you created. Your Mac will appear in your Tailscale network.
          </p>
        </Step>

        <Step number="3" title="Install Tailscale on Your iPhone">
          <p>Download Tailscale from the iOS App Store:</p>
          <a
            href="https://apps.apple.com/app/tailscale/id1470499037"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-4 py-2 mt-3 rounded-lg bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 text-sm font-medium hover:opacity-90 transition-opacity"
          >
            iOS App Store <ExternalLink className="w-3 h-3" />
          </a>
          <p className="mt-3">
            Sign in with the same account. Both devices are now on your private network.
          </p>
          <InfoBox type="success">
            <strong>You're connected!</strong> Your Mac and iPhone can now communicate securely over any network.
          </InfoBox>
        </Step>

        <Step number="4" title="Connect in Talkie">
          <p>
            Open Talkie Settings → iPhone and enable iPhone Sync. Talkie will detect Tailscale and display a QR code. Scan it with the Talkie iPhone app to pair.
          </p>
        </Step>
      </div>

      {/* Troubleshooting */}
      <h2 id="troubleshooting">Troubleshooting</h2>

      <div className="space-y-4 my-6 not-prose">
        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"Tailscale not running"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Open the Tailscale app from your menu bar and ensure it shows "Connected". If it says "Disconnected", click to reconnect.
          </p>
        </div>

        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"No peers found"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Make sure both devices are signed into the same Tailscale account. Check the Tailscale admin console at <a href="https://login.tailscale.com/admin/machines" className="text-blue-600 dark:text-blue-400 hover:underline">login.tailscale.com/admin</a> to verify.
          </p>
        </div>

        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"Connection timeout"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Some networks block UDP traffic. Try switching your iPhone to cellular data temporarily. If that works, your WiFi network may have restrictions.
          </p>
        </div>

        <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
          <h4 className="font-bold text-zinc-900 dark:text-white mb-2">"Needs login"</h4>
          <p className="text-sm text-zinc-600 dark:text-zinc-400">
            Your Tailscale session has expired. Open Tailscale and re-authenticate. This typically happens after extended periods of inactivity.
          </p>
        </div>
      </div>

      {/* Navigation */}
      <h2 id="navigation">Next Steps</h2>
      <div className="flex flex-col sm:flex-row gap-4 not-prose">
        <Link
          href="/docs/bridge-setup"
          className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-emerald-500 group-hover:-translate-x-1 transition-all" />
          <div>
            <span className="text-xs text-zinc-500">Previous</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
              TalkieServer Setup
            </span>
          </div>
        </Link>

        <Link
          href="/"
          className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
        >
          <div>
            <span className="text-xs text-zinc-500">Done?</span>
            <span className="block font-bold text-zinc-900 dark:text-white group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
              Back to Home
            </span>
          </div>
          <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-emerald-500 group-hover:translate-x-1 transition-all" />
        </Link>
      </div>
    </DocsLayout>
  )
}
