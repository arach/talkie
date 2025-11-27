"use client"
import React from 'react'
import {
  ShieldCheck,
  Lock,
  Smartphone,
  Cloud,
  Monitor,
  Network,
  Workflow,
  ArrowRight,
  Globe
} from 'lucide-react'

const ServiceBadge = ({ label, icon: Icon, imgSrc, color = "text-zinc-400" }) => (
  <div className="flex items-center gap-2.5 bg-zinc-950 border border-zinc-800 px-3 py-2.5 rounded shadow-sm hover:border-zinc-700 hover:bg-zinc-900 transition-all cursor-default group">
    {imgSrc ? (
       <img src={imgSrc} alt={label} className="w-3.5 h-3.5 object-contain opacity-70 group-hover:opacity-100 transition-all grayscale group-hover:grayscale-0" />
    ) : (
       Icon && <Icon className={`w-3.5 h-3.5 ${color}`} />
    )}
    <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-400 group-hover:text-zinc-300 transition-colors">{label}</span>
  </div>
)

export function SecurityInfographic() {
  return (
    <div className="bg-zinc-950 border border-zinc-800 p-6 md:p-12 relative overflow-visible rounded-sm select-none">
      <div className="absolute inset-0 bg-tactical-grid-dark opacity-20 pointer-events-none" />

      <div className="relative z-10">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-12">
            <div className="flex items-center gap-3">
            <ShieldCheck className="w-6 h-6 text-emerald-500" />
            <div className="flex flex-col">
                <h2 className="text-xl font-bold text-white uppercase tracking-wide leading-none">Security Architecture</h2>
                <span className="text-[10px] font-mono text-zinc-500 uppercase mt-1">Data Sovereignty Model v1.2</span>
            </div>
            </div>
             <div className="flex items-center gap-4 text-[10px] font-mono uppercase text-zinc-500">
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.5)]"></div>
                    <span>Trusted</span>
                </div>
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-indigo-500"></div>
                    <span>Runtime</span>
                </div>
                <div className="flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-amber-500"></div>
                    <span>External</span>
                </div>
            </div>
        </div>

        {/* 3-Part Grid Layout */}
        <div className="grid grid-cols-1 lg:grid-cols-12 border border-zinc-800 rounded-sm overflow-visible bg-zinc-950/50">

          {/* LEFT: TRUSTED ZONE (5 cols) - Green Hover */}
          <div className="lg:col-span-5 relative bg-zinc-900/30 p-8 flex flex-col justify-between border-b lg:border-b-0 lg:border-r border-zinc-800 group/trusted hover:bg-emerald-900/10 transition-colors duration-500">
             {/* Header */}
             <div className="flex items-center justify-between mb-8 lg:mb-0">
                <div className="flex items-center gap-2">
                    <Lock className="w-3 h-3 text-emerald-500" />
                    <span className="text-xs font-mono font-bold uppercase text-emerald-500 tracking-widest group-hover/trusted:text-emerald-400 transition-colors">Extended Trusted Zone</span>
                </div>
             </div>

             {/* Content: Vertical Stack with Custom Spacing */}
             <div className="flex flex-col gap-6 relative mt-4">
                {/* Connecting Line (Vertical) */}
                <div className="absolute left-6 top-6 bottom-6 w-px bg-zinc-800 z-0 border-l border-dashed border-zinc-700/50 group-hover/trusted:border-emerald-500/30 transition-colors"></div>

                {/* iPhone Card */}
                <div className="w-full flex items-start gap-4 bg-zinc-950 p-4 border border-zinc-800 rounded-sm z-10 relative group hover:border-emerald-500/50 transition-colors">
                   <div className="p-2 bg-zinc-900 rounded-sm text-white border border-zinc-800 group-hover:border-emerald-500/50 transition-colors">
                      <Smartphone className="w-4 h-4 group-hover:text-emerald-400 transition-colors" />
                   </div>
                   <div className="flex-1">
                      <h4 className="text-xs font-bold text-white uppercase tracking-wider mb-2">iPhone</h4>
                      <ul className="space-y-1.5">
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-400">
                            <span className="w-1 h-1 bg-zinc-600 rounded-full group-hover:bg-emerald-500 transition-colors"></span> Voice Input
                         </li>
                      </ul>
                   </div>
                </div>

                {/* iCloud Card */}
                <div className="w-full flex items-start gap-4 bg-zinc-950 p-4 border border-zinc-800 rounded-sm z-10 relative group hover:border-emerald-500/50 transition-colors">
                   <div className="p-2 bg-zinc-900 rounded-sm text-zinc-400 border border-zinc-800 group-hover:border-emerald-500/50 transition-colors">
                      <Cloud className="w-4 h-4 group-hover:text-emerald-400 transition-colors" />
                   </div>
                   <div className="flex-1">
                      <h4 className="text-xs font-bold text-zinc-300 uppercase tracking-wider mb-2">iCloud</h4>
                      <ul className="space-y-1.5">
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-500">
                            <span className="w-1 h-1 bg-zinc-700 rounded-full group-hover:bg-emerald-500 transition-colors"></span> Encrypted Sync
                         </li>
                      </ul>
                   </div>
                </div>

                {/* Mac Card - Bottom Aligned */}
                <div className="w-full flex items-start gap-4 bg-zinc-950 p-4 border border-zinc-800 rounded-sm z-10 relative group hover:border-emerald-500/50 transition-colors">
                   <div className="p-2 bg-zinc-900 rounded-sm text-white border border-zinc-800 group-hover:border-emerald-500/50 transition-colors">
                      <Monitor className="w-4 h-4 group-hover:text-emerald-400 transition-colors" />
                   </div>
                   <div className="flex-1">
                      <h4 className="text-xs font-bold text-white uppercase tracking-wider mb-2">Mac</h4>
                      <ul className="space-y-1.5">
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-400">
                            <span className="w-1 h-1 bg-zinc-600 rounded-full group-hover:bg-emerald-500 transition-colors"></span> File System
                         </li>
                         <li className="flex items-center gap-2 text-[9px] font-mono text-zinc-400">
                            <span className="w-1 h-1 bg-zinc-600 rounded-full group-hover:bg-emerald-500 transition-colors"></span> Neural Engine
                         </li>
                      </ul>
                   </div>

                   {/* Connector to Talkie (Horizontal Pipe) */}
                   <div className="absolute -right-8 top-1/2 -translate-y-1/2 z-30 hidden lg:block w-8 h-10 overflow-visible pointer-events-none">
                      <div className="absolute top-1/2 left-0 w-full h-[2px] bg-zinc-800 group-hover:bg-emerald-500/50 transition-colors"></div>
                   </div>
                </div>

             </div>

             {/* Background tint */}
             <div className="absolute inset-0 bg-emerald-500/0 group-hover/trusted:bg-emerald-500/5 pointer-events-none transition-colors duration-500" />
          </div>

          {/* MIDDLE: TALKIE ENGINE (3 cols) - Indigo Hover */}
          <div className="lg:col-span-3 relative bg-zinc-900/10 flex flex-col justify-end border-b lg:border-b-0 lg:border-r border-zinc-800 group/engine hover:bg-indigo-500/5 transition-colors duration-500">
             <div className="absolute inset-0 bg-tactical-grid-dark opacity-10 pointer-events-none" />

             {/* Header */}
             <div className="absolute top-0 left-0 right-0 p-8 text-center border-b border-zinc-800/50 group-hover/engine:border-indigo-500/20 transition-colors">
                <div className="flex items-center justify-center gap-2 mb-2">
                    <Network className="w-3 h-3 text-zinc-500 group-hover/engine:text-indigo-400 transition-colors" />
                    <span className="text-xs font-mono font-bold uppercase text-zinc-500 tracking-widest group-hover/engine:text-indigo-400 transition-colors">Talkie Engine</span>
                </div>
                <span className="text-[9px] font-mono text-zinc-600 uppercase">Local Runtime</span>
             </div>

             {/* Workflow Conduit - Bottom Aligned with Mac */}
             <div className="flex flex-col items-center justify-end p-4 pb-8 relative z-20">

                {/* Connector Entry Point Overlay (Left) */}
                <div className="absolute left-0 top-1/2 w-4 h-[2px] bg-zinc-800 group-hover/engine:bg-indigo-500/50 transition-colors -translate-y-1/2 hidden lg:block"></div>

                {/* Conduit Card */}
                <div className="relative w-full p-5 flex flex-col items-center justify-center bg-zinc-950 border border-zinc-700 rounded-sm shadow-xl group-hover/engine:border-indigo-500/50 transition-all duration-300">
                   {/* Animated Pulse BG */}
                   <div className="absolute inset-0 bg-zinc-800/20 group-hover/engine:bg-indigo-900/20 transition-colors"></div>

                   <div className="mb-3 p-2 bg-black border border-zinc-800 rounded group-hover/engine:border-indigo-500/50 transition-colors">
                       <Workflow className="w-5 h-5 text-indigo-500" />
                   </div>
                   <span className="text-[10px] font-bold text-white uppercase tracking-wider text-center mb-4">Workflow Conduit</span>

                   {/* Mini Steps */}
                   <div className="w-full space-y-1.5">
                      <div className="flex items-center gap-2 text-[9px] font-mono text-zinc-400 bg-zinc-900/80 px-2 py-1.5 rounded border border-zinc-800/50">
                        <span className="w-1 h-1 bg-zinc-600 rounded-full"></span> 1. Assemble
                      </div>
                      <div className="flex items-center gap-2 text-[9px] font-mono text-zinc-400 bg-zinc-900/80 px-2 py-1.5 rounded border border-zinc-800/50">
                        <span className="w-1 h-1 bg-indigo-500 rounded-full"></span> 2. Sanitize
                      </div>
                      <div className="flex items-center gap-2 text-[9px] font-mono text-zinc-400 bg-zinc-900/80 px-2 py-1.5 rounded border border-zinc-800/50">
                         <span className="w-1 h-1 bg-zinc-600 rounded-full"></span> 3. Dispatch
                      </div>
                   </div>
                </div>

                {/* Exit Arrow - Layered Above Border */}
                <div className="absolute -right-3 top-1/2 -translate-y-1/2 z-30 hidden lg:block">
                   <div className="w-6 h-6 bg-zinc-900 border border-amber-500/50 rounded-full flex items-center justify-center shadow-[0_0_10px_rgba(245,158,11,0.2)] hover:scale-110 transition-transform">
                      <ArrowRight className="w-3 h-3 text-amber-500" />
                   </div>
                </div>
             </div>
          </div>

          {/* RIGHT: EXTERNAL WORLD (4 cols) - Amber Hover */}
          <div className="lg:col-span-4 relative bg-zinc-950 p-8 flex flex-col z-10 group/external hover:bg-amber-900/10 transition-colors duration-500">

             {/* Header */}
             <div className="flex items-center justify-between mb-8">
                <div className="flex items-center gap-2">
                    <Globe className="w-3 h-3 text-amber-500" />
                    <span className="text-xs font-mono font-bold uppercase text-amber-500 tracking-widest group-hover/external:text-amber-400 transition-colors">External World</span>
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

                 <div className="w-full max-w-[200px] border-t border-dashed border-zinc-800 mt-2 group-hover/external:border-amber-500/30 transition-colors"></div>

                 <div className="group relative">
                    <p className="text-[10px] text-zinc-500 text-center max-w-[250px] leading-relaxed cursor-help border-b border-dotted border-zinc-700/50 inline-block pb-0.5 hover:text-zinc-400 transition-colors">
                      Outbound: <span className="text-zinc-400 font-bold group-hover/external:text-amber-500 transition-colors">Text-Only Stream</span>
                    </p>

                    {/* Tooltip */}
                    <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-3 w-48 p-3 bg-zinc-900 border border-zinc-700 rounded shadow-xl opacity-0 group-hover:opacity-100 transition-all duration-200 pointer-events-none z-50">
                       <p className="text-[9px] text-zinc-300 text-center leading-relaxed">
                         Strict Sanitization: Audio remains local. Only text prompts are transmitted.
                       </p>
                       <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 w-2 h-2 bg-zinc-900 border-b border-r border-zinc-700 rotate-45"></div>
                    </div>
                 </div>
             </div>
          </div>

        </div>
      </div>
    </div>
  )
}
