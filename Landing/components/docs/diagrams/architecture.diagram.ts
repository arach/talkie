import type { ArcDiagramData } from '../ArcDiagram'

const diagram: ArcDiagramData = {
  id: 'SYS.ARCH.001',
  layout: { width: 960, height: 460 },

  // Top row: Talkie, iCloud, iPhone (vertically aligned)
  // Large=200w, Medium=140w, Small=90w
  nodes: {
    talkie:       { x: 50,  y: 40,  size: 'l' },   // Main app
    talkieLive:   { x: 80,  y: 175, size: 'm' },   // Centered under Talkie
    talkieEngine: { x: 80,  y: 295, size: 'm' },   // Centered under Talkie
    iCloud:       { x: 350, y: 48,  size: 'm' },   // Top row (-10px)
    iPhone:       { x: 570, y: 48,  size: 'm' },   // Top row (-20px total)
    watch:        { x: 595, y: 155, size: 's' },   // Centered under iPhone
  },

  nodeData: {
    talkie:       { icon: 'Monitor',    name: 'Talkie',       subtitle: 'Swift/SwiftUI', description: 'Orchestrator & UI', color: 'violet' },
    talkieLive:   { icon: 'Mic',        name: 'TalkieLive',   subtitle: 'Swift',         description: 'Ears & Hands',      color: 'emerald' },
    talkieEngine: { icon: 'Cpu',        name: 'TalkieEngine', subtitle: 'Swift',         description: 'Local Brain',       color: 'blue' },
    iCloud:       { icon: 'Cloud',      name: 'iCloud',       subtitle: 'CloudKit',      description: 'Memo Sync',         color: 'sky' },
    iPhone:       { icon: 'Smartphone', name: 'iPhone',       subtitle: 'iOS',           description: 'Voice Capture',     color: 'zinc' },
    watch:        { icon: 'Watch',      name: 'Watch',        subtitle: 'watchOS',                                         color: 'zinc' },
  },

  connectors: [
    { from: 'talkie',     to: 'talkieLive',   fromAnchor: 'bottom', toAnchor: 'top',  style: 'xpc' },
    { from: 'talkieLive', to: 'talkieEngine', fromAnchor: 'bottom', toAnchor: 'top',  style: 'audio' },
    { from: 'talkie',     to: 'iCloud',       fromAnchor: 'right',  toAnchor: 'left', style: 'cloudkit' },
    { from: 'iPhone',     to: 'iCloud',       fromAnchor: 'left',   toAnchor: 'right', style: 'cloudkit' },
    { from: 'iPhone',     to: 'watch',        fromAnchor: 'bottom', toAnchor: 'top',  style: 'peer' },
  ],

  connectorStyles: {
    xpc:      { color: 'emerald', strokeWidth: 2, label: 'XPC' },
    audio:    { color: 'blue',    strokeWidth: 2, label: 'Audio' },
    cloudkit: { color: 'sky',     strokeWidth: 2 },
    peer:     { color: 'zinc',    strokeWidth: 2 },
  },
}

export default diagram
