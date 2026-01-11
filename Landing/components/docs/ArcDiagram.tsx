"use client"
import React from 'react'
import * as LucideIcons from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

// ============================================
// Types
// ============================================

export type NodeSize = 's' | 'm' | 'l'
export type AnchorPosition = 'left' | 'right' | 'top' | 'bottom' | 'bottomLeft' | 'bottomRight' | 'topLeft' | 'topRight'
export type DiagramColor = 'violet' | 'emerald' | 'blue' | 'amber' | 'sky' | 'zinc' | 'rose' | 'orange'

export interface NodePosition {
  x: number
  y: number
  size: NodeSize
}

export interface NodeData {
  icon: string
  name: string
  subtitle?: string
  description?: string
  color: DiagramColor
}

export interface Connector {
  from: string
  to: string
  fromAnchor: AnchorPosition
  toAnchor: AnchorPosition
  style: string
  curve?: 'natural' | 'step'
}

export interface ConnectorStyle {
  color: DiagramColor
  strokeWidth: number
  label?: string
  dashed?: boolean
}

export interface DiagramLayout {
  width: number
  height: number
}

export interface ArcDiagramData {
  layout: DiagramLayout
  nodes: Record<string, NodePosition>
  nodeData: Record<string, NodeData>
  connectors: Connector[]
  connectorStyles: Record<string, ConnectorStyle>
}

// ============================================
// Constants
// ============================================

const NODE_SIZES: Record<NodeSize, { width: number; height: number }> = {
  l: { width: 200, height: 80 },
  m: { width: 140, height: 65 },
  s: { width: 90, height: 40 },
}

const COLORS: Record<DiagramColor, { border: string; bg: string; icon: string; stroke: string }> = {
  violet:  { border: 'border-violet-400/50',  bg: 'bg-violet-500/10',  icon: 'text-violet-400',  stroke: '#a78bfa' },
  emerald: { border: 'border-emerald-400/50', bg: 'bg-emerald-500/10', icon: 'text-emerald-400', stroke: '#34d399' },
  blue:    { border: 'border-blue-400/50',    bg: 'bg-blue-500/10',    icon: 'text-blue-400',    stroke: '#60a5fa' },
  amber:   { border: 'border-amber-400/50',   bg: 'bg-amber-500/10',   icon: 'text-amber-400',   stroke: '#fbbf24' },
  sky:     { border: 'border-sky-400/50',     bg: 'bg-sky-500/10',     icon: 'text-sky-400',     stroke: '#38bdf8' },
  zinc:    { border: 'border-zinc-600',       bg: 'bg-zinc-800/50',    icon: 'text-zinc-400',    stroke: '#71717a' },
  rose:    { border: 'border-rose-400/50',    bg: 'bg-rose-500/10',    icon: 'text-rose-400',    stroke: '#fb7185' },
  orange:  { border: 'border-orange-400/50',  bg: 'bg-orange-500/10',  icon: 'text-orange-400',  stroke: '#fb923c' },
}

// ============================================
// Components
// ============================================

interface NodeProps {
  node: NodePosition
  data: NodeData
}

function Node({ node, data }: NodeProps) {
  const size = NODE_SIZES[node.size]
  const color = COLORS[data.color] || COLORS.zinc
  const Icon = (LucideIcons as Record<string, LucideIcon>)[data.icon] || LucideIcons.Box

  const isLarge = node.size === 'l'
  const isSmall = node.size === 's'

  return (
    <div
      className={`
        absolute rounded-xl border-2 ${color.border} ${color.bg}
        ${isLarge ? 'px-5 py-3' : isSmall ? 'px-3 py-2' : 'px-4 py-2.5'}
        bg-zinc-900/90 backdrop-blur-sm
      `}
      style={{ left: node.x, top: node.y, width: size.width }}
    >
      <div className="flex items-center gap-3">
        <div className={`
          flex-shrink-0 rounded-lg border border-zinc-700 bg-zinc-900
          ${isLarge ? 'w-10 h-10' : isSmall ? 'w-6 h-6' : 'w-8 h-8'}
          flex items-center justify-center
        `}>
          <Icon className={`${isLarge ? 'w-5 h-5' : isSmall ? 'w-3 h-3' : 'w-4 h-4'} ${color.icon}`} />
        </div>
        <div className="min-w-0">
          <div className={`font-semibold text-white ${isLarge ? 'text-sm' : isSmall ? 'text-[10px]' : 'text-xs'}`}>
            {data.name}
          </div>
          {data.subtitle && (
            <div className={`font-mono text-zinc-500 ${isSmall ? 'text-[8px]' : 'text-[10px]'}`}>
              {data.subtitle}
            </div>
          )}
        </div>
      </div>
      {data.description && !isSmall && (
        <div className={`mt-1.5 text-zinc-400 ${isLarge ? 'text-[11px]' : 'text-[10px]'}`}>
          {data.description}
        </div>
      )}
    </div>
  )
}

function getAnchorPoint(node: NodePosition, anchor: AnchorPosition): { x: number; y: number } {
  const size = NODE_SIZES[node.size]
  const gap = 8

  const anchors: Record<AnchorPosition, { x: number; y: number }> = {
    left:        { x: node.x - gap,              y: node.y + size.height / 2 },
    right:       { x: node.x + size.width + gap, y: node.y + size.height / 2 },
    top:         { x: node.x + size.width / 2,   y: node.y - gap },
    bottom:      { x: node.x + size.width / 2,   y: node.y + size.height + gap },
    bottomRight: { x: node.x + size.width + gap, y: node.y + size.height - 12 },
    bottomLeft:  { x: node.x - gap,              y: node.y + size.height - 12 },
    topRight:    { x: node.x + size.width + gap, y: node.y + 12 },
    topLeft:     { x: node.x - gap,              y: node.y + 12 },
  }

  return anchors[anchor]
}

interface ConnectorProps {
  connector: Connector
  nodes: Record<string, NodePosition>
  styles: Record<string, ConnectorStyle>
}

function ConnectorPath({ connector, nodes, styles }: ConnectorProps) {
  const fromNode = nodes[connector.from]
  const toNode = nodes[connector.to]
  if (!fromNode || !toNode) return null

  const style = styles[connector.style] || { color: 'zinc', strokeWidth: 2 }
  const from = getAnchorPoint(fromNode, connector.fromAnchor)
  const to = getAnchorPoint(toNode, connector.toAnchor)
  const color = COLORS[style.color]?.stroke || COLORS.zinc.stroke

  let path: string
  if (connector.curve === 'natural') {
    const cp = 50
    path = `M ${from.x} ${from.y} C ${from.x + cp} ${from.y + 40}, ${to.x - cp} ${to.y - 30}, ${to.x} ${to.y}`
  } else {
    path = `M ${from.x} ${from.y} L ${to.x} ${to.y}`
  }

  const mid = { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 }
  const markerId = `arc-arrow-${connector.from}-${connector.to}`

  return (
    <g>
      <defs>
        <marker
          id={markerId}
          markerWidth="6"
          markerHeight="4"
          refX="6"
          refY="2"
          orient="auto"
        >
          <polygon points="0 0, 6 2, 0 4" fill={color} />
        </marker>
      </defs>
      <path
        d={path}
        fill="none"
        stroke={color}
        strokeWidth={style.strokeWidth}
        strokeDasharray={style.dashed ? '6 3' : undefined}
        markerEnd={`url(#${markerId})`}
      />
      {style.label && (
        <text
          x={mid.x}
          y={mid.y - 8}
          textAnchor="middle"
          fill={color}
          className="text-[10px] font-mono"
        >
          {style.label}
        </text>
      )}
    </g>
  )
}

// ============================================
// Main Component
// ============================================

interface ArcDiagramProps {
  data: ArcDiagramData
  className?: string
}

export default function ArcDiagram({ data, className = '' }: ArcDiagramProps) {
  const { layout, nodes, nodeData, connectors, connectorStyles } = data

  return (
    <div className={`rounded-2xl bg-zinc-950 border border-zinc-800 overflow-x-auto ${className}`}>
      <div
        className="relative"
        style={{ width: layout.width, height: layout.height, minWidth: layout.width }}
      >
        {/* Grid background */}
        <div
          className="absolute inset-0 opacity-[0.08]"
          style={{
            backgroundImage: 'radial-gradient(circle, #71717a 1px, transparent 1px)',
            backgroundSize: '24px 24px',
          }}
        />

        {/* Connectors */}
        <svg
          className="absolute inset-0 w-full h-full pointer-events-none"
          viewBox={`0 0 ${layout.width} ${layout.height}`}
        >
          {connectors.map((conn, i) => (
            <ConnectorPath
              key={i}
              connector={conn}
              nodes={nodes}
              styles={connectorStyles}
            />
          ))}
        </svg>

        {/* Nodes */}
        {Object.entries(nodes).map(([id, node]) => (
          <Node key={id} node={node} data={nodeData[id]} />
        ))}
      </div>
    </div>
  )
}
