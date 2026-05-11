import React from 'react';
import {
  Box, Layers, Zap, MousePointer2, Move, Palette,
  Eye, Settings, Code2, Workflow, GitBranch, Package,
  Cpu, Smartphone, Monitor, ChevronRight, CheckCircle2
} from 'lucide-react';

// Canvas screenshot with fallback to mockup
const CanvasScreenshot = () => {
  const [imageError, setImageError] = React.useState(false);
  const imageSrc = `${import.meta.env.BASE_URL}screenshots/canvas-preview.png`;

  if (imageError) {
    return <CanvasMockup />;
  }

  return (
    <div className="relative w-full aspect-[16/10] bg-[#0a0a0c] rounded-sm overflow-hidden border border-zinc-800">
      <img
        src={imageSrc}
        alt="WFKit Workflow Editor Canvas"
        className="w-full h-full object-cover"
        onError={() => setImageError(true)}
      />
      {/* Status bar overlay */}
      <div className="absolute bottom-2 left-2 right-2 flex items-center justify-between px-3 py-1.5 bg-black/80 border border-zinc-800 rounded-sm">
        <div className="flex items-center gap-4 text-[9px] text-zinc-500">
          <span>Nodes: 5</span>
          <span>Connections: 4</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
          <span className="text-[9px] text-zinc-400">Ready</span>
        </div>
      </div>
    </div>
  );
};

// Visual mockup of the workflow editor canvas
const CanvasMockup = () => (
  <div className="relative w-full aspect-[16/10] bg-[#0a0a0c] rounded-sm overflow-hidden border border-zinc-800">
    {/* Grid background */}
    <div
      className="absolute inset-0 opacity-30"
      style={{
        backgroundImage: `
          linear-gradient(to right, #27272a 1px, transparent 1px),
          linear-gradient(to bottom, #27272a 1px, transparent 1px)
        `,
        backgroundSize: '20px 20px'
      }}
    />

    {/* Nodes */}
    <div className="absolute top-8 left-8 w-40 bg-[#18181b] border border-zinc-700 rounded shadow-lg">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-zinc-700 bg-purple-500/10">
        <div className="w-2 h-2 rounded-full bg-purple-500" />
        <span className="text-[10px] font-bold text-white">TRIGGER</span>
      </div>
      <div className="p-3">
        <div className="text-[10px] text-zinc-400 font-mono">Voice Input</div>
        <div className="text-[9px] text-zinc-600 mt-1">audio/wav</div>
      </div>
      <div className="absolute -right-2 top-1/2 w-3 h-3 bg-zinc-700 rounded-full border-2 border-zinc-800" />
    </div>

    <div className="absolute top-8 left-56 w-44 bg-[#18181b] border border-zinc-700 rounded shadow-lg">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-zinc-700 bg-blue-500/10">
        <div className="w-2 h-2 rounded-full bg-blue-500" />
        <span className="text-[10px] font-bold text-white">LLM</span>
      </div>
      <div className="p-3">
        <div className="text-[10px] text-zinc-400 font-mono">Transcribe</div>
        <div className="text-[9px] text-zinc-600 mt-1">whisper-small</div>
      </div>
      <div className="absolute -left-2 top-1/2 w-3 h-3 bg-zinc-700 rounded-full border-2 border-zinc-800" />
      <div className="absolute -right-2 top-1/2 w-3 h-3 bg-zinc-700 rounded-full border-2 border-zinc-800" />
    </div>

    <div className="absolute top-8 right-8 w-44 bg-[#18181b] border border-zinc-700 rounded shadow-lg">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-zinc-700 bg-green-500/10">
        <div className="w-2 h-2 rounded-full bg-green-500" />
        <span className="text-[10px] font-bold text-white">OUTPUT</span>
      </div>
      <div className="p-3">
        <div className="text-[10px] text-zinc-400 font-mono">Save to File</div>
        <div className="text-[9px] text-zinc-600 mt-1">markdown</div>
      </div>
      <div className="absolute -left-2 top-1/2 w-3 h-3 bg-zinc-700 rounded-full border-2 border-zinc-800" />
    </div>

    {/* Conditional Branch Node */}
    <div className="absolute bottom-12 left-1/2 -translate-x-1/2 w-48 bg-[#18181b] border border-yellow-500/50 rounded shadow-lg">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-zinc-700 bg-yellow-500/10">
        <GitBranch size={10} className="text-yellow-500" />
        <span className="text-[10px] font-bold text-white">CONDITION</span>
      </div>
      <div className="p-3">
        <div className="text-[10px] text-zinc-400 font-mono">Check Length</div>
        <div className="text-[9px] text-zinc-600 mt-1">output.length &gt; 100</div>
      </div>
      <div className="absolute -left-2 top-1/2 w-3 h-3 bg-zinc-700 rounded-full border-2 border-zinc-800" />
      <div className="absolute -right-2 top-1/3 w-3 h-3 bg-green-600 rounded-full border-2 border-zinc-800" />
      <div className="absolute -right-2 top-2/3 w-3 h-3 bg-red-600 rounded-full border-2 border-zinc-800" />
    </div>

    {/* Connection lines (SVG) */}
    <svg className="absolute inset-0 w-full h-full pointer-events-none">
      <path
        d="M 168 52 Q 200 52 220 52"
        stroke="#3b82f6"
        strokeWidth="2"
        fill="none"
        strokeDasharray="4 2"
        className="animate-pulse"
      />
      <path
        d="M 400 52 Q 440 52 460 52"
        stroke="#22c55e"
        strokeWidth="2"
        fill="none"
        strokeDasharray="4 2"
      />
    </svg>

    {/* Status bar */}
    <div className="absolute bottom-2 left-2 right-2 flex items-center justify-between px-3 py-1.5 bg-black/60 border border-zinc-800 rounded-sm">
      <div className="flex items-center gap-4 text-[9px] text-zinc-500">
        <span>Nodes: 4</span>
        <span>Connections: 3</span>
      </div>
      <div className="flex items-center gap-2">
        <div className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
        <span className="text-[9px] text-zinc-400">Ready</span>
      </div>
    </div>
  </div>
);

// Inspector panel mockup
const InspectorMockup = () => (
  <div className="w-full bg-[#0c0c0e] border border-zinc-800 rounded-sm">
    <div className="px-4 py-3 border-b border-zinc-800 flex items-center gap-2">
      <Settings size={14} className="text-zinc-500" />
      <span className="text-xs font-bold text-white uppercase tracking-wider">Inspector</span>
    </div>

    <div className="p-4 space-y-4">
      <div>
        <label className="text-[10px] text-zinc-500 uppercase tracking-wider block mb-2">Node Title</label>
        <div className="bg-black border border-zinc-700 px-3 py-2 text-xs text-white font-mono">
          LLM Generation
        </div>
      </div>

      <div>
        <label className="text-[10px] text-zinc-500 uppercase tracking-wider block mb-2">Cost Tier</label>
        <div className="flex gap-2">
          {['Budget', 'Balanced', 'Capable'].map((tier, i) => (
            <div
              key={tier}
              className={`px-3 py-1.5 text-[10px] font-bold uppercase tracking-wider border ${
                i === 1
                  ? 'bg-blue-500/20 border-blue-500 text-blue-400'
                  : 'border-zinc-700 text-zinc-500'
              }`}
            >
              {tier}
            </div>
          ))}
        </div>
      </div>

      <div>
        <label className="text-[10px] text-zinc-500 uppercase tracking-wider block mb-2">Prompt</label>
        <div className="bg-black border border-zinc-700 p-3 text-[11px] text-zinc-400 font-mono h-20 overflow-hidden">
          Summarize the following transcript in 3 bullet points:
          <br />
          <span className="text-purple-400">{"{{TRANSCRIPT}}"}</span>
        </div>
      </div>

      <div>
        <label className="text-[10px] text-zinc-500 uppercase tracking-wider block mb-2">Temperature</label>
        <div className="flex items-center gap-3">
          <div className="flex-1 h-1 bg-zinc-800 rounded-full overflow-hidden">
            <div className="w-3/5 h-full bg-blue-500" />
          </div>
          <span className="text-[10px] text-zinc-400 font-mono w-8">0.7</span>
        </div>
      </div>
    </div>
  </div>
);

// Feature card with visual demo
const FeatureShowcase = ({
  icon,
  title,
  description,
  visual
}: {
  icon: React.ReactNode;
  title: string;
  description: string;
  visual: React.ReactNode;
}) => (
  <div className="border border-zinc-800 bg-[#0c0c0e] overflow-hidden group hover:border-zinc-700 transition-colors">
    <div className="aspect-video bg-[#050505] p-4 relative overflow-hidden">
      {visual}
    </div>
    <div className="p-6 border-t border-zinc-800">
      <div className="flex items-center gap-3 mb-3">
        <div className="text-zinc-400 group-hover:text-white transition-colors">{icon}</div>
        <h3 className="text-sm font-bold text-white uppercase tracking-wide">{title}</h3>
      </div>
      <p className="text-xs text-zinc-500 font-mono leading-relaxed">{description}</p>
    </div>
  </div>
);

// Technical specs table
const TechnicalSpecs = () => (
  <div className="border border-zinc-800 bg-[#0c0c0e]">
    <div className="px-6 py-4 border-b border-zinc-800 flex items-center gap-2">
      <Cpu size={16} className="text-zinc-500" />
      <h3 className="text-sm font-bold text-white uppercase tracking-widest">Technical Specifications</h3>
    </div>
    <div className="divide-y divide-zinc-800">
      {[
        { label: "Platforms", value: "macOS 13+, iOS 16+, iPadOS 16+", icon: <Monitor size={14} /> },
        { label: "Swift Version", value: "5.9+", icon: <Code2 size={14} /> },
        { label: "UI Framework", value: "SwiftUI (100% native)", icon: <Layers size={14} /> },
        { label: "Dependencies", value: "Zero external dependencies", icon: <Package size={14} /> },
        { label: "Memory Footprint", value: "~12MB typical", icon: <Zap size={14} /> },
        { label: "Startup Time", value: "<50ms cold start", icon: <Zap size={14} /> },
        { label: "Rendering", value: "Metal-accelerated, 120 FPS", icon: <Eye size={14} /> },
        { label: "State Management", value: "@Observable / Combine", icon: <Workflow size={14} /> },
        { label: "License", value: "MIT", icon: <CheckCircle2 size={14} /> },
      ].map((spec, i) => (
        <div key={i} className="grid grid-cols-2 hover:bg-white/5 transition-colors">
          <div className="px-6 py-4 flex items-center gap-3">
            <span className="text-zinc-600">{spec.icon}</span>
            <span className="text-xs font-mono text-zinc-400">{spec.label}</span>
          </div>
          <div className="px-6 py-4 text-xs font-mono text-white border-l border-zinc-800">
            {spec.value}
          </div>
        </div>
      ))}
    </div>
  </div>
);

// Pan/zoom visual mockup
const PanZoomVisual = () => (
  <div className="relative w-full h-full flex items-center justify-center">
    <div className="relative">
      {/* Zoomed out view */}
      <div className="absolute -top-2 -left-2 w-32 h-20 border border-dashed border-zinc-600 rounded opacity-50 transform scale-75 origin-center">
        <div className="w-6 h-4 bg-zinc-700 rounded-sm absolute top-2 left-2" />
        <div className="w-6 h-4 bg-zinc-700 rounded-sm absolute top-2 left-10" />
        <div className="w-6 h-4 bg-zinc-700 rounded-sm absolute bottom-2 left-6" />
      </div>

      {/* Zoom indicator */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-16 h-16 border-2 border-blue-500/50 rounded-lg flex items-center justify-center">
        <span className="text-[10px] text-blue-400 font-bold">150%</span>
      </div>

      {/* Mouse cursor */}
      <MousePointer2 size={20} className="absolute bottom-4 right-8 text-white animate-pulse" />
    </div>

    {/* Controls hint */}
    <div className="absolute bottom-2 left-1/2 -translate-x-1/2 flex items-center gap-4 text-[9px] text-zinc-600">
      <span>Scroll: Zoom</span>
      <span>Drag: Pan</span>
    </div>
  </div>
);

// Node types visual
const NodeTypesVisual = () => (
  <div className="grid grid-cols-3 gap-2 p-4 h-full">
    {[
      { type: 'Trigger', color: 'purple', icon: <Zap size={10} /> },
      { type: 'LLM', color: 'blue', icon: <Cpu size={10} /> },
      { type: 'Transform', color: 'cyan', icon: <Workflow size={10} /> },
      { type: 'Condition', color: 'yellow', icon: <GitBranch size={10} /> },
      { type: 'Output', color: 'green', icon: <Box size={10} /> },
      { type: 'Custom', color: 'pink', icon: <Palette size={10} /> },
    ].map((node, i) => (
      <div
        key={i}
        className={`flex flex-col items-center justify-center p-2 rounded border border-zinc-700 bg-zinc-900/50`}
        style={{ borderColor: `var(--${node.color}-500, #71717a)` }}
      >
        <div className={`text-${node.color}-400`}>{node.icon}</div>
        <span className="text-[8px] text-zinc-400 mt-1 uppercase tracking-wider">{node.type}</span>
      </div>
    ))}
  </div>
);

// Theme customization visual
const ThemeVisual = () => (
  <div className="flex items-center justify-center gap-4 h-full p-4">
    <div className="w-20 h-24 rounded border border-zinc-700 bg-[#09090b] p-2 relative overflow-hidden">
      <div className="text-[8px] text-zinc-500 uppercase tracking-wider mb-2">Dark</div>
      <div className="w-full h-3 bg-zinc-800 rounded-sm mb-1" />
      <div className="w-3/4 h-3 bg-blue-600 rounded-sm mb-1" />
      <div className="w-full h-3 bg-zinc-800 rounded-sm" />
      <div className="absolute -bottom-1 -right-1 w-4 h-4 border-t border-l border-white" />
    </div>
    <ChevronRight size={16} className="text-zinc-600" />
    <div className="w-20 h-24 rounded border border-zinc-300 bg-white p-2 relative overflow-hidden">
      <div className="text-[8px] text-zinc-500 uppercase tracking-wider mb-2">Light</div>
      <div className="w-full h-3 bg-zinc-200 rounded-sm mb-1" />
      <div className="w-3/4 h-3 bg-blue-500 rounded-sm mb-1" />
      <div className="w-full h-3 bg-zinc-200 rounded-sm" />
      <div className="absolute -bottom-1 -right-1 w-4 h-4 border-t border-l border-black" />
    </div>
  </div>
);

export const FeaturesPage = () => {
  return (
    <div id="features" className="scroll-mt-24">
      {/* Section Header */}
      <div className="flex items-end justify-between mb-10">
        <h2 className="text-3xl font-bold text-white font-sans tracking-tight">FEATURES & SCREENSHOTS</h2>
        <span className="text-xs font-bold text-zinc-600 uppercase tracking-widest">Visual Tour</span>
      </div>

      {/* Main Canvas Showcase */}
      <div className="mb-12 border border-zinc-800 bg-[#0c0c0e] overflow-hidden">
        <div className="grid lg:grid-cols-12 divide-y lg:divide-y-0 lg:divide-x divide-zinc-800">
          {/* Canvas Preview */}
          <div className="lg:col-span-8 p-6">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-red-500" />
                <div className="w-3 h-3 rounded-full bg-yellow-500" />
                <div className="w-3 h-3 rounded-full bg-green-500" />
              </div>
              <span className="text-[10px] text-zinc-600 font-mono">WFWorkflowEditor.swift</span>
            </div>
            <CanvasScreenshot />
          </div>

          {/* Inspector Preview */}
          <div className="lg:col-span-4 p-6 bg-[#050505]">
            <h4 className="text-xs font-bold text-zinc-500 uppercase tracking-widest mb-4">Property Inspector</h4>
            <InspectorMockup />
          </div>
        </div>
      </div>

      {/* Feature Grid */}
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 mb-12">
        <FeatureShowcase
          icon={<Move size={20} />}
          title="Pan & Zoom"
          description="Smooth 60fps pan and zoom with trackpad, mouse wheel, and touch gestures. Minimap navigation for large workflows."
          visual={<PanZoomVisual />}
        />

        <FeatureShowcase
          icon={<Layers size={20} />}
          title="Node Types"
          description="Built-in types for triggers, LLM, transforms, conditions, and outputs. Extend with your own custom node types via protocols."
          visual={<NodeTypesVisual />}
        />

        <FeatureShowcase
          icon={<Palette size={20} />}
          title="Theming"
          description="Full light and dark mode support. Customize colors, fonts, spacing, and borders to match your app's design system."
          visual={<ThemeVisual />}
        />
      </div>

      {/* Technical Specs */}
      <div className="mb-12">
        <h3 className="text-xl font-bold text-white font-sans tracking-tight mb-6">TECHNICAL SPECS</h3>
        <TechnicalSpecs />
      </div>

      {/* Platform Support */}
      <div className="grid md:grid-cols-3 gap-6 mb-12">
        {[
          { platform: 'macOS', version: '13.0+', icon: <Monitor size={24} />, features: ['Full keyboard navigation', 'Context menus', 'Drag & drop from Finder'] },
          { platform: 'iOS', version: '16.0+', icon: <Smartphone size={24} />, features: ['Touch gestures', 'Haptic feedback', 'iPad multitasking'] },
          { platform: 'visionOS', version: 'Coming Soon', icon: <Eye size={24} />, features: ['Spatial canvas', '3D node arrangement', 'Eye tracking'] },
        ].map((p, i) => (
          <div key={i} className="border border-zinc-800 bg-[#0c0c0e] p-6">
            <div className="flex items-center gap-3 mb-4">
              <div className="text-zinc-400">{p.icon}</div>
              <div>
                <h4 className="text-sm font-bold text-white uppercase tracking-wide">{p.platform}</h4>
                <span className="text-[10px] text-zinc-600 font-mono">{p.version}</span>
              </div>
            </div>
            <ul className="space-y-2">
              {p.features.map((f, j) => (
                <li key={j} className="flex items-center gap-2 text-xs text-zinc-500 font-mono">
                  <CheckCircle2 size={12} className="text-green-500 shrink-0" />
                  {f}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      {/* Architecture Diagram */}
      <div className="border border-zinc-800 bg-[#0c0c0e] p-8">
        <h3 className="text-sm font-bold text-white uppercase tracking-widest mb-6">Architecture Overview</h3>
        <div className="grid md:grid-cols-4 gap-4">
          {[
            { layer: 'View Layer', components: ['WFWorkflowEditor', 'NodeView', 'ConnectionView', 'InspectorView'], color: 'blue' },
            { layer: 'State Layer', components: ['CanvasState', 'WorkflowNode', 'Connection', 'Selection'], color: 'purple' },
            { layer: 'Schema Layer', components: ['WFSchemaProvider', 'WFNodeTypeSchema', 'WFFieldSchema'], color: 'green' },
            { layer: 'Theme Layer', components: ['WFTheme', 'WFColors', 'WFTypography', 'WFSpacing'], color: 'orange' },
          ].map((layer, i) => (
            <div key={i} className="border border-zinc-700 p-4">
              <h4 className={`text-[10px] font-bold text-${layer.color}-400 uppercase tracking-widest mb-3`}>
                {layer.layer}
              </h4>
              <ul className="space-y-1">
                {layer.components.map((c, j) => (
                  <li key={j} className="text-[10px] text-zinc-500 font-mono">{c}</li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
