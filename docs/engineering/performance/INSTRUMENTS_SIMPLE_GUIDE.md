# Instruments - Simple Guide (Ignore 95% of the UI)

Instruments is overwhelming. Here's what to actually look at.

## Quick Start (2 minutes)

### Step 1: Open Instruments
```
Product → Profile (Cmd+I)
```

### Step 2: Setup (ONE TIME ONLY)
1. Select **"Blank"** template
2. Click **"+"** button (top left)
3. Search for: **"Points of Interest"**
4. Double-click to add it
5. Click **Record** button (red circle)

### Step 3: Use Your App
Click around, load data, do whatever feels slow

### Step 4: Stop Recording
Click **Stop** button (red square)

---

## What to Look At (Ignore Everything Else)

### The ONLY View That Matters: Timeline

You'll see this:

```
┌─────────────────────────────────────────────────────────────┐
│ Points of Interest                                          │
├─────────────────────────────────────────────────────────────┤
│ ViewLifecycle              |----------| 145ms               │
│   DatabaseRead                |--| 8ms                      │
│   DatabaseRead                  |-| 2ms                     │
│ Click                      •                                │
│ DatabaseRead                  |--| 6ms                      │
└─────────────────────────────────────────────────────────────┘
```

**What this means:**
- **Horizontal bars** = How long something took
- **Dots** = Instant events (clicks)
- **Nested/indented** = Happened during the parent event

---

## How to Find Slow Things

### 1. Look for LONG Bars

**Short bar (good):**
```
DatabaseRead  |--| 8ms
```

**Long bar (investigate!):**
```
DatabaseRead  |--------------------| 250ms  ← WHY IS THIS SO LONG?
```

### 2. Click on the bar

When you click a long bar, bottom panel shows:
```
Name: DatabaseRead
Duration: 250ms
Message: GRDBRepository.fetchMemos  ← THIS IS THE SLOW OPERATION
```

Now you know: **"fetchMemos is taking 250ms"**

---

## Filtering Out Noise

You'll see A LOT of system events you don't care about. Filter them:

### Bottom of window, find the search box:
```
[🔍 Filter: _________________]
```

### Type: `talkie`

Now you ONLY see your app's events. Much cleaner!

---

## Most Useful Trick: Find the Slowest Operations

1. Click **"Points of Interest"** track in the left sidebar
2. Look at the **Summary** view (bottom panel)
3. Click **"Duration"** column header to sort

You'll see:
```
Name                           Count    Duration
────────────────────────────────────────────────
DatabaseRead (fetchMemos)      10       2,450ms  ← SLOWEST!
DatabaseRead (countMemos)      10       200ms
ViewLifecycle (AllMemos)       5        725ms
Click                          25       0ms
```

**Translation:**
- `fetchMemos` was called 10 times, took 2.45 seconds total
- That's 245ms per call on average
- **This is your bottleneck!**

---

## When to Use Instruments vs In-App View

### Use In-App Performance Monitor When:
- ✅ Quick check during development
- ✅ Showing performance to someone else
- ✅ User reports slowness → screenshot it
- ✅ Real-time monitoring while using app

### Use Instruments When:
- ✅ Something feels slow but you don't know why
- ✅ You want to see timeline/duration of everything
- ✅ You want to compare "before/after" optimization
- ✅ Deep performance investigation

---

## 3 Minute Workflow

**Fastest way to find slow things:**

1. **Cmd+I** (open Instruments)
2. **Blank** template → Add **"Points of Interest"**
3. **Record** → Use app → **Stop**
4. **Type `talkie` in filter box** (bottom)
5. **Click "Duration" column** to sort
6. **Look at top 3 slowest operations**

Done! Now you know what's slow.

---

## Visual Guide

### What You're Looking For:

```
GOOD (Everything fast):
─────────────────────────────────────
ViewLifecycle    |-----| 50ms
  DatabaseRead      |-| 5ms
  DatabaseRead       |-| 3ms
Click            •
─────────────────────────────────────
All bars are short = app is snappy ✅


BAD (Something slow):
─────────────────────────────────────
ViewLifecycle    |---------------------------| 500ms  ← SLOW!
  DatabaseRead      |------------------------| 450ms  ← PROBLEM!
  DatabaseRead         |-| 3ms
Click            •
─────────────────────────────────────
Long bar = investigate this! ❌
```

---

## Ignore These (They're Confusing)

- ❌ CPU track
- ❌ Memory track
- ❌ Threads track
- ❌ All the tabs at the top
- ❌ Everything in the left sidebar except "Points of Interest"

**Just look at Points of Interest timeline. That's it.**

---

## Quick Reference Card

| Want to... | Do this... |
|-----------|-----------|
| See what's slow | Sort by Duration column |
| See your events only | Filter: `talkie` |
| See how long X took | Click the bar, read bottom panel |
| Find database issues | Look for long `DatabaseRead` bars |
| Find UI issues | Look for long `ViewLifecycle` bars |

---

## TL;DR

1. **Cmd+I** → Blank → Add Points of Interest
2. **Record** → Use app → **Stop**
3. **Filter: `talkie`**
4. **Sort by Duration**
5. **Fix the longest bars**

That's all you need to know! Ignore the rest of Instruments.
