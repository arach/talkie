"use client"
import React from 'react'
import { Monitor, Mic, Cpu, Server, Smartphone, Watch } from 'lucide-react'

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
      ${isLarge ? 'px-6 py-4' : 'px-4 py-3'}
      shadow-sm bg-white/80 dark:bg-zinc-900/80 backdrop-blur-sm
      ${className}
    `}>
      <div className="flex items-center gap-3">
        <div className={`
          flex-shrink-0 rounded-lg
          ${isLarge ? 'w-11 h-11' : 'w-9 h-9'}
          flex items-center justify-center
          bg-white dark:bg-zinc-900 shadow-sm border border-zinc-200 dark:border-zinc-700
        `}>
          <Icon className={`${isLarge ? 'w-5 h-5' : 'w-4 h-4'} ${iconColors[color]}`} />
        </div>
        <div>
          <div className={`font-bold text-zinc-900 dark:text-white ${isLarge ? 'text-base' : 'text-sm'}`}>
            {name}
          </div>
          <div className="text-[10px] font-mono text-zinc-500 dark:text-zinc-400">
            {subtitle}
          </div>
        </div>
      </div>
      {description && (
        <div className={`mt-2 text-[11px] text-zinc-600 dark:text-zinc-400`}>
          {description}
        </div>
      )}
    </div>
  )
}

// Curved arrow path with label
const CurvedArrow = ({ d, label, labelPos, color = 'zinc' }) => {
  const colors = {
    zinc: 'stroke-zinc-400 dark:stroke-zinc-600',
    emerald: 'stroke-emerald-400 dark:stroke-emerald-500',
    blue: 'stroke-blue-400 dark:stroke-blue-500',
    amber: 'stroke-amber-400 dark:stroke-amber-500',
  }

  return (
    <g>
      {/* Main path */}
      <path
        d={d}
        fill="none"
        className={colors[color]}
        strokeWidth="1.5"
        strokeLinecap="round"
        markerEnd="url(#arrowhead)"
      />
      {/* Label */}
      <text
        x={labelPos.x}
        y={labelPos.y}
        textAnchor="middle"
        className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono"
      >
        {label}
      </text>
    </g>
  )
}

// Main Architecture Diagram with SVG curves
export default function ArchitectureDiagram() {
  return (
    <div className="my-8 p-4 md:p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="relative min-w-[580px] h-[420px]">
        {/* SVG layer for curved connections */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox="0 0 580 420"
          preserveAspectRatio="xMidYMid meet"
        >
          {/* Arrow marker definition */}
          <defs>
            <marker
              id="arrowhead"
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
              id="arrowhead-amber"
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
          </defs>

          {/* Curved path: Talkie → TalkieLive (left curve) */}
          <path
            d="M 200 95 C 200 130, 120 130, 120 175"
            fill="none"
            className="stroke-emerald-400/70 dark:stroke-emerald-500/70"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrowhead)"
          />
          <text x="140" y="140" textAnchor="middle" className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono">
            XPC
          </text>

          {/* Curved path: Talkie → TalkieEngine (center, slight curve) */}
          <path
            d="M 290 95 C 290 120, 290 150, 290 175"
            fill="none"
            className="stroke-blue-400/70 dark:stroke-blue-500/70"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrowhead)"
          />
          <text x="308" y="140" textAnchor="middle" className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono">
            XPC
          </text>

          {/* Curved path: Talkie → TalkieServer (right curve) */}
          <path
            d="M 380 95 C 380 130, 460 130, 460 175"
            fill="none"
            className="stroke-amber-400/70 dark:stroke-amber-500/70"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrowhead)"
          />
          <text x="440" y="140" textAnchor="middle" className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono">
            HTTP
          </text>

          {/* Curved path: TalkieServer → iPhone (S-curve down-right) */}
          <path
            d="M 460 270 C 460 300, 420 320, 420 350"
            fill="none"
            className="stroke-zinc-400/70 dark:stroke-zinc-500/70"
            strokeWidth="2"
            strokeLinecap="round"
            markerEnd="url(#arrowhead)"
          />
          <text x="455" y="310" textAnchor="middle" className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono">
            Tailscale
          </text>

          {/* Curved path: iPhone → Watch (small connector) */}
          <path
            d="M 450 380 C 470 380, 480 380, 500 380"
            fill="none"
            className="stroke-zinc-300/70 dark:stroke-zinc-600/70"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeDasharray="4 2"
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

        {/* Helper processes row */}
        <div className="absolute top-[180px] left-[30px]">
          <ProcessBox
            icon={Mic}
            name="TalkieLive"
            subtitle="Swift"
            description="Ears & Hands"
            color="emerald"
          />
        </div>

        <div className="absolute top-[180px] left-1/2 -translate-x-1/2">
          <ProcessBox
            icon={Cpu}
            name="TalkieEngine"
            subtitle="Swift"
            description="Local Brain"
            color="blue"
          />
        </div>

        <div className="absolute top-[180px] right-[30px]">
          <ProcessBox
            icon={Server}
            name="TalkieServer"
            subtitle="TypeScript"
            description="iOS Bridge"
            color="amber"
          />
        </div>

        {/* Mobile devices */}
        <div className="absolute bottom-[10px] right-[120px]">
          <ProcessBox
            icon={Smartphone}
            name="iPhone"
            subtitle="iOS"
            description="Voice Capture"
            color="zinc"
          />
        </div>

        <div className="absolute bottom-[10px] right-[10px]">
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

// Simpler horizontal flow diagram for overview page
export function SimpleArchitectureDiagram() {
  return (
    <div className="my-8 p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="relative min-w-[500px] h-[100px]">
        {/* SVG for curved connections */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox="0 0 500 100"
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
              <stop offset="0%" className="[stop-color:rgb(139,92,246)]" stopOpacity="0.6" />
              <stop offset="50%" className="[stop-color:rgb(16,185,129)]" stopOpacity="0.6" />
              <stop offset="100%" className="[stop-color:rgb(113,113,122)]" stopOpacity="0.6" />
            </linearGradient>
          </defs>

          {/* Flowing curve from Talkie through helpers to iPhone */}
          <path
            d="M 70 50 C 100 50, 110 50, 140 50
               L 160 50
               C 190 50, 200 30, 220 30
               C 240 30, 250 50, 280 50
               C 310 50, 320 70, 340 70
               C 360 70, 370 50, 400 50
               L 430 50"
            fill="none"
            stroke="url(#flowGradient)"
            strokeWidth="2"
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
        <div className="absolute left-[140px] top-1/2 -translate-y-1/2 flex gap-2">
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
        <div className="absolute right-[60px] top-1/2 -translate-y-1/2 flex gap-2">
          <div className="flex flex-col items-center">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-zinc-100 to-zinc-50 dark:from-zinc-700 dark:to-zinc-800 border-2 border-zinc-300 dark:border-zinc-600 flex items-center justify-center shadow-sm">
              <Smartphone className="w-4 h-4 text-zinc-600 dark:text-zinc-400" />
            </div>
            <span className="mt-1 text-[9px] font-medium text-zinc-600 dark:text-zinc-400">iPhone</span>
          </div>
          <div className="flex flex-col items-center">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-zinc-100 to-zinc-50 dark:from-zinc-700 dark:to-zinc-800 border-2 border-zinc-300 dark:border-zinc-600 flex items-center justify-center shadow-sm">
              <Watch className="w-4 h-4 text-zinc-600 dark:text-zinc-400" />
            </div>
            <span className="mt-1 text-[9px] font-medium text-zinc-600 dark:text-zinc-400">Watch</span>
          </div>
        </div>
      </div>
    </div>
  )
}
