import React, { useState, useRef, useEffect } from 'react';
import { NodeData, EdgeData } from '../types';
import { Plus, Trash2, GripHorizontal, Play, Zap, Database, MessageSquare } from 'lucide-react';

const INITIAL_NODES: NodeData[] = [
  { id: '1', type: 'trigger', label: 'Voice Input', position: { x: 100, y: 150 }, color: '#f59e0b', inputs: [], outputs: ['out'] },
  { id: '2', type: 'llm', label: 'Summarize', description: 'Summarize the following transcript...', position: { x: 380, y: 120 }, color: '#a855f7', inputs: ['in'], outputs: ['out'] },
  { id: '3', type: 'condition', label: 'Has Task?', description: "if: output contains 'task'", position: { x: 680, y: 220 }, color: '#eab308', inputs: ['in'], outputs: ['true', 'false'] },
  { id: '4', type: 'action', label: 'Create Reminder', description: 'reminder', position: { x: 1000, y: 100 }, color: '#22c55e', inputs: ['in'], outputs: [] },
  { id: '5', type: 'output', label: 'Save Result', position: { x: 950, y: 350 }, color: '#ef4444', inputs: ['in'], outputs: [] },
];

const INITIAL_EDGES: EdgeData[] = [
  { id: 'e1', source: '1', target: '2' },
  { id: 'e2', source: '2', target: '3' },
  { id: 'e3', source: '3', target: '4', label: 'true' },
  { id: 'e4', source: '3', target: '5', label: 'false' },
];

interface NodeComponentProps {
  node: NodeData;
  isSelected: boolean;
  onSelect: () => void;
  onDragStart: (e: React.MouseEvent, id: string) => void;
}

const NodeComponent: React.FC<NodeComponentProps> = ({ node, isSelected, onSelect, onDragStart }) => {
  const Icon = () => {
    switch(node.type) {
      case 'trigger': return <Zap size={14} className="text-white fill-white" />;
      case 'action': return <Play size={14} className="text-white fill-white" />;
      case 'condition': return <div className="text-[10px] font-bold text-black">Y</div>;
      case 'llm': return <MessageSquare size={14} className="text-white" />;
      default: return <Database size={14} className="text-white" />;
    }
  };

  return (
    <div
      className={`absolute flex flex-col w-64 rounded-lg shadow-xl backdrop-blur-md transition-shadow duration-200 cursor-grab active:cursor-grabbing border ${isSelected ? 'border-primary ring-2 ring-primary/20' : 'border-zinc-700/50'}`}
      style={{
        left: node.position.x,
        top: node.position.y,
        backgroundColor: '#18181b', // zinc-900
      }}
      onMouseDown={(e) => {
        onSelect();
        onDragStart(e, node.id);
      }}
    >
      {/* Node Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-zinc-800 rounded-t-lg bg-zinc-900/50">
        <div className="flex items-center gap-2">
          <div className="flex items-center justify-center w-6 h-6 rounded-md shadow-sm" style={{ backgroundColor: node.color }}>
             <Icon />
          </div>
          <span className="text-sm font-semibold text-zinc-200">{node.label}</span>
        </div>
        <div className="px-1.5 py-0.5 text-[10px] uppercase tracking-wider font-bold text-zinc-500 bg-zinc-800 rounded">
          {node.type}
        </div>
      </div>

      {/* Node Body */}
      <div className="p-3">
        {node.description && (
          <p className="text-xs text-zinc-400 font-mono leading-relaxed mb-2">
            {node.description}
          </p>
        )}
        
        {/* Connection Ports Simulation */}
        <div className="flex justify-between mt-2">
           <div className="flex flex-col gap-1">
             {node.inputs.map((_, i) => (
               <div key={i} className="flex items-center gap-2">
                  <div className="w-2.5 h-2.5 rounded-full border border-zinc-600 bg-zinc-900 hover:bg-primary transition-colors cursor-crosshair"></div>
               </div>
             ))}
           </div>
           <div className="flex flex-col gap-1">
             {node.outputs.map((_, i) => (
               <div key={i} className="flex items-center gap-2 justify-end">
                  <div className="w-2.5 h-2.5 rounded-full border border-zinc-600 bg-zinc-900 hover:bg-primary transition-colors cursor-crosshair"></div>
               </div>
             ))}
           </div>
        </div>
      </div>
    </div>
  );
};

export const VisualEditor = () => {
  const [nodes, setNodes] = useState<NodeData[]>(INITIAL_NODES);
  const [selectedNode, setSelectedNode] = useState<string | null>(null);
  const [scale, setScale] = useState(1);
  const containerRef = useRef<HTMLDivElement>(null);
  
  // Dragging state
  const draggingRef = useRef<{ id: string, startX: number, startY: number, initialNodeX: number, initialNodeY: number } | null>(null);

  const handleDragStart = (e: React.MouseEvent, id: string) => {
    e.stopPropagation();
    const node = nodes.find(n => n.id === id);
    if (!node) return;

    draggingRef.current = {
      id,
      startX: e.clientX,
      startY: e.clientY,
      initialNodeX: node.position.x,
      initialNodeY: node.position.y
    };
  };

  const handleMouseMove = (e: MouseEvent) => {
    if (!draggingRef.current) return;

    const { id, startX, startY, initialNodeX, initialNodeY } = draggingRef.current;
    const dx = (e.clientX - startX) / scale;
    const dy = (e.clientY - startY) / scale;

    setNodes(prev => prev.map(n => {
      if (n.id === id) {
        return {
          ...n,
          position: {
            x: initialNodeX + dx,
            y: initialNodeY + dy
          }
        };
      }
      return n;
    }));
  };

  const handleMouseUp = () => {
    draggingRef.current = null;
  };

  useEffect(() => {
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [scale]); // Re-bind if scale changes

  // SVG Path Generator for Bezier Curves
  const getPath = (sourceId: string, targetId: string) => {
    const sourceNode = nodes.find(n => n.id === sourceId);
    const targetNode = nodes.find(n => n.id === targetId);
    if (!sourceNode || !targetNode) return '';

    // Simple port calculation (center right to center left)
    const sx = sourceNode.position.x + 256; // Width of node
    const sy = sourceNode.position.y + 60; // Approx vertical center
    const tx = targetNode.position.x;
    const ty = targetNode.position.y + 60;

    const dist = Math.abs(tx - sx);
    const controlPointOffset = Math.max(dist * 0.5, 50);

    return `M ${sx} ${sy} C ${sx + controlPointOffset} ${sy}, ${tx - controlPointOffset} ${ty}, ${tx} ${ty}`;
  };

  return (
    <div className="relative w-full h-[600px] overflow-hidden rounded-xl border border-zinc-800 bg-[#0c0c0e] shadow-2xl">
      {/* Editor Toolbar */}
      <div className="absolute top-4 left-4 right-4 z-10 flex items-center justify-between pointer-events-none">
         <div className="flex items-center gap-2 pointer-events-auto bg-zinc-900/80 backdrop-blur-md p-1.5 rounded-lg border border-zinc-800 shadow-lg">
            <button className="flex items-center gap-2 px-3 py-1.5 bg-primary text-white text-xs font-medium rounded hover:bg-blue-600 transition-colors">
              <Plus size={14} />
              Add Node
            </button>
            <div className="h-4 w-[1px] bg-zinc-700 mx-1"></div>
            <div className="text-xs text-zinc-400 px-2 font-mono">1 selected</div>
            <button className="p-1.5 text-zinc-400 hover:text-red-400 transition-colors">
              <Trash2 size={14} />
            </button>
         </div>
         
         <div className="flex items-center gap-4 pointer-events-auto">
             <div className="flex items-center gap-2 bg-zinc-900/80 backdrop-blur-md px-3 py-1.5 rounded-lg border border-zinc-800">
               <span className="text-xs text-zinc-400">Zoom</span>
               <span className="text-xs font-mono text-white">100%</span>
             </div>
         </div>
      </div>

      {/* Canvas Area */}
      <div 
        ref={containerRef}
        className="w-full h-full dots-bg cursor-default relative"
        style={{ transform: `scale(${scale})`, transformOrigin: '0 0' }}
        onMouseDown={() => setSelectedNode(null)}
      >
        <svg className="absolute inset-0 pointer-events-none w-full h-full overflow-visible z-0">
          <defs>
             <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto">
               <polygon points="0 0, 10 3.5, 0 7" fill="#52525b" />
             </marker>
          </defs>
          {INITIAL_EDGES.map(edge => {
            const isSelected = nodes.find(n => n.id === edge.source)?.id === selectedNode || nodes.find(n => n.id === edge.target)?.id === selectedNode;
            return (
              <g key={edge.id}>
                <path 
                  d={getPath(edge.source, edge.target)} 
                  stroke={isSelected ? '#3b82f6' : '#52525b'} 
                  strokeWidth={isSelected ? 3 : 2} 
                  fill="none" 
                  markerEnd="url(#arrowhead)"
                  className="transition-colors duration-300"
                />
              </g>
            );
          })}
        </svg>

        <div className="relative z-10 w-full h-full">
           {nodes.map(node => (
             <NodeComponent 
               key={node.id} 
               node={node} 
               isSelected={selectedNode === node.id}
               onSelect={() => setSelectedNode(node.id)}
               onDragStart={handleDragStart}
             />
           ))}
        </div>
      </div>
      
      {/* Inspector Panel (Visual Only) */}
      <div className="absolute top-0 right-0 w-80 h-full bg-zinc-950 border-l border-zinc-800 z-20 flex flex-col transform transition-transform duration-300" 
           style={{ transform: selectedNode ? 'translateX(0)' : 'translateX(100%)' }}>
          {selectedNode && (() => {
             const node = nodes.find(n => n.id === selectedNode)!;
             return (
               <>
                 <div className="h-12 border-b border-zinc-800 flex items-center justify-between px-4">
                    <span className="text-xs font-bold text-zinc-400 tracking-wider">INSPECTOR</span>
                    <button onClick={() => setSelectedNode(null)} className="text-zinc-500 hover:text-white">×</button>
                 </div>
                 <div className="p-4 space-y-6">
                    <div>
                      <label className="block text-xs font-medium text-zinc-500 mb-2">APPEARANCE</label>
                      <div className="grid grid-cols-5 gap-2">
                        {['#f59e0b', '#a855f7', '#eab308', '#22c55e', '#ef4444', '#3b82f6', '#ec4899', '#6366f1'].map(c => (
                          <div key={c} className={`w-6 h-6 rounded cursor-pointer ring-offset-2 ring-offset-zinc-950 transition-all ${node.color === c ? 'ring-2 ring-white scale-110' : 'hover:scale-110'}`} style={{ backgroundColor: c }}></div>
                        ))}
                      </div>
                    </div>
                    
                    <div>
                       <label className="block text-xs font-medium text-zinc-500 mb-2">TITLE</label>
                       <input readOnly value={node.label} className="w-full bg-zinc-900 border border-zinc-800 rounded px-3 py-2 text-sm text-zinc-200 focus:outline-none focus:border-primary" />
                    </div>
                    
                    <div>
                       <label className="block text-xs font-medium text-zinc-500 mb-2">TYPE</label>
                       <div className="w-full bg-zinc-900 border border-zinc-800 rounded px-3 py-2 text-sm text-zinc-200 capitalize">
                         {node.type}
                       </div>
                    </div>

                    <div>
                       <label className="block text-xs font-medium text-zinc-500 mb-2">CONFIGURATION</label>
                       <textarea 
                          readOnly 
                          value={node.description || ''} 
                          className="w-full bg-zinc-900 border border-zinc-800 rounded px-3 py-2 text-sm text-zinc-400 font-mono h-24 resize-none focus:outline-none"
                        />
                    </div>
                 </div>
               </>
             )
          })()}
      </div>
    </div>
  );
};