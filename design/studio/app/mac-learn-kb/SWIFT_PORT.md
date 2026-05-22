# Mac Learn KB — Swift / WKWebView Port Notes

Handoff notes for the agent (Codex) that wires this into the macOS app.
None of the points below need Studio changes — they are constraints the
Swift integration must satisfy for the design to work as intended.

## Boundary

```
┌──────────────────────────────────────────────────────────────────┐
│ SwiftUI Learn KB shell                                           │
│  ├─ Sidebar / table of contents (SwiftUI)                        │
│  ├─ Search (SwiftUI)                                             │
│  ├─ Back / forward / history (SwiftUI)                           │
│  └─ Article slot                                                 │
│      ┌──────────────────────────────────────────────────────┐    │
│      │ WKWebView  ◀── this design's surface                  │    │
│      │  ├─ Hero / dek                                        │    │
│      │  ├─ Metadata ledger                                   │    │
│      │  ├─ Shortcut strip                                    │    │
│      │  ├─ Body (para / subhead / callout / steps)           │    │
│      │  ├─ Related rows                                      │    │
│      │  └─ Bridge action rows  (talkie://...)                │    │
│      └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

The web view never paints chrome it doesn't own. No back button, no
search, no theme switcher rendered inside the article — those belong to
the SwiftUI shell. If the article needs to suggest a related article,
it does so via a `Related` row whose `href` resolves to another
WKWebView load triggered by the shell.

## Theme

The web view receives a single attribute on the article wrapper:

```html
<article data-theme="scope">   <!-- or midnight / tactical / ghost -->
```

`globals.css` (the same one used in Studio) defines `[data-theme="X"]`
blocks that set every `--theme-*` variable consumed by the reader.

**The Swift side decides theme at load time** by reading the user's
`scopeTheme` setting and stamping `data-theme` on the root `<article>`
element. Theme transitions can be implemented two ways:

1. **Reload on theme change.** Simplest; one full WKWebView reload
   when the user flips theme. Acceptable for a low-traffic surface
   where theme changes are rare.
2. **JS bridge to swap the attribute.** Inject a tiny script that
   listens for a `theme-change` message from Swift and mutates
   `document.documentElement.dataset.theme`. No reload, CSS variables
   cascade.

(Recommended: reload. KB theme flips are rare enough that the
simplicity wins.)

## Fonts

Fonts come from `--theme-font-display | -body | -mono`, which the
Studio resolves to Newsreader / Inter / JetBrains Mono. In the shipping
app:

- These should be bundled in the macOS app and exposed to the web view
  via a custom URL scheme handler OR the standard `font-face` rule
  pointing at `file://` URLs that the WKWebView can read.
- Until the bundled fonts land, the existing `var(--theme-font-*)`
  stacks fall back to system serif / sans / mono — readable but not
  identity-correct.
- The Talkie custom display face (planned) replaces `Newsreader` in
  the same stack with no other code changes.

## Deep links — `talkie://`

The bridge rows use the `talkie://` URL scheme. WKWebView must be
configured to intercept these and hand them to the SwiftUI router,
NOT navigate the web view.

Suggested decision policy (`WKNavigationDelegate.decidePolicyFor`):

```swift
if let url = navigationAction.request.url, url.scheme == "talkie" {
    NSWorkspace.shared.open(url)   // or call into the AppRouter directly
    decisionHandler(.cancel)
    return
}
decisionHandler(.allow)
```

URLs used by the sample articles (real routes are owned by Swift):

| URL                              | Meaning                                                   |
|----------------------------------|-----------------------------------------------------------|
| `talkie://tray`                  | Drop down the recording tray                              |
| `talkie://settings/surface`      | Open Settings → Surface (Hyper keys, surface bindings)    |
| `talkie://open/workflows`        | Jump to Workflows with context-rule panel expanded        |

Add new bridge URLs as the KB grows; the Swift side owns the route
table.

## Internal article links

Article-to-article navigation (the `Related` block) uses internal
paths like `/learn/customize-hyper-keys`. WKWebView should NOT navigate
to these as external URLs — they need to load the next article in the
SAME web view with the SAME theme attribute. Implementation:

- Intercept `/learn/...` paths in `decidePolicyFor`.
- Resolve to a file URL / HTML payload for the next article.
- Re-load with the correct `data-theme` attribute.

If the SwiftUI sidebar is also showing a TOC, the sidebar should sync
its selection from the same nav event so the two stay coherent.

## Article content shape

Studio's `KBArticle` interface (in `MacLearnKB.tsx`) is the porting
contract. The Swift side will likely consume markdown with frontmatter,
then render to HTML at build time. The block model in TypeScript:

```ts
type ArticleBlock =
  | { kind: "para";    text: string }
  | { kind: "subhead"; text: string }
  | { kind: "callout"; tone: "note" | "tip" | "warn"; title: string; text: string }
  | { kind: "steps";   items: { title: string; text: string }[] }
  | { kind: "related"; items: { title: string; topic: string; href: string }[] }
  | { kind: "bridge";  items: { label: string; href: string; detail: string }[] }
```

These map cleanly to markdown:

- `para` → paragraph
- `subhead` → `## Heading`
- `callout` → admonition syntax (e.g. `:::tip Title \n text \n :::`)
- `steps` → ordered list where each item is `**Title** — text`
- `related`/`bridge` → list with custom link metadata, parsed from a
  trailing frontmatter section per article (`related:` / `bridge:`).

Detail format is owned by the content agent. The renderer (Swift or a
build step) must preserve the same DOM shape this Studio component
emits — that's where the CSS variable cascade does its work.

## Sizing & layout

- Article body uses `max-width: 720px`. SwiftUI host can be wider; the
  web view will letterbox the content column with `--theme-canvas` on
  the sides. That's intentional — paragraphs stay readable.
- Hero + ledger + shortcut strip span the full available width.
- The component does not call `scrollIntoView` or set any viewport
  meta — scrolling is the host's responsibility.

## What Studio cannot test

- Real WKWebView intercept of `talkie://` (those just navigate in the
  browser preview).
- macOS-specific font rendering on Retina vs non-Retina.
- The shell's back/forward history when bouncing between articles.
- Accessibility: VoiceOver flows through WKWebView differently than a
  native view; verify rotor navigation lands on the section eyebrows
  in reading order.

When porting, run those four manually before declaring done.
