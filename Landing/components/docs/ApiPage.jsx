"use client"
import React from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Code, Server, Link2, Terminal } from 'lucide-react'
import Container from '../Container'

const Section = ({ title, children }) => (
  <section className="mb-12">
    <h2 className="text-2xl font-bold text-zinc-900 dark:text-white mb-4">{title}</h2>
    <div className="text-zinc-600 dark:text-zinc-400 space-y-4">{children}</div>
  </section>
)

const Placeholder = ({ children }) => (
  <div className="p-6 rounded-lg border border-dashed border-zinc-300 dark:border-zinc-700 bg-zinc-100 dark:bg-zinc-900/50">
    <p className="text-sm text-zinc-500 dark:text-zinc-500 italic">{children}</p>
  </div>
)

const CodeBlock = ({ children, title }) => (
  <div className="rounded-lg border border-zinc-200 dark:border-zinc-800 overflow-hidden">
    {title && (
      <div className="px-4 py-2 bg-zinc-100 dark:bg-zinc-800 border-b border-zinc-200 dark:border-zinc-700">
        <span className="text-xs font-mono text-zinc-500">{title}</span>
      </div>
    )}
    <pre className="p-4 bg-zinc-50 dark:bg-zinc-900 overflow-x-auto">
      <code className="text-sm font-mono text-zinc-800 dark:text-zinc-200">{children}</code>
    </pre>
  </div>
)

const EndpointCard = ({ method, path, description }) => {
  const methodColors = {
    GET: 'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-700 dark:text-emerald-400',
    POST: 'bg-blue-100 dark:bg-blue-500/20 text-blue-700 dark:text-blue-400',
    PUT: 'bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-400',
    DELETE: 'bg-red-100 dark:bg-red-500/20 text-red-700 dark:text-red-400',
  }

  return (
    <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
      <div className="flex items-center gap-3 mb-2">
        <span className={`px-2 py-0.5 text-xs font-bold rounded ${methodColors[method]}`}>
          {method}
        </span>
        <code className="text-sm font-mono text-zinc-800 dark:text-zinc-200">{path}</code>
      </div>
      <p className="text-sm text-zinc-600 dark:text-zinc-400">{description}</p>
    </div>
  )
}

export default function ApiPage() {
  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/90 dark:bg-zinc-950/90 backdrop-blur-md border-b border-zinc-200 dark:border-zinc-800">
        <Container className="h-14 flex items-center justify-between">
          <Link
            href="/docs"
            className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-zinc-500 hover:text-black dark:hover:text-white transition-colors group"
          >
            <ArrowLeft className="w-3 h-3 transition-transform group-hover:-translate-x-0.5" />
            DOCS
          </Link>

          <div className="flex items-center gap-2 sm:gap-3">
            <div className="h-3 w-px bg-zinc-300 dark:bg-zinc-700"></div>
            <span className="text-[10px] font-mono font-bold uppercase tracking-widest text-zinc-900 dark:text-white">API</span>
          </div>
        </Container>
      </nav>

      <main className="pt-24 pb-32 px-6">
        <Container>
          <div className="max-w-3xl">
            {/* Header */}
            <div className="mb-12">
              <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-orange-200 dark:border-orange-500/30 bg-orange-50 dark:bg-orange-500/10 mb-6">
                <Code className="w-4 h-4 text-orange-600 dark:text-orange-400" />
                <span className="text-xs font-medium text-orange-700 dark:text-orange-400">Reference</span>
              </div>

              <h1 className="text-4xl md:text-5xl font-bold tracking-tight text-zinc-900 dark:text-white mb-6">
                API Reference
              </h1>

              <p className="text-lg text-zinc-600 dark:text-zinc-400">
                Integration points for developers. HTTP endpoints, URL schemes,
                and programmatic access to Talkie.
              </p>
            </div>

            {/* TalkieServer HTTP Endpoints */}
            <Section title="TalkieServer HTTP Endpoints">
              <p>
                TalkieServer exposes HTTP endpoints for iOS connectivity and local integrations.
                By default, it listens on port 8765.
              </p>

              <div className="space-y-3 mt-6">
                <EndpointCard
                  method="GET"
                  path="/health"
                  description="Health check endpoint. Returns server status and version."
                />
                <EndpointCard
                  method="GET"
                  path="/pair"
                  description="Returns pairing information for iOS device connection."
                />
                <EndpointCard
                  method="POST"
                  path="/memos"
                  description="Upload a new voice memo from iOS device."
                />
                <EndpointCard
                  method="GET"
                  path="/memos"
                  description="List recent memos (for iOS sync)."
                />
              </div>

              <Placeholder>
                Coming soon: Full endpoint documentation with request/response
                schemas, authentication details, and error codes.
              </Placeholder>
            </Section>

            {/* URL Schemes */}
            <Section title="URL Schemes">
              <p>
                Talkie registers URL schemes for deep linking and automation.
              </p>

              <CodeBlock title="Supported URL Schemes">
{`talkie://                    # Open Talkie
talkie://record              # Start recording
talkie://stop                # Stop recording
talkie://memo/{id}           # Open specific memo
talkie://settings            # Open settings`}
              </CodeBlock>

              <Placeholder>
                Coming soon: Complete URL scheme reference with parameters,
                Shortcuts integration, and automation examples.
              </Placeholder>
            </Section>

            {/* AppleScript */}
            <Section title="AppleScript Support">
              <div className="p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900">
                <div className="flex items-center gap-3 mb-3">
                  <Terminal className="w-5 h-5 text-violet-500" />
                  <h3 className="font-bold text-zinc-900 dark:text-white">Scriptable</h3>
                </div>
                <p className="text-sm text-zinc-600 dark:text-zinc-400">
                  Talkie is scriptable via AppleScript, enabling integration with
                  Alfred, Keyboard Maestro, and other automation tools.
                </p>
              </div>

              <CodeBlock title="Example AppleScript">
{`tell application "Talkie"
  start recording
  delay 5
  stop recording
end tell`}
              </CodeBlock>

              <Placeholder>
                Coming soon: Complete AppleScript dictionary documentation,
                example scripts, and integration guides.
              </Placeholder>
            </Section>

            {/* Shortcuts Integration */}
            <Section title="Shortcuts Integration">
              <Placeholder>
                Coming soon: Available Shortcuts actions, example shortcuts,
                and Siri integration.
              </Placeholder>
            </Section>

            {/* Error Codes */}
            <Section title="Error Codes">
              <Placeholder>
                Coming soon: List of error codes, meanings, and
                troubleshooting guidance.
              </Placeholder>
            </Section>

            {/* Navigation */}
            <section className="pt-8 border-t border-zinc-200 dark:border-zinc-800">
              <div className="flex flex-col sm:flex-row gap-4">
                <Link
                  href="/docs/workflows"
                  className="group flex-1 flex items-center gap-4 p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <ArrowLeft className="w-5 h-5 text-zinc-400 group-hover:text-rose-500 group-hover:-translate-x-1 transition-all" />
                  <div>
                    <span className="text-xs text-zinc-500">Previous</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-rose-600 dark:group-hover:text-rose-400 transition-colors">
                      Workflows
                    </h3>
                  </div>
                </Link>

                <Link
                  href="/docs/extensibility"
                  className="group flex-1 flex items-center justify-between p-4 rounded-lg border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 hover:border-zinc-300 dark:hover:border-zinc-700 transition-colors"
                >
                  <div>
                    <span className="text-xs text-zinc-500">Next</span>
                    <h3 className="font-bold text-zinc-900 dark:text-white group-hover:text-indigo-600 dark:group-hover:text-indigo-400 transition-colors">
                      Extensibility
                    </h3>
                  </div>
                  <ArrowRight className="w-5 h-5 text-zinc-400 group-hover:text-indigo-500 group-hover:translate-x-1 transition-all" />
                </Link>
              </div>
            </section>
          </div>
        </Container>
      </main>
    </div>
  )
}
