"use client"
import React, { useState } from 'react'
import {
  ShieldCheck,
  Lock,
  Smartphone,
  Cloud,
  Monitor,
  ArrowRight,
  Globe,
  Database,
  FileKey,
  Wifi,
  Info
} from 'lucide-react'

const ServiceBadge = ({ label, icon: Icon, imgSrc, color = "text-zinc-400" }) => (
  <div className="flex items-center gap-2.5 bg-zinc-100 dark:bg-zinc-950 border border-zinc-300 dark:border-zinc-800 px-3 py-2.5 rounded shadow-sm hover:border-zinc-400 dark:hover:border-zinc-700 hover:bg-zinc-200 dark:hover:bg-zinc-900 transition-all cursor-default group">
    {imgSrc ? (
       <img src={imgSrc} alt={label} className="w-3.5 h-3.5 object-contain opacity-70 group-hover:opacity-100 transition-all grayscale group-hover:grayscale-0 dark:invert-0" />
    ) : (
       Icon && <Icon className={`w-3.5 h-3.5 ${color}`} />
    )}
    <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-600 dark:text-zinc-400 group-hover:text-zinc-800 dark:group-hover:text-zinc-300 transition-colors">{label}</span>
  </div>
)

export function SecurityInfographic() {
  const [activeZone, setActiveZone] = useState(null)

  // Focus States
  const isInput = activeZone === 'input'      // Specific iPhone focus
  const isProcessing = activeZone === 'processing' // Specific Mac focus
  const isUserZone = activeZone === 'user-zone'    // General Zone focus
  const isBarrier = activeZone === 'barrier'       // Lock/Gate focus
  const isExternal = activeZone === 'external'     // Services focus

  // Derived Color States
  // If User Zone is hovered, everything inside turns Green.
  // Otherwise, iPhone is Blue, Mac is Purple.
  const iphoneColorState = isUserZone ? 'green' : (isInput ? 'blue' : 'idle')
  const macColorState = isUserZone ? 'green' : (isProcessing ? 'purple' : 'idle')
  const icloudActive = isUserZone || isInput || isProcessing // iCloud lights up for any internal activity

  // Highlight connection if either end is active or if user zone is active
  const iphoneConnState = isUserZone ? 'green' : (isInput ? 'blue' : 'idle')
  const macConnState = isUserZone ? 'green' : (isProcessing ? 'purple' : 'idle')

  // Outbound Path Highlight: Active if Processing (Mac) OR Barrier OR External is hovered
  const isOutboundActive = isProcessing || isBarrier || isExternal

  // Helper for conditional classes based on color state
  const getThemeClasses = (colorState) => {
    switch (colorState) {
        case 'green': return 'bg-emerald-500/10 border-emerald-500/30 shadow-[0_0_15px_rgba(16,185,129,0.1)]'
        case 'blue': return 'bg-blue-500/10 border-blue-500/30 shadow-[0_0_15px_rgba(59,130,246,0.1)]'
        case 'purple': return 'bg-purple-500/10 border-purple-500/30 shadow-[0_0_15px_rgba(168,85,247,0.1)]'
        default: return 'bg-white/50 dark:bg-zinc-900/30 border-zinc-300 dark:border-zinc-800'
    }
  }

  const getIconColor = (colorState) => {
      switch (colorState) {
          case 'green': return 'text-emerald-500 dark:text-emerald-400'
          case 'blue': return 'text-blue-500 dark:text-blue-400'
          case 'purple': return 'text-purple-500 dark:text-purple-400'
          default: return 'text-zinc-400 dark:text-zinc-500'
      }
  }

  const getTextColor = (colorState) => {
    switch (colorState) {
        case 'green': return 'text-emerald-600 dark:text-emerald-300'
        case 'blue': return 'text-blue-600 dark:text-blue-300'
        case 'purple': return 'text-purple-600 dark:text-purple-300'
        default: return 'text-zinc-700 dark:text-zinc-300'
    }
  }

  // Legend Dynamic Colors
  const inputLegendColor = isUserZone ? 'bg-emerald-500' : 'bg-blue-500'
  const processingLegendColor = isUserZone ? 'bg-emerald-500' : 'bg-purple-500'

  return (
    <div className="bg-zinc-100 dark:bg-zinc-950 border border-zinc-300 dark:border-zinc-800 p-6 md:p-12 relative overflow-visible rounded-sm select-none" onMouseLeave={() => setActiveZone(null)}>
      <div className="absolute inset-0 bg-tactical-grid-dark opacity-10 dark:opacity-20 pointer-events-none" />

      <div className="relative z-10">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-12">
            <div className="flex items-center gap-3">
            <ShieldCheck className="w-6 h-6 text-emerald-500" />
            <div className="flex flex-col">
                <h2 className="text-xl font-bold text-zinc-900 dark:text-white uppercase tracking-wide leading-none">Security Architecture</h2>
                <span className="text-[10px] font-mono text-zinc-500 uppercase mt-1">Data Sovereignty Model v1.2</span>
            </div>
            </div>
             <div className="flex items-center gap-4 text-[10px] font-mono uppercase text-zinc-500">
                {/* Legend: Input */}
                <div className={`flex items-center gap-2 transition-opacity duration-300 ${activeZone && !isInput && !isUserZone ? 'opacity-30' : 'opacity-100'}`}>
                    <div className={`w-2 h-2 rounded-full shadow-[0_0_8px_rgba(255,255,255,0.2)] transition-colors duration-300 ${inputLegendColor}`}></div>
                    <span>Input (iOS)</span>
                </div>
                {/* Legend: Processing */}
                 <div className={`flex items-center gap-2 transition-opacity duration-300 ${activeZone && !isProcessing && !isUserZone ? 'opacity-30' : 'opacity-100'}`}>
                    <div className={`w-2 h-2 rounded-full shadow-[0_0_8px_rgba(255,255,255,0.2)] transition-colors duration-300 ${processingLegendColor}`}></div>
                    <span>Processing (macOS)</span>
                </div>
                {/* Legend: Services */}
                <div className={`flex items-center gap-2 transition-opacity duration-300 ${activeZone && !isExternal && !isBarrier && !isProcessing ? 'opacity-30' : 'opacity-100'}`}>
                    <div className={`w-2 h-2 rounded-full bg-amber-500 transition-colors ${isBarrier ? 'animate-pulse' : ''}`}></div>
                    <span>Services</span>
                </div>
            </div>
        </div>

        {/* Main Grid Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-12 border border-zinc-300 dark:border-zinc-800 rounded-sm overflow-visible bg-white/50 dark:bg-zinc-950/50 relative">

          {/* === USER OWNED ZONE (Left 8 Cols) === */}
          <div
            className="lg:col-span-8 relative flex flex-col p-8 group/zone z-20"
            onMouseOver={() => setActiveZone('user-zone')}
          >

             {/* Zone Header */}
             <div className="flex items-center justify-between mb-8 z-20 pointer-events-none">
                <div className="flex items-center gap-2">
                    <Lock className={`w-3 h-3 transition-colors ${icloudActive ? 'text-emerald-400' : 'text-zinc-500'}`} />
                    <span className={`text-xs font-mono font-bold uppercase tracking-widest transition-colors ${icloudActive ? 'text-emerald-400' : 'text-zinc-500'}`}>User Owned Zone</span>
                </div>
             </div>

             {/* SVG Overlay for Internal Flows */}
             <svg className="absolute inset-0 w-full h-full pointer-events-none z-0" xmlns="http://www.w3.org/2000/svg">
                <defs>
                  {/* Colors: Emerald, Blue, Purple */}
                  <marker id="arrowhead-emerald" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                    <path d="M0,0 L6,3 L0,6 L0,0" fill="#10b981" />
                  </marker>
                  <marker id="arrowhead-blue" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                     <path d="M0,0 L6,3 L0,6 L0,0" fill="#3b82f6" />
                  </marker>
                   <marker id="arrowhead-purple" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                     <path d="M0,0 L6,3 L0,6 L0,0" fill="#a855f7" />
                  </marker>
                  <marker id="arrowhead-zinc" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
                     <path d="M0,0 L6,3 L0,6 L0,0" fill="#52525b" />
                  </marker>
                </defs>

                {/* iPhone <-> iCloud (2 Paths for Bidirectional Juice) */}
                {/* Upstream (Upload) */}
                <path
                  d="M 23% 62% L 23% 45%"
                  fill="none"
                  stroke={iphoneConnState === 'green' ? '#10b981' : (iphoneConnState === 'blue' ? '#3b82f6' : '#3f3f46')}
                  strokeWidth="1.5"
                  strokeDasharray={iphoneConnState !== 'idle' ? "0" : "4 4"}
                  className="transition-colors duration-500"
                  markerEnd={iphoneConnState === 'green' ? "url(#arrowhead-emerald)" : (iphoneConnState === 'blue' ? "url(#arrowhead-blue)" : "url(#arrowhead-zinc)")}
                />
                {/* Downstream (Sync Back) */}
                 <path
                  d="M 27% 45% L 27% 62%"
                  fill="none"
                  stroke={iphoneConnState === 'green' ? '#10b981' : (iphoneConnState === 'blue' ? '#3b82f6' : '#3f3f46')}
                  strokeWidth="1.5"
                  strokeDasharray={iphoneConnState !== 'idle' ? "0" : "4 4"}
                  className="transition-colors duration-500"
                  markerEnd={iphoneConnState === 'green' ? "url(#arrowhead-emerald)" : (iphoneConnState === 'blue' ? "url(#arrowhead-blue)" : "url(#arrowhead-zinc)")}
                />

                {/* Mac <-> iCloud (2 Paths for Bidirectional Juice) */}
                {/* Upstream (Status/Upload) */}
                <path
                  d="M 73% 62% L 73% 45%"
                  fill="none"
                  stroke={macConnState === 'green' ? '#10b981' : (macConnState === 'purple' ? '#a855f7' : '#3f3f46')}
                  strokeWidth="1.5"
                  strokeDasharray={macConnState !== 'idle' ? "0" : "4 4"}
                  className="transition-colors duration-500"
                  markerEnd={macConnState === 'green' ? "url(#arrowhead-emerald)" : (macConnState === 'purple' ? "url(#arrowhead-purple)" : "url(#arrowhead-zinc)")}
                />
                {/* Downstream (Sync Down) */}
                 <path
                  d="M 77% 45% L 77% 62%"
                  fill="none"
                  stroke={macConnState === 'green' ? '#10b981' : (macConnState === 'purple' ? '#a855f7' : '#3f3f46')}
                  strokeWidth="1.5"
                  strokeDasharray={macConnState !== 'idle' ? "0" : "4 4"}
                  className="transition-colors duration-500"
                  markerEnd={macConnState === 'green' ? "url(#arrowhead-emerald)" : (macConnState === 'purple' ? "url(#arrowhead-purple)" : "url(#arrowhead-zinc)")}
                />
             </svg>

             {/* Content Grid */}
             <div className="grid grid-cols-1 md:grid-cols-2 gap-x-12 gap-y-12 relative z-10">

                {/* --- ROW 1: iCloud (Spans 2) --- */}
                <div className="col-span-1 md:col-span-2">
                   <div
                      className={`w-full flex items-center justify-between gap-4 p-4 border rounded-sm transition-all duration-300 ${
                          icloudActive
                          ? 'bg-emerald-500/5 border-emerald-500/30'
                          : 'bg-white/50 dark:bg-zinc-900/30 border-zinc-300 dark:border-zinc-800'
                      }`}
                  >
                     <div className="flex items-center gap-4">
                        <div className={`p-2 rounded-sm border transition-colors ${
                            icloudActive ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-500' : 'bg-zinc-100 dark:bg-zinc-950 border-zinc-300 dark:border-zinc-800 text-zinc-500'
                        }`}>
                            <Cloud className="w-5 h-5" />
                        </div>
                        <div>
                            <h4 className={`text-xs font-bold uppercase tracking-wider mb-1 transition-colors ${icloudActive ? 'text-emerald-500 dark:text-emerald-400' : 'text-zinc-700 dark:text-zinc-300'}`}>iCloud</h4>
                            <span className="text-[10px] font-mono text-zinc-500">Encrypted CloudKit Container</span>
                        </div>
                     </div>

                     <div className="hidden md:flex items-center gap-6 pr-4">
                        <div className="flex items-center gap-2 text-[9px] font-mono uppercase text-zinc-500">
                           <Database className="w-3 h-3" /> Private DB
                        </div>
                         <div className="flex items-center gap-2 text-[9px] font-mono uppercase text-zinc-500">
                           <FileKey className="w-3 h-3" /> User Keys Only
                        </div>
                         <div className="flex items-center gap-2 text-[9px] font-mono uppercase text-zinc-500">
                           <Wifi className="w-3 h-3" /> Sync Only
                        </div>
                     </div>
                  </div>
                </div>

                {/* --- ROW 2: iPhone (Left) --- */}
                <div className="flex flex-col gap-2">
                   {/* Card */}
                   <div
                      onMouseOver={(e) => {
                          e.stopPropagation()
                          setActiveZone('input')
                      }}
                      className={`flex flex-col border rounded-sm transition-all duration-300 h-full ${getThemeClasses(iphoneColorState)}`}
                  >
                     {/* Card Header */}
                     <div className="flex items-center gap-3 p-4 border-b border-inherit">
                        <Smartphone className={`w-4 h-4 transition-colors ${getIconColor(iphoneColorState)}`} />
                        <h4 className={`text-xs font-bold uppercase tracking-wider transition-colors ${getTextColor(iphoneColorState)}`}>iPhone</h4>
                     </div>

                     {/* Details Block */}
                     <div className="p-4 flex-1">
                        <div className={`mb-3 text-[9px] font-mono font-bold uppercase tracking-widest transition-colors ${
                             iphoneColorState !== 'idle' ? 'opacity-100' : 'text-zinc-600'
                        }`} style={{ color: iphoneColorState === 'green' ? '#10b981' : (iphoneColorState === 'blue' ? '#60a5fa' : '') }}>
                           Input Context
                        </div>
                        <div className="space-y-2">
                           {[
                              "1. Audio Capture (VAD)",
                              "2. Local Encryption",
                              "3. Sync Push"
                           ].map((step, i) => (
                              <div key={i} className={`flex items-center gap-2 p-1.5 border rounded-sm transition-colors ${
                                  iphoneColorState !== 'idle'
                                    ? (iphoneColorState === 'green' ? 'bg-emerald-500/20 border-emerald-500/30 text-emerald-700 dark:text-emerald-100' : 'bg-blue-500/20 border-blue-500/30 text-blue-700 dark:text-blue-100')
                                    : 'bg-zinc-100 dark:bg-zinc-950/50 border-zinc-300/50 dark:border-zinc-800/50 text-zinc-600'
                              }`}>
                                 <span className="text-[9px] font-mono uppercase tracking-wide">{step}</span>
                              </div>
                           ))}
                        </div>
                     </div>
                  </div>
                </div>

                {/* --- ROW 2: Mac (Right) --- */}
                <div className="flex flex-col gap-2 relative">
                   {/* Card */}
                   <div
                      onMouseOver={(e) => {
                          e.stopPropagation()
                          setActiveZone('processing')
                      }}
                      className={`flex flex-col border rounded-sm transition-all duration-300 h-full ${getThemeClasses(macColorState)}`}
                  >
                     {/* Card Header */}
                     <div className="flex items-center gap-3 p-4 border-b border-inherit">
                        <Monitor className={`w-4 h-4 transition-colors ${getIconColor(macColorState)}`} />
                        <h4 className={`text-xs font-bold uppercase tracking-wider transition-colors ${getTextColor(macColorState)}`}>Mac</h4>
                     </div>

                     {/* Details Block */}
                     <div className="p-4 flex-1">
                        <div className={`mb-3 text-[9px] font-mono font-bold uppercase tracking-widest transition-colors ${
                            macColorState !== 'idle' ? 'opacity-100' : 'text-zinc-600'
                        }`} style={{ color: macColorState === 'green' ? '#10b981' : (macColorState === 'purple' ? '#c084fc' : '') }}>
                           Runtime Details
                        </div>
                        <div className="space-y-2">
                           {[
                              "1. Context Assembly",
                              "2. PII Redaction",
                              "3. Secure Dispatch"
                           ].map((step, i) => (
                              <div key={i} className={`flex items-center gap-2 p-1.5 border rounded-sm transition-colors ${
                                  macColorState !== 'idle'
                                    ? (macColorState === 'green' ? 'bg-emerald-500/20 border-emerald-500/30 text-emerald-700 dark:text-emerald-100' : 'bg-purple-500/20 border-purple-500/30 text-purple-700 dark:text-purple-100')
                                    : 'bg-zinc-100 dark:bg-zinc-950/50 border-zinc-300/50 dark:border-zinc-800/50 text-zinc-600'
                              }`}>
                                 <span className="text-[9px] font-mono uppercase tracking-wide">{step}</span>
                              </div>
                           ))}
                        </div>
                     </div>
                  </div>

                  {/* Outbound Arrow (Interactive via Barrier) */}
                  <div className="absolute top-[60%] left-full z-50 flex items-center pointer-events-none -ml-px pl-2">
                       <div className={`w-24 h-0.5 relative transition-colors delay-75 ${isOutboundActive ? 'bg-amber-500 shadow-[0_0_10px_rgba(245,158,11,0.8)]' : 'bg-zinc-400 dark:bg-zinc-800'}`}></div>
                       <ArrowRight className={`w-4 h-4 -ml-1 transition-colors delay-75 ${isOutboundActive ? 'text-amber-500' : 'text-zinc-500 dark:text-zinc-600'}`} />
                  </div>
                </div>

             </div>

             {/* SANITIZATION BARRIER (Interactive) */}
             <div
                className="hidden lg:flex absolute top-0 right-0 bottom-0 w-[40px] translate-x-1/2 z-40 flex-col items-center justify-center cursor-crosshair group/barrier"
                onMouseOver={(e) => {
                    e.stopPropagation()
                    setActiveZone('barrier')
                }}
             >
                 {/* Visual Line */}
                 <div className={`absolute inset-y-0 w-[8px] border-l border-r transition-colors duration-300 ${
                     isBarrier ? 'bg-amber-950/50 border-amber-500/50 shadow-[0_0_15px_rgba(0,0,0,0.8)]' : 'bg-zinc-100/80 dark:bg-zinc-950 border-zinc-300/60 dark:border-zinc-700 shadow-[0_0_10px_rgba(0,0,0,0.05)] dark:shadow-[0_0_15px_rgba(0,0,0,0.8)]'
                 }`}></div>

                 {/* Hatch Pattern */}
                 <div className={`absolute inset-y-0 w-[6px] bg-[length:6px_6px] transition-opacity duration-300 ${
                     isBarrier
                        ? 'bg-[linear-gradient(45deg,transparent_25%,#fbbf24_25%,#fbbf24_50%,transparent_50%,transparent_75%,#fbbf24_75%,#fbbf24_100%)] opacity-40'
                        : 'bg-[linear-gradient(45deg,transparent_25%,#fbbf24_25%,#fbbf24_50%,transparent_50%,transparent_75%,#fbbf24_75%,#fbbf24_100%)] opacity-20'
                 }`}></div>

                 {/* Lock Icon */}
                 <div className={`relative z-10 p-1.5 bg-zinc-100 dark:bg-zinc-950 border rounded-full transition-all duration-300 ${
                     isBarrier ? 'text-amber-500 border-amber-500 shadow-[0_0_15px_rgba(245,158,11,0.5)] scale-110' : (isProcessing ? 'text-amber-500 border-amber-500/50' : 'text-zinc-500 dark:text-zinc-600 border-zinc-400 dark:border-zinc-700')
                 }`}>
                    <Lock className="w-3.5 h-3.5" />
                 </div>
             </div>

          </div>

          {/* === EXTERNAL SERVICES (Right 4 Cols) === */}
          <div
            onMouseOver={() => setActiveZone('external')}
            className={`lg:col-span-4 relative bg-zinc-50 dark:bg-zinc-950 p-8 flex flex-col z-10 transition-colors duration-500 ${
                isExternal ? 'bg-amber-100/50 dark:bg-amber-900/10' : ''
            }`}
          >

             {/* Header */}
             <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-2">
                    <Globe className={`w-3 h-3 transition-colors ${isOutboundActive ? 'text-amber-400' : 'text-amber-500/70'}`} />
                    <span className={`text-xs font-mono font-bold uppercase tracking-widest transition-colors ${isOutboundActive ? 'text-amber-400' : 'text-amber-500/70'}`}>External Services</span>
                </div>
             </div>

             {/* Content */}
             <div className="flex-1 flex flex-col justify-center items-center gap-8">
                 <div className="grid grid-cols-2 gap-3 w-full max-w-[280px]">
                    <ServiceBadge label="OpenAI" imgSrc="https://cdn.simpleicons.org/openai/white" />
                    <ServiceBadge label="Anthropic" imgSrc="https://cdn.simpleicons.org/anthropic/white" />
                    <ServiceBadge label="Google" imgSrc="https://cdn.simpleicons.org/google" />
                    <ServiceBadge label="Notion" imgSrc="https://cdn.simpleicons.org/notion/white" />
                    <ServiceBadge label="Zapier" imgSrc="https://cdn.simpleicons.org/zapier/FF4F00" />
                    <ServiceBadge label="Linear" imgSrc="https://cdn.simpleicons.org/linear/5E6AD2" />
                 </div>

                 <div className={`w-full max-w-[200px] border-t border-dashed mt-2 transition-colors ${isOutboundActive ? 'border-amber-500/50' : 'border-zinc-300 dark:border-zinc-800'}`}></div>

                 <div className={`group/tooltip relative transition-all duration-300 ${isBarrier ? 'scale-105' : ''}`}>
                    <p className={`text-[10px] text-center max-w-[250px] leading-relaxed cursor-help border-b border-dotted inline-block pb-0.5 transition-colors ${
                        isOutboundActive ? 'text-zinc-900 dark:text-zinc-100 border-amber-500' : 'text-zinc-500 border-zinc-400/50 dark:border-zinc-700/50'
                    }`}>
                      Outbound: <span className={`font-bold transition-colors ${isOutboundActive ? 'text-amber-500' : 'text-zinc-600 dark:text-zinc-400'}`}>Text-Only Stream</span>
                    </p>

                    {/* Tooltip Pop-up */}
                    <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-3 w-56 p-3 bg-white dark:bg-zinc-900 border border-zinc-300 dark:border-zinc-800 text-zinc-700 dark:text-zinc-300 text-[10px] leading-relaxed rounded shadow-xl opacity-0 group-hover/tooltip:opacity-100 transition-all duration-300 pointer-events-none z-50">
                       <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 w-2 h-2 bg-white dark:bg-zinc-900 border-r border-b border-zinc-300 dark:border-zinc-800 rotate-45"></div>
                       <div className="flex gap-2">
                          <Info className="w-3.5 h-3.5 text-amber-500 shrink-0 mt-0.5" />
                          <span>
                             Only the final, sanitized text prompt is sent. Audio files never leave your device.
                          </span>
                       </div>
                    </div>
                 </div>
             </div>
          </div>

        </div>
      </div>
    </div>
  )
}
