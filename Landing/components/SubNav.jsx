"use client"
import React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Laptop, Smartphone, Bot } from 'lucide-react'

const navItems = [
  { href: '/dictation', label: 'Mac', icon: Laptop, color: 'emerald' },
  { href: '/capture', label: 'Mobile', icon: Smartphone, color: 'blue' },
  { href: '/workflows', label: 'Agents', icon: Bot, color: 'purple' },
]

export default function SubNav() {
  const pathname = usePathname()

  return (
    <div className="inline-flex items-center p-1 bg-white/60 dark:bg-zinc-900/60 backdrop-blur-xl border border-zinc-200/50 dark:border-zinc-700/50 rounded-full shadow-lg shadow-black/5 dark:shadow-black/20">
      {navItems.map(({ href, label, icon: Icon, color }) => {
        const isActive = pathname === href || pathname.startsWith(href + '/')

        const activeClasses = {
          emerald: 'bg-emerald-500 text-white shadow-lg shadow-emerald-500/25',
          blue: 'bg-blue-500 text-white shadow-lg shadow-blue-500/25',
          purple: 'bg-purple-500 text-white shadow-lg shadow-purple-500/25',
        }

        return (
          <Link
            key={href}
            href={href}
            className={`flex items-center justify-center gap-2 w-32 py-2 rounded-full transition-all ${
              isActive
                ? activeClasses[color]
                : 'text-zinc-500 hover:text-zinc-900 dark:hover:text-white hover:bg-white/80 dark:hover:bg-zinc-800/80'
            }`}
          >
            <Icon className="w-4 h-4" />
            <span className="text-[11px] font-bold uppercase tracking-wider">{label}</span>
          </Link>
        )
      })}
    </div>
  )
}
