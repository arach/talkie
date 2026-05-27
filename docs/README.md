# Talkie Docs

This directory contains a mix of public-facing references, active engineering notes, audits, specs, and historical planning documents. Treat docs as useful context, not always as guaranteed current product behavior.

## Start Here

- [`../README.md`](../README.md): project overview, fresh-clone setup, and repo map
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md): build, test, and contribution workflow
- [`../SECURITY.md`](../SECURITY.md): local auth, HMAC, Tailscale/LAN, and secret policy
- [`../LICENSE`](../LICENSE): source-available PolyForm Noncommercial license
- [`engineering/ARCHITECTURE.md`](engineering/ARCHITECTURE.md): broad architecture notes
- [`specs/tlk-006-gateway-protocol.md`](specs/tlk-006-gateway-protocol.md): gateway protocol wire format
- [`specs/gateway-reference.md`](specs/gateway-reference.md): TalkieServer gateway reference

## Categories

| Area | Path | Notes |
|------|------|-------|
| Engineering | `engineering/` | Architecture, performance, onboarding, testing, and proposals |
| Numbered specs | `specs/tlk-*.md` | TLK-NNN eng-doc series. Each is a discrete decision/proposal with Status, Summary, and Open Questions. TLK-001 through TLK-021 currently. Studio can review them at `/eng/tlk-NNN` when the doc declares a `**Studio**` route. |
| Reference specs | `specs/*.md` (non-numbered) | Protocol references, inventories, and supporting specs that don't carry a TLK decision. |
| Product | `product/` | Positioning and product direction |
| Legal | `legal/` | App EULA and non-source-license legal references |
| Review | `review/` | Codebase review notes and subsystem audits |
| Plans | `plans/`, `gemini-plans/`, root-level plan files | Exploratory or historical planning; verify against code before implementing |
| Apps | `apps/` | App-specific documentation |

## Public Readiness

The most public-ready docs are the root README, CONTRIBUTING, SECURITY, gateway specs, and current architecture notes. Many older docs were written during private development and may mention stale features, private workflows, or release-specific assumptions.

Before using a doc as implementation guidance:

1. Check the current code and project settings.
2. Prefer docs that describe shipped protocols or current architecture.
3. Update stale docs when you find a mismatch.
4. Keep private credentials, signing details, App Store metadata, and owner-specific release steps out of public docs.
