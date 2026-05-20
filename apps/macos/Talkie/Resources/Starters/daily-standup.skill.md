---
id: 00000000-0000-0000-0000-000000000011
name: Daily Standup
description: Three bullets, Claude tightens the language, then posts to Slack. Phase 1 requires UserDefaults key SkillsSlackWebhookURL; the skill stops before posting if that key is missing.
icon: person.3.fill
color: blue
isEnabled: true
---

WHEN voice "standup"

WITH dictation

DO slack.post
      ↳ channel: #standup
      ↳ polish: claude.tighten

THEN voice ack
