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
// Layout (three rows, balanced):
//   Row 1: Talkie (left) ──HTTP──► TalkieServer (right)
//   Row 2: TalkieLive → TalkieEngine (left)    iCloud (center)    iPhone (right)
//   Row 3: (empty left)                                           Watch (right)
// Connections:
//   - Talkie → TalkieLive (XPC, vertical)
//   - Talkie → TalkieEngine (XPC, diagonal)
//   - TalkieLive → TalkieEngine (audio, horizontal)
//   - TalkieServer → iPhone (Tailscale, vertical)
//   - Talkie → iCloud (CloudKit, dashed)
//   - iPhone → iCloud (CloudKit, dashed)
//   - iPhone → Watch (dashed)
export default function ArchitectureDiagram() {
  return (
    <div className="my-8 p-4 md:p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="relative min-w-[700px] h-[400px]">
        {/* SVG layer for curved connections */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox="0 0 700 400"
          preserveAspectRatio="xMidYMid meet"
        >
          {/* Arrow marker definitions - refX=0 so line connects to back-center of triangle */}
          <defs>
            <marker
              id="arrow-emerald"
              markerWidth="10"
              markerHeight="8"
              refX="0"
              refY="4"
              orient="auto"
              markerUnits="strokeWidth"
            >
              <polygon
                points="0 0, 10 4, 0 8"
                className="fill-emerald-400 dark:fill-emerald-500"
              />
            </marker>
            <marker
              id="arrow-blue"
              markerWidth="10"
              markerHeight="8"
              refX="0"
              refY="4"
              orient="auto"
              markerUnits="strokeWidth"
            >
              <polygon
                points="0 0, 10 4, 0 8"
                className="fill-blue-400 dark:fill-blue-500"
              />
            </marker>
            <marker
              id="arrow-amber"
              markerWidth="10"
              markerHeight="8"
              refX="0"
              refY="4"
              orient="auto"
              markerUnits="strokeWidth"
            >
              <polygon
                points="0 0, 10 4, 0 8"
                className="fill-amber-400 dark:fill-amber-500"
              />
            </marker>
            <marker
              id="arrow-zinc"
              markerWidth="10"
              markerHeight="8"
              refX="0"
              refY="4"
              orient="auto"
              markerUnits="strokeWidth"
            >
              <polygon
                points="0 0, 10 4, 0 8"
                className="fill-zinc-400 dark:fill-zinc-500"
              />
            </marker>
            <marker
              id="arrow-sky"
              markerWidth="10"
              markerHeight="8"
              refX="0"
              refY="4"
              orient="auto"
              markerUnits="strokeWidth"
            >
              <polygon
                points="0 0, 10 4, 0 8"
                className="fill-sky-400 dark:fill-sky-500"
              />
            </marker>
          </defs>

          {/* === Talkie → TalkieLive (XPC) === */}
          {/* Straight down from Talkie to TalkieLive */}
          <path
            d="M 100 95 L 100 145"
            fill="none"
            className="stroke-emerald-400 dark:stroke-emerald-500"
            strokeWidth="2"
            markerEnd="url(#arrow-emerald)"
          />
          <text x="112" y="123" className="fill-emerald-600 dark:fill-emerald-400 text-[10px] font-mono">
            XPC
          </text>

          {/* === TalkieLive → TalkieEngine (audio) === */}
          {/* Horizontal from Live to Engine */}
          <path
            d="M 175 190 L 223 190"
            fill="none"
            className="stroke-emerald-400 dark:stroke-emerald-500"
            strokeWidth="3"
            markerEnd="url(#arrow-emerald)"
          />
          <text x="199" y="180" textAnchor="middle" className="fill-emerald-600 dark:fill-emerald-400 text-[9px] font-mono">
            audio
          </text>

          {/* === Talkie → TalkieEngine (XPC) === */}
          {/* Right from Talkie, curve down to Engine */}
          <path
            d="M 225 55 L 285 55 Q 305 55 305 75 L 305 145"
            fill="none"
            className="stroke-blue-400 dark:stroke-blue-500"
            strokeWidth="2"
            markerEnd="url(#arrow-blue)"
          />
          <text x="255" y="45" className="fill-blue-600 dark:fill-blue-400 text-[10px] font-mono">
            XPC
          </text>

          {/* === Talkie → TalkieServer (HTTP) === */}
          {/* Horizontal from Talkie to Server */}
          <path
            d="M 225 40 L 503 40"
            fill="none"
            className="stroke-amber-400 dark:stroke-amber-500"
            strokeWidth="2"
            markerEnd="url(#arrow-amber)"
          />
          <text x="365" y="30" textAnchor="middle" className="fill-amber-600 dark:fill-amber-400 text-[10px] font-mono">
            HTTP
          </text>

          {/* === TalkieServer → iPhone (Tailscale) === */}
          {/* Vertical down from Server to iPhone */}
          <path
            d="M 580 95 L 580 145"
            fill="none"
            className="stroke-zinc-400 dark:stroke-zinc-500"
            strokeWidth="2"
            markerEnd="url(#arrow-zinc)"
          />
          <text x="592" y="123" className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono">
            Tailscale
          </text>

          {/* === iPhone → Watch === */}
          {/* Horizontal line to Watch (beside iPhone) */}
          <path
            d="M 660 190 L 660 270"
            fill="none"
            className="stroke-zinc-300 dark:stroke-zinc-600"
            strokeWidth="1.5"
            strokeDasharray="4 2"
          />

          {/* === Talkie → iCloud (CloudKit sync) === */}
          {/* Down from Talkie right side to iCloud */}
          <path
            d="M 200 95 L 200 310 Q 200 330 220 330 L 310 330"
            fill="none"
            className="stroke-sky-400 dark:stroke-sky-500"
            strokeWidth="2"
            strokeDasharray="6 3"
            markerEnd="url(#arrow-sky)"
          />
          <text x="260" y="348" textAnchor="middle" className="fill-sky-600 dark:fill-sky-400 text-[9px] font-mono">
            CloudKit
          </text>

          {/* === iPhone → iCloud (CloudKit sync) === */}
          {/* Down from iPhone to iCloud */}
          <path
            d="M 560 225 L 560 330 L 430 330"
            fill="none"
            className="stroke-sky-400 dark:stroke-sky-500"
            strokeWidth="2"
            strokeDasharray="6 3"
            markerEnd="url(#arrow-sky)"
          />
        </svg>

        {/* Process boxes positioned absolutely */}
        {/*
          Box dimensions (measured):
          - Large: ~210px wide x 85px tall
          - Normal: ~145px wide x 68px tall
          - Small: ~95px wide x 42px tall

          Layout grid:
          - Row 1 top: 15px (Talkie, TalkieServer)
          - Row 2 top: 155px (TalkieLive, TalkieEngine, iCloud, iPhone)
          - Row 3 top: 280px (Watch)
        */}

        {/* === ROW 1: Main Apps === */}

        {/* Talkie - top left, prominent */}
        <div className="absolute left-[25px] top-[15px]">
          <ProcessBox
            icon={Monitor}
            name="Talkie"
            subtitle="Swift/SwiftUI"
            description="UI, Workflows, Data, Orchestration"
            color="violet"
            size="large"
          />
        </div>

        {/* TalkieServer - top right */}
        <div className="absolute left-[515px] top-[15px]">
          <ProcessBox
            icon={Server}
            name="TalkieServer"
            subtitle="TypeScript"
            description="iOS Bridge"
            color="amber"
          />
        </div>

        {/* === ROW 2: Helpers & Mobile === */}

        {/* TalkieLive - below Talkie */}
        <div className="absolute left-[25px] top-[155px]">
          <ProcessBox
            icon={Mic}
            name="TalkieLive"
            subtitle="Swift"
            description="Ears & Hands"
            color="emerald"
          />
        </div>

        {/* TalkieEngine - right of TalkieLive */}
        <div className="absolute left-[235px] top-[155px]">
          <ProcessBox
            icon={Cpu}
            name="TalkieEngine"
            subtitle="Swift"
            description="Local Brain"
            color="blue"
          />
        </div>

        {/* iCloud - bottom center, sync hub between Talkie and iPhone */}
        <div className="absolute left-[320px] top-[310px]">
          <ProcessBox
            icon={Cloud}
            name="iCloud"
            subtitle="CloudKit"
            color="sky"
            size="small"
          />
        </div>

        {/* iPhone - below TalkieServer */}
        <div className="absolute left-[515px] top-[155px]">
          <ProcessBox
            icon={Smartphone}
            name="iPhone"
            subtitle="iOS"
            description="Voice Capture"
            color="zinc"
          />
        </div>

        {/* === ROW 3: Watch === */}

        {/* Watch - below iPhone */}
        <div className="absolute left-[610px] top-[275px]">
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
