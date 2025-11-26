"use client"
import React, { useEffect, useState } from 'react'
import { Sun, Moon } from 'lucide-react'

export default function ThemeToggle({ className = '', floating = true }) {
  const [dark, setDark] = useState(false)

  useEffect(() => {
    const stored = typeof window !== 'undefined' ? localStorage.getItem('theme') : null
    const prefers = typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches
    const useDark = stored ? stored === 'dark' : prefers
    setDark(useDark)
    updateClass(useDark)
  }, [])

  function updateClass(useDark) {
    const root = document.documentElement
    if (useDark) root.classList.add('dark')
    else root.classList.remove('dark')
  }

  function toggle() {
    const next = !dark
    setDark(next)
    updateClass(next)
    try { localStorage.setItem('theme', next ? 'dark' : 'light') } catch {}
  }

  const base = 'inline-flex items-center justify-center rounded-md border border-zinc-200/60 dark:border-zinc-700/60 bg-white/60 dark:bg-zinc-900/60 backdrop-blur px-2 py-1 text-zinc-700 dark:text-zinc-200 hover:bg-white/80 dark:hover:bg-zinc-800/80 transition-colors shadow-sm'
  const floatingCls = floating ? 'fixed bottom-4 right-4 md:bottom-5 md:right-5 opacity-70 hover:opacity-100 z-50' : ''
  return (
    <button aria-label="Toggle theme" onClick={toggle} className={`${base} ${floatingCls} ${className}`}>
      {dark ? <Sun className="h-3.5 w-3.5" /> : <Moon className="h-3.5 w-3.5" />}
    </button>
  )}
