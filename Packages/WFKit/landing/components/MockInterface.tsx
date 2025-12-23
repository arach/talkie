import React from 'react';

const Node = ({ x, y, label, type, inputs = 1, outputs = 1, width = 180, color = 'zinc' }: any) => {
  const getColor = () => {
    switch(color) {
      case 'orange': return 'border-orange-500/50 text-orange-500';
      case 'blue': return 'border-blue-500/50 text-blue-500';
      case 'green': return 'border-green-500/50 text-green-500';
      case 'red': return 'border-red-500/50 text-red-500';
      default: return 'border-zinc-700 text-zinc-300';
    }
  };

  const getBgColor = () => {
     switch(color) {
      case 'orange': return 'bg-orange-500';
      case 'blue': return 'bg-blue-500';
      case 'green': return 'bg-green-500';
      case 'red': return 'bg-red-500';
      default: return 'bg-zinc-500';
    }
  };

  return (
    <div 
      className={`absolute border bg-[#0c0c0e] flex flex-col z-10 transition-colors duration-500 ${getColor()} border-opacity-40`}
      style={{ left: x, top: y, width, boxShadow: '4px 4px 0px 0px rgba(0, 0, 0, 0.5)' }}
    >
      {/* Header */}
      <div className="h-8 border-b border-inherit flex items-center justify-between px-3 bg-zinc-900/30">
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 ${getBgColor()}`}></div>
          <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-300">{label}</span>
        </div>
        <span className="text-[8px] font-mono text-zinc-600">{type.toUpperCase().slice(0, 3)}</span>
      </div>
      
      {/* Body */}
      <div className="p-3 relative">
        <div className="space-y-2">
          <div className="h-1 w-2/3 bg-zinc-800/50"></div>
          <div className="h-1 w-1/2 bg-zinc-800/50"></div>
        </div>
        
        {/* Ports */}
        <div className="absolute -left-1 top-1/2 -translate-y-1/2 flex flex-col gap-2">
          {Array.from({ length: inputs }).map((_, i) => (
            <div key={i} className="w-2 h-2 border border-zinc-600 bg-[#0c0c0e]"></div>
          ))}
        </div>
        <div className="absolute -right-1 top-1/2 -translate-y-1/2 flex flex-col gap-2">
           {Array.from({ length: outputs }).map((_, i) => (
            <div key={i} className="w-2 h-2 border border-zinc-600 bg-[#0c0c0e]"></div>
          ))}
        </div>
      </div>
    </div>
  );
};

export const MockInterface = () => {
  return (
    <div className="w-full h-full bg-[#09090b] relative overflow-hidden select-none group">
      {/* Grid Background */}
      <div className="absolute inset-0" 
           style={{ 
             backgroundImage: 'linear-gradient(#18181b 1px, transparent 1px), linear-gradient(90deg, #18181b 1px, transparent 1px)', 
             backgroundSize: '40px 40px' 
           }}>
      </div>
      
      {/* Content Layer - Grayscale by default, color on hover */}
      <div className="absolute inset-0 w-full h-full z-10 grayscale group-hover:grayscale-0 transition-all duration-700 ease-in-out">
        {/* SVG Connections */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none z-0">
          <path d="M 190 120 C 250 120, 250 200, 310 200" fill="none" stroke="#3f3f46" strokeWidth="1" />
          <path d="M 470 200 C 530 200, 530 150, 590 150" fill="none" stroke="#3f3f46" strokeWidth="1" />
          <path d="M 470 200 C 530 200, 530 280, 590 280" fill="none" stroke="#3f3f46" strokeWidth="1" strokeDasharray="4 4" />
        </svg>

        {/* Nodes */}
        <Node x={30} y={80} width={160} label="App Trigger" type="trigger" inputs={0} color="orange" />
        <Node x={310} y={160} width={160} label="Process Data" type="action" color="blue" />
        <Node x={590} y={110} width={140} label="Save to DB" type="output" outputs={0} color="green" />
        <Node x={590} y={240} width={140} label="Log Error" type="output" outputs={0} color="red" />
      </div>
      
      {/* Floating Panel (Inspector) */}
      <div className="absolute top-4 right-4 w-48 border border-zinc-800 bg-[#0c0c0e]/90 backdrop-blur-sm shadow-xl hidden md:block z-20">
        <div className="border-b border-zinc-800 px-3 py-2">
          <span className="text-[10px] font-bold uppercase tracking-widest text-zinc-500">Inspector</span>
        </div>
        <div className="p-3 space-y-3">
          <div className="flex justify-between items-center">
             <span className="text-[10px] font-mono text-zinc-400">X Position</span>
             <span className="text-[10px] font-mono text-white">310.0</span>
          </div>
          <div className="flex justify-between items-center">
             <span className="text-[10px] font-mono text-zinc-400">Y Position</span>
             <span className="text-[10px] font-mono text-white">160.0</span>
          </div>
          <div className="h-px bg-zinc-800 my-2"></div>
          <div className="space-y-1">
             <span className="text-[10px] font-mono text-zinc-500 block">Inputs</span>
             <div className="h-1 w-full bg-zinc-800"></div>
          </div>
        </div>
      </div>
      
      {/* Floating Toolbar */}
      <div className="absolute bottom-6 left-1/2 -translate-x-1/2 flex items-center gap-px bg-zinc-800 border border-zinc-800 z-20">
        <div className="px-4 py-2 bg-[#09090b] hover:bg-black text-zinc-400 hover:text-white cursor-pointer transition-colors">
          <div className="w-3 h-3 border border-current"></div>
        </div>
        <div className="px-4 py-2 bg-[#09090b] hover:bg-black text-zinc-400 hover:text-white cursor-pointer transition-colors">
          <div className="w-3 h-3 rounded-full border border-current"></div>
        </div>
        <div className="px-4 py-2 bg-[#09090b] hover:bg-black text-zinc-400 hover:text-white cursor-pointer transition-colors">
          <span className="text-[10px] font-mono">TEXT</span>
        </div>
      </div>
      
    </div>
  );
};