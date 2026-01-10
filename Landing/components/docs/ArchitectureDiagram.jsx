"use client"
import React from 'react'
import { Monitor, Mic, Cpu, Server, Smartphone, Watch, Cloud } from 'lucide-react'

// Process box component
const ProcessBox = ({
  icon: Icon,
  name,
  subtitle,
  description,
  color = 'violet',
  size = 'normal',
  className = ''
}) => {
  const colors = {
    violet: 'border-violet-300 dark:border-violet-500/40 bg-gradient-to-br from-violet-50 to-violet-100/50 dark:from-violet-500/10 dark:to-violet-500/5',
    emerald: 'border-emerald-300 dark:border-emerald-500/40 bg-gradient-to-br from-emerald-50 to-emerald-100/50 dark:from-emerald-500/10 dark:to-emerald-500/5',
    blue: 'border-blue-300 dark:border-blue-500/40 bg-gradient-to-br from-blue-50 to-blue-100/50 dark:from-blue-500/10 dark:to-blue-500/5',
    amber: 'border-amber-300 dark:border-amber-500/40 bg-gradient-to-br from-amber-50 to-amber-100/50 dark:from-amber-500/10 dark:to-amber-500/5',
    zinc: 'border-zinc-300 dark:border-zinc-600 bg-gradient-to-br from-zinc-50 to-zinc-100/50 dark:from-zinc-800/50 dark:to-zinc-800/30',
    sky: 'border-sky-300 dark:border-sky-500/40 bg-gradient-to-br from-sky-50 to-sky-100/50 dark:from-sky-500/10 dark:to-sky-500/5',
  }

  const iconColors = {
    violet: 'text-violet-600 dark:text-violet-400',
    emerald: 'text-emerald-600 dark:text-emerald-400',
    blue: 'text-blue-600 dark:text-blue-400',
    amber: 'text-amber-600 dark:text-amber-400',
    zinc: 'text-zinc-600 dark:text-zinc-400',
    sky: 'text-sky-600 dark:text-sky-400',
  }

  const isLarge = size === 'large'
  const isSmall = size === 'small'

  return (
    <div className={`
      relative rounded-xl border-2 ${colors[color]}
      ${isLarge ? 'px-6 py-4' : isSmall ? 'px-3 py-2' : 'px-4 py-3'}
      shadow-sm bg-white/80 dark:bg-zinc-900/80 backdrop-blur-sm
      ${className}
    `}>
      <div className="flex items-center gap-3">
        <div className={`
          flex-shrink-0 rounded-lg
          ${isLarge ? 'w-11 h-11' : isSmall ? 'w-7 h-7' : 'w-9 h-9'}
          flex items-center justify-center
          bg-white dark:bg-zinc-900 shadow-sm border border-zinc-200 dark:border-zinc-700
        `}>
          <Icon className={`${isLarge ? 'w-5 h-5' : isSmall ? 'w-3.5 h-3.5' : 'w-4 h-4'} ${iconColors[color]}`} />
        </div>
        <div>
          <div className={`font-bold text-zinc-900 dark:text-white ${isLarge ? 'text-base' : isSmall ? 'text-xs' : 'text-sm'}`}>
            {name}
          </div>
          <div className={`font-mono text-zinc-500 dark:text-zinc-400 ${isSmall ? 'text-[8px]' : 'text-[10px]'}`}>
            {subtitle}
          </div>
        </div>
      </div>
      {description && (
        <div className={`mt-2 text-zinc-600 dark:text-zinc-400 ${isSmall ? 'text-[9px]' : 'text-[11px]'}`}>
          {description}
        </div>
      )}
    </div>
  )
}

// Main Architecture Diagram with SVG curves
export default function ArchitectureDiagram() {
  // Box positions (centers) - calculated for 620px width viewBox
  // TalkieLive: left-[20px], ~150px wide → center at 95px
  // TalkieEngine: centered → center at 310px
  // TalkieServer: right-[20px] → center at 525px
  // iPhone: positioned between TalkieServer and center → ~400px

  return (
    <div className="my-8 p-4 md:p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="relative min-w-[620px] h-[420px]">
        {/* SVG layer for curved connections */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox="0 0 620 420"
          preserveAspectRatio="xMidYMid meet"
        >
          {/* Arrow marker definitions - color matched */}
          <defs>
            <marker
              id="arrow-emerald"
              markerWidth="8"
              markerHeight="6"
              refX="7"
              refY="3"
              orient="auto"
            >
              <polygon
                points="0 0, 8 3, 0 6"
                className="fill-emerald-400 dark:fill-emerald-500"
              />
            </marker>
            <marker
              id="arrow-blue"
              markerWidth="8"
              markerHeight="6"
              refX="7"
              refY="3"
              orient="auto"
            >
              <polygon
                points="0 0, 8 3, 0 6"
                className="fill-blue-400 dark:fill-blue-500"
              />
            </marker>
            <marker
              id="arrow-amber"
              markerWidth="8"
              markerHeight="6"
              refX="7"
              refY="3"
              orient="auto"
            >
              <polygon
                points="0 0, 8 3, 0 6"
                className="fill-amber-400 dark:fill-amber-500"
              />
            </marker>
            <marker
              id="arrow-zinc"
              markerWidth="8"
              markerHeight="6"
              refX="7"
              refY="3"
              orient="auto"
            >
              <polygon
                points="0 0, 8 3, 0 6"
                className="fill-zinc-400 dark:fill-zinc-500"
              />
            </marker>
            <marker
              id="arrow-sky"
              markerWidth="8"
              markerHeight="6"
              refX="7"
              refY="3"
              orient="auto"
            >
              <polygon
                points="0 0, 8 3, 0 6"
                className="fill-sky-400 dark:fill-sky-500"
              />
            </marker>
          </defs>

          {/* === XPC connections from Talkie to helpers === */}

          {/* Talkie → TalkieLive (left curve)
              Start: bottom-left area of Talkie
              End: top-center of TalkieLive (x=95) */}
          <path
            d="M 220 95
               C 220 130, 95 130, 95 170"
            fill="none"
            className="stroke-emerald-400 dark:stroke-emerald-500"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrow-emerald)"
          />
          <text x="140" y="118" textAnchor="middle" className="fill-emerald-600 dark:fill-emerald-400 text-[10px] font-mono font-medium">
            XPC
          </text>

          {/* Talkie → TalkieEngine (center, slight curve)
              Start: bottom-center of Talkie
              End: top-center of TalkieEngine (x=310) */}
          <path
            d="M 310 95
               C 310 130, 310 130, 310 170"
            fill="none"
            className="stroke-blue-400 dark:stroke-blue-500"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrow-blue)"
          />
          <text x="328" y="135" textAnchor="start" className="fill-blue-600 dark:fill-blue-400 text-[10px] font-mono font-medium">
            XPC
          </text>

          {/* Talkie → TalkieServer (right curve)
              Start: bottom-right area of Talkie
              End: top-center of TalkieServer (x=525) */}
          <path
            d="M 400 95
               C 400 130, 525 130, 525 170"
            fill="none"
            className="stroke-amber-400 dark:stroke-amber-500"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrow-amber)"
          />
          <text x="480" y="118" textAnchor="middle" className="fill-amber-600 dark:fill-amber-400 text-[10px] font-mono font-medium">
            HTTP
          </text>

          {/* === TalkieLive ↔ TalkieEngine (heavy communication) === */}
          {/* This is the bulk of transcription traffic */}
          <path
            d="M 170 210 L 235 210"
            fill="none"
            className="stroke-emerald-400/60 dark:stroke-emerald-500/60"
            strokeWidth="3"
            strokeLinecap="round"
            markerEnd="url(#arrow-emerald)"
          />
          <text x="203" y="228" textAnchor="middle" className="fill-emerald-600/80 dark:fill-emerald-400/80 text-[9px] font-mono">
            audio
          </text>

          {/* === TalkieServer → iPhone === */}
          <path
            d="M 525 265
               C 525 300, 400 300, 400 335"
            fill="none"
            className="stroke-zinc-400 dark:stroke-zinc-500"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrow-zinc)"
          />
          <text x="480" y="295" textAnchor="middle" className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono font-medium">
            Tailscale
          </text>

          {/* === iCloud sync connections === */}

          {/* Talkie → iCloud */}
          <path
            d="M 420 45
               C 470 45, 520 35, 555 35"
            fill="none"
            className="stroke-sky-400 dark:stroke-sky-500"
            strokeWidth="2"
            strokeLinecap="round"
            strokeDasharray="6 3"
            markerEnd="url(#arrow-sky)"
          />

          {/* iPhone → iCloud */}
          <path
            d="M 430 335
               C 500 310, 560 200, 570 80"
            fill="none"
            className="stroke-sky-400 dark:stroke-sky-500"
            strokeWidth="2"
            strokeLinecap="round"
            strokeDasharray="6 3"
            markerEnd="url(#arrow-sky)"
          />
          <text x="530" y="200" textAnchor="middle" className="fill-sky-600 dark:fill-sky-400 text-[10px] font-mono font-medium">
            CloudKit
          </text>

          {/* iPhone → Watch (subordinate) */}
          <path
            d="M 440 375 L 475 375"
            fill="none"
            className="stroke-zinc-300 dark:stroke-zinc-600"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeDasharray="3 2"
          />
        </svg>

        {/* Process boxes positioned absolutely */}

        {/* Main Talkie app - centered at top */}
        <div className="absolute left-1/2 -translate-x-1/2 top-0">
          <ProcessBox
            icon={Monitor}
            name="Talkie"
            subtitle="Swift/SwiftUI"
            description="UI • Workflows • Data • Orchestration"
            color="violet"
            size="large"
          />
        </div>

        {/* iCloud - top right */}
        <div className="absolute right-[20px] top-[10px]">
          <ProcessBox
            icon={Cloud}
            name="iCloud"
            subtitle="CloudKit"
            color="sky"
            size="small"
          />
        </div>

        {/* Helper processes row - all at top-[175px] */}
        <div className="absolute top-[175px] left-[20px]">
          <ProcessBox
            icon={Mic}
            name="TalkieLive"
            subtitle="Swift"
            description="Ears & Hands"
            color="emerald"
          />
        </div>

        <div className="absolute top-[175px] left-1/2 -translate-x-1/2">
          <ProcessBox
            icon={Cpu}
            name="TalkieEngine"
            subtitle="Swift"
            description="Local Brain"
            color="blue"
          />
        </div>

        <div className="absolute top-[175px] right-[20px]">
          <ProcessBox
            icon={Server}
            name="TalkieServer"
            subtitle="TypeScript"
            description="iOS Bridge"
            color="amber"
          />
        </div>

        {/* Mobile section - iPhone positioned between Talkie center and TalkieServer */}
        <div className="absolute bottom-[30px] left-1/2 translate-x-[20px]">
          <div className="flex items-end gap-3">
            {/* iPhone - primary */}
            <ProcessBox
              icon={Smartphone}
              name="iPhone"
              subtitle="iOS"
              description="Voice Capture"
              color="zinc"
            />
            {/* Watch - subordinate, smaller */}
            <div className="pb-1">
              <ProcessBox
                icon={Watch}
                name="Watch"
                subtitle="watchOS"
                color="zinc"
                size="small"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// Simpler horizontal flow diagram for overview page
export function SimpleArchitectureDiagram() {
  return (
    <div className="my-8 p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="relative min-w-[520px] h-[100px]">
        {/* SVG for curved connections */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox="0 0 520 100"
          preserveAspectRatio="xMidYMid meet"
        >
          <defs>
            <marker
              id="arrow-simple"
              markerWidth="6"
              markerHeight="5"
              refX="5"
              refY="2.5"
              orient="auto"
            >
              <polygon
                points="0 0, 6 2.5, 0 5"
                className="fill-zinc-400 dark:fill-zinc-500"
              />
            </marker>
            {/* Gradient for the flow */}
            <linearGradient id="flowGradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" className="[stop-color:rgb(139,92,246)]" stopOpacity="0.7" />
              <stop offset="40%" className="[stop-color:rgb(16,185,129)]" stopOpacity="0.7" />
              <stop offset="70%" className="[stop-color:rgb(245,158,11)]" stopOpacity="0.7" />
              <stop offset="100%" className="[stop-color:rgb(113,113,122)]" stopOpacity="0.7" />
            </linearGradient>
          </defs>

          {/* Flowing S-curve from Talkie through helpers to iPhone */}
          <path
            d="M 75 50
               C 95 50, 105 50, 125 50
               Q 145 50, 160 35
               Q 175 20, 195 30
               Q 215 40, 230 50
               Q 245 60, 265 60
               Q 285 60, 305 50
               C 340 35, 370 50, 420 50"
            fill="none"
            stroke="url(#flowGradient)"
            strokeWidth="2.5"
            strokeLinecap="round"
            markerEnd="url(#arrow-simple)"
          />
        </svg>

        {/* Boxes */}
        <div className="absolute left-0 top-1/2 -translate-y-1/2 flex flex-col items-center">
          <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-violet-100 to-violet-50 dark:from-violet-500/20 dark:to-violet-500/10 border-2 border-violet-300 dark:border-violet-500/40 flex items-center justify-center shadow-sm">
            <Monitor className="w-7 h-7 text-violet-600 dark:text-violet-400" />
          </div>
          <span className="mt-1.5 text-xs font-bold text-zinc-900 dark:text-white">Talkie</span>
        </div>

        {/* Helper cluster */}
        <div className="absolute left-[130px] top-1/2 -translate-y-1/2 flex gap-2">
          <div className="flex flex-col items-center">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-100 to-emerald-50 dark:from-emerald-500/20 dark:to-emerald-500/10 border-2 border-emerald-300 dark:border-emerald-500/40 flex items-center justify-center shadow-sm">
              <Mic className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
            </div>
            <span className="mt-1 text-[9px] font-medium text-zinc-600 dark:text-zinc-400">Live</span>
          </div>
          <div className="flex flex-col items-center">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-blue-100 to-blue-50 dark:from-blue-500/20 dark:to-blue-500/10 border-2 border-blue-300 dark:border-blue-500/40 flex items-center justify-center shadow-sm">
              <Cpu className="w-4 h-4 text-blue-600 dark:text-blue-400" />
            </div>
            <span className="mt-1 text-[9px] font-medium text-zinc-600 dark:text-zinc-400">Engine</span>
          </div>
          <div className="flex flex-col items-center">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-amber-100 to-amber-50 dark:from-amber-500/20 dark:to-amber-500/10 border-2 border-amber-300 dark:border-amber-500/40 flex items-center justify-center shadow-sm">
              <Server className="w-4 h-4 text-amber-600 dark:text-amber-400" />
            </div>
            <span className="mt-1 text-[9px] font-medium text-zinc-600 dark:text-zinc-400">Server</span>
          </div>
        </div>

        {/* Mobile devices */}
        <div className="absolute right-[30px] top-1/2 -translate-y-1/2 flex items-end gap-1.5">
          <div className="flex flex-col items-center">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-zinc-100 to-zinc-50 dark:from-zinc-700 dark:to-zinc-800 border-2 border-zinc-300 dark:border-zinc-600 flex items-center justify-center shadow-sm">
              <Smartphone className="w-4 h-4 text-zinc-600 dark:text-zinc-400" />
            </div>
            <span className="mt-1 text-[9px] font-medium text-zinc-600 dark:text-zinc-400">iPhone</span>
          </div>
          <div className="flex flex-col items-center mb-0.5">
            <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-zinc-100 to-zinc-50 dark:from-zinc-700 dark:to-zinc-800 border border-zinc-300 dark:border-zinc-600 flex items-center justify-center shadow-sm">
              <Watch className="w-3 h-3 text-zinc-500 dark:text-zinc-500" />
            </div>
          </div>
        </div>

        {/* iCloud indicator */}
        <div className="absolute right-0 top-0">
          <div className="flex items-center gap-1 px-2 py-1 rounded-full bg-sky-50 dark:bg-sky-500/10 border border-sky-200 dark:border-sky-500/30">
            <Cloud className="w-3 h-3 text-sky-500" />
            <span className="text-[8px] font-medium text-sky-600 dark:text-sky-400">iCloud</span>
          </div>
        </div>
      </div>
    </div>
  )
}
