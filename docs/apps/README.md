# Talkie Apps

Extend Talkie with JavaScript apps. Build custom integrations, automations, and experiences using a familiar Chrome extension-style API.

## Overview

Talkie Apps are small JavaScript programs that run alongside Talkie. They can:

- **React to events** — Get notified when memos are created, dictations complete, or sessions start
- **Access app state** — Read memo counts, streaks, and usage statistics
- **Show notifications** — Display native toast messages to celebrate milestones or provide feedback
- **Store data** — Persist settings and state between sessions
- **Render UI** — Show rich HTML panels when needed (optional)

Apps run in a lightweight JavaScript environment (JavaScriptCore) with no browser overhead. When you need to display HTML interfaces, Talkie lazily creates contained WebViews on demand.

## Quick Start

### 1. Create Your App Folder

Apps live in `~/Library/Application Support/Talkie/Apps/`. Each app is a folder:

```
~/Library/Application Support/Talkie/Apps/
└── my-app/
    ├── manifest.json
    └── background.js
```

### 2. Define Your Manifest

Every app needs a `manifest.json`:

```json
{
  "name": "My First App",
  "version": "1.0",
  "description": "A simple Talkie app",
  "background": {
    "script": "background.js"
  }
}
```

### 3. Write Your Background Script

`background.js` is your app's entry point:

```javascript
// Listen for new memos
talkie.events.onMemoCreated.addListener((data) => {
  console.log(`New memo! ${data.wordCount} words`);

  // Show a notification
  talkie.notifications.create('memo-created', {
    title: 'Memo Saved',
    message: `${data.wordCount} words captured`,
    iconUrl: 'checkmark.circle.fill'
  });
});

console.log('My app loaded!');
```

### 4. Refresh Apps in Talkie

Open Talkie → Settings → Apps → Click "Refresh"

Your app will appear in the list and start running.

---

## App Structure

### manifest.json

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Display name for your app |
| `version` | string | Yes | Version string (e.g., "1.0", "2.1.3") |
| `description` | string | No | Short description shown in Settings |
| `background.script` | string | Yes | Path to your background script |
| `icons` | object | No | Icon paths: `{ "32": "icon-32.png", "128": "icon-128.png" }` |

### File Structure

```
my-app/
├── manifest.json          # Required: App metadata
├── background.js          # Required: Main script
├── panel.html            # Optional: UI panel
├── styles.css            # Optional: Panel styles
└── icons/                # Optional: App icons
    ├── icon-32.png
    └── icon-128.png
```

---

## API Reference

### talkie.events

Subscribe to Talkie events. Follows the Chrome extension pattern.

#### onMemoCreated

Fired when a voice memo is saved.

```javascript
talkie.events.onMemoCreated.addListener((data) => {
  // data.wordCount   - Words in this memo
  // data.memoCount   - Total memos saved
  // data.totalWords  - Lifetime word count
});
```

#### onDictationCompleted

Fired when live dictation finishes.

```javascript
talkie.events.onDictationCompleted.addListener((data) => {
  // data.wordCount       - Words dictated
  // data.dictationCount  - Total dictations
});
```

#### onPolishCompleted

Fired when AI polish/rewrite completes.

```javascript
talkie.events.onPolishCompleted.addListener((data) => {
  // data.instruction  - The polish instruction used
  // data.polishCount  - Total polishes performed
});
```

#### onSessionStarted

Fired when Talkie launches (once per day).

```javascript
talkie.events.onSessionStarted.addListener((data) => {
  // data.sessionNumber - Total sessions/days used
});
```

#### Event Methods

All events support:

```javascript
// Add listener
talkie.events.onMemoCreated.addListener(callback);

// Remove listener
talkie.events.onMemoCreated.removeListener(callback);

// Check if listening
talkie.events.onMemoCreated.hasListener(callback); // → boolean
```

---

### talkie.storage

Persist data between sessions. Scoped to your app.

#### storage.local.get

```javascript
// Get single key
talkie.storage.local.get('settings', (result) => {
  console.log(result.settings); // → { theme: 'dark' }
});

// Get multiple keys
talkie.storage.local.get(['settings', 'lastRun'], (result) => {
  console.log(result.settings);
  console.log(result.lastRun);
});
```

#### storage.local.set

```javascript
// Set values
talkie.storage.local.set({
  settings: { theme: 'dark' },
  lastRun: Date.now()
}, () => {
  console.log('Saved!');
});
```

---

### talkie.state

Read current Talkie state (read-only).

#### state.get

```javascript
talkie.state.get(['memoCount', 'currentStreak'], (state) => {
  console.log(`${state.memoCount} memos, ${state.currentStreak} day streak`);
});
```

**Available state keys:**

| Key | Type | Description |
|-----|------|-------------|
| `memoCount` | number | Total memos saved |
| `dictationCount` | number | Total dictations completed |
| `totalWords` | number | Lifetime words captured |
| `currentStreak` | number | Current daily streak |
| `sessionCount` | number | Total app sessions |
| `polishCount` | number | Total AI polishes |
| `workflowCount` | number | Total workflows run |

---

### talkie.notifications

Show native toast notifications.

#### notifications.create

```javascript
talkie.notifications.create('notification-id', {
  title: 'Achievement Unlocked!',
  message: 'You saved 100 memos',
  iconUrl: 'star.fill'  // SF Symbol name
}, () => {
  console.log('Notification shown');
});
```

**Options:**

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Bold heading |
| `message` | string | Body text |
| `iconUrl` | string | SF Symbol name (e.g., `star.fill`, `checkmark.circle`) |

---

### talkie.ui

Show rich HTML interfaces (creates WebView on demand).

#### ui.showPanel

```javascript
talkie.ui.showPanel({
  html: 'settings.html',  // File in your app folder
  width: 400,
  height: 300
}, () => {
  console.log('Panel opened');
});
```

Your HTML file has full access to CSS and JavaScript. Keep panels lightweight.

---

## Examples

### Milestone Tracker

Celebrate user achievements:

```javascript
// background.js
const MILESTONES = [
  { count: 1, title: 'First Memo!', message: 'Your voice journey begins' },
  { count: 10, title: 'Getting Started', message: '10 memos captured' },
  { count: 50, title: 'On a Roll', message: '50 memos and counting' },
  { count: 100, title: 'Centurion', message: '100 memos saved!' },
];

talkie.events.onMemoCreated.addListener((data) => {
  const milestone = MILESTONES.find(m => m.count === data.memoCount);

  if (milestone) {
    talkie.notifications.create(`milestone-${milestone.count}`, {
      title: milestone.title,
      message: milestone.message,
      iconUrl: 'trophy.fill'
    });
  }
});
```

### Daily Streak Reminder

Welcome users back:

```javascript
// background.js
talkie.events.onSessionStarted.addListener((data) => {
  talkie.state.get('currentStreak', (state) => {
    if (state.currentStreak > 1) {
      talkie.notifications.create('streak', {
        title: `${state.currentStreak} Day Streak!`,
        message: 'Keep the momentum going',
        iconUrl: 'flame.fill'
      });
    }
  });
});
```

### Word Count Logger

Track daily productivity:

```javascript
// background.js
talkie.events.onMemoCreated.addListener((data) => {
  const today = new Date().toDateString();

  talkie.storage.local.get('dailyWords', (result) => {
    const dailyWords = result.dailyWords || {};
    dailyWords[today] = (dailyWords[today] || 0) + data.wordCount;

    talkie.storage.local.set({ dailyWords });

    console.log(`Today: ${dailyWords[today]} words`);
  });
});
```

---

## Chrome Extension Alignment

Talkie Apps intentionally mirror Chrome extension patterns:

| Chrome Extension | Talkie Apps |
|-----------------|-------------|
| `manifest.json` | `manifest.json` |
| `chrome.runtime` | `talkie.events` |
| `chrome.storage.local` | `talkie.storage.local` |
| `chrome.notifications` | `talkie.notifications` |

**Why?** Familiarity. If you've built Chrome extensions, you already know how to build Talkie apps. The callback-based API style, event subscription pattern, and manifest structure all follow conventions you likely know.

**Differences:**

- No content scripts (Talkie isn't a browser)
- No tabs/windows API (single app context)
- SF Symbols for icons instead of image URLs
- `talkie.state` for app-specific read-only state
- `talkie.ui.showPanel()` instead of browser popups

---

## Debugging

### Console Output

Your `console.log()` calls appear in Talkie's debug output:

```javascript
console.log('Hello from my app!');
// → [App:my-app] Hello from my app!
```

### Error Handling

JavaScript exceptions are logged automatically:

```
JS Exception in app my-app: TypeError: undefined is not a function
```

### Reload During Development

Settings → Apps → Right-click your app → "Reload"

Or click "Reload All" to refresh everything.

---

## Best Practices

1. **Keep background scripts light** — They run continuously. Avoid heavy computation.

2. **Use storage for persistence** — Don't rely on in-memory state across reloads.

3. **Debounce frequent events** — `onMemoCreated` can fire rapidly during active use.

4. **Provide clear notifications** — Users see your toasts. Make them meaningful.

5. **Test with Reload** — Use the reload button during development, not app restart.

---

## Publishing

Coming soon: Talkie App Directory for sharing your creations.

For now, share your app folder directly. Users drop it into their Apps directory.

---

## Resources

- [SF Symbols Reference](https://developer.apple.com/sf-symbols/) — Icons for notifications
- [Chrome Extensions Docs](https://developer.chrome.com/docs/extensions/) — Similar patterns

---

*Built with love for the Talkie community.*
