"use client"
import React from 'react'
import { Monitor, Mic, Cpu, Server, Smartphone, Watch } from 'lucide-react'

// Connection line component
const Connection = ({ label, direction = 'down', className = '' }) => {
  const isHorizontal = direction === 'right' || direction === 'left'

  return (
    <div className={`flex ${isHorizontal ? 'flex-row items-center' : 'flex-col items-center'} ${className}`}>
      {!isHorizontal && (
        <>
          <div className="w-px h-6 bg-gradient-to-b from-zinc-400 to-zinc-500 dark:from-zinc-600 dark:to-zinc-500" />
          <div className="text-[10px] font-mono text-zinc-500 dark:text-zinc-400 py-1">{label}</div>
          <svg className="w-3 h-3 text-zinc-500" viewBox="0 0 12 12" fill="none">
            <path d="M6 0V9M6 9L2 5M6 9L10 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </>
      )}
      {isHorizontal && (
        <>
          <div className="h-px w-8 bg-gradient-to-r from-zinc-400 to-zinc-500 dark:from-zinc-600 dark:to-zinc-500" />
          <div className="text-[10px] font-mono text-zinc-500 dark:text-zinc-400 px-2">{label}</div>
          <svg className="w-3 h-3 text-zinc-500 rotate-[-90deg]" viewBox="0 0 12 12" fill="none">
            <path d="M6 0V9M6 9L2 5M6 9L10 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </>
      )}
    </div>
  )
}

// Process box component
const ProcessBox = ({
  icon: Icon,
  name,
  subtitle,
  description,
  color = 'violet',
  size = 'normal'
}) => {
  const colors = {
    violet: 'border-violet-300 dark:border-violet-500/40 bg-gradient-to-br from-violet-50 to-violet-100/50 dark:from-violet-500/10 dark:to-violet-500/5',
    emerald: 'border-emerald-300 dark:border-emerald-500/40 bg-gradient-to-br from-emerald-50 to-emerald-100/50 dark:from-emerald-500/10 dark:to-emerald-500/5',
    blue: 'border-blue-300 dark:border-blue-500/40 bg-gradient-to-br from-blue-50 to-blue-100/50 dark:from-blue-500/10 dark:to-blue-500/5',
    amber: 'border-amber-300 dark:border-amber-500/40 bg-gradient-to-br from-amber-50 to-amber-100/50 dark:from-amber-500/10 dark:to-amber-500/5',
    zinc: 'border-zinc-300 dark:border-zinc-600 bg-gradient-to-br from-zinc-50 to-zinc-100/50 dark:from-zinc-800/50 dark:to-zinc-800/30',
  }

  const iconColors = {
    violet: 'text-violet-600 dark:text-violet-400',
    emerald: 'text-emerald-600 dark:text-emerald-400',
    blue: 'text-blue-600 dark:text-blue-400',
    amber: 'text-amber-600 dark:text-amber-400',
    zinc: 'text-zinc-600 dark:text-zinc-400',
  }

  const isLarge = size === 'large'

  return (
    <div className={`
      relative rounded-xl border-2 ${colors[color]}
      ${isLarge ? 'px-8 py-6' : 'px-4 py-3'}
      shadow-sm
    `}>
      <div className="flex items-center gap-3">
        <div className={`
          flex-shrink-0 rounded-lg
          ${isLarge ? 'w-12 h-12' : 'w-10 h-10'}
          flex items-center justify-center
          bg-white dark:bg-zinc-900 shadow-sm border border-zinc-200 dark:border-zinc-700
        `}>
          <Icon className={`${isLarge ? 'w-6 h-6' : 'w-5 h-5'} ${iconColors[color]}`} />
        </div>
        <div>
          <div className={`font-bold text-zinc-900 dark:text-white ${isLarge ? 'text-lg' : 'text-sm'}`}>
            {name}
          </div>
          <div className="text-[11px] font-mono text-zinc-500 dark:text-zinc-400">
            {subtitle}
          </div>
        </div>
      </div>
      {description && (
        <div className={`mt-3 text-xs text-zinc-600 dark:text-zinc-400 ${isLarge ? 'text-sm' : ''}`}>
          {description}
        </div>
      )}
    </div>
  )
}

// Main Architecture Diagram
export default function ArchitectureDiagram() {
  return (
    <div className="my-8 p-6 md:p-8 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="min-w-[600px]">
        {/* Main App */}
        <div className="flex justify-center mb-2">
          <ProcessBox
            icon={Monitor}
            name="Talkie"
            subtitle="Swift/SwiftUI"
            description="UI • Workflows • Data • Orchestration"
            color="violet"
            size="large"
          />
        </div>

        {/* Connection arrows from main app */}
        <div className="flex justify-center gap-24 mb-2">
          <Connection label="XPC" />
          <Connection label="XPC" />
          <Connection label="HTTP" />
        </div>

        {/* Helper processes row */}
        <div className="flex justify-center gap-4 mb-6">
          <ProcessBox
            icon={Mic}
            name="TalkieLive"
            subtitle="Swift"
            description="Ears & Hands"
            color="emerald"
          />
          <ProcessBox
            icon={Cpu}
            name="TalkieEngine"
            subtitle="Swift"
            description="Local Brain"
            color="blue"
          />
          <ProcessBox
            icon={Server}
            name="TalkieServer"
            subtitle="TypeScript"
            description="iOS Bridge"
            color="amber"
          />
        </div>

        {/* Tailscale connection */}
        <div className="flex justify-end pr-[72px]">
          <Connection label="Tailscale" />
        </div>

        {/* Mobile devices */}
        <div className="flex justify-end gap-4 pr-8">
          <ProcessBox
            icon={Smartphone}
            name="iPhone"
            subtitle="iOS"
            description="Voice Capture"
            color="zinc"
          />
          <ProcessBox
            icon={Watch}
            name="Watch"
            subtitle="watchOS"
            description="Quick Capture"
            color="zinc"
          />
        </div>
      </div>
    </div>
  )
}

// Simpler data flow diagram for overview page
export function SimpleArchitectureDiagram() {
  return (
    <div className="my-8 p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800">
      <div className="flex flex-col md:flex-row items-center justify-center gap-6 md:gap-8">
        {/* Main App */}
        <div className="flex flex-col items-center">
          <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-violet-100 to-violet-50 dark:from-violet-500/20 dark:to-violet-500/10 border-2 border-violet-300 dark:border-violet-500/40 flex items-center justify-center shadow-sm">
            <Monitor className="w-8 h-8 text-violet-600 dark:text-violet-400" />
          </div>
          <span className="mt-2 text-sm font-bold text-zinc-900 dark:text-white">Talkie</span>
          <span className="text-[10px] text-zinc-500">Mac App</span>
        </div>

        {/* Arrow */}
        <div className="flex items-center gap-2 rotate-90 md:rotate-0">
          <div className="h-px w-12 bg-gradient-to-r from-violet-400 to-emerald-400" />
          <svg className="w-3 h-3 text-emerald-500 -rotate-90" viewBox="0 0 12 12" fill="none">
            <path d="M6 0V9M6 9L2 5M6 9L10 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </div>

        {/* Helper processes */}
        <div className="flex gap-3">
          <div className="flex flex-col items-center">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-emerald-100 to-emerald-50 dark:from-emerald-500/20 dark:to-emerald-500/10 border-2 border-emerald-300 dark:border-emerald-500/40 flex items-center justify-center shadow-sm">
              <Mic className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
            </div>
            <span className="mt-1 text-[10px] font-medium text-zinc-700 dark:text-zinc-300">Live</span>
          </div>
          <div className="flex flex-col items-center">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-blue-100 to-blue-50 dark:from-blue-500/20 dark:to-blue-500/10 border-2 border-blue-300 dark:border-blue-500/40 flex items-center justify-center shadow-sm">
              <Cpu className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            </div>
            <span className="mt-1 text-[10px] font-medium text-zinc-700 dark:text-zinc-300">Engine</span>
          </div>
          <div className="flex flex-col items-center">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-amber-100 to-amber-50 dark:from-amber-500/20 dark:to-amber-500/10 border-2 border-amber-300 dark:border-amber-500/40 flex items-center justify-center shadow-sm">
              <Server className="w-5 h-5 text-amber-600 dark:text-amber-400" />
            </div>
            <span className="mt-1 text-[10px] font-medium text-zinc-700 dark:text-zinc-300">Server</span>
          </div>
        </div>

        {/* Arrow to mobile */}
        <div className="flex items-center gap-2 rotate-90 md:rotate-0">
          <div className="h-px w-8 bg-gradient-to-r from-amber-400 to-zinc-400" />
          <svg className="w-3 h-3 text-zinc-500 -rotate-90" viewBox="0 0 12 12" fill="none">
            <path d="M6 0V9M6 9L2 5M6 9L10 5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </div>

        {/* Mobile */}
        <div className="flex flex-col items-center">
          <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-zinc-100 to-zinc-50 dark:from-zinc-700 dark:to-zinc-800 border-2 border-zinc-300 dark:border-zinc-600 flex items-center justify-center shadow-sm">
            <Smartphone className="w-5 h-5 text-zinc-600 dark:text-zinc-400" />
          </div>
          <span className="mt-1 text-[10px] font-medium text-zinc-700 dark:text-zinc-300">iPhone</span>
        </div>
      </div>
    </div>
  )
}
