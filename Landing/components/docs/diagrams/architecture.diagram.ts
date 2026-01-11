import type { ArcDiagramData } from '../ArcDiagram'

const diagram: ArcDiagramData = {
  layout: { width: 800, height: 350 },

  nodes: {
    talkie:       { x: 50,  y: 45,  size: 'l' },
    talkieLive:   { x: 50,  y: 155, size: 'm' },
    talkieEngine: { x: 50,  y: 255, size: 'm' },
    talkieServer: { x: 360, y: 55,  size: 'm' },
    iCloud:       { x: 380, y: 255, size: 'm' },
    iPhone:       { x: 600, y: 55,  size: 'm' },
    watch:        { x: 620, y: 155, size: 's' },
  },

  nodeData: {
    talkie:       { icon: 'Monitor',    name: 'Talkie',       subtitle: 'Swift/SwiftUI', description: 'UI, Workflows, Data, Orchestration', color: 'violet' },
    talkieLive:   { icon: 'Mic',        name: 'TalkieLive',   subtitle: 'Swift',         description: 'Ears & Hands',                      color: 'emerald' },
    talkieEngine: { icon: 'Cpu',        name: 'TalkieEngine', subtitle: 'Swift',         description: 'Local Brain',                       color: 'blue' },
    talkieServer: { icon: 'Server',     name: 'TalkieServer', subtitle: 'TypeScript',    description: 'iOS Bridge',                        color: 'amber' },
    iCloud:       { icon: 'Cloud',      name: 'iCloud',       subtitle: 'CloudKit',      description: 'Memo Sync',                         color: 'sky' },
    iPhone:       { icon: 'Smartphone', name: 'iPhone',       subtitle: 'iOS',           description: 'Voice Capture',                     color: 'zinc' },
    watch:        { icon: 'Watch',      name: 'Watch',        subtitle: 'watchOS',                                                         color: 'zinc' },
  },

  connectors: [
    { from: 'talkie',       to: 'talkieLive',   fromAnchor: 'bottom',      toAnchor: 'top',   style: 'xpc' },
    { from: 'talkieLive',   to: 'talkieEngine', fromAnchor: 'bottom',      toAnchor: 'top',   style: 'audio' },
    { from: 'talkie',       to: 'talkieServer', fromAnchor: 'right',       toAnchor: 'left',  style: 'http' },
    { from: 'talkieServer', to: 'iPhone',       fromAnchor: 'right',       toAnchor: 'left',  style: 'tailscale' },
    { from: 'iPhone',       to: 'watch',        fromAnchor: 'bottom',      toAnchor: 'top',   style: 'peer' },
    { from: 'talkie',       to: 'iCloud',       fromAnchor: 'bottomRight', toAnchor: 'left',  style: 'cloudkit', curve: 'natural' },
    { from: 'iPhone',       to: 'iCloud',       fromAnchor: 'bottomLeft',  toAnchor: 'right', style: 'cloudkit', curve: 'natural' },
  ],

  connectorStyles: {
    xpc:       { color: 'sky',   strokeWidth: 2, dashed: true },
    http:      { color: 'amber', strokeWidth: 2, dashed: true, label: 'HTTP' },
    tailscale: { color: 'sky',   strokeWidth: 2, dashed: true, label: 'Tailscale' },
    cloudkit:  { color: 'sky',   strokeWidth: 2, dashed: true },
    audio:     { color: 'sky',   strokeWidth: 2, dashed: true },
    peer:      { color: 'sky',   strokeWidth: 2, dashed: true },
  },
}

export default diagram
