"use client"
import React, { useEffect } from 'react'
import Link from 'next/link'
import { ArrowLeft, ShieldCheck, Database, Cloud, FileText, Key, Eye, Lock, Server, Cpu, HardDrive } from 'lucide-react'
import { SecurityInfographic } from './SecurityInfographic'

const SecurityFeature = ({ icon: Icon, title, subtitle, description }) => (
  <div className="group relative p-6 bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 hover:border-zinc-400 dark:hover:border-zinc-600 transition-all">
    <div className="absolute top-0 right-0 w-8 h-8 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
        <div className="w-2 h-2 border-t border-r border-zinc-400 dark:border-zinc-500"></div>
    </div>

    <div className="mb-4 inline-flex items-center justify-center w-10 h-10 rounded bg-zinc-100 dark:bg-zinc-800 text-zinc-900 dark:text-white group-hover:bg-emerald-500/10 group-hover:text-emerald-600 dark:group-hover:text-emerald-400 transition-colors">
      <Icon className="w-5 h-5" strokeWidth={1.5} />
    </div>

    <div className="mb-2">
        <h3 className="text-sm font-bold uppercase tracking-wide text-zinc-900 dark:text-white">{title}</h3>
        <p className="text-[10px] font-mono text-emerald-600 dark:text-emerald-500 uppercase tracking-wider mt-1">{subtitle}</p>
    </div>

    <p className="text-xs text-zinc-600 dark:text-zinc-400 leading-relaxed">
      {description}
    </p>
  </div>
)

export default function SecurityPage() {
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 font-sans selection:bg-zinc-900 selection:text-white dark:selection:bg-white dark:selection:text-black">

      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <div className="mx-auto max-w-6xl px-6 h-14 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            BACK
          </Link>

          <div className="flex items-center gap-3">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">SECURITY & SOVEREIGNTY</span>
          </div>
        </div>
      </nav>

      <main className="pt-32 pb-32 px-6">
        <div className="mx-auto max-w-6xl">

          {/* Hero */}
          <div className="max-w-3xl mb-16">
            <h1 className="text-4xl md:text-6xl font-bold tracking-tighter text-zinc-900 dark:text-white uppercase mb-6 leading-[0.9]">
              Privacy is not a setting.<br/>
              It&apos;s the architecture.
            </h1>
            <p className="text-lg text-zinc-600 dark:text-zinc-400 leading-relaxed max-w-2xl border-l-2 border-emerald-500 pl-6">
              Talkie is built on a &quot;Local-First&quot; doctrine. We do not own servers that store your data. We do not train on your ideas. You own the keys, the database, and the AI models.
            </p>
          </div>

          {/* Architecture Visual */}
          <section className="mb-24">
            <SecurityInfographic />
          </section>

          {/* Deep Dive Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-24">

            <SecurityFeature
              icon={HardDrive}
              title="Local-First Storage"
              subtitle="SQLite Database"
              description="Your data lives in a local SQLite database file on your device's encrypted disk. It is not just 'cached' locally; it is authoritative locally. Deleting the app deletes the data."
            />

            <SecurityFeature
              icon={Cloud}
              title="Apple iCloud Sync"
              subtitle="Zero-Knowledge Architecture"
              description="We use Apple's CloudKit for sync. Your data is encrypted with keys managed by your Apple ID. We (Talkie Systems) have no access to these keys and cannot decrypt your data."
            />

            <SecurityFeature
              icon={Cpu}
              title="On-Device Intelligence"
              subtitle="CoreML & MLX"
              description="Transcriptions occur 100% on-device using the Neural Engine. You can also download local LLMs (Llama 3, Mistral) to run full AI workflows without a single packet leaving your Mac."
            />

            <SecurityFeature
              icon={Lock}
              title="Sanitization Barrier"
              subtitle="Selective Disclosure"
              description="When using external models (like GPT-4), audio never leaves your device. Only the specific text prompt you construct is sent. You can redact PII before dispatch."
            />

            <SecurityFeature
              icon={Eye}
              title="Audit Trails"
              subtitle="Full Transparency"
              description="Every network request initiated by a workflow is logged in a local, immutable audit trail. You can inspect exactly what text was sent to which API and when."
            />

             <SecurityFeature
              icon={Key}
              title="BYO API Keys"
              subtitle="Secure Keychain Storage"
              description="If you use OpenAI or Anthropic, you bring your own keys. They are stored in the macOS Keychain/Secure Enclave and are only accessed at runtime to sign requests."
            />

          </div>

          {/* Comparison Table */}
          <div className="border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-950 rounded-sm overflow-hidden">
             <div className="grid grid-cols-3 border-b border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900/50 text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-500 p-4">
                <div>Feature</div>
                <div>Talkie OS</div>
                <div>Standard AI Apps</div>
             </div>

             {[
               { feature: "Audio Processing", talkie: "Local (Neural Engine)", other: "Cloud Server" },
               { feature: "Database Location", talkie: "Local Disk + iCloud", other: "Vendor's Cloud SQL" },
               { feature: "Offline Access", talkie: "100% Full Functionality", other: "Limited / None" },
               { feature: "Model Training", talkie: "Never", other: "Default Opt-in" },
               { feature: "API Key Ownership", talkie: "User Owned", other: "Vendor Owned" },
             ].map((row, i) => (
                <div key={i} className="grid grid-cols-3 border-b last:border-0 border-zinc-100 dark:border-zinc-800/50 p-4 text-xs">
                   <div className="font-bold text-zinc-900 dark:text-white">{row.feature}</div>
                   <div className="text-emerald-600 dark:text-emerald-500 font-medium flex items-center gap-2">
                      <span className="w-1.5 h-1.5 bg-emerald-500 rounded-full"></span> {row.talkie}
                   </div>
                   <div className="text-zinc-500">{row.other}</div>
                </div>
             ))}
          </div>

          <div className="mt-24 text-center">
             <div className="inline-flex flex-col items-center p-8 bg-zinc-100 dark:bg-zinc-900/50 border border-zinc-200 dark:border-zinc-800 rounded-sm">
                <Server className="w-8 h-8 text-zinc-400 mb-4" />
                <h3 className="text-lg font-bold text-zinc-900 dark:text-white uppercase mb-2">We don&apos;t want your data.</h3>
                <p className="text-sm text-zinc-500 max-w-md mx-auto">
                  Running a secure cloud is hard. We chose not to. By architecture, we cannot see your memos, your transcripts, or your thoughts.
                </p>
             </div>
          </div>

        </div>
      </main>
    </div>
  )
}
