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
// Layout (three columns, clear hierarchy):
//   Column 1: Talkie → TalkieLive → TalkieEngine
//   Column 2: TalkieServer (top) + iCloud (lower)
//   Column 3: iPhone → Watch
// Connections:
//   - Talkie → TalkieLive (XPC)
//   - TalkieLive → TalkieEngine (audio)
//   - Talkie → TalkieServer (HTTP)
//   - TalkieServer → iPhone (Tailscale)
//   - Talkie → iCloud (CloudKit, dashed)
//   - iPhone → iCloud (CloudKit, dashed)
//   - iPhone → Watch (dashed)
export default function ArchitectureDiagram() {
  // === LAYOUT CONFIG ===
  const layout = { width: 700, height: 340 }

  const nodeSizes = {
    large:  { width: 210, height: 85 },
    normal: { width: 145, height: 68 },
    small:  { width: 95,  height: 42 },
  }

  // Box positions - adjust these to move boxes
  const nodes = {
    talkie:       { x: 25,  y: 15,  size: 'large' },
    talkieLive:   { x: 25,  y: 125, size: 'normal' },
    talkieEngine: { x: 25,  y: 220, size: 'normal' },
    talkieServer: { x: 280, y: 15,  size: 'normal' },
    iCloud:       { x: 280, y: 220, size: 'normal' },
    iPhone:       { x: 520, y: 15,  size: 'normal' },
    watch:        { x: 548, y: 115, size: 'small' },
  }

  // === CONNECTOR STYLES ===
  const connectorStyles = {
    xpc:      { color: 'emerald', stroke: 2, label: 'XPC' },
    http:     { color: 'amber',   stroke: 2, label: 'HTTP' },
    tailscale:{ color: 'zinc',    stroke: 2, label: 'Tailscale' },
    cloudkit: { color: 'sky',     stroke: 2, label: 'CloudKit', dashed: true },
    audio:    { color: 'emerald', stroke: 3, label: 'audio' },
    peer:     { color: 'zinc',    stroke: 1.5, dashed: true },
  }

  // === CONNECTORS ===
  const connectors = [
    { from: 'talkie',       to: 'talkieLive',   fromAnchor: 'bottom', toAnchor: 'top',    style: 'xpc' },
    { from: 'talkieLive',   to: 'talkieEngine', fromAnchor: 'bottom', toAnchor: 'top',    style: 'audio' },
    { from: 'talkie',       to: 'talkieServer', fromAnchor: 'right',  toAnchor: 'left',   style: 'http' },
    { from: 'talkieServer', to: 'iPhone',       fromAnchor: 'right',  toAnchor: 'left',   style: 'tailscale' },
    { from: 'iPhone',       to: 'watch',        fromAnchor: 'bottom', toAnchor: 'top',    style: 'peer' },
    { from: 'talkie',       to: 'iCloud',       fromAnchor: 'bottomRight', toAnchor: 'left', style: 'cloudkit', curve: 'down' },
    { from: 'iPhone',       to: 'iCloud',       fromAnchor: 'bottomLeft',  toAnchor: 'right', style: 'cloudkit', curve: 'down' },
  ]

  // === HELPER FUNCTIONS ===
  const getNode = (id) => {
    const node = nodes[id]
    const size = nodeSizes[node.size]
    return { ...node, ...size }
  }

  const gap = 8
  const anchor = (node, position) => {
    const n = typeof node === 'string' ? getNode(node) : node
    switch (position) {
      case 'left':        return { x: n.x - gap, y: n.y + n.height / 2 }
      case 'right':       return { x: n.x + n.width + gap, y: n.y + n.height / 2 }
      case 'top':         return { x: n.x + n.width / 2, y: n.y - gap }
      case 'bottom':      return { x: n.x + n.width / 2, y: n.y + n.height + gap }
      case 'bottomRight': return { x: n.x + n.width + gap, y: n.y + n.height - 15 }
      case 'bottomLeft':  return { x: n.x - gap, y: n.y + n.height - 15 }
      default:            return { x: n.x + n.width / 2, y: n.y + n.height / 2 }
    }
  }

  const straightPath = (from, to) => `M ${from.x} ${from.y} L ${to.x} ${to.y}`
  const curvedPath = (from, to, direction = 'down') => {
    const cp = 50
    if (direction === 'down') {
      return `M ${from.x} ${from.y} C ${from.x + cp} ${from.y + 50}, ${to.x - cp} ${to.y - 30}, ${to.x} ${to.y}`
    }
    return straightPath(from, to)
  }

  // Resolve all nodes
  const talkie = getNode('talkie')
  const talkieLive = getNode('talkieLive')
  const talkieEngine = getNode('talkieEngine')
  const talkieServer = getNode('talkieServer')
  const iPhone = getNode('iPhone')
  const watch = getNode('watch')
  const iCloud = getNode('iCloud')

  // Helper for midpoint
  const midPoint = (p1, p2) => ({ x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2 })

  // Compute connector endpoints
  const talkieToLive = {
    start: anchor('talkie', 'bottom'),
    end: anchor('talkieLive', 'top')
  }
  const liveToEngine = {
    start: anchor('talkieLive', 'bottom'),
    end: anchor('talkieEngine', 'top')
  }
  const talkieToServer = {
    start: anchor('talkie', 'right'),
    end: anchor('talkieServer', 'left')
  }
  const serverToPhone = {
    start: anchor('talkieServer', 'right'),
    end: anchor('iPhone', 'left')
  }
  const phoneToWatch = {
    start: anchor('iPhone', 'bottom'),
    end: anchor('watch', 'top')
  }

  // Curved paths for CloudKit
  const talkieCloudStart = anchor('talkie', 'bottomRight')
  const talkieCloudEnd = anchor('iCloud', 'left')
  const talkieToCloudCurve = curvedPath(talkieCloudStart, talkieCloudEnd, 'down')

  const phoneCloudStart = anchor('iPhone', 'bottomLeft')
  const phoneCloudEnd = anchor('iCloud', 'right')
  const phoneToCloudCurve = curvedPath(phoneCloudStart, phoneCloudEnd, 'down')

  return (
    <div className="my-8 p-4 md:p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 overflow-x-auto">
      <div className="relative min-w-[700px] h-[400px]">
        {/* SVG layer for curved connections */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox={`0 0 ${layout.width} ${layout.height}`}
          preserveAspectRatio="xMidYMid meet"
        >
          {/* Arrow marker definitions - smaller arrows */}
          <defs>
            <marker
              id="arrow-emerald"
              markerWidth="6"
              markerHeight="4"
              refX="6"
              refY="2"
              orient="auto"
              markerUnits="userSpaceOnUse"
            >
              <polygon
                points="0 0, 6 2, 0 4"
                className="fill-emerald-400 dark:fill-emerald-500"
              />
            </marker>
            <marker
              id="arrow-amber"
              markerWidth="6"
              markerHeight="4"
              refX="6"
              refY="2"
              orient="auto"
              markerUnits="userSpaceOnUse"
            >
              <polygon
                points="0 0, 6 2, 0 4"
                className="fill-amber-400 dark:fill-amber-500"
              />
            </marker>
            <marker
              id="arrow-zinc"
              markerWidth="6"
              markerHeight="4"
              refX="6"
              refY="2"
              orient="auto"
              markerUnits="userSpaceOnUse"
            >
              <polygon
                points="0 0, 6 2, 0 4"
                className="fill-zinc-400 dark:fill-zinc-500"
              />
            </marker>
            <marker
              id="arrow-sky"
              markerWidth="6"
              markerHeight="4"
              refX="6"
              refY="2"
              orient="auto"
              markerUnits="userSpaceOnUse"
            >
              <polygon
                points="0 0, 6 2, 0 4"
                className="fill-sky-400 dark:fill-sky-500"
              />
            </marker>
          </defs>

          {/* === Talkie → TalkieLive (XPC) === */}
          <path
            d={`M ${talkieToLive.start.x} ${talkieToLive.start.y} L ${talkieToLive.end.x} ${talkieToLive.end.y}`}
            fill="none"
            className="stroke-emerald-400 dark:stroke-emerald-500"
            strokeWidth="2"
            markerEnd="url(#arrow-emerald)"
            vectorEffect="non-scaling-stroke"
          />
          <text
            x={talkieToLive.start.x + 10}
            y={midPoint(talkieToLive.start, talkieToLive.end).y + 4}
            className="fill-emerald-600 dark:fill-emerald-400 text-[10px] font-mono"
          >
            XPC
          </text>

          {/* === TalkieLive → TalkieEngine (audio) === */}
          <path
            d={`M ${liveToEngine.start.x} ${liveToEngine.start.y} L ${liveToEngine.end.x} ${liveToEngine.end.y}`}
            fill="none"
            className="stroke-emerald-400 dark:stroke-emerald-500"
            strokeWidth="3"
            markerEnd="url(#arrow-emerald)"
            vectorEffect="non-scaling-stroke"
          />
          <text
            x={liveToEngine.start.x + 12}
            y={midPoint(liveToEngine.start, liveToEngine.end).y + 4}
            className="fill-emerald-600 dark:fill-emerald-400 text-[9px] font-mono"
          >
            audio
          </text>

          {/* === Talkie → TalkieServer (HTTP) === */}
          <path
            d={`M ${talkieToServer.start.x} ${talkieToServer.start.y} L ${talkieToServer.end.x} ${talkieToServer.end.y}`}
            fill="none"
            className="stroke-amber-400 dark:stroke-amber-500"
            strokeWidth="2"
            markerEnd="url(#arrow-amber)"
            vectorEffect="non-scaling-stroke"
          />
          <text
            x={midPoint(talkieToServer.start, talkieToServer.end).x}
            y={talkieToServer.start.y - 10}
            textAnchor="middle"
            className="fill-amber-600 dark:fill-amber-400 text-[10px] font-mono"
          >
            HTTP
          </text>

          {/* === TalkieServer → iPhone (Tailscale) === */}
          <path
            d={`M ${serverToPhone.start.x} ${serverToPhone.start.y} L ${serverToPhone.end.x} ${serverToPhone.end.y}`}
            fill="none"
            className="stroke-zinc-400 dark:stroke-zinc-500"
            strokeWidth="2"
            markerEnd="url(#arrow-zinc)"
            vectorEffect="non-scaling-stroke"
          />
          <text
            x={midPoint(serverToPhone.start, serverToPhone.end).x}
            y={serverToPhone.start.y - 10}
            textAnchor="middle"
            className="fill-zinc-500 dark:fill-zinc-400 text-[10px] font-mono"
          >
            Tailscale
          </text>

          {/* === iPhone → Watch === */}
          <path
            d={`M ${phoneToWatch.start.x} ${phoneToWatch.start.y} L ${phoneToWatch.end.x} ${phoneToWatch.end.y}`}
            fill="none"
            className="stroke-zinc-300 dark:stroke-zinc-600"
            strokeWidth="1.5"
            strokeDasharray="4 2"
            vectorEffect="non-scaling-stroke"
          />

          {/* === Talkie → iCloud (CloudKit sync) === */}
          <path
            d={talkieToCloudCurve}
            fill="none"
            className="stroke-sky-400 dark:stroke-sky-500"
            strokeWidth="2"
            strokeDasharray="6 3"
            markerEnd="url(#arrow-sky)"
            vectorEffect="non-scaling-stroke"
          />

          {/* === iPhone → iCloud (CloudKit sync) === */}
          <path
            d={phoneToCloudCurve}
            fill="none"
            className="stroke-sky-400 dark:stroke-sky-500"
            strokeWidth="2"
            strokeDasharray="6 3"
            markerEnd="url(#arrow-sky)"
            vectorEffect="non-scaling-stroke"
          />
          <text
            x={iCloud.x + iCloud.width / 2}
            y={iCloud.y - 8}
            textAnchor="middle"
            className="fill-sky-600 dark:fill-sky-400 text-[9px] font-mono"
          >
            CloudKit
          </text>
        </svg>

        {/* Process boxes positioned absolutely */}

        {/* === COLUMN 1: Main App Stack === */}

        {/* Talkie - top left, prominent */}
        <div className="absolute" style={{ left: talkie.x, top: talkie.y }}>
          <ProcessBox
            icon={Monitor}
            name="Talkie"
            subtitle="Swift/SwiftUI"
            description="UI, Workflows, Data, Orchestration"
            color="violet"
            size="large"
          />
        </div>

        {/* TalkieServer - top middle */}
        <div className="absolute" style={{ left: talkieServer.x, top: talkieServer.y }}>
          <ProcessBox
            icon={Server}
            name="TalkieServer"
            subtitle="TypeScript"
            description="iOS Bridge"
            color="amber"
          />
        </div>

        {/* === COLUMN 1: Helpers === */}

        {/* TalkieLive - below Talkie */}
        <div className="absolute" style={{ left: talkieLive.x, top: talkieLive.y }}>
          <ProcessBox
            icon={Mic}
            name="TalkieLive"
            subtitle="Swift"
            description="Ears & Hands"
            color="emerald"
          />
        </div>

        {/* TalkieEngine - below TalkieLive */}
        <div className="absolute" style={{ left: talkieEngine.x, top: talkieEngine.y }}>
          <ProcessBox
            icon={Cpu}
            name="TalkieEngine"
            subtitle="Swift"
            description="Local Brain"
            color="blue"
          />
        </div>

        {/* iCloud - lower middle, sync hub between Talkie and iPhone */}
        <div className="absolute" style={{ left: iCloud.x, top: iCloud.y }}>
          <ProcessBox
            icon={Cloud}
            name="iCloud"
            subtitle="CloudKit"
            description="Memo Sync"
            color="sky"
          />
        </div>

        {/* iPhone - top right */}
        <div className="absolute" style={{ left: iPhone.x, top: iPhone.y }}>
          <ProcessBox
            icon={Smartphone}
            name="iPhone"
            subtitle="iOS"
            description="Voice Capture"
            color="zinc"
          />
        </div>

        {/* Watch - below iPhone */}
        <div className="absolute" style={{ left: watch.x, top: watch.y }}>
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

// Simpler diagram for overview page - shows Talkie as orchestrator
export function SimpleArchitectureDiagram() {
  return (
    <div className="my-8 p-6 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 relative">
      <div className="flex flex-col items-center gap-6">
        {/* Talkie - the orchestrator */}
        <div className="flex flex-col items-center">
          <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-violet-100 to-violet-50 dark:from-violet-500/20 dark:to-violet-500/10 border-2 border-violet-300 dark:border-violet-500/40 flex items-center justify-center shadow-sm">
            <Monitor className="w-8 h-8 text-violet-600 dark:text-violet-400" />
          </div>
          <span className="mt-2 text-sm font-bold text-zinc-900 dark:text-white">Talkie</span>
          <span className="text-[10px] text-zinc-500 dark:text-zinc-400">Orchestrator</span>
        </div>

        {/* Connection lines */}
        <div className="flex items-center gap-1">
          <div className="w-16 h-0.5 bg-emerald-300 dark:bg-emerald-500/50"></div>
          <div className="w-16 h-0.5 bg-blue-300 dark:bg-blue-500/50"></div>
          <div className="w-16 h-0.5 bg-amber-300 dark:bg-amber-500/50"></div>
        </div>

        {/* Helper processes with protocol labels inline */}
        <div className="flex items-start justify-center gap-8">
          {/* TalkieLive */}
          <div className="flex flex-col items-center">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-emerald-100 to-emerald-50 dark:from-emerald-500/20 dark:to-emerald-500/10 border-2 border-emerald-300 dark:border-emerald-500/40 flex items-center justify-center shadow-sm">
              <Mic className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />
            </div>
            <span className="mt-1.5 text-xs font-semibold text-zinc-900 dark:text-white">TalkieLive</span>
            <span className="text-[10px] text-zinc-500 dark:text-zinc-400">Ears & Hands</span>
            <span className="mt-2 px-2 py-0.5 rounded bg-zinc-100 dark:bg-zinc-800 text-[10px] font-mono text-zinc-400 dark:text-zinc-500">XPC</span>
          </div>

          {/* TalkieEngine */}
          <div className="flex flex-col items-center">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-blue-100 to-blue-50 dark:from-blue-500/20 dark:to-blue-500/10 border-2 border-blue-300 dark:border-blue-500/40 flex items-center justify-center shadow-sm">
              <Cpu className="w-5 h-5 text-blue-600 dark:text-blue-400" />
            </div>
            <span className="mt-1.5 text-xs font-semibold text-zinc-900 dark:text-white">TalkieEngine</span>
            <span className="text-[10px] text-zinc-500 dark:text-zinc-400">Local Brain</span>
            <span className="mt-2 px-2 py-0.5 rounded bg-zinc-100 dark:bg-zinc-800 text-[10px] font-mono text-zinc-400 dark:text-zinc-500">XPC</span>
          </div>

          {/* TalkieServer */}
          <div className="flex flex-col items-center">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-amber-100 to-amber-50 dark:from-amber-500/20 dark:to-amber-500/10 border-2 border-amber-300 dark:border-amber-500/40 flex items-center justify-center shadow-sm">
              <Server className="w-5 h-5 text-amber-600 dark:text-amber-400" />
            </div>
            <span className="mt-1.5 text-xs font-semibold text-zinc-900 dark:text-white">TalkieServer</span>
            <span className="text-[10px] text-zinc-500 dark:text-zinc-400">iOS Bridge</span>
            <span className="mt-2 px-2 py-0.5 rounded bg-zinc-100 dark:bg-zinc-800 text-[10px] font-mono text-zinc-400 dark:text-zinc-500">HTTP</span>
          </div>
        </div>
      </div>
      {/* Diagram ID */}
      <div className="absolute bottom-2 left-3 font-mono text-[9px] text-zinc-400 dark:text-zinc-600 tracking-wider">
        SYS.OVERVIEW.001
      </div>
    </div>
  )
}
