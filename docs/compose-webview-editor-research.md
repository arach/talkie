
## Talkie WKWebView editor research report — July 7, 2026

### Executive recommendation

**Best library to reuse directly:** **CodeMirror 6 + `@codemirror/lang-markdown`**, wrapped by a small Talkie JS API.
It is the best fit for Talkie’s hard constraint that **Markdown/plain text remains the source of truth**. The editor document is already a string-like text model; insert-at-cursor, selection get/set, replacement, decorations, and native-driven undo/redo all map cleanly to public APIs. CodeMirror is not a full WYSIWYG editor, but it is the safest base for **live Markdown editing + review decorations + a separate or inline preview layer**.

**Best codebases to learn/borrow from if Talkie builds thin:**
1. **Atomic Editor** — best modern example of CodeMirror 6 “live Markdown preview” while keeping raw Markdown byte-for-byte source of truth.
2. **ink-mde** — practical CM6 Markdown editor shell, good for API/UX ideas.
3. **HyperMD** — historical CM5 pattern source only; do not reuse directly.

**Best direct WYSIWYG fallback if product insists on richer visual editing:** **Milkdown / Crepe**. It is Markdown-oriented and actively maintained, but because it is ProseMirror/`contenteditable`-based, Markdown is serialized from an internal document model rather than being the actual live source string.

Shortlist:

1. **CodeMirror 6 family** — primary recommendation.
2. **Milkdown / Crepe** — best “ready-made WYSIWYG Markdown” option, but heavier/riskier.
3. **ProseMirror or Tiptap** — best if Talkie wants to build a real rich-text editor and accepts Markdown canonicalization.

---

## Key Talkie constraint fit

| Candidate | Fit for Markdown-as-String SoT | Rich editing | Diff/review spans | WKWebView/offline | Native bridge / Cmd+Z | Verdict |
|---|---:|---:|---:|---:|---:|---|
| **CodeMirror 6** | Excellent | Medium | Excellent | Excellent | Excellent | **Use** |
| **ink-mde** | Excellent | Medium | Good via CM6 | Good | Good if APIs exposed | Prototype / borrow |
| **Atomic Editor** | Excellent | Medium-high | Excellent via CM6 | React wrapper, CM6 internals reusable | Good | Borrow patterns |
| **Milkdown / Crepe** | Good, not exact | High | Good | Good, heavier | Good | WYSIWYG fallback |
| **ProseMirror** | Medium | Excellent | Excellent | Good | Good | Learn/build if accepting PM doc |
| **Tiptap** | Medium | Excellent | Excellent | Good | Excellent commands | Good ecosystem, Markdown beta |
| **Lexical** | Weak for Markdown SoT | Excellent | Excellent | Good | Good but node-key selections | Not for current constraints |
| **Toast UI Editor** | Medium | High | Medium | Good, but stale | Good API | Avoid new core |
| **EasyMDE** | Excellent | Low-medium | Medium | Excellent | Good | Simple fallback, legacy CM5 |
| **ByteMD** | Excellent | Split preview | Medium | Good | Medium | If split preview is enough |
| **Vditor** | Medium | High | Medium | Heavy/offline asset work | Medium | Too heavy/opinionated |
| **HyperMD** | Excellent | Medium | Medium | Legacy | Medium | Learn only |

---

## Candidate details

### 1. CodeMirror 6 + Markdown extensions

Sources: [CodeMirror](https://codemirror.net/), [reference manual](https://codemirror.net/docs/ref/), [`@codemirror/lang-markdown`](https://www.npmjs.com/package/@codemirror/lang-markdown)

- **License:** MIT.
- **Maintenance/activity:** Very active at package level. `@codemirror/view` latest checked: **6.43.6, July 6, 2026**; `@codemirror/state`: **6.7.1, July 5, 2026**; `@codemirror/lang-markdown`: **6.5.0, October 23, 2025**. Bus factor is still mostly Marijn Haverbeke, but the project is mature and widely used.
- **Weight:** Modular. NPM unpacked sizes checked: `@codemirror/view` ~1.25 MB, `@codemirror/state` ~436 KB, `@codemirror/lang-markdown` ~72 KB, plus commands/language packages. Actual bundle should be measured after tree-shaking.
- **Markdown source of truth:** **Excellent.** The document is text. No Markdown serialization layer is needed; Talkie’s native `String` can mirror `view.state.doc.toString()`.
- **Editing model:** Source editor with syntax highlighting and optional live-preview decorations, not true WYSIWYG.
- **Inline diff/review UI:** **Excellent.** CM6 decorations support marks, replaced ranges, block widgets, inline widgets, gutters, and state effects. Green/red review spans with accept/reject buttons are a natural fit.
- **Bridge fit:** Best of all candidates:
  - `getText` → `state.doc.toString()`
  - `insertTextAtCursor` → `state.replaceSelection(text)` + `view.dispatch`
  - `replaceRange` → `view.dispatch({ changes: { from, to, insert } })`
  - `getSelection` → `{ anchor, head }`
  - `setSelection` → `EditorSelection.single(anchor, head)`
  - `undo/redo` → `undo(view)` / `redo(view)` from `@codemirror/commands`
- **Offline WKWebView:** Excellent. Bundle local JS/CSS assets; no framework required.
- **iOS WKWebView risk:** Lower than `contenteditable` WYSIWYG frameworks, but not zero. CodeMirror uses native selection/editing on mobile, and there are still open mobile selection/scroll issues. Needs real WKWebView testing with dictation, hardware keyboard, selection handles, and long docs.
- **Verdict:** **Best fit.** Build Talkie’s editor shell on CM6.

---

### 2. ink-mde

Source: [ink-mde GitHub](https://github.com/davidmyersdev/ink-mde)

- **License:** MIT.
- **Maintenance/activity:** Latest NPM checked: **0.34.0, September 28, 2024**; repo pushed **July 7, 2025**. Smaller project, likely single-maintainer.
- **Weight:** ~1.3 MB unpacked, 15 dependencies, 2 peer dependencies.
- **Markdown source of truth:** Strong. It uses a Markdown string `doc` and exposes update hooks.
- **Editing model:** Hybrid Markdown source editor with live rendering, powered by CodeMirror 6.
- **Inline diff/review UI:** Good in principle because CM6 is underneath, but Talkie may need to drop below ink-mde’s public API or fork it for serious accept/reject widgets.
- **Bridge fit:** Good for basic value sync; uncertain for every required low-level operation unless relying on underlying CM6 instance.
- **Offline WKWebView:** Good. Framework-agnostic, local bundle possible.
- **iOS risk:** Same broad CM6 class; likely acceptable but must test.
- **Verdict:** Good prototype or reference. I would not make it the core dependency unless Talkie is comfortable forking.

---

### 3. Atomic Editor

Source: [Atomic Editor GitHub](https://github.com/kenforthewin/atomic-editor)

- **License:** MIT.
- **Maintenance/activity:** Latest NPM checked: **0.4.3, May 31, 2026**. Very small project: ~114 stars, ~7 forks as checked; high bus-factor risk.
- **Weight:** ~353 KB unpacked for package, but 25 peer dependencies and React orientation.
- **Markdown source of truth:** **Excellent.** Its design explicitly keeps raw Markdown as the source and uses view-only decorations.
- **Editing model:** Obsidian-style inline live preview on top of CM6.
- **Inline diff/review UI:** Excellent pattern source: stable-height decorations, widgets, cursor-scoped syntax reveal, iOS-aware scroll fixes.
- **Bridge fit:** The React wrapper is not ideal for Talkie, but the CM6 pieces and architecture are highly relevant.
- **Offline WKWebView:** Direct reuse would pull React assumptions. Borrowing its CM6 extension patterns is better.
- **Verdict:** **Best pattern/codebase to learn from** for a thin Talkie-built CM6 editor.

---

### 4. ProseMirror

Sources: [ProseMirror reference](https://prosemirror.net/docs/ref/), [Markdown example](https://prosemirror.net/examples/markdown/)

- **License:** MIT.
- **Maintenance/activity:** Core packages are active. Checked versions: `prosemirror-view` **1.42.0, July 1, 2026**; `prosemirror-model` **1.25.10, July 6, 2026**; `prosemirror-markdown` **1.13.5, July 6, 2026**. Bus factor is Marijn-heavy, but the ecosystem is large and mature.
- **Weight:** Moderate. `prosemirror-view` ~900 KB unpacked; `model` ~530 KB; `markdown` ~163 KB.
- **Markdown source of truth:** Medium. ProseMirror can parse/serialize Markdown and can constrain its schema to Markdown-expressible constructs, but the live source of truth is a ProseMirror document tree, not a plain Markdown string. Byte-for-byte round-trip is not guaranteed.
- **Editing model:** True rich-text/WYSIWYG document model.
- **Inline diff/review UI:** **Excellent.** Decorations, plugin state, transactions, node views, and history are very strong.
- **Bridge fit:** Technically good: transactions support selection, insert text, replacement, undo/redo. But Talkie would need mapping between native Markdown string offsets and ProseMirror document positions.
- **Offline WKWebView:** Good; plain JS modules, no framework.
- **iOS risk:** Higher than CM6 because it relies on `contenteditable`; selection/focus/keyboard behavior in iOS WKWebView must be tested carefully.
- **Verdict:** Great engine if Talkie accepts an internal rich document model. Not ideal for strict native String source-of-truth.

---

### 5. Tiptap

Sources: [Tiptap overview](https://tiptap.dev/docs/editor/getting-started/overview), [Tiptap Markdown](https://tiptap.dev/docs/editor/markdown)

- **License:** MIT for open-source core; some advanced extensions are paid/pro.
- **Maintenance/activity:** Very active. Checked NPM: `@tiptap/core`, `starter-kit`, and `markdown` all **3.27.3, July 7, 2026**. Stronger org/company bus factor than raw ProseMirror.
- **Weight:** `@tiptap/core` ~2.4 MB unpacked; `starter-kit` has many deps; `@tiptap/markdown` ~413 KB.
- **Markdown source of truth:** Medium. The Markdown extension is marked beta/early release and acts as a bridge between Markdown and Tiptap JSON/ProseMirror state. Current limitations include unsupported comments and table-cell constraints.
- **Editing model:** Headless rich-text editor built on ProseMirror.
- **Inline diff/review UI:** Strong through extensions, marks, decorations, node views. Tiptap also has paid collaboration/comment/versioning products; custom diff review is feasible but not free out of the box.
- **Bridge fit:** Very good command API: `insertContent`, `setTextSelection`, `deleteRange`, `undo`, `redo`, etc. But positions are document positions, not Markdown string offsets.
- **Offline WKWebView:** Good; can run plain JS, though many examples/components target React/Vue.
- **iOS risk:** Same ProseMirror/`contenteditable` class.
- **Verdict:** Best higher-level ProseMirror ecosystem. Use if Talkie wants extension velocity more than exact Markdown-string purity.

---

### 6. Milkdown / Crepe

Sources: [Milkdown GitHub](https://github.com/Milkdown/milkdown), [Crepe package](https://github.com/Milkdown/milkdown/tree/main/packages/crepe)

- **License:** MIT.
- **Maintenance/activity:** Active. Latest checked: **7.21.2, June 2, 2026**; repo pushed July 2026; ~11.7k stars. Bus factor appears more concentrated than Tiptap/Lexical.
- **Weight:** `@milkdown/core` ~198 KB unpacked; `@milkdown/crepe` ~3.33 MB unpacked with 17 deps. Crepe is meaningfully heavier.
- **Markdown source of truth:** Good semantically, not exact. Milkdown is Markdown-oriented and built with ProseMirror + remark, but live editing still flows through a document model and serialization.
- **Editing model:** WYSIWYG Markdown, Typora-like. Crepe gives a ready-made UI.
- **Inline diff/review UI:** Good via ProseMirror plugin/decorations under the hood, but Talkie would be integrating through Milkdown abstractions.
- **Bridge fit:** Feasible but more complex than CM6. Native string offsets will not map directly to editor positions after parsing.
- **Offline WKWebView:** Good with local JS/CSS assets, but heavier.
- **iOS risk:** `contenteditable` risk like ProseMirror.
- **Verdict:** **Best direct WYSIWYG Markdown option** if Talkie accepts canonicalized Markdown and more WKWebView testing risk.

---

### 7. Lexical

Sources: [Lexical editor state](https://lexical.dev/docs/concepts/editor-state), [`@lexical/markdown`](https://lexical.dev/docs/packages/lexical-markdown), [`@lexical/history`](https://lexical.dev/docs/packages/lexical-history)

- **License:** MIT.
- **Maintenance/activity:** Very active, Meta-backed. Checked: `lexical` and `@lexical/markdown` **0.46.0, June 26, 2026**.
- **Weight:** `lexical` ~3.17 MB unpacked; `@lexical/markdown` ~371 KB; many optional packages.
- **Markdown source of truth:** Weak for Talkie. Lexical’s source of truth is Lexical editor state JSON, not Markdown. Markdown import/export exists through transformers.
- **Editing model:** Rich-text framework with immutable editor state, commands, custom nodes.
- **Inline diff/review UI:** Excellent generally: custom nodes, decorator nodes, commands, transforms.
- **Bridge fit:** Possible, but selection is node-key/offset based. Mapping native Markdown string offsets to Lexical selections is non-trivial.
- **Undo/redo:** Good: `UNDO_COMMAND` / `REDO_COMMAND`.
- **Offline WKWebView:** Core can run without React, but most ecosystem examples/plugins are React-oriented.
- **iOS risk:** `contenteditable` plus Lexical’s own selection reconciliation. Lexical docs note updates/commands can “steal focus” unless special update tags are used.
- **Verdict:** Excellent rich editor framework, but **not a fit while Markdown String remains canonical**.

---

### 8. Toast UI Editor

Sources: [Toast UI Editor GitHub](https://github.com/nhn/tui.editor), [API docs](https://nhn.github.io/tui.editor/latest/ToastUIEditorCore/)

- **License:** MIT.
- **Maintenance/activity:** Latest release checked: **3.2.2, February 2023**; repo last pushed in 2024. Large user base but stale for a new core dependency.
- **Weight:** ~3.27 MB unpacked, 8 deps.
- **Markdown source of truth:** Medium. It has Markdown mode and WYSIWYG mode; WYSIWYG conversion can canonicalize/alter Markdown.
- **Editing model:** Markdown editor + preview + WYSIWYG mode.
- **Inline diff/review UI:** Medium. Has widget rules and custom renderers, but not as clean/powerful as CM6/ProseMirror decorations for review spans.
- **Bridge fit:** Good surface: `getMarkdown`, `setMarkdown`, `insertText`, `replaceSelection`, `getSelection`, `setSelection`.
- **Offline WKWebView:** Possible. Must disable `usageStatistics` because default docs indicate it sends hostname analytics.
- **iOS risk:** WYSIWYG mode is `contenteditable`-class risk.
- **Verdict:** Featureful, but I would **avoid** for Talkie because maintenance appears stale.

---

### 9. EasyMDE

Source: [EasyMDE GitHub](https://github.com/Ionaru/easy-markdown-editor)

- **License:** MIT.
- **Maintenance/activity:** Latest checked: **2.21.0, May 3, 2026**. Active enough, but based on CodeMirror 5.
- **Weight:** ~498 KB unpacked, 5 deps.
- **Markdown source of truth:** Excellent; it wraps a textarea/CodeMirror source editor.
- **Editing model:** Markdown source editing with preview, not rich WYSIWYG.
- **Inline diff/review UI:** Medium. CM5 overlays/addons can decorate, but CM6 is much better for modern widgets and state.
- **Bridge fit:** Good through `easyMDE.value()` and underlying CodeMirror APIs.
- **Offline WKWebView:** Excellent; simple local dist.
- **iOS risk:** Legacy editor/mobile behavior; less attractive than CM6.
- **Verdict:** Simple fallback, not the right future-facing base.

---

### 10. HyperMD

Source: [HyperMD GitHub](https://github.com/laobubu/HyperMD)

- **License:** MIT.
- **Maintenance/activity:** Latest NPM checked: **0.3.11, October 2018**; repo pushed 2021. Effectively unmaintained.
- **Weight:** ~560 KB unpacked, CM5 peer.
- **Markdown source of truth:** Excellent, source Markdown remains live text.
- **Editing model:** Live Markdown preview inside CodeMirror 5.
- **Inline diff/review UI:** Interesting historical patterns, but legacy API.
- **Offline WKWebView:** Possible, but not worth adopting.
- **Verdict:** **Learn only.** Do not reuse directly.

---

### 11. ByteMD

Source: [ByteMD GitHub](https://github.com/pd4d10/bytemd)

- **License:** MIT.
- **Maintenance/activity:** Latest v1 checked: **1.22.0, February 12, 2025**. Repo says v2/HashMD is under active development.
- **Weight:** ~3.18 MB unpacked, 19 deps.
- **Markdown source of truth:** Excellent. Value is a Markdown string.
- **Editing model:** Markdown source editor with split/tab preview; not inline rich WYSIWYG.
- **Inline diff/review UI:** Medium. It exposes editor config/plugins, but review spans would be less direct than CM6-first.
- **Offline WKWebView:** Good; Svelte compiles to vanilla JS and can be bundled.
- **Bridge fit:** Medium. Basic value sync is easy; low-level selection/replacement depends on underlying editor access.
- **Verdict:** Reasonable if Talkie only wants split preview. Less ideal for inline review affordances.

---

### 12. Vditor

Source: [Vditor GitHub](https://github.com/Vanessa219/vditor)

- **License:** MIT.
- **Maintenance/activity:** Latest checked: **3.11.2, September 2, 2025**; repo pushed July 2026; ~11k stars.
- **Weight:** Very heavy package: ~22.9 MB unpacked. It lazy-loads/assets via CDN by default; offline embedding requires self-hosting/copying its dist assets and configuring CDN/path options.
- **Markdown source of truth:** Medium. It supports WYSIWYG, instant-rendering, and split-view modes, but WYSIWYG/IR can canonicalize.
- **Editing model:** Full-featured Markdown editor with WYSIWYG, Typora-like instant rendering, and split preview.
- **Inline diff/review UI:** Medium. It is extensible but not as clean for custom diff spans/widgets as CM6/ProseMirror.
- **Bridge fit:** Likely adequate for basic set/get/insert, but Talkie-specific dictation/selection APIs need POC validation.
- **Offline WKWebView:** Possible but heavier asset-management burden.
- **iOS risk:** Claims mobile friendliness, but still needs real WKWebView tests.
- **Verdict:** Good demo/proof candidate; too large/opinionated for Talkie’s core editor.

---

### 13. MDXEditor, Gravity UI Markdown Editor, other React-heavy options

Sources: [MDXEditor](https://github.com/mdx-editor/editor), [Gravity UI Markdown Editor](https://github.com/gravity-ui/markdown-editor)

- **License:** MIT.
- **Maintenance/activity:** Active.
- **Main issue:** React-heavy and dependency-heavy. MDXEditor is Lexical-based; Gravity UI is a larger UI ecosystem component.
- **Markdown source of truth:** Better than generic rich editors, but still typically an internal rich editor model.
- **Verdict:** Useful reference material, not a simple WKWebView-local plain-JS dependency for Talkie.

---

## Native bridge implications

For Talkie, I would define a narrow JS contract independent of the editor library:

```js
window.TalkieEditor = {
  getText(),
  setText(text, options),
  getSelection(),        // { anchor, head }
  setSelection(sel),
  insertTextAtCursor(text),
  replaceRange(from, to, text),
  undo(),
  redo(),
  setReviewRanges(ranges),
  clearReviewRanges()
}
```

With **CodeMirror 6**, every method maps directly to stable editor primitives and string offsets. With ProseMirror/Tiptap/Milkdown/Lexical, the hard part is **position mapping** between Markdown string offsets and internal document positions. That mapping becomes especially risky for live dictation insertion.

For native Cmd+Z, do not rely solely on WKWebView key propagation. Expose explicit `undo()` / `redo()` JS methods and have the Swift layer call them for menu/hardware keyboard actions.

---

## iOS WKWebView risk summary

- **CM6/source-editor family:** lower risk. Still test native selection handles, long-doc scrolling, external keyboard shortcuts, dictation composition, and selection restoration.
- **ProseMirror/Tiptap/Milkdown/Lexical/Toast/Vditor:** higher risk because `contenteditable` on iOS/WKWebView has a long history of focus, keyboard, selection, and composition edge cases.
- **Dictation specifically:** favors CM6 because live insertion is a text transaction at a string offset. Rich document models may shift positions through parsing/normalization.

---

## Final recommendation

Build a **thin Talkie editor around CodeMirror 6**:

1. Keep Markdown as the authoritative string.
2. Use CM6 Markdown parsing/highlighting.
3. Add review spans using CM6 decorations.
4. Add accept/reject affordances as inline or block widgets.
5. Render Markdown preview either as:
   - a separate preview pane first, or
   - later as live inline decorations borrowing from Atomic Editor / ink-mde.
6. Expose a small JS bridge for text, selection, replacement, and undo/redo.
7. Run a separate Milkdown/Crepe POC only if true WYSIWYG becomes a product requirement.

This path best satisfies Talkie’s native String model, live dictation insertion, review UI, offline WKWebView embedding, and native-driven undo/redo.
