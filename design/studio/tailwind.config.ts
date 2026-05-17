import type { Config } from "tailwindcss";

/**
 * Studio Tailwind config.
 *
 * Two color namespaces:
 *  - `studio-*` — chrome around the artifact (nav, page bg, ink ladder).
 *    Fixed values, never themed. Source of truth for the studio's neutral.
 *  - `scheme-*` — the artifact's material palette. Backed by CSS vars
 *    set by `<SchemeCard>` at runtime; values come from `lib/schemes.ts`.
 *
 * Per-iOS-theme tokens (Scope / Midnight / Tactical / Ghost) for the
 * iphone-themes study live in `lib/themes.ts` and apply via inline
 * style on the theme wrapper, not via Tailwind classes — themes are
 * 4 bundles, not a palette extension.
 */
const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        studio: {
          canvas: "#FBFBFA",
          "canvas-alt": "#F2F2F1",
          ink: "#2A2620",
          "ink-faint": "#7A746C",
          edge: "#E0DCD3",
        },
        // Scheme-* tokens reference CSS vars set by <SchemeCard>.
        scheme: {
          bg: "var(--scheme-bg)",
          ink: "var(--scheme-ink)",
          "ink-faint": "var(--scheme-ink-faint)",
          accent: "var(--scheme-accent)",
          trace: "var(--scheme-trace)",
          rec: "var(--scheme-rec)",
          edge: "var(--scheme-edge)",
          "edge-strong": "var(--scheme-edge-strong)",
        },
      },
      fontFamily: {
        // Newsreader / Inter / JetBrains Mono — the design family the
        // custom face inherits from. Display = Newsreader (editorial
        // serif). Body = Inter (UI workhorse). Mono = JetBrains Mono
        // (channel labels, eyebrows, chrome).
        display: ["Newsreader", '"Iowan Old Style"', "Georgia", "serif"],
        sans: ["Inter", "-apple-system", '"SF Pro Text"', "sans-serif"],
        mono: ['"JetBrains Mono"', "ui-monospace", '"SF Mono"', "Menlo", "monospace"],
      },
      letterSpacing: {
        eyebrow: "0.22em",
        ch: "0.18em",
        status: "0.28em",
      },
      boxShadow: {
        artifact: "0 6px 14px rgba(0, 0, 0, 0.18)",
      },
      maxWidth: {
        page: "1680px",
      },
    },
  },
  plugins: [],
};

export default config;
