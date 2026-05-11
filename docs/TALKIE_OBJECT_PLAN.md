# TalkieObject Refactor Plan

## Vision

Every piece of content in Talkie is a **TalkieObject**. The `.type` (memo, dictation, note, segment, future types) determines what asset is primary and how it's presented. A single `TalkieView` renders any TalkieObject using a **SectionSlot** recipe — same sections, different emphasis, order, and chrome per type.

## End State

### Model Layer
- `Recording` renamed to `TalkieObject`
- `RecordingType` renamed to `TalkieObjectType`
- Same GRDB table (`recordings`), same columns — only Swift naming changes

### Layout System
```
TalkieObjectType → [SectionSlot] (the "recipe")

SectionSlot = SectionKind + SectionMode + SectionChrome

SectionKind:  transcript, playback, mediaGallery, attachments,
              notes, workflowRuns, refinement, dictationContext, actionBar

SectionMode:  .hero, .reader, .editor, .compact, .gallery

SectionChrome: .card, .inline, .fullBleed
```

Each type declares its recipe. `TalkieView` loops the recipe. Sections self-gate (render nothing if no data).

### View Structure
```
Views/
  TalkieObject/
    TalkieView.swift                 // ~100-150 lines: recipe loop + state
    TalkieRowView.swift              // List row (replaces inline row code)
    TalkieDetailLayout.swift         // SectionSlot, SectionKind, recipes
    SectionRouter.swift              // Maps SectionSlot → section view
    Sections/
      HeaderSection.swift
      TranscriptSection.swift
      PlaybackSection.swift
      ActionBarSection.swift
      MediaGallerySection.swift
      AttachmentsSection.swift
      NotesSection.swift
      WorkflowRunsSection.swift
      RefinementSection.swift
      DictationContextSection.swift
```

### List Layer
- `RecordingsScreen` + `NotesScreen` → `TalkieObjectsList`
- Single list view with type filter (All / Memos / Dictations / Notes)
- Uses `TalkieRowView` for all types

## Recipes Per Type

### Memo (audio-primary)
```
header          (always)
transcript      .reader    .card
actionBar       .compact   .inline
workflowRuns    .compact   .card
playback        .hero      .card
mediaGallery    .compact   .card
notes           .editor    .inline
attachments     .compact   .card
```

### Dictation (context+transcript-primary)
```
header          (always)
dictationContext .hero      .card
transcript      .reader    .card
actionBar       .compact   .inline
refinement      .compact   .inline
playback        .compact   .card
```

### Note (media/text-primary)
```
header          (always)
mediaGallery    .hero      .fullBleed
transcript      .editor    .inline
actionBar       .compact   .inline
attachments     .gallery   .card
playback        .compact   .card
notes           .editor    .inline
```

### Segment (minimal)
```
header          (always)
transcript      .reader    .card
playback        .compact   .card
```

## Phases

### Phase 1: Foundation + Section Extraction
- Create `Views/TalkieObject/` directory
- Define `SectionSlot`, `SectionKind`, `SectionMode`, `SectionChrome`
- Define recipes per `RecordingType`
- Extract sections from `RecordingDetail.swift` into individual files
- Build `SectionRouter` that maps slot → view
- Build `TalkieView` as the recipe-driven compositor
- Wire existing screens to use `TalkieView`

### Phase 2: List Unification
- Add Notes to `RecordingTypeFilter`
- Extract `TalkieRowView` from inline row code
- Fold `NotesScreen` into `RecordingsScreen` → rename to `TalkieObjectsList`
- Delete `NotesScreen.swift`

### Phase 3: Model Rename
- `Recording` → `TalkieObject`
- `RecordingType` → `TalkieObjectType`
- `RecordingRepository` → `TalkieObjectRepository`
- Mechanical find-replace, same GRDB schema

### Phase 4: Cleanup
- Delete `RecordingDetail.swift`
- Delete `MemoDetail.swift` + `MemoDetailComponents.swift`
- Remove `toMemoModel()` bridge
- Remove any remaining legacy code

### Phase 5: Model Consolidation (Future)
- Consolidate JSON blob columns into `assetsJSON`
- GRDB migration
- Do when adding a new type motivates it
