# Talkie Draft Renderers

Custom renderers that connect to Talkie's Draft Extension API for specialized editing workflows.

## Quick Start

1. Open Talkie and navigate to **Drafts**
2. Open `tweet-composer.html` in a browser
3. Start dictating in Talkie - your tweet preview updates in real-time
4. Use the action buttons to refine with AI

## Files

- **draft-link.js** - Client SDK for connecting to Talkie
- **tweet-composer.html** - Example: Tweet composer with character count and thread support

## API

### Connection

```javascript
const talkie = new TalkieLink({
  name: 'My Renderer',
  capabilities: ['preview', 'diff']
})
```

### Events

```javascript
talkie.on('state', draft => {
  // draft.content, draft.mode, draft.wordCount, draft.charCount
})

talkie.on('revision', rev => {
  // rev.before, rev.after, rev.diff, rev.instruction
})

talkie.on('resolved', result => {
  // result.accepted, result.content
})
```

### Commands

```javascript
talkie.update('new content')                    // Push content to Talkie
talkie.refine('make it shorter', { maxLength: 280 })  // Request LLM revision
talkie.accept()                                 // Accept revision
talkie.reject()                                 // Reject revision
talkie.copyToClipboard()                        // Copy to clipboard
```

## Building Your Own Renderer

1. Include `draft-link.js` in your HTML
2. Create a `TalkieLink` instance
3. Listen for `state` and `revision` events
4. Send commands back to Talkie

See `tweet-composer.html` for a complete example.
