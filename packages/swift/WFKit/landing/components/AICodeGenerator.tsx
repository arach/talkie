import React, { useState } from 'react';
import { Highlight } from 'prism-react-renderer';
import { Terminal, Copy, Check, Box, ArrowDown, Lightbulb, BookOpen, Brain } from 'lucide-react';

const SNIPPETS = {
  'App.swift': `import SwiftUI
import WFKit

@main
struct MyApp: App {
    @State private var canvas = CanvasState()

    var body: some Scene {
        WindowGroup {
            WFWorkflowEditor(state: canvas)
                .onAppear {
                    if let url = Bundle.main.url(
                        forResource: "KeyInsights",
                        withExtension: "json"
                    ) {
                        canvas.load(from: url)
                    }
                }
        }
    }
}`,
  'KeyInsights.json': `{
  "slug": "key-insights",
  "name": "Key Insights",
  "description": "Extract 3-5 key takeaways",
  "icon": "lightbulb",
  "color": "yellow",
  "steps": [
    {
      "id": "extract-insights",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "provider": "gemini",
          "modelId": "gemini-2.0-flash",
          "prompt": "Extract 3-5 key takeaways...",
          "temperature": 0.5,
          "maxTokens": 1024
        }
      }
    }
  ]
}`,
  'LearningCapture.json': `{
  "slug": "learning-capture",
  "name": "Learning Capture",
  "description": "Voice notes → Obsidian",
  "icon": "book.pages",
  "color": "indigo",
  "steps": [
    {
      "id": "extract-concepts",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "balanced",
          "prompt": "Extract concepts: {{TRANSCRIPT}}"
        }
      }
    },
    {
      "id": "parse-json",
      "type": "Transform Data",
      "config": {
        "transform": { "operation": "Extract JSON" }
      }
    },
    {
      "id": "format-note",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "costTier": "budget",
          "prompt": "Format as Obsidian note: {{parse-json}}"
        }
      }
    },
    {
      "id": "save-note",
      "type": "Save to File",
      "config": {
        "saveFile": {
          "filename": "{{DATE}}-{{parse-json.mainTopic}}.md",
          "directory": "@Obsidian/Learning"
        }
      }
    }
  ]
}`,
  'BrainDump.json': `{
  "slug": "brain-dump-processor",
  "name": "Brain Dump Processor",
  "description": "Brainstorms → Ideas + Reminders",
  "icon": "brain.head.profile",
  "color": "purple",
  "steps": [
    {
      "id": "transcribe",
      "type": "Transcribe Audio",
      "config": {
        "transcribe": { "model": "whisper-small" }
      }
    },
    {
      "id": "extract-ideas",
      "type": "LLM Generation",
      "config": {
        "llm": {
          "provider": "gemini",
          "prompt": "Extract ideas: {{transcribe}}"
        }
      }
    },
    {
      "id": "check-actions",
      "type": "Conditional Branch",
      "config": {
        "conditional": {
          "condition": "{{extract-ideas.nextActions.length}} > 0",
          "thenSteps": ["create-reminder"],
          "elseSteps": []
        }
      }
    },
    {
      "id": "create-reminder",
      "type": "Create Reminder",
      "config": {
        "appleReminders": {
          "title": "{{extract-ideas.nextActions[0]}}",
          "dueDate": "{{NOW+1d}}"
        }
      }
    }
  ]
}`
};

type FileName = keyof typeof SNIPPETS;

// Content for left panel based on selected file
const FILE_CONTENT = {
  'App.swift': {
    icon: Box,
    title: ['TURNKEY', 'INTEGRATION'],
    description: 'Add workflow visualization to your app in minutes. Just initialize a canvas state, load your workflow definitions, and WFKit handles the rendering.',
    cta: 'View Integration'
  },
  'KeyInsights.json': {
    icon: Lightbulb,
    title: ['DECLARATIVE', 'WORKFLOWS'],
    description: 'Define workflows as simple JSON. Each step specifies its type, configuration, and how data flows between steps using template variables.',
    cta: 'View Workflow Schema'
  },
  'LearningCapture.json': {
    icon: BookOpen,
    title: ['MULTI-STEP', 'PIPELINES'],
    description: 'Chain multiple steps together. Extract data, transform it, generate content, and save results. Steps reference each other via {{step-id}} variables.',
    cta: 'View Pipeline'
  },
  'BrainDump.json': {
    icon: Brain,
    title: ['CONDITIONAL', 'LOGIC'],
    description: 'Add branching logic to your workflows. Evaluate conditions on step outputs and route execution to different paths based on results.',
    cta: 'View Branching'
  }
};

// Custom dark theme matching the site
const customTheme = {
  plain: {
    color: '#a1a1aa',
    backgroundColor: 'transparent',
  },
  styles: [
    { types: ['comment', 'prolog', 'doctype', 'cdata'], style: { color: '#52525b', fontStyle: 'italic' as const } },
    { types: ['punctuation'], style: { color: '#71717a' } },
    { types: ['property', 'tag', 'boolean', 'number', 'constant', 'symbol'], style: { color: '#fbbf24' } },
    { types: ['selector', 'attr-name', 'string', 'char', 'builtin'], style: { color: '#4ade80' } },
    { types: ['operator', 'entity', 'url', 'variable'], style: { color: '#a1a1aa' } },
    { types: ['atrule', 'attr-value', 'keyword'], style: { color: '#c084fc' } },
    { types: ['function', 'class-name'], style: { color: '#fde68a' } },
    { types: ['regex', 'important'], style: { color: '#fb923c' } },
  ],
};

interface CodeArchitectureProps {
  frameless?: boolean;
}

export const CodeArchitecture: React.FC<CodeArchitectureProps> = ({ frameless = false }) => {
  const [activeFile, setActiveFile] = useState<FileName>('App.swift');
  const isJson = activeFile.endsWith('.json');
  const [copied, setCopied] = useState(false);

  const codeSnippet = SNIPPETS[activeFile];
  const content = FILE_CONTENT[activeFile];

  const copyToClipboard = () => {
    navigator.clipboard.writeText(codeSnippet);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const FileItem = ({ name, icon: Icon, color }: { name: FileName, icon: any, color: string }) => (
    <div
      onClick={() => setActiveFile(name)}
      className={`flex items-center gap-2 p-2 rounded cursor-pointer transition-colors border ${activeFile === name ? 'bg-zinc-800/50 border-zinc-700 text-white' : 'border-transparent text-zinc-500 hover:text-zinc-300'}`}
    >
       <Icon size={12} className={color} />
       <span className="text-[10px] font-mono">{name}</span>
    </div>
  );

  // If frameless, render without the outer border and include text panel
  if (frameless) {
    return (
      <div className="grid lg:grid-cols-12 min-h-[600px] h-full divide-x divide-zinc-800">
        {/* Text Panel */}
        <div className="lg:col-span-4 p-6 lg:p-10 flex flex-col justify-center relative bg-[#09090b]">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 border border-zinc-700 flex items-center justify-center">
              <content.icon size={20} strokeWidth={1} className="text-white" />
            </div>
            <span className="text-xs font-bold uppercase tracking-widest text-zinc-500">WFKit</span>
          </div>
          <h2 className="text-2xl lg:text-3xl font-bold text-white font-sans tracking-tight mb-4">
            {content.title[0]}<br/>{content.title[1]}
          </h2>
          <p className="text-zinc-500 text-sm leading-relaxed mb-8">
            {content.description}
          </p>
          <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-white">
            <ArrowDown size={14} />
            <span>{content.cta}</span>
          </div>

          {/* Technical Hinge / Divider */}
          <div className="absolute top-1/2 -right-[11px] -translate-y-1/2 hidden lg:flex flex-col items-center z-10">
            <div className="w-px h-16 bg-gradient-to-b from-transparent to-zinc-700"></div>
            <div className="w-[20px] h-[20px] bg-[#0c0c0e] border border-zinc-600 rotate-45 flex items-center justify-center shadow-xl">
              <div className="w-1.5 h-1.5 bg-white rounded-full"></div>
            </div>
            <div className="w-px h-16 bg-gradient-to-t from-transparent to-zinc-700"></div>
          </div>
        </div>

        {/* Code Panel with sidebar */}
        <div className="lg:col-span-8 grid lg:grid-cols-5 bg-[#0c0c0e]">
          {/* File Explorer Sidebar */}
          <div className="lg:col-span-1 border-b lg:border-b-0 lg:border-r border-zinc-800 bg-[#0c0c0e] p-4 flex flex-col gap-6">
            <div className="flex items-center gap-2 text-white mb-2">
              <Terminal size={14} />
              <span className="text-xs font-bold uppercase tracking-wider">Explorer</span>
            </div>

            <div className="flex flex-col gap-1">
              <FileItem name="App.swift" icon={Box} color="text-orange-400" />
              <FileItem name="KeyInsights.json" icon={Lightbulb} color="text-yellow-400" />
              <FileItem name="LearningCapture.json" icon={BookOpen} color="text-indigo-400" />
              <FileItem name="BrainDump.json" icon={Brain} color="text-purple-400" />
            </div>

            <div className="mt-auto border-t border-zinc-800 pt-4">
              <div className="text-[10px] text-zinc-600 uppercase tracking-widest font-bold mb-2">Build Status</div>
              <div className="flex items-center gap-2 text-green-500">
                <div className="w-1.5 h-1.5 rounded-full bg-current"></div>
                <span className="text-xs font-mono">Succeeded</span>
              </div>
            </div>
          </div>

          {/* Code Viewer */}
          <div className="lg:col-span-4 flex flex-col h-full bg-[#050505] relative">
            <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800 bg-zinc-900/20">
              <div className="flex items-center gap-2">
                <span className="text-[10px] text-zinc-500 font-mono">Workflows /</span>
                <span className="text-[10px] text-zinc-300 font-bold uppercase tracking-widest">{activeFile}</span>
              </div>
              <button onClick={copyToClipboard} className="text-zinc-500 hover:text-white transition-colors">
                {copied ? <Check size={14} /> : <Copy size={14} />}
              </button>
            </div>

            <div className="flex-1 overflow-auto p-6 custom-scrollbar">
              <Highlight
                theme={customTheme}
                code={codeSnippet}
                language={isJson ? 'json' : 'swift'}
              >
                {({ style, tokens, getLineProps, getTokenProps }) => (
                  <pre className="font-mono text-xs md:text-sm leading-6" style={style}>
                    {tokens.map((line, i) => (
                      <div key={i} {...getLineProps({ line })} className="table-row">
                        <span className="table-cell text-zinc-800 select-none text-right pr-4 w-8">
                          {i + 1}
                        </span>
                        <span className="table-cell">
                          {line.map((token, key) => (
                            <span key={key} {...getTokenProps({ token })} />
                          ))}
                        </span>
                      </div>
                    ))}
                  </pre>
                )}
              </Highlight>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Non-frameless version (with outer border)
  return (
    <div className="border border-zinc-800 bg-[#09090b] grid lg:grid-cols-5 relative group min-h-[600px] h-full">
      <div className="absolute -top-1 -left-1 w-2 h-2 border-t border-l border-white"></div>
      <div className="absolute -top-1 -right-1 w-2 h-2 border-t border-r border-white"></div>
      <div className="absolute -bottom-1 -left-1 w-2 h-2 border-b border-l border-white"></div>
      <div className="absolute -bottom-1 -right-1 w-2 h-2 border-b border-r border-white"></div>

      {/* Sidebar / File Explorer */}
      <div className="lg:col-span-1 border-b lg:border-b-0 lg:border-r border-zinc-800 bg-[#0c0c0e] p-4 flex flex-col gap-6">
        <div className="flex items-center gap-2 text-white mb-2">
          <Terminal size={14} />
          <span className="text-xs font-bold uppercase tracking-wider">Explorer</span>
        </div>

        <div className="flex flex-col gap-1">
          <FileItem name="App.swift" icon={Box} color="text-orange-400" />
          <FileItem name="KeyInsights.json" icon={Lightbulb} color="text-yellow-400" />
          <FileItem name="LearningCapture.json" icon={BookOpen} color="text-indigo-400" />
          <FileItem name="BrainDump.json" icon={Brain} color="text-purple-400" />
        </div>

        <div className="mt-auto border-t border-zinc-800 pt-4">
          <div className="text-[10px] text-zinc-600 uppercase tracking-widest font-bold mb-2">Build Status</div>
          <div className="flex items-center gap-2 text-green-500">
            <div className="w-1.5 h-1.5 rounded-full bg-current"></div>
            <span className="text-xs font-mono">Succeeded</span>
          </div>
        </div>
      </div>

      {/* Code Viewer */}
      <div className="lg:col-span-4 flex flex-col h-full bg-[#050505] relative">
        <div className="flex items-center justify-between px-4 py-3 border-b border-zinc-800 bg-zinc-900/20">
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-zinc-500 font-mono">Workflows /</span>
            <span className="text-[10px] text-zinc-300 font-bold uppercase tracking-widest">{activeFile}</span>
          </div>
          <button onClick={copyToClipboard} className="text-zinc-500 hover:text-white transition-colors">
            {copied ? <Check size={14} /> : <Copy size={14} />}
          </button>
        </div>

        <div className="flex-1 overflow-auto p-6 custom-scrollbar">
          <Highlight
            theme={customTheme}
            code={codeSnippet}
            language={isJson ? 'json' : 'swift'}
          >
            {({ style, tokens, getLineProps, getTokenProps }) => (
              <pre className="font-mono text-xs md:text-sm leading-6" style={style}>
                {tokens.map((line, i) => (
                  <div key={i} {...getLineProps({ line })} className="table-row">
                    <span className="table-cell text-zinc-800 select-none text-right pr-4 w-8">
                      {i + 1}
                    </span>
                    <span className="table-cell">
                      {line.map((token, key) => (
                        <span key={key} {...getTokenProps({ token })} />
                      ))}
                    </span>
                  </div>
                ))}
              </pre>
            )}
          </Highlight>
        </div>
      </div>
    </div>
  );
};
