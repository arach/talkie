---
id: 00000000-0000-0000-0000-000000000024
name: Log Bug
description: No GitHub auth wired yet — webhook step ships with placeholder OWNER/REPO and no credential; running this skill will fail at the webhook step until GitHub auth is added.
icon: ant.fill
color: red
isEnabled: true
---

WHEN voice "log bug"

WITH region screenshot
      ↳ last paragraph

DO   github.issue
      ↳ title: derive from selection
      ↳ body: selection + screenshot

THEN voice ack
