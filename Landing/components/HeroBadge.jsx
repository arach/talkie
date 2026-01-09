import React from 'react'

export default function HeroBadge() {
  return (
    <div className="group/badge inline-flex items-center gap-2.5 rounded-full border border-emerald-500/20 bg-emerald-500/5 dark:bg-emerald-500/10 backdrop-blur px-4 py-2 cursor-default transition-all hover:border-emerald-500/40 hover:bg-emerald-500/10 dark:hover:bg-emerald-500/15">
      <span className="relative flex h-2 w-2">
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
        <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.6)]"></span>
      </span>
      <span className="text-xs font-medium text-emerald-600 dark:text-emerald-400 whitespace-nowrap">
        Available Now
      </span>
    </div>
  )
}
