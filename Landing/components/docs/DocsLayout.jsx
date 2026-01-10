"use client"
import React from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ArrowLeft, Book, Lightbulb, Boxes, Database, Workflow, Code2, Puzzle, Server, Globe, ChevronRight, Menu, X, Route } from 'lucide-react'
import Container from '../Container'

// Navigation structure for all docs
const docsNav = [
  {
    title: 'Getting Started',
    items: [
      { title: 'Overview', href: '/docs/overview', icon: Lightbulb, description: 'Philosophy & principles' },
      { title: 'Architecture', href: '/docs/architecture', icon: Boxes, description: 'How it all fits together' },
      { title: 'Lifecycle', href: '/docs/lifecycle', icon: Route, description: 'Voice to action flow' },
      { title: 'Your Data', href: '/docs/data', icon: Database, description: 'Storage & exports' },
    ]
  },
  {
    title: 'Setup',
    items: [
      { title: 'TalkieServer', href: '/docs/bridge-setup', icon: Server, description: 'Local bridge service' },
      { title: 'Tailscale', href: '/docs/tailscale', icon: Globe, description: 'Secure networking' },
    ]
  },
  {
    title: 'Advanced',
    items: [
      { title: 'Workflows', href: '/docs/workflows', icon: Workflow, description: 'Automation & pipelines' },
      { title: 'API Reference', href: '/docs/api', icon: Code2, description: 'Endpoints & schemes' },
      { title: 'Extensibility', href: '/docs/extensibility', icon: Puzzle, description: 'Webhooks & integrations' },
    ]
  }
]

// Left sidebar navigation
function DocsSidebar({ isOpen, onClose }) {
  const pathname = usePathname()

  return (
    <>
      {/* Mobile overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 bg-black/50 z-40 lg:hidden"
          onClick={onClose}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        fixed top-14 left-0 bottom-0 w-72 bg-white dark:bg-zinc-950 border-r border-zinc-200 dark:border-zinc-800
        overflow-y-auto z-50
        transform transition-transform duration-200 ease-in-out
        lg:translate-x-0 lg:z-30
        ${isOpen ? 'translate-x-0' : '-translate-x-full'}
      `}>
        <div className="p-6">
          {/* Back to docs index */}
          <Link
            href="/docs"
            className="flex items-center gap-2 text-sm font-medium text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white mb-6"
          >
            <Book className="w-4 h-4" />
            Documentation
          </Link>

          {/* Navigation groups */}
          <nav className="space-y-8">
            {docsNav.map((group) => (
              <div key={group.title}>
                <h3 className="text-xs font-bold uppercase tracking-wider text-zinc-400 dark:text-zinc-500 mb-3">
                  {group.title}
                </h3>
                <ul className="space-y-1">
                  {group.items.map((item) => {
                    const isActive = pathname === item.href
                    const Icon = item.icon
                    return (
                      <li key={item.href}>
                        <Link
                          href={item.href}
                          onClick={onClose}
                          className={`
                            flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors
                            ${isActive
                              ? 'bg-emerald-50 dark:bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 font-medium'
                              : 'text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-900 dark:hover:text-white'
                            }
                          `}
                        >
                          <Icon className="w-4 h-4 flex-shrink-0" />
                          <span>{item.title}</span>
                        </Link>
                      </li>
                    )
                  })}
                </ul>
              </div>
            ))}
          </nav>
        </div>
      </aside>
    </>
  )
}

// Right sidebar table of contents
function TableOfContents({ sections }) {
  const [activeSection, setActiveSection] = React.useState('')

  React.useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setActiveSection(entry.target.id)
          }
        })
      },
      { rootMargin: '-100px 0px -66% 0px' }
    )

    sections.forEach((section) => {
      const el = document.getElementById(section.id)
      if (el) observer.observe(el)
    })

    return () => observer.disconnect()
  }, [sections])

  if (!sections || sections.length === 0) return null

  return (
    <aside className="hidden xl:block fixed top-14 right-0 w-64 h-[calc(100vh-3.5rem)] overflow-y-auto border-l border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-950">
      <div className="p-6">
        <h4 className="text-xs font-bold uppercase tracking-wider text-zinc-400 dark:text-zinc-500 mb-4">
          On this page
        </h4>
        <nav>
          <ul className="space-y-2">
            {sections.map((section) => (
              <li key={section.id}>
                <a
                  href={`#${section.id}`}
                  className={`
                    block text-sm transition-colors
                    ${section.level === 2 ? 'pl-0' : 'pl-3'}
                    ${activeSection === section.id
                      ? 'text-emerald-600 dark:text-emerald-400 font-medium'
                      : 'text-zinc-500 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-white'
                    }
                  `}
                >
                  {section.title}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </aside>
  )
}

// Main layout wrapper
export default function DocsLayout({
  children,
  title,
  description,
  badge,
  badgeColor = 'emerald',
  sections = []
}) {
  const [sidebarOpen, setSidebarOpen] = React.useState(false)

  const badgeColors = {
    emerald: 'border-emerald-200 dark:border-emerald-500/30 bg-emerald-50 dark:bg-emerald-500/10 text-emerald-700 dark:text-emerald-400',
    blue: 'border-blue-200 dark:border-blue-500/30 bg-blue-50 dark:bg-blue-500/10 text-blue-700 dark:text-blue-400',
    purple: 'border-purple-200 dark:border-purple-500/30 bg-purple-50 dark:bg-purple-500/10 text-purple-700 dark:text-purple-400',
    amber: 'border-amber-200 dark:border-amber-500/30 bg-amber-50 dark:bg-amber-500/10 text-amber-700 dark:text-amber-400',
    rose: 'border-rose-200 dark:border-rose-500/30 bg-rose-50 dark:bg-rose-500/10 text-rose-700 dark:text-rose-400',
  }

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950">
      {/* Top navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 h-14 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <div className="h-full px-4 flex items-center justify-between">
          <div className="flex items-center gap-4">
            {/* Mobile menu button */}
            <button
              onClick={() => setSidebarOpen(!sidebarOpen)}
              className="lg:hidden p-2 -ml-2 text-zinc-500 hover:text-zinc-900 dark:hover:text-white"
            >
              {sidebarOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>

            <Link
              href="/"
              className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
            >
              <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
              <span className="hidden sm:inline">TALKIE</span>
            </Link>
          </div>

          <div className="flex items-center gap-2 sm:gap-3">
            <Link
              href="/docs"
              className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
            >
              DOCS
            </Link>
          </div>
        </div>
      </nav>

      {/* Left sidebar */}
      <DocsSidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      {/* Right table of contents */}
      <TableOfContents sections={sections} />

      {/* Main content */}
      <main className="pt-14 lg:pl-72 xl:pr-64">
        <div className="max-w-3xl mx-auto px-6 py-12">
          {/* Page header */}
          {badge && (
            <div className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-full border ${badgeColors[badgeColor]} mb-6`}>
              <span className="text-xs font-medium">{badge}</span>
            </div>
          )}

          {title && (
            <h1 className="text-3xl md:text-4xl font-display font-semibold tracking-tight text-zinc-900 dark:text-white mb-4">
              {title}
            </h1>
          )}

          {description && (
            <p className="text-lg text-zinc-600 dark:text-zinc-400 mb-12">
              {description}
            </p>
          )}

          {/* Page content */}
          <div className="prose prose-zinc dark:prose-invert max-w-none
            prose-headings:scroll-mt-20 prose-headings:font-display
            prose-h2:text-2xl prose-h2:font-semibold prose-h2:mt-12 prose-h2:mb-4 prose-h2:tracking-tight
            prose-h3:text-xl prose-h3:font-medium prose-h3:mt-8 prose-h3:mb-3
            prose-p:text-zinc-600 dark:prose-p:text-zinc-400 prose-p:leading-relaxed
            prose-a:text-emerald-600 dark:prose-a:text-emerald-400 prose-a:no-underline hover:prose-a:underline
            prose-strong:font-semibold prose-strong:text-zinc-800 dark:prose-strong:text-zinc-200
            prose-code:bg-zinc-100 dark:prose-code:bg-zinc-800 prose-code:px-1.5 prose-code:py-0.5 prose-code:rounded prose-code:text-sm prose-code:font-normal prose-code:before:content-none prose-code:after:content-none
            prose-pre:bg-zinc-900 dark:prose-pre:bg-zinc-900 prose-pre:border prose-pre:border-zinc-800
            prose-ul:text-zinc-600 dark:prose-ul:text-zinc-400
            prose-li:marker:text-zinc-400 prose-li:leading-relaxed
          ">
            {children}
          </div>
        </div>
      </main>
    </div>
  )
}

// Export nav structure for use in other components
export { docsNav }
