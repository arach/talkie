
import React from 'react';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'outline' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  children: React.ReactNode;
  icon?: React.ReactNode;
}

export const Button: React.FC<ButtonProps> = ({ 
  variant = 'primary', 
  size = 'md', 
  children, 
  className = '', 
  icon,
  ...props 
}) => {
  const baseStyles = "relative inline-flex items-center justify-center font-bold uppercase tracking-wide transition-all focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed group overflow-hidden";
  
  const variants = {
    // Primary: White to Darker Gray
    primary: "bg-white text-black border border-white hover:bg-zinc-300 hover:border-zinc-300",
    // Secondary: Zinc-800 to Almost Black
    secondary: "bg-zinc-800 text-white border border-zinc-800 hover:bg-black hover:border-black",
    // Outline: Transparent to Darker BG
    outline: "bg-transparent border border-zinc-700 text-zinc-300 hover:border-white hover:text-white hover:bg-zinc-900",
    ghost: "border border-transparent text-zinc-400 hover:text-white hover:bg-zinc-900",
  };

  const sizes = {
    sm: "px-4 py-2 text-[10px]",
    md: "px-6 py-3 text-xs",
    lg: "px-8 py-4 text-sm",
  };

  return (
    <button 
      className={`${baseStyles} ${variants[variant]} ${sizes[size]} ${className}`}
      {...props}
    >
      {/* Brutalist hover decor */}
      <span className="absolute top-0 right-0 w-2 h-2 border-t border-r border-transparent group-hover:border-current opacity-50 transition-colors"></span>
      <span className="absolute bottom-0 left-0 w-2 h-2 border-b border-l border-transparent group-hover:border-current opacity-50 transition-colors"></span>
      
      {icon && <span className="mr-3">{icon}</span>}
      {children}
    </button>
  );
};
