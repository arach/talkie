import React from 'react';
import { CodeArchitecture } from './components/AICodeGenerator';
import { Button } from './components/Button';
import { MockInterface } from './components/MockInterface';
import { FeaturesPage } from './components/FeaturesPage';
import { Github, Box, Layers, Zap, MousePointer2, ArrowDown, Package, Copy, CheckCircle2, XCircle, Puzzle, Gamepad2, Workflow, Bot, Brain, MessageSquare, GitBranch, Cpu, Eye } from 'lucide-react';

const Features = () => (
  <div className="relative border-t border-zinc-800">
    <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-px bg-zinc-800">
      {[
        { icon: <Zap size={24} strokeWidth={1} />, title: "NATIVE SWIFT", desc: "Zero WebViews. Pure Metal-accelerated SwiftUI rendering engine." },
        { icon: <Layers size={24} strokeWidth={1} />, title: "NODE GRAPH", desc: "Directed acyclic graph architecture with cycle detection." },
        { icon: <Puzzle size={24} strokeWidth={1} />, title: "EXTENSIBLE", desc: "Protocol-oriented design for custom node types." },
        { icon: <MousePointer2 size={24} strokeWidth={1} />, title: "INTERACTIVE", desc: "Custom gesture recognizers for pan, zoom, and drag operations." }
      ].map((f, i) => (
        <div key={i} className="p-10 bg-[#09090b] hover:bg-[#050505] transition-colors group relative border-r border-zinc-800 last:border-r-0">
          <div className="mb-6 text-zinc-500 group-hover:text-white transition-colors">{f.icon}</div>
          <h3 className="text-sm font-bold text-white mb-3 font-sans uppercase tracking-widest">{f.title}</h3>
          <p className="text-sm text-zinc-500 leading-relaxed font-mono">{f.desc}</p>
        </div>
      ))}
    </div>
  </div>
);

const ComparisonTable = () => (
  <div className="border border-zinc-800 bg-[#0c0c0e]">
    <div className="grid grid-cols-3 border-b border-zinc-800 bg-zinc-900/20">
      <div className="p-4 text-xs font-bold text-zinc-500 uppercase tracking-widest">Feature</div>
      <div className="p-4 text-xs font-bold text-white uppercase tracking-widest border-l border-zinc-800 bg-zinc-900/40">WFKit</div>
      <div className="p-4 text-xs font-bold text-zinc-600 uppercase tracking-widest border-l border-zinc-800">Web-based</div>
    </div>
    {[
      { label: "Startup time", wf: "<50ms", web: "500ms+" },
      { label: "Memory footprint", wf: "12MB", web: "100MB+" },
      { label: "Offline support", wf: "Always", web: "Depends" },
      { label: "Native feel", wf: "100%", web: "Electron-ish" },
      { label: "Bundle size", wf: "2MB", web: "20MB+" },
    ].map((row, i) => (
      <div key={i} className="grid grid-cols-3 border-b last:border-b-0 border-zinc-800 hover:bg-white/5 transition-colors">
        <div className="p-4 text-xs font-mono text-zinc-400">{row.label}</div>
        <div className="p-4 text-xs font-mono text-white border-l border-zinc-800 font-bold bg-white/5">{row.wf}</div>
        <div className="p-4 text-xs font-mono text-zinc-600 border-l border-zinc-800">{row.web}</div>
      </div>
    ))}
  </div>
);

const UseCases = () => (
  <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
    {[
      { title: "AI Workflows", icon: <Workflow size={20}/>, desc: "Build visual agent orchestration tools with drag-and-drop simplicity." },
      { title: "Data Pipelines", icon: <Layers size={20}/>, desc: "Let users design ETL workflows without writing code." },
      { title: "Automation", icon: <Zap size={20}/>, desc: "Create Shortcuts-like experiences in your own apps." },
      { title: "Game Logic", icon: <Gamepad2 size={20}/>, desc: "Visual scripting for game designers and modders." },
    ].map((useCase, i) => (
      <div key={i} className="border border-zinc-800 p-6 bg-[#0c0c0e] hover:border-zinc-600 transition-colors">
        <div className="mb-4 text-zinc-400">{useCase.icon}</div>
        <h4 className="text-sm font-bold text-white mb-2 uppercase tracking-wide">{useCase.title}</h4>
        <p className="text-xs text-zinc-500 font-mono leading-relaxed">{useCase.desc}</p>
      </div>
    ))}
  </div>
);

const Navbar = () => (
  <nav className="fixed top-0 left-0 right-0 z-50 bg-[#09090b]/90 backdrop-blur-md border-b border-zinc-800">
    <div className="max-w-[1400px] mx-auto px-6 h-16 flex items-center justify-between">
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 bg-white flex items-center justify-center">
          <Box size={16} className="text-black" strokeWidth={3} />
        </div>
        <span className="font-sans font-bold text-lg tracking-tighter text-white">WFKit</span>
      </div>
      <div className="hidden md:flex items-center gap-8">
        <a href="#features" className="text-xs font-bold uppercase tracking-widest text-zinc-500 hover:text-white transition-colors">Features</a>
        <a href="#docs" className="text-xs font-bold uppercase tracking-widest text-zinc-500 hover:text-white transition-colors">Documentation</a>
        <a href="#specs" className="text-xs font-bold uppercase tracking-widest text-zinc-500 hover:text-white transition-colors">Specs</a>
        <a href="#install" className="text-xs font-bold uppercase tracking-widest text-zinc-500 hover:text-white transition-colors">Install</a>
        <div className="h-4 w-[1px] bg-zinc-800"></div>
        <a href="https://github.com/arach/WFKit" className="text-zinc-500 hover:text-white transition-colors flex items-center gap-2 border border-zinc-800 hover:border-zinc-600 px-4 py-2">
            <Github size={16} />
            <span className="text-xs font-bold uppercase tracking-widest">GitHub</span>
        </a>
      </div>
    </div>
  </nav>
);

const Footer = () => (
  <footer className="border-t border-zinc-800 bg-[#050505] py-20 mt-20 relative">
    <div className="max-w-[1400px] mx-auto px-6 flex flex-col md:flex-row justify-between items-start md:items-center gap-10">
       <div className="flex flex-col gap-4">
         <div className="flex items-center gap-2">
            <Box size={20} className="text-white" />
            <span className="font-sans font-bold text-xl text-white tracking-tighter">WFKit</span>
         </div>
         <p className="text-zinc-600 text-xs font-mono max-w-xs">
           A professional-grade workflow visualization library for the Swift ecosystem.
         </p>
      </div>
      
      <div className="flex gap-12">
        <div className="flex flex-col gap-4">
          <h4 className="font-bold text-white text-xs uppercase tracking-widest">Project</h4>
          <a href="#" className="text-zinc-600 hover:text-white text-xs font-mono transition-colors">Source Code</a>
          <a href="#" className="text-zinc-600 hover:text-white text-xs font-mono transition-colors">License (MIT)</a>
          <a href="#" className="text-zinc-600 hover:text-white text-xs font-mono transition-colors">Releases</a>
        </div>
        <div className="flex flex-col gap-4">
          <h4 className="font-bold text-white text-xs uppercase tracking-widest">Community</h4>
          <a href="#" className="text-zinc-600 hover:text-white text-xs font-mono transition-colors">Discussions</a>
          <a href="#" className="text-zinc-600 hover:text-white text-xs font-mono transition-colors">Issues</a>
          <a href="#" className="text-zinc-600 hover:text-white text-xs font-mono transition-colors">Twitter</a>
        </div>
      </div>
    </div>
  </footer>
);

export default function App() {
  return (
    <div className="min-h-screen bg-[#09090b] selection:bg-white selection:text-black font-mono flex flex-col">
      <Navbar />
      
      <main className="flex-1 pt-32 pb-20 px-6 max-w-[1400px] mx-auto w-full">
        
        {/* Hero Section */}
        <div className="grid lg:grid-cols-12 gap-12 lg:gap-24 items-center mb-40 border-b border-zinc-800 pb-20 relative">

          <div className="lg:col-span-5 relative z-10">
             <div className="inline-flex items-center gap-2 mb-8 border border-zinc-800 px-3 py-1 rounded-full bg-zinc-900/50">
               <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse"></div>
               <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-400">MIT License</span>
             </div>
             
             <h1 className="text-6xl md:text-8xl font-bold text-white mb-8 tracking-tighter leading-[0.85] font-sans">
               NATIVE<br/>
               FLOW<br/>
               ENGINE<span className="text-zinc-600">.</span>
             </h1>
             
             <p className="text-lg text-zinc-400 mb-10 max-w-md leading-relaxed font-light font-sans">
               Bring React Flow-like node editing to your native macOS and iOS apps. 
               Zero dependencies. Pure SwiftUI.
             </p>
             
             <div className="flex flex-col sm:flex-row items-start sm:items-center gap-6">
               <a href="#install"><Button size="lg" icon={<Package size={16}/>}>ADD PACKAGE</Button></a>
               <a href="#docs"><Button size="lg" variant="outline" icon={<ArrowDown size={16}/>}>READ THE DOCS</Button></a>
             </div>
             
             <div className="mt-16 border-t border-zinc-800 pt-6 flex flex-wrap items-center gap-4 text-[10px] text-zinc-600 uppercase tracking-widest font-bold">
                <span className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 bg-zinc-500"></div> iOS 16+
                </span>
                <span className="text-zinc-800">/</span>
                <span className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 bg-zinc-500"></div> macOS 13+
                </span>
                <span className="text-zinc-800">/</span>
                <span>Swift 5.9</span>
             </div>
          </div>

          {/* Graphic / Screenshot Area */}
          <div className="lg:col-span-7 relative">
            <div className="relative border border-zinc-800 bg-[#0c0c0e] p-2 group">
              {/* Technical markers */}
              <div className="absolute top-0 left-0 w-4 h-4 border-t border-l border-white z-20"></div>
              <div className="absolute top-0 right-0 w-4 h-4 border-t border-r border-white z-20"></div>
              <div className="absolute bottom-0 left-0 w-4 h-4 border-b border-l border-white z-20"></div>
              <div className="absolute bottom-0 right-0 w-4 h-4 border-b border-r border-white z-20"></div>
              
              <div className="relative aspect-[16/10] overflow-hidden bg-[#0c0c0e] border border-zinc-800/50">
                 <MockInterface />
                 
                 <div className="absolute bottom-6 right-6 px-4 py-2 bg-black border border-zinc-800 flex items-center gap-4 z-20">
                    <div className="flex items-center gap-2">
                       <div className="w-1.5 h-1.5 bg-green-500 animate-pulse"></div>
                       <span className="text-[10px] text-zinc-300 font-bold uppercase tracking-wider">SwiftUI Preview</span>
                    </div>
                    <span className="text-[10px] text-zinc-600 font-mono">120 FPS</span>
                 </div>
              </div>
            </div>
            
            {/* Background decorative element */}
            <div className="absolute -z-10 top-8 -right-8 w-full h-full border border-zinc-800/30 bg-[url('data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI4IiBoZWlnaHQ9IjgiPgo8cmVjdCB3aWR0aD0iOCIgaGVpZ2h0PSI4IiBmaWxsPSIjMTgxODFiIi8+CjxwYXRoIGQ9Ik0wIDBMOCA4Wk04IDBMMCA4WiIgc3Ryb2tlPSIjMjcyNzJhIiBzdHJva2Utd2lkdGg9IjEiLz4KPC9zdmc+')] opacity-40"></div>
          </div>
        </div>

        {/* Features Section */}
        <div className="mb-40">
          <div className="flex items-end justify-between mb-10">
            <h2 className="text-3xl font-bold text-white font-sans tracking-tight">SYSTEM_ARCHITECTURE</h2>
            <span className="text-xs font-bold text-zinc-600 uppercase tracking-widest">v1.0.0-beta.2</span>
          </div>
          <Features />
        </div>

        {/* Code Showcase Section */}
        <div className="mb-40 border border-zinc-800 bg-[#0c0c0e]">
          <CodeArchitecture frameless />
        </div>

        {/* Features & Screenshots Page */}
        <div className="mb-40">
          <FeaturesPage />
        </div>

        {/* Comparison & Use Cases Grid */}
        <div className="mb-40 grid xl:grid-cols-12 gap-12">
           <div className="xl:col-span-5">
              <h2 className="text-2xl font-bold text-white font-sans tracking-tight mb-8">WHY WFKIT?</h2>
              <ComparisonTable />
           </div>
           <div className="xl:col-span-7">
              <h2 className="text-2xl font-bold text-white font-sans tracking-tight mb-8">USE CASES</h2>
              <UseCases />
           </div>
        </div>

        {/* Agent Development Section */}
        <div id="agents" className="mb-40 scroll-mt-24">
          <div className="flex items-end justify-between mb-10">
            <h2 className="text-3xl font-bold text-white font-sans tracking-tight">FOR AGENT DEVELOPERS</h2>
            <span className="text-xs font-bold text-zinc-600 uppercase tracking-widest">TWF-First</span>
          </div>

          <div className="border border-zinc-800 bg-[#0c0c0e]">
            <div className="grid lg:grid-cols-2 divide-y lg:divide-y-0 lg:divide-x divide-zinc-800">
              {/* Left: Benefits */}
              <div className="p-8 lg:p-12">
                <div className="flex items-center gap-3 mb-6">
                  <Bot size={24} className="text-purple-400" />
                  <h3 className="text-xl font-bold text-white font-sans">Define in JSON, Visualize Natively</h3>
                </div>
                <p className="text-zinc-400 text-sm mb-8 leading-relaxed">
                  TWF (Talkie Workflow Format) lets you define workflows as human-readable JSON.
                  WFKit loads them into a native Swift canvas - no WebViews, pure performance.
                </p>

                <div className="space-y-4">
                  {[
                    { icon: <Brain size={16}/>, title: "LLM Steps", desc: "costTier routing, multi-provider support, template variables" },
                    { icon: <GitBranch size={16}/>, title: "Conditional Logic", desc: "Branch on outputs, loop back, parallel execution" },
                    { icon: <MessageSquare size={16}/>, title: "14 Step Types", desc: "LLM, transcribe, transform, notify, save, shell, and more" },
                    { icon: <Cpu size={16}/>, title: "Deterministic UUIDs", desc: "Slug-based IDs that stay stable across imports" },
                  ].map((item, i) => (
                    <div key={i} className="flex items-start gap-3 p-3 border border-zinc-800 hover:border-zinc-700 transition-colors">
                      <div className="text-zinc-500 mt-0.5">{item.icon}</div>
                      <div>
                        <h4 className="text-xs font-bold text-white uppercase tracking-wide">{item.title}</h4>
                        <p className="text-[11px] text-zinc-500 font-mono mt-1">{item.desc}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Right: TWF Example */}
              <div className="bg-[#050505]">
                <div className="border-b border-zinc-800 px-6 py-3 flex items-center justify-between">
                  <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest">research-pipeline.twf.json</span>
                  <div className="flex items-center gap-2">
                    <div className="w-1.5 h-1.5 bg-purple-500 rounded-full"></div>
                    <span className="text-[10px] text-zinc-600 font-mono">TWF Workflow</span>
                  </div>
                </div>
                <pre className="p-6 text-[11px] text-zinc-400 font-mono overflow-x-auto leading-relaxed">
{`{
  "slug": "research-pipeline",
  "name": "Research & Write",
  "icon": "brain.head.profile",
  "color": "purple",
  "isEnabled": true,
  "steps": [
    {
      "id": "research",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "capable",
          "systemPrompt": "Research assistant.",
          "prompt": "Analyze: {{TRANSCRIPT}}"
        }
      }
    },
    {
      "id": "write",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "balanced",
          "prompt": "Write based on:\\n{{research}}"
        }
      }
    },
    {
      "id": "save-output",
      "type": "Save to File",
      "config": {
        "saveFile": {
          "filename": "{{DATE}}-{{TITLE}}.md",
          "directory": "@Obsidian/Research",
          "content": "# {{TITLE}}\\n\\n{{write}}"
        }
      }
    },
    {
      "id": "notify",
      "type": "Send Notification",
      "config": {
        "notification": {
          "title": "Research complete",
          "body": "{{TITLE}} saved",
          "sound": true
        }
      }
    }
  ]
}`}
                </pre>
              </div>
            </div>
          </div>

          {/* Real TWF Examples */}
          <div className="mt-6 grid lg:grid-cols-3 gap-4">
            <div className="border border-zinc-800 bg-[#050505] p-4">
              <div className="flex items-center gap-2 mb-3">
                <div className="w-2 h-2 bg-blue-500 rounded-full"></div>
                <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">quick-summary.twf.json</span>
              </div>
              <pre className="text-[10px] text-zinc-500 font-mono leading-relaxed">
{`{
  "slug": "quick-summary",
  "name": "Quick Summary",
  "icon": "list.bullet.clipboard",
  "color": "blue",
  "steps": [{
    "id": "summarize",
    "type": "LLM Generation",
    "config": {
      "llm": {
        "costTier": "budget",
        "prompt": "Summarize into a concise paragraph:\\n{{TRANSCRIPT}}"
      }
    }
  }]
}`}
              </pre>
            </div>

            <div className="border border-zinc-800 bg-[#050505] p-4">
              <div className="flex items-center gap-2 mb-3">
                <div className="w-2 h-2 bg-purple-500 rounded-full"></div>
                <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">hq-transcribe.twf.json</span>
              </div>
              <pre className="text-[10px] text-zinc-500 font-mono leading-relaxed">
{`{
  "slug": "hq-transcribe",
  "name": "HQ Transcribe",
  "icon": "waveform.badge.magnifyingglass",
  "color": "purple",
  "steps": [
    { "id": "transcribe-hq",
      "type": "Transcribe Audio",
      "config": { "transcribe": {
        "model": "distil-whisper_distil-large-v3"
      }}},
    { "id": "polish",
      "type": "LLM Generation",
      "config": { "llm": {
        "costTier": "budget",
        "prompt": "Clean up: {{transcribe-hq}}"
      }}}
  ]
}`}
              </pre>
            </div>

            <div className="border border-zinc-800 bg-[#050505] p-4">
              <div className="flex items-center gap-2 mb-3">
                <div className="w-2 h-2 bg-yellow-500 rounded-full"></div>
                <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-widest">feature-ideation.twf.json</span>
              </div>
              <pre className="text-[10px] text-zinc-500 font-mono leading-relaxed">
{`{
  "slug": "feature-ideation",
  "name": "Feature Ideation",
  "icon": "lightbulb.max",
  "color": "yellow",
  "steps": [
    { "id": "extract-features",
      "type": "LLM Generation",
      "config": { "llm": {
        "costTier": "balanced",
        "prompt": "Extract features as JSON..."
      }}},
    { "id": "parse-json",
      "type": "Transform Data",
      "config": { "transform": {
        "operation": "Extract JSON"
      }}},
    { "id": "check-quick-wins",
      "type": "Conditional Branch",
      "config": { "conditional": {
        "condition": "{{parse-json.quickWins.length}} > 0",
        "thenSteps": ["create-reminder"]
      }}},
    { "id": "create-reminder",
      "type": "Create Reminder",
      "config": { "appleReminders": {
        "title": "{{parse-json.quickWins[0]}}",
        "dueDate": "{{NOW+1d}}"
      }}}
  ]
}`}
              </pre>
            </div>
          </div>

          {/* Swift Loading */}
          <div className="mt-6 border border-zinc-800 bg-[#0c0c0e]">
            <div className="border-b border-zinc-800 px-6 py-3">
              <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest">Loading TWF into WFKit</span>
            </div>
            <pre className="p-6 text-[11px] text-zinc-400 font-mono overflow-x-auto leading-relaxed">
{`// Load TWF files into WFKit canvas
let workflows = TWFLoader.loadFromBundle()   // Load all .twf.json from Resources/

for workflow in workflows {
    let nodes = TWFLoader.convert(workflow)  // TWF → WorkflowNode[]
    canvas.nodes.append(contentsOf: nodes)

    // Connections are auto-created from step order
    // Conditional branches create routing connections
}

// Or load a single workflow
if let data = Bundle.main.url(forResource: "research-pipeline", withExtension: "twf.json") {
    let workflow = try TWFLoader.load(from: data)
    canvas.load(workflow)  // UUIDs are deterministic from slugs
}`}
            </pre>
          </div>
        </div>

        {/* Documentation Section */}
        <div id="docs" className="mb-40 scroll-mt-24">
          <div className="flex items-end justify-between mb-10">
            <h2 className="text-3xl font-bold text-white font-sans tracking-tight">DOCUMENTATION</h2>
            <span className="text-xs font-bold text-zinc-600 uppercase tracking-widest">Quick Start</span>
          </div>

          <div className="grid lg:grid-cols-3 gap-6">
            {/* Step 1 */}
            <div className="border border-zinc-800 bg-[#0c0c0e] p-6">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-8 h-8 border border-zinc-700 flex items-center justify-center text-xs font-bold text-white">1</div>
                <h3 className="text-sm font-bold text-white uppercase tracking-wide">Add Dependency</h3>
              </div>
              <p className="text-xs text-zinc-500 font-mono mb-4">Add WFKit to your Package.swift dependencies:</p>
              <pre className="bg-black border border-zinc-800 p-3 text-[10px] text-zinc-400 font-mono overflow-x-auto">
{`dependencies: [
  .package(
    url: "https://github.com/arach/WFKit.git",
    from: "1.0.0"
  )
]`}
              </pre>
            </div>

            {/* Step 2 */}
            <div className="border border-zinc-800 bg-[#0c0c0e] p-6">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-8 h-8 border border-zinc-700 flex items-center justify-center text-xs font-bold text-white">2</div>
                <h3 className="text-sm font-bold text-white uppercase tracking-wide">Import & Initialize</h3>
              </div>
              <p className="text-xs text-zinc-500 font-mono mb-4">Import WFKit and create a canvas state:</p>
              <pre className="bg-black border border-zinc-800 p-3 text-[10px] text-zinc-400 font-mono overflow-x-auto">
{`import SwiftUI
import WFKit

struct ContentView: View {
  @State var canvas = CanvasState()

  var body: some View {
    WFWorkflowEditor(state: canvas)
  }
}`}
              </pre>
            </div>

            {/* Step 3 */}
            <div className="border border-zinc-800 bg-[#0c0c0e] p-6">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-8 h-8 border border-zinc-700 flex items-center justify-center text-xs font-bold text-white">3</div>
                <h3 className="text-sm font-bold text-white uppercase tracking-wide">Add Nodes</h3>
              </div>
              <p className="text-xs text-zinc-500 font-mono mb-4">Create nodes and connections programmatically:</p>
              <pre className="bg-black border border-zinc-800 p-3 text-[10px] text-zinc-400 font-mono overflow-x-auto">
{`let node = WorkflowNode(
  type: .action,
  title: "Process Data",
  position: CGPoint(x: 200, y: 100)
)

canvas.addNode(node)
canvas.connect(from: source, to: node)`}
              </pre>
            </div>
          </div>

          {/* API Reference */}
          <div className="mt-10 border border-zinc-800 bg-[#0c0c0e]">
            <div className="border-b border-zinc-800 px-6 py-4">
              <h3 className="text-sm font-bold text-white uppercase tracking-widest">Core API</h3>
            </div>
            <div className="grid md:grid-cols-2 lg:grid-cols-4 divide-x divide-zinc-800">
              {[
                { name: "CanvasState", desc: "Observable state container for the workflow canvas" },
                { name: "WorkflowNode", desc: "Represents a single node with inputs/outputs" },
                { name: "WFWorkflowEditor", desc: "Main SwiftUI view component" },
                { name: "NodeType", desc: "Extensible node type definitions" },
              ].map((api, i) => (
                <div key={i} className="p-4">
                  <code className="text-xs text-white font-mono font-bold">{api.name}</code>
                  <p className="text-[10px] text-zinc-500 mt-1 font-mono">{api.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Quick Install */}
        <div id="install" className="max-w-2xl mx-auto text-center border border-zinc-800 p-12 bg-[#0c0c0e] relative overflow-hidden scroll-mt-24">
           <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-transparent via-white to-transparent opacity-20"></div>

           <h2 className="text-3xl font-bold text-white font-sans tracking-tight mb-6">START BUILDING</h2>
           <p className="text-zinc-500 mb-8 max-w-md mx-auto font-mono text-sm">
            Add the package to your project and import WFKit to get started instantly.
           </p>

           <div className="flex flex-col items-center gap-4">
              <div className="flex items-center bg-black border border-zinc-800 p-4 w-full max-w-lg group hover:border-zinc-600 transition-colors cursor-pointer" onClick={() => navigator.clipboard.writeText('.package(url: "https://github.com/arach/WFKit.git", from: "1.0.0")')}>
                 <span className="text-zinc-500 mr-4 select-none">$</span>
                 <code className="flex-1 text-left text-xs md:text-sm text-zinc-300 font-mono">
                   .package(url: "https://github.com/arach/WFKit.git", from: "1.0.0")
                 </code>
                 <Copy size={14} className="text-zinc-600 group-hover:text-white transition-colors" />
              </div>
              <span className="text-[10px] text-zinc-600 uppercase tracking-widest">Click to copy dependency</span>
           </div>
        </div>

        {/* TWF Specification Section */}
        <div id="specs" className="mt-40 scroll-mt-24">
          <div className="flex items-end justify-between mb-10">
            <h2 className="text-3xl font-bold text-white font-sans tracking-tight">SPECIFICATIONS</h2>
            <span className="text-xs font-bold text-zinc-600 uppercase tracking-widest">TWF v1.0</span>
          </div>

          <div className="border border-zinc-800 bg-[#0c0c0e] mb-10">
            <div className="border-b border-zinc-800 px-6 py-4 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Workflow size={20} className="text-purple-400" />
                <h3 className="text-sm font-bold text-white uppercase tracking-widest">TWF (Talkie Workflow Format)</h3>
              </div>
              <span className="text-[10px] text-zinc-500 font-mono">.twf.json</span>
            </div>

            <div className="p-6 lg:p-8">
              <p className="text-zinc-400 text-sm mb-6 leading-relaxed max-w-3xl">
                TWF is a human-readable, LLM-friendly workflow definition format designed for voice memo and AI processing pipelines.
                It uses slug-based IDs (not UUIDs) for portability and git-friendliness.
              </p>

              {/* Format Overview */}
              <div className="grid lg:grid-cols-2 gap-6 mb-8">
                <div>
                  <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Workflow Structure</h4>
                  <pre className="bg-black border border-zinc-800 p-4 text-[11px] text-zinc-400 font-mono overflow-x-auto leading-relaxed">
{`{
  "slug": "workflow-slug",
  "name": "Display Name",
  "description": "What this does",
  "icon": "sf.symbol.name",
  "color": "purple",
  "isEnabled": true,
  "isPinned": false,
  "autoRun": false,
  "steps": [...]
}`}
                  </pre>
                </div>
                <div>
                  <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Step Structure</h4>
                  <pre className="bg-black border border-zinc-800 p-4 text-[11px] text-zinc-400 font-mono overflow-x-auto leading-relaxed">
{`{
  "id": "step-slug",
  "type": "LLM Generation",
  "config": {
    "llm": {
      "costTier": "balanced",
      "prompt": "{{TRANSCRIPT}}",
      "temperature": 0.7,
      "maxTokens": 1024
    }
  }
}`}
                  </pre>
                </div>
              </div>

              {/* Root Properties Table */}
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Root Properties</h4>
              <div className="border border-zinc-800 bg-black mb-8 overflow-x-auto">
                <div className="grid grid-cols-4 border-b border-zinc-800 bg-zinc-900/20 min-w-[600px]">
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest">Property</div>
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest border-l border-zinc-800">Type</div>
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest border-l border-zinc-800">Required</div>
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest border-l border-zinc-800">Description</div>
                </div>
                {[
                  { prop: "slug", type: "string", req: "Yes", desc: "Unique kebab-case identifier. Used to generate stable UUIDs." },
                  { prop: "name", type: "string", req: "Yes", desc: "Display name shown in UI" },
                  { prop: "description", type: "string", req: "Yes", desc: "Brief description of workflow purpose" },
                  { prop: "icon", type: "string", req: "Yes", desc: "SF Symbol name (e.g., \"waveform\", \"doc.text\")" },
                  { prop: "color", type: "string", req: "Yes", desc: "Theme: blue, purple, pink, red, orange, yellow, green, mint, teal, cyan, indigo, gray" },
                  { prop: "isEnabled", type: "bool", req: "Yes", desc: "Whether workflow can be run" },
                  { prop: "isPinned", type: "bool", req: "Yes", desc: "Shows in quick access / iOS widget" },
                  { prop: "autoRun", type: "bool", req: "Yes", desc: "Runs automatically after recording" },
                  { prop: "steps", type: "array", req: "Yes", desc: "Ordered list of workflow steps" },
                ].map((row, i) => (
                  <div key={i} className="grid grid-cols-4 border-b last:border-b-0 border-zinc-800 hover:bg-white/5 transition-colors min-w-[600px]">
                    <div className="p-3 text-[11px] font-mono text-purple-400">{row.prop}</div>
                    <div className="p-3 text-[11px] font-mono text-zinc-400 border-l border-zinc-800">{row.type}</div>
                    <div className="p-3 text-[11px] font-mono text-zinc-500 border-l border-zinc-800">{row.req}</div>
                    <div className="p-3 text-[11px] font-mono text-zinc-500 border-l border-zinc-800">{row.desc}</div>
                  </div>
                ))}
              </div>

              {/* Step Types with Config Keys */}
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">14 Step Types & Config Keys</h4>
              <div className="grid md:grid-cols-2 gap-4 mb-8">
                {[
                  { category: "AI", color: "purple", steps: [
                    { type: "LLM Generation", key: "llm", props: "costTier, provider, modelId, prompt, systemPrompt, temperature, maxTokens, topP" },
                    { type: "Transcribe Audio", key: "transcribe", props: "model, overwriteExisting, saveAsVersion" },
                  ]},
                  { category: "Logic", color: "blue", steps: [
                    { type: "Transform Data", key: "transform", props: "operation (Extract JSON|List|Regex Match|Split Text), parameters" },
                    { type: "Conditional Branch", key: "conditional", props: "condition, thenSteps[], elseSteps[]" },
                  ]},
                  { category: "Output", color: "green", steps: [
                    { type: "Send Notification", key: "notification", props: "title, body, sound" },
                    { type: "Notify iPhone", key: "iOSPush", props: "title, body, sound, includeOutput" },
                    { type: "Copy to Clipboard", key: "clipboard", props: "content" },
                    { type: "Save to File", key: "saveFile", props: "filename, directory (@Obsidian/|@Documents/|@Desktop/), content, appendIfExists" },
                  ]},
                  { category: "Integration", color: "orange", steps: [
                    { type: "Create Reminder", key: "appleReminders", props: "listName, title, notes, dueDate, priority (1=high, 5=medium, 9=low)" },
                    { type: "Run Shell Command", key: "shell", props: "executable, arguments[], timeout, captureStderr" },
                    { type: "Trigger Detection", key: "trigger", props: "phrases[], caseSensitive, searchLocation (Start|End|Anywhere), stopIfNoMatch" },
                    { type: "Extract Intents", key: "intentExtract", props: "inputKey, extractionMethod (LLM|Keywords|Hybrid), confidenceThreshold" },
                    { type: "Execute Workflows", key: "executeWorkflows", props: "intentsKey, stopOnError, parallel" },
                    { type: "Webhook", key: "webhook", props: "url, method, headers, body" },
                  ]},
                ].map((group, i) => (
                  <div key={i} className="border border-zinc-800 p-4">
                    <h5 className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-3">{group.category}</h5>
                    <div className="space-y-3">
                      {group.steps.map((step, j) => (
                        <div key={j} className="border-l-2 border-zinc-700 pl-3">
                          <div className="text-[11px] text-white font-mono font-bold">{step.type}</div>
                          <div className="text-[10px] text-purple-400 font-mono">config.{step.key}</div>
                          <div className="text-[10px] text-zinc-600 font-mono mt-1">{step.props}</div>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
              </div>

              {/* Template Variables - Enhanced */}
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Template Variables</h4>
              <div className="grid md:grid-cols-3 gap-6 mb-8">
                <div className="border border-zinc-800 p-4">
                  <h5 className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-3">Built-in Variables</h5>
                  <div className="space-y-2 text-[11px] font-mono">
                    {[
                      { var: "{{TRANSCRIPT}}", desc: "Full transcript text" },
                      { var: "{{TITLE}}", desc: "Voice memo title" },
                      { var: "{{DATE}}", desc: "Recording date (YYYY-MM-DD)" },
                      { var: "{{DATETIME}}", desc: "Full timestamp" },
                      { var: "{{DURATION}}", desc: "Recording duration" },
                      { var: "{{AUDIO_PATH}}", desc: "Path to audio file" },
                      { var: "{{MEMO_ID}}", desc: "Unique memo identifier" },
                    ].map((v, i) => (
                      <div key={i} className="flex items-start gap-2">
                        <code className="text-purple-400 shrink-0">{v.var}</code>
                        <span className="text-zinc-500">{v.desc}</span>
                      </div>
                    ))}
                  </div>
                </div>
                <div className="border border-zinc-800 p-4">
                  <h5 className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-3">Step References</h5>
                  <div className="space-y-2 text-[11px] font-mono">
                    <div className="flex items-start gap-2">
                      <code className="text-purple-400">{"{{step-id}}"}</code>
                      <span className="text-zinc-500">Full output of step</span>
                    </div>
                    <div className="flex items-start gap-2">
                      <code className="text-purple-400">{"{{step-id.prop}}"}</code>
                      <span className="text-zinc-500">Nested property (JSON)</span>
                    </div>
                    <div className="flex items-start gap-2">
                      <code className="text-purple-400">{"{{step.arr[0]}}"}</code>
                      <span className="text-zinc-500">Array element access</span>
                    </div>
                    <div className="mt-3 pt-3 border-t border-zinc-800">
                      <div className="text-[10px] text-zinc-600">Example chain:</div>
                      <code className="text-[10px] text-zinc-400">{"{{extract.features[0].title}}"}</code>
                    </div>
                  </div>
                </div>
                <div className="border border-zinc-800 p-4">
                  <h5 className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-3">Date Expressions</h5>
                  <div className="space-y-2 text-[11px] font-mono">
                    {[
                      { var: "{{NOW}}", desc: "Current time" },
                      { var: "{{NOW+1d}}", desc: "Tomorrow" },
                      { var: "{{NOW+3d}}", desc: "3 days from now" },
                      { var: "{{NOW+1w}}", desc: "1 week from now" },
                    ].map((v, i) => (
                      <div key={i} className="flex items-center gap-3">
                        <code className="text-purple-400">{v.var}</code>
                        <span className="text-zinc-500">{v.desc}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              {/* LLM Generation Example - Full */}
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">LLM Generation Config (Most Common)</h4>
              <div className="grid lg:grid-cols-2 gap-6 mb-8">
                <pre className="bg-black border border-zinc-800 p-4 text-[11px] text-zinc-400 font-mono overflow-x-auto leading-relaxed">
{`{
  "id": "summarize",
  "type": "LLM Generation",
  "config": {
    "llm": {
      "costTier": "budget",
      "prompt": "Summarize: {{TRANSCRIPT}}",
      "systemPrompt": "You are helpful.",
      "temperature": 0.7,
      "maxTokens": 1024
    }
  }
}`}
                </pre>
                <div className="border border-zinc-800 p-4">
                  <h5 className="text-[10px] font-bold text-zinc-500 uppercase tracking-widest mb-3">LLM Config Properties</h5>
                  <div className="space-y-2 text-[11px] font-mono">
                    <div><code className="text-purple-400">costTier</code> <span className="text-zinc-600">"budget" | "balanced" | "capable"</span></div>
                    <div><code className="text-purple-400">provider</code> <span className="text-zinc-600">"gemini" | "openai" | "anthropic" | "groq" | "mlx"</span></div>
                    <div><code className="text-purple-400">modelId</code> <span className="text-zinc-600">Optional specific model ID</span></div>
                    <div><code className="text-purple-400">prompt</code> <span className="text-zinc-600">Required. Template with variables</span></div>
                    <div><code className="text-purple-400">systemPrompt</code> <span className="text-zinc-600">Optional system message</span></div>
                    <div><code className="text-purple-400">temperature</code> <span className="text-zinc-600">0.0-2.0, default 0.7</span></div>
                    <div><code className="text-purple-400">maxTokens</code> <span className="text-zinc-600">Max output tokens, default 1024</span></div>
                    <div><code className="text-purple-400">topP</code> <span className="text-zinc-600">0.0-1.0, default 0.9</span></div>
                  </div>
                </div>
              </div>

              {/* TWF to WFKit Mapping */}
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">TWF → WFKit Node Mapping</h4>
              <div className="border border-zinc-800 bg-black mb-8">
                <div className="grid grid-cols-3 border-b border-zinc-800 bg-zinc-900/20">
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest">TWF Step Type</div>
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest border-l border-zinc-800">WFKit NodeType</div>
                  <div className="p-3 text-[10px] font-bold text-zinc-500 uppercase tracking-widest border-l border-zinc-800">Category</div>
                </div>
                {[
                  { twf: "LLM Generation", wfkit: ".llm", cat: "AI" },
                  { twf: "Transcribe Audio", wfkit: ".llm", cat: "AI" },
                  { twf: "Conditional Branch", wfkit: ".condition", cat: "Logic" },
                  { twf: "Transform Data", wfkit: ".transform", cat: "Logic" },
                  { twf: "Send Notification", wfkit: ".notification", cat: "Output" },
                  { twf: "Notify iPhone", wfkit: ".notification", cat: "Output" },
                  { twf: "Copy to Clipboard", wfkit: ".output", cat: "Output" },
                  { twf: "Save to File", wfkit: ".output", cat: "Output" },
                  { twf: "Create Reminder", wfkit: ".output", cat: "Apple" },
                  { twf: "Run Shell Command", wfkit: ".action", cat: "Integration" },
                  { twf: "Trigger Detection", wfkit: ".trigger", cat: "Trigger" },
                  { twf: "Extract Intents", wfkit: ".trigger", cat: "Trigger" },
                  { twf: "Execute Workflows", wfkit: ".trigger", cat: "Trigger" },
                ].map((row, i) => (
                  <div key={i} className="grid grid-cols-3 border-b last:border-b-0 border-zinc-800 hover:bg-white/5 transition-colors">
                    <div className="p-3 text-[11px] font-mono text-zinc-400">{row.twf}</div>
                    <div className="p-3 text-[11px] font-mono text-white border-l border-zinc-800">{row.wfkit}</div>
                    <div className="p-3 text-[11px] font-mono text-zinc-500 border-l border-zinc-800">{row.cat}</div>
                  </div>
                ))}
              </div>

              {/* Validation Rules */}
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Validation Rules</h4>
              <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
                {[
                  { rule: "1", desc: "slug must be unique, kebab-case, no spaces" },
                  { rule: "2", desc: "Step id must be unique within workflow" },
                  { rule: "3", desc: "thenSteps/elseSteps must reference valid step IDs" },
                  { rule: "4", desc: "Template variables must reference existing steps or built-ins" },
                  { rule: "5", desc: "At least one step required" },
                  { rule: "6", desc: "File naming: {slug}.twf.json" },
                ].map((r, i) => (
                  <div key={i} className="flex items-start gap-3 border border-zinc-800 p-3">
                    <div className="w-5 h-5 bg-zinc-800 flex items-center justify-center text-[10px] font-bold text-zinc-400 shrink-0">{r.rule}</div>
                    <div className="text-[11px] text-zinc-500 font-mono">{r.desc}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Sample Workflows & UUID Generation */}
          <div className="grid lg:grid-cols-2 gap-6">
            <div className="border border-zinc-800 bg-[#0c0c0e] p-6">
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Sample Workflows</h4>
              <p className="text-xs text-zinc-500 mb-4">
                Included in <code className="text-zinc-400">Sources/WFKit/Resources/SampleWorkflows/</code>
              </p>
              <div className="space-y-2">
                {[
                  { file: "quick-summary.twf.json", desc: "Single LLM step", complexity: "Simple" },
                  { file: "tweet-summary.twf.json", desc: "LLM + clipboard + notification", complexity: "Medium" },
                  { file: "hq-transcribe.twf.json", desc: "WhisperKit + LLM polish", complexity: "Medium" },
                  { file: "feature-ideation.twf.json", desc: "JSON extraction + conditional + reminders", complexity: "Complex" },
                  { file: "learning-capture.twf.json", desc: "Multi-step Obsidian integration", complexity: "Complex" },
                  { file: "hey-talkie.twf.json", desc: "Trigger detection + intent dispatch", complexity: "Complex" },
                ].map((f, i) => (
                  <div key={i} className="flex items-center justify-between text-[11px] font-mono p-2 border border-zinc-800 hover:border-zinc-700 transition-colors">
                    <div>
                      <span className="text-zinc-300">{f.file}</span>
                      <span className="text-zinc-600 ml-2">— {f.desc}</span>
                    </div>
                    <span className="text-zinc-600 shrink-0">{f.complexity}</span>
                  </div>
                ))}
              </div>
            </div>

            <div className="border border-zinc-800 bg-[#0c0c0e] p-6">
              <h4 className="text-xs font-bold text-white uppercase tracking-widest mb-4">Deterministic UUID Generation</h4>
              <p className="text-xs text-zinc-500 mb-4">
                TWF uses slug-based IDs that convert to stable UUIDs via SHA256 hashing. Same slug always produces the same UUID.
              </p>
              <pre className="bg-black border border-zinc-800 p-3 text-[10px] text-zinc-400 font-mono overflow-x-auto leading-relaxed">
{`// Workflow UUID
UUID = SHA256("talkie.twf:{slug}")[:16]

// Step UUID
UUID = SHA256("talkie.twf:{slug}/{step-id}")[:16]

// With version 4 bits set
uuidBytes[6] = (bytes[6] & 0x0F) | 0x40
uuidBytes[8] = (bytes[8] & 0x3F) | 0x80

// Benefits:
// ✓ Same slug → same UUID
// ✓ Safe re-imports (no duplication)
// ✓ Git-friendly (no random UUIDs)`}
              </pre>
            </div>
          </div>

          {/* Full Spec Link */}
          <div className="mt-8 text-center">
            <a
              href="https://github.com/arach/WFKit/blob/main/Sources/WFKit/Resources/SampleWorkflows/TWF_SPEC.md"
              target="_blank"
              className="inline-flex items-center gap-2 border border-zinc-700 hover:border-zinc-500 px-6 py-3 text-xs font-bold uppercase tracking-widest text-zinc-400 hover:text-white transition-colors"
            >
              <Github size={14} />
              View Full TWF Specification
            </a>
          </div>
        </div>

      </main>
      
      <Footer />
    </div>
  );
}