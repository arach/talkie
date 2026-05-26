# Hudson embedded design tool primitives

Hudson is the vanilla TypeScript layer for Talkie WKWebView surfaces that behave like small design tools. It is loaded from app resources via `loadFileURL`; no dev server, React, or Next.js runtime is involved.

Current status: v0 scaffold. Capture Markup still owns its consumer-specific DOM, image binding, bridge messages, and renderer. The primitives here mirror the Capture Markup machinery so it can be moved behind this API without changing the user flow.

## Exposed primitives

- `Hudson.Viewport`: pan/zoom math, fit-to-bounds, cursor-centered zoom, screen-to-world conversion.
- `Hudson.History`: bounded `{ past, future }` undo/redo stacks over serializable snapshots.
- `Hudson.HitTest`: reverse-order hit testing for rect and segment layers.
- `Hudson.Selection`: selection state helpers and attach payload creation.
- `Hudson.Tools`: first-pass shape factories for rect, arrow, line, text label, and blur placeholder layers.
- `Hudson.Chrome`: tiny DOM shell helpers for sidebars/toolbars/inspectors; consumers provide markup and styling.

## Consumer bind points

A WKWebView consumer should provide:

- `host.exportDocument(): Hudson.Document` for Swift bridge export.
- `host.onDocumentChanged(document)` for autosave/update bridge messages.
- `host.onSelectionChanged(selection)` for sidebar/inspector sync.
- `host.onAttach(layer)` for explicit grip-click attachment gestures.
- render handlers per layer kind: `drawLayer(kind, ctx, layer, viewport)`.

## Build

Run:

```bash
./build.sh
```

This runs the cached TypeScript compiler when present, otherwise `bunx tsc -p tsconfig.json`, and writes `dist/hudson.js`. The generated file is committed/shipped as an app resource so WKWebView pages can include it with a normal `<script>` tag.
