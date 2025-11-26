import React from 'react'

export default function HeroBadge() {
  return (
    <div className="inline-flex items-center gap-2 rounded-[10px] border border-zinc-200/70 dark:border-zinc-800/70 bg-white/80 dark:bg-zinc-900/80 backdrop-blur px-3.5 py-1.5 shadow-[0_1px_0_rgba(255,255,255,0.4)_inset,0_2px_10px_rgba(0,0,0,0.06)]">
      <span className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.55)]" />
      <span className="font-mono text-[10px] font-bold uppercase tracking-[0.22em] text-zinc-700 dark:text-zinc-300 whitespace-nowrap">
        Native on iOS & macOS
      </span>
    </div>
  )
}

