# Learn KB — content corpus

First-pass content for the embedded **Learn** knowledge base. Articles live
beside this README and are loaded by the local web KB (served inside the
Scope Learn surface) and answered against by the agent in the *Ask Talkie*
box on `ScopeLearnScreen`.

This folder owns **content only**. Swift loading code and the WebView shell
live elsewhere; Studio owns the page chrome. Authors here should never
touch those.

## Layout

```
Resources/Learn/Content/
├── README.md          ← you are here
├── schema.json        ← machine-readable contract for one article
├── index.json         ← ordered manifest of articles (KB catalog)
└── articles/
    ├── tray-shelf.md
    ├── hyper-keys.md
    ├── compose-diffs.md
    ├── workflows.md
    ├── context-rules.md
    ├── console-agents.md
    ├── llm-providers.md
    └── privacy-local-sync.md
```

Articles are Markdown with YAML front matter. The front matter is the
structured part (loaded as JSON by the KB index); the Markdown body is the
human-readable article.

## Article front-matter contract

See `schema.json` for the authoritative field list. Required fields:

| field      | type            | purpose                                         |
| ---------- | --------------- | ----------------------------------------------- |
| `id`       | kebab-case slug | stable identifier referenced from `related[]`   |
| `title`    | short string    | h1-equivalent rendered above the body           |
| `summary`  | one sentence    | rendered as the article's lead / search snippet |
| `category` | enum            | groups articles in the KB sidebar               |
| `tags`     | string[]        | free-form retrieval hints                       |
| `updated`  | YYYY-MM-DD      | last meaningful edit                            |

Optional, but recommended:

- `surfaces[]` — list of `{ label, url }` pairs. The KB renders these as
  "Open in Talkie" pills. `url` is a `talkie://` bridge link the native
  shell maps to a `NavigationSection` or `SettingsSection`. See **Bridge
  URLs** below.
- `shortcuts[]` — list of `{ chord, action }` pairs. The KB renders these
  as kbd badges in a side rail. `chord` follows the format the
  `HotkeyConfig.displayString` produces (`⌃⌥⇧⌘S`, `⌘⇧4`, etc).
- `related[]` — list of article ids. The KB renders these as "Related"
  cards at the bottom of the article.
- `agent_facts[]` — short, high-signal sentences the Ask Talkie box can
  cite verbatim. Keep one fact per line.

## Bridge URLs

The KB declares an aspirational URL contract that the native shell maps
onto existing navigation. The mapping table below is the source of truth
for both content authors and the bridge implementation:

| KB URL                          | Native target                                       | Status   |
| ------------------------------- | --------------------------------------------------- | -------- |
| `talkie://home`                 | `NavigationSection.home`                            | wired    |
| `talkie://library`              | `NavigationSection.recordings`                      | wired    |
| `talkie://library/memo?id=…`    | open a specific memo                                | wired    |
| `talkie://compose`              | `NavigationSection.drafts`                          | wired    |
| `talkie://compose?text=…`       | open Drafts with pre-filled text                    | wired    |
| `talkie://agent`                | `NavigationSection.liveDashboard` (Learn in Scope)  | wired    |
| `talkie://settings`             | open Settings                                       | wired    |
| `talkie://settings/agent`       | dictation capture settings                          | wired    |
| `talkie://open/workflows`       | `NavigationSection.workflows`                       | proposed |
| `talkie://open/context`         | `NavigationSection.contextRules`                    | proposed |
| `talkie://open/console`         | `NavigationSection.systemConsole`                   | proposed |
| `talkie://open/screenshots`     | `NavigationSection.screenshots`                     | proposed |
| `talkie://settings/surface`     | `SettingsSection.surface` (overlay/tray/shortcuts)  | proposed |
| `talkie://settings/providers`   | `SettingsSection.aiProviders`                       | proposed |
| `talkie://settings/models`      | `SettingsSection.models`                            | proposed |
| `talkie://settings/sync`        | `SettingsSection.sync`                              | proposed |
| `talkie://settings/helpers`     | `SettingsSection.helpers`                           | proposed |
| `talkie://settings/context`     | `SettingsSection.context`                           | proposed |
| `talkie://tray`                 | open Tray Shelf (`Hyper+T` equivalent)              | proposed |
| `talkie://tray/viewer`          | open Tray Viewer (`⌘⇧5` equivalent)                 | proposed |
| `talkie://workflows/run?id=…`   | trigger a workflow by id                            | proposed |

"Proposed" URLs are written into article front matter today. The native
shell (handled by Codex) is expected to extend `AppDelegate`'s URL
handler so the `open/`, `tray`, and `settings/<section>` paths route to
the existing `NavigationState` / `SettingsSection` enums. Authors should
not wait for that wiring — keep the URLs in the content; the bridge
catches up.

## Adding an article

1. Pick a kebab-case `id`. Reuse the `id` as the filename: `articles/<id>.md`.
2. Copy the front matter from the closest existing article.
3. Keep prose concise. Articles are reference material, not marketing —
   one short paragraph of context + a structured list beats six
   paragraphs of explanation. Aim for 80–200 words of body text.
4. Append the new entry to `index.json` (preserves manual ordering in
   the KB sidebar).
5. Run no build step — the KB reads these files directly out of the app
   bundle.

## Voice

Talkie-native: declarative, second-person where useful, no marketing
adjectives, no exclamation. State what the surface does and what
shortcut opens it. If a behavior is conditional, say so plainly.
