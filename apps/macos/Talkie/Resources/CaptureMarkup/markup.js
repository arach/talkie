(function () {
  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.talkie;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  const state = {
    sessionId: null,
    imageURL: null,
    document: { version: 1, imageWidth: 1, imageHeight: 1, layers: [] },
    selectedLayerId: null,
    /** Layer ids explicitly tagged into the next agent message. */
    messageLayerIds: new Set(),
    activeTool: null,
    image: null,
    /** Existing-layer move drag (the original behaviour) — frame-based layers */
    drag: null,
    /** Frame resize drag — a selected rect/label/highlight/patch handle. */
    frameResize: null,
    /** Segment (arrow / line) edit drag — move an endpoint or the whole thing.
     *  `handle` is "from" | "to" (reshape one end) or "both" (move the segment). */
    segDrag: null,
    /** New-layer creation drag started with rect / arrow / line / blur */
    creating: null,
    /** Space+drag pan state. */
    panDrag: null,
    isSpaceDown: false,
    /** Logical markup workspace. Layer frames are normalized against this
     *  viewport (not the raw source image). The optional copy persisted in
     *  the sidecar keeps version-2 documents stable across panel sizes while
     *  preserving the existing normalized `frame` schema. */
    viewport: { width: 1, height: 1, imageX: 0, imageY: 0, imageScale: 1, zoom: 1, panX: 0, panY: 0 },
    /** Snapshot stacks for universal undo/redo. Pre-mutation snapshots of
     *  `document` (deep copy). Each side is capped at HISTORY_LIMIT. */
    history: { past: [], future: [] },
    /** Per-tool defaults. Picked via the style stack on the toolbar.
     *  Applied at layer creation; selected-layer live-edit is a follow-up. */
    style: {
      color: "#4F7DFF",
      textColor: "#FFFFFF",
      backgroundColor: "#14181E",
      backgroundAlpha: 0.86,
      borderColor: "#FFFFFF",
      borderAlpha: 0.22,
      strokeWidth: 2,
      arrowHeads: "end", // none | start | end | both
      pointerStyle: "open", // open | filled | dot | bar
      fontSize: 16,
      fontFamily: "mono", // sans | serif | mono — mono preserves the legacy tag look
      bold: false,
      italic: false,
      plain: false, // false = white-on-dark pill (default); true = plain colored text
      textPreset: "on-light",
    },
  };

  const HISTORY_LIMIT = 50;

  const canvas = document.getElementById("canvas");
  const ctx = canvas.getContext("2d");
  const canvasWrap = document.querySelector(".canvas-wrap");
  const layerList = document.getElementById("layer-list");
  const layerCount = document.getElementById("layer-count");
  const popover = document.getElementById("popover");
  const toolToolbar = document.getElementById("tool-toolbar");
  const styleStack = document.getElementById("style-stack");
  const zoomCluster = document.getElementById("canvas-zoom-cluster");
  const zoomDisplay = document.getElementById("zoom-display");
  const undoButton = toolToolbar.querySelector('[data-action="undo"]');
  const redoButton = toolToolbar.querySelector('[data-action="redo"]');

  const DEFAULT_COLOR = "#4F7DFF";
  const DEFAULT_POINTER_STYLE = "open";
  const DEFAULT_ARROW_HEADS = "end";
  const DEFAULT_TEXT_PRESET = "on-light";
  const POINTER_STYLES = new Set(["none", "open", "filled", "dot", "bar"]);
  const ARROW_HEADS = new Set(["none", "start", "end", "both"]);
  const TEXT_PRESETS = {
    // Names describe the capture/background the label is placed on.
    "on-light": {
      plain: false,
      textColor: "#FFFFFF",
      backgroundColor: "#14181E",
      backgroundAlpha: 0.86,
      borderColor: "#FFFFFF",
      borderAlpha: 0.22,
    },
    "on-dark": {
      plain: false,
      textColor: "#232423",
      backgroundColor: "#F4E8D4",
      backgroundAlpha: 0.94,
      borderColor: "#4F7DFF",
      borderAlpha: 0.34,
    },
    accent: {
      plain: false,
      textColor: "#101A33",
      backgroundColor: "#AFC5FF",
      backgroundAlpha: 0.96,
      borderColor: "#2D5BDB",
      borderAlpha: 0.34,
    },
    plain: {
      plain: true,
      textColor: "#4F7DFF",
      backgroundColor: "#FFFFFF",
      backgroundAlpha: 0,
      borderColor: "#4F7DFF",
      borderAlpha: 0,
    },
  };
  // Tools that create a new layer by click-dragging on the canvas
  const DRAG_TOOLS = new Set(["rect", "arrow", "line", "blur", "clone"]);
  // Tools that fire on a single click instead of a drag
  const CLICK_TOOLS = new Set(["text"]);
  // Minimum pixel distance before a mousedown→mousemove counts as a drag
  // (anything smaller is treated as a stray click and discarded for drag tools).
  const MIN_DRAG_PX = 3;

  // ---------------------------------------------------------------------------
  // Bridge
  // ---------------------------------------------------------------------------
  function post(type, payload) {
    if (!bridge) return;
    bridge.postMessage(Object.assign({ type: type }, payload || {}));
  }

  function selectionPayload() {
    const layer = state.document.layers.find((l) => l.id === state.selectedLayerId);
    return layer
      ? { id: layer.id, label: layer.label || layer.text || layer.kind, kind: layer.kind }
      : null;
  }

  function layerSelectionPayload(layer) {
    return {
      id: layer.id,
      kind: layer.kind,
      label: layer.label || layer.text || layer.kind,
    };
  }

  function messageLayerSelections() {
    return state.document.layers
      .filter((layer) => state.messageLayerIds.has(layer.id))
      .map(layerSelectionPayload);
  }

  function postMessageLayers() {
    post("markup.attachments", {
      sessionId: state.sessionId,
      selections: messageLayerSelections(),
    });
  }

  function toggleMessageLayer(layer) {
    if (!layer) return;
    if (state.messageLayerIds.has(layer.id)) {
      state.messageLayerIds.delete(layer.id);
    } else {
      state.messageLayerIds.add(layer.id);
    }
    postMessageLayers();
    render();
  }

  function removeTaggedMessageLayer(id) {
    if (!id || !state.messageLayerIds.has(id)) return;
    state.messageLayerIds.delete(id);
    postMessageLayers();
    render();
  }

  function clearTaggedMessageLayers() {
    if (!state.messageLayerIds.size) return;
    state.messageLayerIds.clear();
    postMessageLayers();
    render();
  }

  function debouncedUpdate() {
    post("markup.update", {
      sessionId: state.sessionId,
      document: attachViewportToDocument(state.document),
      layerCount: state.document.layers.length,
      selection: selectionPayload(),
    });
  }

  // Explicit Save (⌘S / SAVE button). Hands the full document to Swift,
  // which persists it to the sidecar now and confirms on the button. The
  // payload mirrors markup.update so the Swift side has one decode path.
  function requestSave() {
    post("markup.save", {
      sessionId: state.sessionId,
      document: attachViewportToDocument(state.document),
      layerCount: state.document.layers.length,
      selection: selectionPayload(),
    });
  }

  // ---------------------------------------------------------------------------
  // Undo / redo — snapshot-based universal history.
  // Call snapshotForUndo() before any mutation; it pushes current state to
  // `past` and clears `future`. Undo/redo move the current state between sides.
  // ---------------------------------------------------------------------------
  function cloneDocument(doc) {
    return JSON.parse(JSON.stringify(doc));
  }

  function attachViewportToDocument(doc) {
    // Sidecar schema v2 keeps normalized layer geometry unchanged; it only
    // records the viewport that those normalized coordinates use as their
    // basis. Swift decodes this as an optional field, so older sidecars remain
    // valid and older image-normalized docs are migrated on load.
    doc.version = Math.max(2, doc.version || 1);
    doc.viewport = {
      width: state.viewport.width,
      height: state.viewport.height,
      imageX: state.viewport.imageX,
      imageY: state.viewport.imageY,
      imageScale: state.viewport.imageScale,
    };
    doc.imageWidth = state.image ? state.image.width : doc.imageWidth;
    doc.imageHeight = state.image ? state.image.height : doc.imageHeight;
    return doc;
  }

  function currentDocumentSnapshot() {
    return cloneDocument(attachViewportToDocument(cloneDocument(state.document)));
  }

  function updateHistoryButtons() {
    if (undoButton) undoButton.disabled = state.history.past.length === 0;
    if (redoButton) redoButton.disabled = state.history.future.length === 0;
  }

  function snapshotForUndo() {
    state.history.past.push(currentDocumentSnapshot());
    if (state.history.past.length > HISTORY_LIMIT) state.history.past.shift();
    state.history.future = [];
    updateHistoryButtons();
  }

  function undo() {
    const prev = state.history.past.pop();
    if (!prev) return false;
    state.history.future.push(currentDocumentSnapshot());
    if (state.history.future.length > HISTORY_LIMIT) state.history.future.shift();
    state.document = prev;
    applyDocumentViewport(prev);
    state.selectedLayerId = null;
    debouncedUpdate();
    render();
    updateHistoryButtons();
    return true;
  }

  function redo() {
    const next = state.history.future.pop();
    if (!next) return false;
    state.history.past.push(currentDocumentSnapshot());
    if (state.history.past.length > HISTORY_LIMIT) state.history.past.shift();
    state.document = next;
    applyDocumentViewport(next);
    state.selectedLayerId = null;
    debouncedUpdate();
    render();
    updateHistoryButtons();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Geometry helpers
  // ---------------------------------------------------------------------------
  function hexColor(hex, alpha) {
    const c = (hex || DEFAULT_COLOR).replace("#", "");
    const r = parseInt(c.slice(0, 2), 16);
    const g = parseInt(c.slice(2, 4), 16);
    const b = parseInt(c.slice(4, 6), 16);
    return `rgba(${r},${g},${b},${alpha == null ? 1 : alpha})`;
  }

  function normalizePointerStyle(value) {
    return POINTER_STYLES.has(value) ? value : DEFAULT_POINTER_STYLE;
  }

  function normalizeArrowHeads(value) {
    return ARROW_HEADS.has(value) ? value : DEFAULT_ARROW_HEADS;
  }

  function normalizeTextPreset(value) {
    return TEXT_PRESETS[value] ? value : DEFAULT_TEXT_PRESET;
  }

  function pointerPairForHeads(heads, pointerStyle) {
    const h = normalizeArrowHeads(heads);
    const p = normalizePointerStyle(pointerStyle);
    return {
      start: h === "start" || h === "both" ? p : "none",
      end: h === "end" || h === "both" ? p : "none",
    };
  }

  function hasExplicitPointers(layer) {
    return layer && (layer.pointerStart != null || layer.pointerEnd != null);
  }

  function pointerForLayer(layer, endpoint) {
    if (!layer) return "none";
    const raw = endpoint === "start" ? layer.pointerStart : layer.pointerEnd;
    if (raw != null) return normalizePointerStyle(raw);
    if (hasExplicitPointers(layer)) return "none";
    if (layer.label === "line") return "none";
    return endpoint === "end" ? normalizePointerStyle(layer.pointerStyle) : "none";
  }

  function arrowHeadsForLayer(layer) {
    const start = pointerForLayer(layer, "start");
    const end = pointerForLayer(layer, "end");
    if (start !== "none" && end !== "none") return "both";
    if (start !== "none") return "start";
    if (end !== "none") return "end";
    return "none";
  }

  function calloutLabelForLayer(layer) {
    if (!layer || layer.label === "line" || layer.label === "BLUR") return "";
    return layer.label || "";
  }

  function pointerStyleForLayer(layer) {
    const start = pointerForLayer(layer, "start");
    if (start !== "none") return start;
    const end = pointerForLayer(layer, "end");
    if (end !== "none") return end;
    return normalizePointerStyle(layer && layer.pointerStyle);
  }

  function applyArrowStyleToLayer(layer, heads, pointerStyle) {
    const pair = pointerPairForHeads(heads, pointerStyle);
    layer.pointerStart = pair.start;
    layer.pointerEnd = pair.end;
    layer.pointerStyle = normalizePointerStyle(pointerStyle);
    if (pair.start === "none" && pair.end === "none") {
      layer.label = "line";
    } else if (layer.label === "line") {
      delete layer.label;
    }
  }

  function textPresetForLayer(layer) {
    if (layer && layer.textPreset && TEXT_PRESETS[layer.textPreset]) return layer.textPreset;
    if (layer && layer.plain) return "plain";
    return DEFAULT_TEXT_PRESET;
  }

  function labelStyle(layer) {
    const presetName = textPresetForLayer(layer);
    const preset = TEXT_PRESETS[presetName];
    const plain = !!(layer && layer.plain) || preset.plain;
    return {
      preset: presetName,
      plain,
      textColor: (layer && layer.textColor) || (plain && layer && layer.color) || preset.textColor,
      backgroundColor: (layer && layer.backgroundColor) || preset.backgroundColor,
      backgroundAlpha: layer && typeof layer.backgroundAlpha === "number" ? layer.backgroundAlpha : preset.backgroundAlpha,
      borderColor: (layer && layer.borderColor) || preset.borderColor,
      borderAlpha: layer && typeof layer.borderAlpha === "number" ? layer.borderAlpha : preset.borderAlpha,
    };
  }

  function applyTextPresetToStyle(presetName) {
    const name = normalizeTextPreset(presetName);
    const preset = TEXT_PRESETS[name];
    state.style.textPreset = name;
    state.style.plain = preset.plain;
    state.style.textColor = preset.textColor;
    state.style.backgroundColor = preset.backgroundColor;
    state.style.backgroundAlpha = preset.backgroundAlpha;
    state.style.borderColor = preset.borderColor;
    state.style.borderAlpha = preset.borderAlpha;
  }

  function applyTextPresetToLayer(layer, presetName) {
    const name = normalizeTextPreset(presetName);
    const preset = TEXT_PRESETS[name];
    layer.textPreset = name;
    layer.plain = preset.plain;
    layer.textColor = preset.textColor;
    layer.backgroundColor = preset.backgroundColor;
    layer.backgroundAlpha = preset.backgroundAlpha;
    layer.borderColor = preset.borderColor;
    layer.borderAlpha = preset.borderAlpha;
    layer.color = preset.textColor;
  }

  function roundRectPath(context, x, y, w, h, r) {
    const radius = Math.max(0, Math.min(r, w / 2, h / 2));
    if (typeof context.roundRect === "function") {
      context.roundRect(x, y, w, h, radius);
      return;
    }
    context.moveTo(x + radius, y);
    context.lineTo(x + w - radius, y);
    context.quadraticCurveTo(x + w, y, x + w, y + radius);
    context.lineTo(x + w, y + h - radius);
    context.quadraticCurveTo(x + w, y + h, x + w - radius, y + h);
    context.lineTo(x + radius, y + h);
    context.quadraticCurveTo(x, y + h, x, y + h - radius);
    context.lineTo(x, y + radius);
    context.quadraticCurveTo(x, y, x + radius, y);
  }

  function framePx(layer, w, h) {
    const f = layer.frame;
    if (!f) return null;
    return { x: f.x * w, y: f.y * h, w: f.width * w, h: f.height * h };
  }

  // Label typography. `fontFamily` maps to a CSS stack; mono is the default so
  // legacy labels (no family) keep their tag look. Mirrors the Swift renderer.
  function fontFamilyCSS(family) {
    if (family === "sans") return "-apple-system, system-ui, sans-serif";
    if (family === "serif") return "ui-serif, Georgia, 'Times New Roman', serif";
    return "ui-monospace, SFMono-Regular, monospace";
  }
  function labelFontString(layer, px) {
    const ital = layer.italic ? "italic " : "";
    const weight = layer.bold ? "700 " : "";
    return `${ital}${weight}${px}px ${fontFamilyCSS(layer.fontFamily)}`;
  }

  function viewportSize() {
    return {
      w: Math.max(1, state.viewport.width || 1),
      h: Math.max(1, state.viewport.height || 1),
    };
  }

  function canvasPoint(e) {
    const rect = canvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  }

  function screenToViewport(x, y) {
    const v = state.viewport;
    return {
      x: (x - v.panX) / v.zoom,
      y: (y - v.panY) / v.zoom,
    };
  }

  /** Convert a mouse event to normalized viewport coordinates. No clamp:
   *  users may drag into the surrounding workspace, and pan/zoom can expose
   *  off-viewport space while the drag is in progress. */
  function eventToNorm(e) {
    const pt = canvasPoint(e);
    const vp = screenToViewport(pt.x, pt.y);
    const size = viewportSize();
    return {
      nx: vp.x / size.w,
      ny: vp.y / size.h,
      px: vp.x,
      py: vp.y,
    };
  }

  /** Build a normalized rect from two corner points (any drag direction). */
  function normalizedFrame(a, b) {
    const x = Math.min(a.nx, b.nx);
    const y = Math.min(a.ny, b.ny);
    const width = Math.abs(b.nx - a.nx);
    const height = Math.abs(b.ny - a.ny);
    return { x, y, width, height };
  }

  const FRAME_HANDLE_GRAB = 9;
  const FRAME_MIN_SIZE_PX = 14;

  function frameHandlePoints(layer) {
    if (!layer || !layer.frame) return [];
    const f = layer.frame;
    const size = viewportSize();
    const left = f.x * size.w;
    const top = f.y * size.h;
    const right = (f.x + f.width) * size.w;
    const bottom = (f.y + f.height) * size.h;
    const midX = (left + right) / 2;
    const midY = (top + bottom) / 2;
    return [
      { name: "nw", x: left, y: top },
      { name: "n", x: midX, y: top },
      { name: "ne", x: right, y: top },
      { name: "e", x: right, y: midY },
      { name: "se", x: right, y: bottom },
      { name: "s", x: midX, y: bottom },
      { name: "sw", x: left, y: bottom },
      { name: "w", x: left, y: midY },
    ];
  }

  function frameHandleAt(norm, layer) {
    const grab = FRAME_HANDLE_GRAB / Math.max(0.25, state.viewport.zoom || 1);
    for (const handle of frameHandlePoints(layer)) {
      if (Math.abs(norm.px - handle.x) <= grab && Math.abs(norm.py - handle.y) <= grab) {
        return handle.name;
      }
    }
    return null;
  }

  function frameBodyHit(norm, layer) {
    if (!layer || !layer.frame) return false;
    const f = layer.frame;
    return norm.nx >= f.x && norm.nx <= f.x + f.width && norm.ny >= f.y && norm.ny <= f.y + f.height;
  }

  function cursorForFrameHandle(handle) {
    if (handle === "n" || handle === "s") return "ns-resize";
    if (handle === "e" || handle === "w") return "ew-resize";
    if (handle === "nw" || handle === "se") return "nwse-resize";
    if (handle === "ne" || handle === "sw") return "nesw-resize";
    return "default";
  }

  function resizeFrameFromHandle(orig, handle, dx, dy, size) {
    const minW = FRAME_MIN_SIZE_PX / Math.max(1, size.w);
    const minH = FRAME_MIN_SIZE_PX / Math.max(1, size.h);
    let left = orig.x;
    let top = orig.y;
    let right = orig.x + orig.width;
    let bottom = orig.y + orig.height;

    if (handle.includes("w")) left = Math.min(orig.x + dx, right - minW);
    if (handle.includes("e")) right = Math.max(orig.x + orig.width + dx, left + minW);
    if (handle.includes("n")) top = Math.min(orig.y + dy, bottom - minH);
    if (handle.includes("s")) bottom = Math.max(orig.y + orig.height + dy, top + minH);

    return {
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    };
  }

  /**
   * Snap `current` so the segment from `start` is axis-aligned (0° or 90°).
   * Picks whichever axis the cursor is farther along — drag mostly horizontal
   * → lock Y to start; drag mostly vertical → lock X to start. The "more than
   * 45° from horizontal" cutoff is implicit in the |dx| vs |dy| compare.
   */
  function snapToAxis(start, current) {
    const dx = current.nx - start.nx;
    const dy = current.ny - start.ny;
    if (Math.abs(dx) >= Math.abs(dy)) {
      return { nx: current.nx, ny: start.ny, px: current.px, py: start.py };
    }
    return { nx: start.nx, ny: current.ny, px: start.px, py: current.py };
  }

  /** Hit-test layers in reverse order (top-most first). Returns layer or null. */
  function hitTest(norm) {
    const layers = state.document.layers;
    for (let i = layers.length - 1; i >= 0; i--) {
      const layer = layers[i];
      if (!layer.visible) continue;
      if (layer.frame) {
        const f = layer.frame;
        if (norm.nx >= f.x && norm.nx <= f.x + f.width && norm.ny >= f.y && norm.ny <= f.y + f.height) {
          return layer;
        }
      } else if (layer.from && layer.to) {
        // Distance from point to segment, in normalized space.
        const x1 = layer.from.x, y1 = layer.from.y, x2 = layer.to.x, y2 = layer.to.y;
        const dx = x2 - x1, dy = y2 - y1;
        const len2 = dx * dx + dy * dy;
        if (len2 === 0) continue;
        const t = Math.max(0, Math.min(1, ((norm.nx - x1) * dx + (norm.ny - y1) * dy) / len2));
        const cx = x1 + t * dx, cy = y1 + t * dy;
        const d = Math.hypot(norm.nx - cx, norm.ny - cy);
        if (d < 0.018) return layer; // ~18/1000 of canvas — was 0.008, felt finicky on thin strokes
      }
    }
    return null;
  }

  // Endpoint grab radius for segment (arrow / line) editing, in viewport
  // pixels — a touch larger than the rendered handle so the target is easy
  // to land on. Independent of zoom (viewport px are pre-zoom), so the
  // on-screen grab area scales with the visible handle.
  const SEGMENT_HANDLE_GRAB = 10;

  /** Which endpoint of a segment layer is under the cursor, if any.
   *  Returns "from" | "to" | null. Works in viewport-pixel space (norm.px/py). */
  function segmentEndpointAt(norm, layer) {
    if (!layer || !layer.from || !layer.to) return null;
    const size = viewportSize();
    const fx = layer.from.x * size.w, fy = layer.from.y * size.h;
    const tx = layer.to.x * size.w, ty = layer.to.y * size.h;
    if (Math.hypot(norm.px - fx, norm.py - fy) <= SEGMENT_HANDLE_GRAB) return "from";
    if (Math.hypot(norm.px - tx, norm.py - ty) <= SEGMENT_HANDLE_GRAB) return "to";
    return null;
  }

  /** Is the cursor over the body of a segment layer (near the line, but not
   *  on an endpoint handle)? Mirrors hitTest's segment distance check. */
  function segmentBodyHit(norm, layer) {
    if (!layer || !layer.from || !layer.to) return false;
    const x1 = layer.from.x, y1 = layer.from.y, x2 = layer.to.x, y2 = layer.to.y;
    const dx = x2 - x1, dy = y2 - y1;
    const len2 = dx * dx + dy * dy;
    if (len2 === 0) return false;
    const t = Math.max(0, Math.min(1, ((norm.nx - x1) * dx + (norm.ny - y1) * dy) / len2));
    const cx = x1 + t * dx, cy = y1 + t * dy;
    return Math.hypot(norm.nx - cx, norm.ny - cy) < 0.018;
  }

  /** Snap a moving endpoint to a horizontal or vertical line through the
   *  fixed anchor endpoint (Shift while dragging). Normalized coords. */
  function snapPointToAxis(anchor, moving) {
    const dx = moving.x - anchor.x;
    const dy = moving.y - anchor.y;
    if (Math.abs(dx) >= Math.abs(dy)) return { x: moving.x, y: anchor.y };
    return { x: anchor.x, y: moving.y };
  }

  function uuid() {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
      return crypto.randomUUID();
    }
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      const r = (Math.random() * 16) | 0;
      const v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function defaultViewportForImage(img) {
    const margin = Math.max(96, Math.min(img.width, img.height) * 0.18);
    return {
      width: Math.ceil(img.width + margin * 2),
      height: Math.ceil(img.height + margin * 2),
      imageX: margin,
      imageY: margin,
      imageScale: 1,
    };
  }

  function isValidViewport(v) {
    return v && Number.isFinite(v.width) && v.width > 0
      && Number.isFinite(v.height) && v.height > 0
      && Number.isFinite(v.imageX) && Number.isFinite(v.imageY)
      && Number.isFinite(v.imageScale) && v.imageScale > 0;
  }

  function applyDocumentViewport(doc) {
    if (!doc || !isValidViewport(doc.viewport)) return false;
    const oldZoom = state.viewport.zoom || 1;
    const oldPanX = state.viewport.panX || 0;
    const oldPanY = state.viewport.panY || 0;
    state.viewport = Object.assign({}, doc.viewport, {
      zoom: oldZoom,
      panX: oldPanX,
      panY: oldPanY,
    });
    return true;
  }

  function imageNormToViewportPoint(point, basis) {
    return {
      x: (basis.imageX + point.x * basis.imageW * basis.imageScale) / basis.width,
      y: (basis.imageY + point.y * basis.imageH * basis.imageScale) / basis.height,
    };
  }

  function migrateLayerFromImageBasis(layer, basis) {
    if (layer.frame) {
      layer.frame = {
        x: (basis.imageX + layer.frame.x * basis.imageW * basis.imageScale) / basis.width,
        y: (basis.imageY + layer.frame.y * basis.imageH * basis.imageScale) / basis.height,
        width: (layer.frame.width * basis.imageW * basis.imageScale) / basis.width,
        height: (layer.frame.height * basis.imageH * basis.imageScale) / basis.height,
      };
    }
    if (layer.from) layer.from = imageNormToViewportPoint(layer.from, basis);
    if (layer.to) layer.to = imageNormToViewportPoint(layer.to, basis);
  }

  function migrateDocumentFromImageBasis(doc, viewport, onlyIds) {
    if (!state.image || !doc || !Array.isArray(doc.layers)) return doc;
    const basis = {
      width: viewport.width,
      height: viewport.height,
      imageX: viewport.imageX,
      imageY: viewport.imageY,
      imageScale: viewport.imageScale,
      imageW: state.image.width,
      imageH: state.image.height,
    };
    doc.layers.forEach((layer) => {
      if (onlyIds && !onlyIds.has(layer.id)) return;
      migrateLayerFromImageBasis(layer, basis);
    });
    return doc;
  }

  function installDocument(doc, options) {
    const incoming = cloneDocument(doc || state.document);
    const existingIds = new Set((state.document.layers || []).map((layer) => layer.id));
    let viewport = isValidViewport(incoming.viewport) ? incoming.viewport : null;

    if (!viewport && state.image) {
      viewport = defaultViewportForImage(state.image);
      // Version-1 sidecars and fresh agent plans were image-normalized.
      // We keep the layer schema, but migrate coordinates to the v2 viewport
      // basis before the next autosave.
      migrateDocumentFromImageBasis(incoming, viewport);
    } else if (viewport && options && options.convertNewImageBasisLayers) {
      // Agent pushes are full documents. Existing layers are already viewport-
      // normalized; newly added agent layers still follow the prompt's image
      // basis, so migrate just those new ids.
      const newIds = new Set((incoming.layers || []).filter((layer) => !existingIds.has(layer.id)).map((layer) => layer.id));
      migrateDocumentFromImageBasis(incoming, viewport, newIds);
    }

    state.document = incoming;
    const incomingIds = new Set((state.document.layers || []).map((layer) => layer.id));
    let prunedMessageLayers = false;
    state.messageLayerIds.forEach((id) => {
      if (!incomingIds.has(id)) {
        state.messageLayerIds.delete(id);
        prunedMessageLayers = true;
      }
    });
    if (prunedMessageLayers) postMessageLayers();
    if (viewport) {
      const oldZoom = state.viewport.zoom || 1;
      const oldPanX = state.viewport.panX || 0;
      const oldPanY = state.viewport.panY || 0;
      state.viewport = Object.assign({}, viewport, { zoom: oldZoom, panX: oldPanX, panY: oldPanY });
    }
    attachViewportToDocument(state.document);
  }

  function resizeCanvasToHost() {
    const rect = canvasWrap ? canvasWrap.getBoundingClientRect() : { width: window.innerWidth, height: window.innerHeight };
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.floor(rect.width));
    const h = Math.max(1, Math.floor(rect.height));
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    if (canvas.width !== Math.floor(w * dpr) || canvas.height !== Math.floor(h * dpr)) {
      canvas.width = Math.floor(w * dpr);
      canvas.height = Math.floor(h * dpr);
    }
    return { w, h, dpr };
  }

  function updateZoomDisplay() {
    if (!zoomDisplay) return;
    zoomDisplay.textContent = Math.round((state.viewport.zoom || 1) * 100) + "%";
  }

  function fitViewportToCanvas() {
    const rect = canvas.getBoundingClientRect();
    const vw = Math.max(1, state.viewport.width || 1);
    const vh = Math.max(1, state.viewport.height || 1);
    const zoom = Math.max(0.25, Math.min(4, Math.min(rect.width / vw, rect.height / vh, 1)));
    state.viewport.zoom = zoom;
    state.viewport.panX = (rect.width - vw * zoom) / 2;
    state.viewport.panY = (rect.height - vh * zoom) / 2;
    updateZoomDisplay();
  }

  function zoomAt(clientX, clientY, factor) {
    const rect = canvas.getBoundingClientRect();
    const sx = clientX == null ? rect.width / 2 : clientX - rect.left;
    const sy = clientY == null ? rect.height / 2 : clientY - rect.top;
    const before = screenToViewport(sx, sy);
    const next = Math.max(0.25, Math.min(4, state.viewport.zoom * factor));
    state.viewport.zoom = next;
    state.viewport.panX = sx - before.x * next;
    state.viewport.panY = sy - before.y * next;
    updateZoomDisplay();
    render();
  }

  function updateCursor() {
    if (state.panDrag) {
      canvas.style.cursor = "grabbing";
    } else if (state.frameResize) {
      canvas.style.cursor = cursorForFrameHandle(state.frameResize.handle);
    } else if (state.isSpaceDown || state.activeTool === "hand") {
      canvas.style.cursor = "grab";
    } else {
      canvas.style.cursor = state.activeTool == null ? "default" : "crosshair";
    }
  }

  /** Idle hover cursor in select mode: "grab" over a selected segment's
   *  endpoint handle, "move" over its body, default otherwise. Only runs
   *  when no tool is armed and we're not panning. */
  function updateSelectionHoverCursor(e) {
    if (state.activeTool != null || state.isSpaceDown) return;
    const sel = selectedLayer();
    if (sel && sel.frame) {
      const norm = eventToNorm(e);
      const handle = frameHandleAt(norm, sel);
      if (handle) {
        canvas.style.cursor = cursorForFrameHandle(handle);
        return;
      }
      if (frameBodyHit(norm, sel)) {
        canvas.style.cursor = "move";
        return;
      }
    }
    if (sel && sel.from && sel.to) {
      const norm = eventToNorm(e);
      if (segmentEndpointAt(norm, sel)) {
        canvas.style.cursor = "grab";
        return;
      }
      if (segmentBodyHit(norm, sel)) {
        canvas.style.cursor = "move";
        return;
      }
    }
    canvas.style.cursor = "default";
  }

  // ---------------------------------------------------------------------------
  // Layer factories (one per tool — schema-compliant with TalkieKit)
  // ---------------------------------------------------------------------------
  function newRectLayer(frame) {
    return {
      id: uuid(),
      kind: "rect",
      frame,
      color: state.style.color,
      strokeWidth: state.style.strokeWidth,
      visible: true,
      author: "user",
    };
  }

  function newArrowLayer(from, to, asLine) {
    const heads = asLine ? "none" : state.style.arrowHeads;
    const pair = pointerPairForHeads(heads, state.style.pointerStyle);
    return {
      id: uuid(),
      kind: "arrow",
      from,
      to,
      color: state.style.color,
      strokeWidth: state.style.strokeWidth,
      pointerStart: pair.start,
      pointerEnd: pair.end,
      pointerStyle: state.style.pointerStyle,
      // Legacy sentinel for older sidecars/renderers. New renderers prefer
      // pointerStart/pointerEnd, but keeping this for plain lines is harmless.
      label: pair.start === "none" && pair.end === "none" ? "line" : undefined,
      visible: true,
      author: "user",
    };
  }

  function newLabelLayer(frame, text) {
    const preset = TEXT_PRESETS[normalizeTextPreset(state.style.textPreset)];
    const textColor = state.style.textColor || preset.textColor;
    return {
      id: uuid(),
      kind: "label",
      frame,
      text,
      color: textColor,
      fontSize: state.style.fontSize,
      fontFamily: state.style.fontFamily,
      bold: state.style.bold,
      italic: state.style.italic,
      plain: state.style.plain || preset.plain,
      textPreset: normalizeTextPreset(state.style.textPreset),
      textColor,
      backgroundColor: state.style.backgroundColor || preset.backgroundColor,
      backgroundAlpha: typeof state.style.backgroundAlpha === "number" ? state.style.backgroundAlpha : preset.backgroundAlpha,
      borderColor: state.style.borderColor || preset.borderColor,
      borderAlpha: typeof state.style.borderAlpha === "number" ? state.style.borderAlpha : preset.borderAlpha,
      visible: true,
      author: "user",
    };
  }

  // Clone — a `patch` layer. `source` is the copy-from region, `frame` is where
  // it's drawn. Both start identical (copy in place); dragging the frame moves
  // the clone while the source stays put. Non-destructive: no pixels stored,
  // the region is recomputed from the original image on render.
  function newPatchLayer(frame) {
    // Lift the copy off the source by a small offset so the clone reads as a
    // separate, movable cutout the instant it's drawn. (Landing it exactly on
    // the original looks like nothing happened — the #1 reason the tool felt
    // missing.) Clamp so it stays on-canvas; flip the offset near an edge.
    const off = 0.04;
    const dx = frame.x + frame.width + off <= 1 ? off : -off;
    const dy = frame.y + frame.height + off <= 1 ? off : -off;
    const dest = Object.assign({}, frame);
    dest.x = Math.max(0, Math.min(frame.x + dx, 1 - frame.width));
    dest.y = Math.max(0, Math.min(frame.y + dy, 1 - frame.height));
    return {
      id: uuid(),
      kind: "patch",
      source: Object.assign({}, frame),
      frame: dest,
      visible: true,
      author: "user",
    };
  }

  // Blur is not in the TalkieKit schema. Phase-1 placeholder: a `highlight`
  // layer labelled "BLUR" so the user sees a marked region. Replacing this
  // with real blur requires Swift-side renderer support (out of scope).
  function newBlurPlaceholderLayer(frame) {
    return {
      id: uuid(),
      kind: "highlight",
      frame,
      color: "#646464",
      label: "BLUR",
      visible: true,
      author: "user",
    };
  }

  // Deep-clone a layer for Option-drag duplication. New id, lifted off the
  // original by a small offset so the copy reads as distinct the instant it
  // lands (mirrors the patch tool's copy-in-place lift). Handles both
  // frame-based layers (rect/label/patch/highlight) and segment layers
  // (arrow/line). `source` on a patch is intentionally left untouched so the
  // clone copies the same pixels, just drawn at the offset frame.
  function duplicateLayer(layer) {
    const copy = JSON.parse(JSON.stringify(layer));
    copy.id = uuid();
    copy.author = "user";
    const off = 0.03;
    const clamp01 = (v) => Math.max(0, Math.min(1, v));
    if (copy.frame) {
      const f = copy.frame;
      const dx = f.x + f.width + off <= 1 ? off : -off;
      const dy = f.y + f.height + off <= 1 ? off : -off;
      f.x = Math.max(0, Math.min(f.x + dx, 1 - f.width));
      f.y = Math.max(0, Math.min(f.y + dy, 1 - f.height));
    }
    if (copy.from && copy.to) {
      copy.from = { x: clamp01(copy.from.x + off), y: clamp01(copy.from.y + off) };
      copy.to = { x: clamp01(copy.to.x + off), y: clamp01(copy.to.y + off) };
    }
    return copy;
  }

  // ---------------------------------------------------------------------------
  // Selection restyle — change a selected layer's shape / color / width in
  // place. The toolbar's shape buttons + style stack act on the SELECTED layer
  // when one exists and no create-tool is active ("editing selection" mode),
  // instead of only setting new-draw defaults.
  // ---------------------------------------------------------------------------

  function selectedLayer() {
    return state.document.layers.find((l) => l.id === state.selectedLayerId) || null;
  }

  /** The toolbar "shape" identity of a layer (matches data-tool values).
   *  Returns null for kinds that have no shape button (label/guide). */
  function layerShape(layer) {
    if (!layer) return null;
    if (layer.kind === "rect") return "rect";
    if (layer.kind === "highlight") return layer.label === "BLUR" ? "blur" : null;
    if (layer.kind === "arrow") return arrowHeadsForLayer(layer) === "none" ? "line" : "arrow";
    return null; // label (text), guide — not shape-convertible
  }

  // Shapes the user may freely convert between. Two families:
  //   · frame-based:   rect ⇄ blur   (both carry a `frame`)
  //   · segment-based: arrow ⇄ line  (both carry from/to endpoints)
  // Cross-family conversions (rect→arrow) and conversions to/from text/guide
  // are intentionally disallowed — the geometry doesn't map cleanly.
  const CONVERTIBLE_SHAPES = new Set(["rect", "arrow", "line", "blur"]);

  function shapeFamily(shape) {
    if (shape === "rect" || shape === "blur") return "frame";
    if (shape === "arrow" || shape === "line") return "segment";
    return null;
  }

  /** Can the selected layer be converted to `targetShape`? Only within the
   *  same geometry family, and only between convertible shapes. */
  function canConvertSelectionTo(targetShape) {
    const layer = selectedLayer();
    if (!layer) return false;
    const from = layerShape(layer);
    if (!from || !CONVERTIBLE_SHAPES.has(targetShape)) return false;
    if (from === targetShape) return false;
    return shapeFamily(from) === shapeFamily(targetShape);
  }

  /** Mutate the selected layer in place to `targetShape`, preserving geometry,
   *  color and stroke width. Returns true if a change was applied. */
  function convertSelectionTo(targetShape) {
    const layer = selectedLayer();
    if (!layer || !canConvertSelectionTo(targetShape)) return false;
    snapshotForUndo();
    switch (targetShape) {
      case "rect":
        layer.kind = "rect";
        delete layer.label;
        break;
      case "blur":
        // Frame-based placeholder blur (highlight + "BLUR" sentinel). Keep the
        // user's frame; the grey fill comes from the renderer.
        layer.kind = "highlight";
        layer.label = "BLUR";
        break;
      case "arrow":
        layer.kind = "arrow";
        applyArrowStyleToLayer(layer, DEFAULT_ARROW_HEADS, state.style.pointerStyle);
        break;
      case "line":
        layer.kind = "arrow";
        applyArrowStyleToLayer(layer, "none", state.style.pointerStyle);
        break;
    }
    layer.author = "user";
    debouncedUpdate();
    render();
    return true;
  }

  /** Apply a style pick (color / stroke / font-size) to the selected layer.
   *  Returns true if a change was applied. */
  function applyStyleToSelection(kind, value) {
    const layer = selectedLayer();
    if (!layer) return false;
    snapshotForUndo();
    if (kind === "color") {
      layer.color = value;
      if (layer.kind === "label") layer.textColor = value;
    } else if (kind === "stroke") {
      layer.strokeWidth = Number(value) || 2;
    } else if (kind === "font-size") {
      layer.fontSize = Number(value) || 16;
    } else if (kind === "font-family") {
      layer.fontFamily = value;
    } else if (kind === "bold") {
      layer.bold = !!value;
    } else if (kind === "italic") {
      layer.italic = !!value;
    } else if (kind === "plain") {
      applyTextPresetToLayer(layer, value === "1" || value === true ? "plain" : DEFAULT_TEXT_PRESET);
    } else if (kind === "text-preset") {
      applyTextPresetToLayer(layer, value);
    } else if (kind === "arrow-heads") {
      applyArrowStyleToLayer(layer, value, pointerStyleForLayer(layer));
    } else if (kind === "pointer-style") {
      const heads = arrowHeadsForLayer(layer);
      const style = normalizePointerStyle(value);
      layer.pointerStyle = style;
      if (heads !== "none") applyArrowStyleToLayer(layer, heads, style);
    } else if (kind === "swap-arrow") {
      if (!layer.from || !layer.to) {
        state.history.past.pop();
        updateHistoryButtons();
        return false;
      }
      const from = layer.from;
      layer.from = layer.to;
      layer.to = from;
    } else if (kind === "text") {
      layer.text = typeof value === "string" ? value : String(value ?? "");
    } else if (kind === "label") {
      const next = typeof value === "string" ? value : String(value ?? "");
      if (next.length) {
        layer.label = next;
      } else if (layer.from && layer.to && arrowHeadsForLayer(layer) === "none") {
        layer.label = "line";
      } else {
        layer.label = undefined;
      }
    } else {
      state.history.past.pop(); // nothing changed; drop the speculative snapshot
      updateHistoryButtons();
      return false;
    }
    layer.author = "user";
    debouncedUpdate();
    render();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------
  function drawPointer(tipX, tipY, tailX, tailY, w, pointerStyle) {
    const style = normalizePointerStyle(pointerStyle);
    if (style === "none") return;
    const headLen = Math.max(8, w / 90);
    const angle = Math.atan2(tipY - tailY, tipX - tailX);
    const left = {
      x: tipX - headLen * Math.cos(angle - Math.PI / 6),
      y: tipY - headLen * Math.sin(angle - Math.PI / 6),
    };
    const right = {
      x: tipX - headLen * Math.cos(angle + Math.PI / 6),
      y: tipY - headLen * Math.sin(angle + Math.PI / 6),
    };
    const stroke = ctx.strokeStyle;

    if (style === "filled") {
      ctx.beginPath();
      ctx.moveTo(tipX, tipY);
      ctx.lineTo(left.x, left.y);
      ctx.lineTo(right.x, right.y);
      ctx.closePath();
      ctx.fillStyle = stroke;
      ctx.fill();
      return;
    }

    if (style === "dot") {
      ctx.beginPath();
      ctx.fillStyle = stroke;
      ctx.arc(tipX, tipY, Math.max(3.5, headLen * 0.32), 0, Math.PI * 2);
      ctx.fill();
      return;
    }

    if (style === "bar") {
      const len = headLen * 0.74;
      const px = Math.cos(angle + Math.PI / 2) * len;
      const py = Math.sin(angle + Math.PI / 2) * len;
      ctx.beginPath();
      ctx.moveTo(tipX - px, tipY - py);
      ctx.lineTo(tipX + px, tipY + py);
      ctx.stroke();
      return;
    }

    ctx.beginPath();
    ctx.moveTo(tipX, tipY);
    ctx.lineTo(left.x, left.y);
    ctx.moveTo(tipX, tipY);
    ctx.lineTo(right.x, right.y);
    ctx.stroke();
  }

  function messageTagAnchor(layer, w, h) {
    const r = framePx(layer, w, h);
    if (r) return { x: r.x + r.w, y: r.y };
    if (layer.from && layer.to) {
      return {
        x: ((layer.from.x + layer.to.x) / 2) * w,
        y: ((layer.from.y + layer.to.y) / 2) * h,
      };
    }
    return null;
  }

  function drawMessageTag(layer, w, h) {
    const anchor = messageTagAnchor(layer, w, h);
    if (!anchor) return;
    const zoom = Math.max(0.25, state.viewport.zoom || 1);
    const label = "@";
    const padX = 5 / zoom;
    const tagH = 16 / zoom;
    ctx.save();
    ctx.font = `${10 / zoom}px ui-monospace, monospace`;
    const tagW = ctx.measureText(label).width + padX * 2;
    const x = Math.min(w - tagW - 2 / zoom, Math.max(2 / zoom, anchor.x - tagW / 2));
    const y = Math.min(h - tagH - 2 / zoom, Math.max(2 / zoom, anchor.y - tagH - 4 / zoom));
    roundRectPath(ctx, x, y, tagW, tagH, 4 / zoom);
    ctx.fillStyle = "rgba(79,125,255,0.95)";
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.85)";
    ctx.lineWidth = 1 / zoom;
    ctx.stroke();
    ctx.fillStyle = "#fff";
    ctx.textBaseline = "middle";
    ctx.fillText(label, x + padX, y + tagH / 2);
    ctx.restore();
  }

  function drawLayer(layer, w, h) {
    if (!layer.visible) return;
    ctx.save();
    // Stroke scales with image width so a thin pick doesn't disappear on
    // 4K captures. `layer.strokeWidth` (set by the style stack at create
    // time) is interpreted in relative units: 2 matches the historical
    // default of `max(2, w/600)`, so existing sidecar docs that don't
    // carry a strokeWidth still render unchanged.
    const baseUnit = Math.max(1, w / 600);
    const strokeUnits = typeof layer.strokeWidth === "number" ? layer.strokeWidth : 2;
    ctx.lineWidth = strokeUnits * baseUnit;
    switch (layer.kind) {
      case "patch": {
        const r = framePx(layer, w, h);
        const s = layer.source;
        if (!r || !s || !state.image) break;
        const v = state.viewport;
        const scale = v.imageScale || 1;
        // Source region → original-image pixels.
        const sx = (s.x * v.width - v.imageX) / scale;
        const sy = (s.y * v.height - v.imageY) / scale;
        const sw = (s.width * v.width) / scale;
        const sh = (s.height * v.height) / scale;
        if (sw >= 1 && sh >= 1) {
          try {
            ctx.drawImage(state.image, sx, sy, sw, sh, r.x, r.y, r.w, r.h);
          } catch (e) { /* source outside image bounds — skip */ }
        }
        // Thin neutral edge so the clone reads as a distinct object.
        ctx.strokeStyle = "rgba(35,36,35,0.30)";
        ctx.lineWidth = baseUnit;
        ctx.strokeRect(r.x, r.y, r.w, r.h);
        // When selected, show where the pixels came from.
        if (state.selectedLayerId === layer.id) {
          ctx.save();
          ctx.setLineDash([4, 3]);
          ctx.strokeStyle = "rgba(79,125,255,0.7)";
          ctx.lineWidth = baseUnit;
          ctx.strokeRect(s.x * w, s.y * h, s.width * w, s.height * h);
          ctx.restore();
        }
        break;
      }
      case "rect":
      case "highlight": {
        const r = framePx(layer, w, h);
        if (!r) break;
        if (layer.kind === "highlight") {
          ctx.fillStyle = hexColor(layer.color, layer.label === "BLUR" ? 0.32 : 0.12);
          ctx.fillRect(r.x, r.y, r.w, r.h);
        }
        ctx.strokeStyle = hexColor(layer.color);
        ctx.strokeRect(r.x, r.y, r.w, r.h);
        if (layer.label === "BLUR") {
          // Render the "BLUR" placeholder tag in-corner so it's obvious this
          // is a phase-1 marker, not a real blur effect.
          ctx.fillStyle = "rgba(0,0,0,0.7)";
          const tag = "BLUR";
          ctx.font = `${Math.max(10, w / 160)}px ui-monospace, monospace`;
          const tw = ctx.measureText(tag).width + 8;
          const th = Math.max(14, w / 110);
          ctx.fillRect(r.x, r.y, tw, th);
          ctx.fillStyle = "#fff";
          ctx.fillText(tag, r.x + 4, r.y + th - 4);
        }
        break;
      }
      case "arrow": {
        if (!layer.from || !layer.to) break;
        const x1 = layer.from.x * w, y1 = layer.from.y * h;
        const x2 = layer.to.x * w, y2 = layer.to.y * h;
        ctx.strokeStyle = hexColor(layer.color);
        ctx.beginPath();
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.stroke();
        drawPointer(x1, y1, x2, y2, w, pointerForLayer(layer, "start"));
        drawPointer(x2, y2, x1, y1, w, pointerForLayer(layer, "end"));
        break;
      }
      case "label": {
        const r = framePx(layer, w, h);
        const text = layer.text || layer.label || "";
        if (!r || !text) break;
        const scale = (typeof layer.fontSize === "number" ? layer.fontSize : 16) / 16;
        const px = Math.max(11, (w / 140) * scale);
        ctx.font = labelFontString(layer, px);
        const style = labelStyle(layer);
        const padX = 7;
        const padY = 5;
        const textW = ctx.measureText(text).width;
        const bgW = Math.max(r.w, textW + padX * 2);
        const bgH = Math.max(r.h, px + padY * 2);
        ctx.textBaseline = "middle";
        if (style.plain) {
          // Plain mode: colored text, no background chip.
          ctx.fillStyle = hexColor(style.textColor);
          ctx.fillText(text, r.x + 2, r.y + bgH / 2);
        } else {
          ctx.beginPath();
          roundRectPath(ctx, r.x, r.y, bgW, bgH, Math.min(7, bgH / 2));
          ctx.fillStyle = hexColor(style.backgroundColor, style.backgroundAlpha);
          ctx.fill();
          if (style.borderAlpha > 0) {
            ctx.strokeStyle = hexColor(style.borderColor, style.borderAlpha);
            ctx.lineWidth = Math.max(1, w / 1200);
            ctx.stroke();
          }
          ctx.fillStyle = hexColor(style.textColor);
          ctx.fillText(text, r.x + padX, r.y + bgH / 2);
        }
        break;
      }
      case "guide": {
        const interval = layer.interval || 50;
        const orient = layer.orientation || "h";
        ctx.strokeStyle = hexColor(layer.color, 0.55);
        ctx.lineWidth = 1;
        if (orient === "h" || orient === "both") {
          for (let y = interval; y < h; y += interval) {
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
          }
        }
        if (orient === "v" || orient === "both") {
          for (let x = interval; x < w; x += interval) {
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
          }
        }
        break;
      }
    }
    if (state.selectedLayerId === layer.id) {
      const r = framePx(layer, w, h);
      if (r) {
        ctx.setLineDash([4, 3]);
        ctx.strokeStyle = "#4F7DFF";
        ctx.strokeRect(r.x - 2, r.y - 2, r.w + 4, r.h + 4);
        ctx.setLineDash([]);
        ctx.fillStyle = "#fff";
        ctx.strokeStyle = "#4F7DFF";
        const zoom = Math.max(0.25, state.viewport.zoom || 1);
        ctx.lineWidth = 1.25 / zoom;
        const handleSize = 7 / zoom;
        frameHandlePoints(layer).forEach((handle) => {
          ctx.beginPath();
          ctx.rect(handle.x - handleSize / 2, handle.y - handleSize / 2, handleSize, handleSize);
          ctx.fill();
          ctx.stroke();
        });
      } else if (layer.from && layer.to) {
        // Selection markers for line/arrow: filled round grab handles at each
        // endpoint. Drag a handle to reshape that end; drag the body to move
        // the whole segment.
        const x1 = layer.from.x * w, y1 = layer.from.y * h;
        const x2 = layer.to.x * w, y2 = layer.to.y * h;
        ctx.setLineDash([]);
        ctx.lineWidth = 1.5;
        ctx.fillStyle = "#fff";
        ctx.strokeStyle = "#4F7DFF";
        [[x1, y1], [x2, y2]].forEach(([hx, hy]) => {
          ctx.beginPath();
          ctx.arc(hx, hy, 4.5, 0, Math.PI * 2);
          ctx.fill();
          ctx.stroke();
        });
      }
    }
    if (state.messageLayerIds.has(layer.id)) {
      drawMessageTag(layer, w, h);
    }
    ctx.restore();
  }

  function drawCreatingPreview(w, h) {
    const c = state.creating;
    if (!c) return;
    ctx.save();
    ctx.lineWidth = Math.max(2, w / 600);
    ctx.setLineDash([6, 4]);
    ctx.strokeStyle = hexColor(DEFAULT_COLOR, 0.85);
    if (c.tool === "rect" || c.tool === "blur" || c.tool === "clone") {
      const f = normalizedFrame(c.start, c.current);
      ctx.strokeRect(f.x * w, f.y * h, f.width * w, f.height * h);
      if (c.tool === "blur") {
        ctx.fillStyle = "rgba(100,100,100,0.18)";
        ctx.fillRect(f.x * w, f.y * h, f.width * w, f.height * h);
      }
    } else if (c.tool === "arrow" || c.tool === "line") {
      const x1 = c.start.nx * w, y1 = c.start.ny * h;
      const x2 = c.current.nx * w, y2 = c.current.ny * h;
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
      if (c.tool === "arrow") {
        ctx.setLineDash([]);
        const pair = pointerPairForHeads(state.style.arrowHeads, state.style.pointerStyle);
        drawPointer(x1, y1, x2, y2, w, pair.start);
        drawPointer(x2, y2, x1, y1, w, pair.end);
      }
    }
    ctx.setLineDash([]);
    ctx.restore();
  }

  function postSelection() {
    post("markup.selection", {
      sessionId: state.sessionId,
      layerCount: state.document.layers.length,
      selection: selectionPayload(),
    });
  }

  function postStats() {
    post("markup.stats", {
      sessionId: state.sessionId,
      layerCount: state.document.layers.length,
    });
  }

  /** Toggle a layer into the next agent message. Explicit user gesture;
   *  selection alone does NOT attach. */
  function postAttach(layer) {
    toggleMessageLayer(layer);
  }

  function render() {
    if (!state.image) return;
    const canvasSize = resizeCanvasToHost();
    ctx.setTransform(canvasSize.dpr, 0, 0, canvasSize.dpr, 0, 0);
    ctx.clearRect(0, 0, canvasSize.w, canvasSize.h);

    const w = state.viewport.width;
    const h = state.viewport.height;
    ctx.save();
    ctx.translate(state.viewport.panX, state.viewport.panY);
    ctx.scale(state.viewport.zoom, state.viewport.zoom);

    ctx.fillStyle = "rgba(249,251,251,0.78)";
    ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = "rgba(35,36,35,0.10)";
    ctx.lineWidth = 1 / state.viewport.zoom;
    ctx.strokeRect(0, 0, w, h);
    ctx.drawImage(
      state.image,
      state.viewport.imageX,
      state.viewport.imageY,
      state.image.width * state.viewport.imageScale,
      state.image.height * state.viewport.imageScale,
    );
    state.document.layers.forEach((layer) => drawLayer(layer, w, h));
    drawCreatingPreview(w, h);
    ctx.restore();
    renderRail();
    updateRailMode();
    // Keep the toolbar in sync with the current selection (edit-mode shape
    // highlight, disabled conversions, style-stack mirror). render() is the
    // common path for every selection change (canvas/sidebar select, undo,
    // delete, escape), so this is the single place to refresh it.
    syncToolbarState();
    postStats();
    postSelection();
    updateHistoryButtons();
  }

  function renderRail() {
    layerList.innerHTML = "";
    layerCount.textContent = String(state.document.layers.length);
    state.document.layers.forEach((layer) => {
      const row = document.createElement("div");
      const rowClasses = ["layer-row"];
      if (layer.id === state.selectedLayerId) rowClasses.push("selected");
      if (state.messageLayerIds.has(layer.id)) rowClasses.push("attached");
      row.className = rowClasses.join(" ");
      // ⠿ grip is the explicit "attach this layer to the composer"
      // affordance. Click sends a `markup.attach` bridge message
      // (Swift inputBar appends it to the attachments row). The rest
      // of the row is a normal select click. File drag-out is owned by
      // the small native "DRAG PNG" handle over the canvas so it can
      // start an AppKit drag without stealing layer-move drags here.
      const isAttached = state.messageLayerIds.has(layer.id);
      const attachTitle = isAttached ? "Remove from next message" : "Add to next message";
      // ⊕ / ⊖ reads as a click-to-add toggle. (Was ⠿ with a grab cursor —
      // that looked like a drag handle and invited a drag that did nothing.)
      const attachGlyph = isAttached ? "⊖" : "⊕";
      row.dataset.layerId = layer.id;
      row.innerHTML = `<span class="grip" title="${attachTitle}">${attachGlyph}</span><span class="dot ${layer.author || "agent"}"></span><span class="layer-row-label">${layer.kind}${layer.label ? " · " + layer.label : ""}</span>`;
      const grip = row.querySelector(".grip");
      if (grip) {
        grip.onclick = (e) => {
          e.stopPropagation();
          postAttach(layer);
        };
      }
      row.onclick = () => {
        state.selectedLayerId = layer.id;
        // Sidebar select → drop any active creation tool so the
        // user's next canvas click adjusts the selected layer
        // instead of stamping a new shape on top of it.
        setActiveTool(null);
        render();
      };
      layerList.appendChild(row);
    });
    renderInspector();
  }

  function escHtml(value) {
    return String(value == null ? "" : value).replace(/[&<>"]/g, (c) => (
      { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]
    ));
  }

  function hasLayerTurn(layer) {
    return !!layer && (
      layer.turnPass != null ||
      layer.turnInstruction ||
      layer.turnModel ||
      layer.turnSummary ||
      layer.turnElapsed != null
    );
  }

  function turnDetailsForInspector(layer) {
    if (hasLayerTurn(layer)) {
      const elapsed = Number(layer.turnElapsed);
      return {
        title: "turn",
        pass: layer.turnPass,
        model: layer.turnModel,
        summary: layer.turnSummary,
        elapsed: Number.isFinite(elapsed) ? `${elapsed.toFixed(1)}s` : "",
        instruction: layer.turnInstruction,
      };
    }
    const t = state.thread;
    if (!t) return null;
    return {
      title: "latest turn",
      pass: t.pass,
      model: t.model,
      summary: t.live ? (t.statusText || "running") : (t.summary || "done"),
      elapsed: t.elapsed,
      instruction: t.instruction,
    };
  }

  function renderTurnDetails(turn) {
    if (!turn) return "";
    const rows = [];
    if (turn.pass != null) rows.push(["PASS", turn.pass]);
    if (turn.model) rows.push(["MODEL", turn.model]);
    if (turn.summary) rows.push(["STATUS", turn.summary]);
    if (turn.elapsed) rows.push(["TIME", turn.elapsed]);
    const rowHTML = rows.map(([k, v]) =>
      `<div class="insp-turn-row"><span class="insp-turn-k">${escHtml(k)}</span><span class="insp-turn-v">${escHtml(v)}</span></div>`
    ).join("");
    const prompt = turn.instruction
      ? `<div class="insp-turn-prompt">${escHtml(turn.instruction)}</div>`
      : "";
    return `<div class="insp-section"><div class="insp-kicker">${escHtml(turn.title)}</div><div class="insp-turn">${rowHTML}${prompt}</div></div>`;
  }

  // Convert a layer's viewport-normalized geometry into SOURCE-IMAGE pixels —
  // the meaningful "where on the screenshot." Mirrors the renderer's
  // image-basis math: imagePx = (norm * viewportDim - imageOrigin) / imageScale.
  function frameImagePx(frame) {
    const v = state.viewport;
    const scale = v.imageScale || 1;
    return {
      x: (frame.x * v.width - v.imageX) / scale,
      y: (frame.y * v.height - v.imageY) / scale,
      w: (frame.width * v.width) / scale,
      h: (frame.height * v.height) / scale,
    };
  }
  function pointImagePx(point) {
    const v = state.viewport;
    const scale = v.imageScale || 1;
    return {
      x: (point.x * v.width - v.imageX) / scale,
      y: (point.y * v.height - v.imageY) / scale,
    };
  }

  function renderInspector() {
    const body = document.getElementById("inspector-body");
    if (!body) return;
    const sel = state.document.layers.find((l) => l.id === state.selectedLayerId);
    if (!sel) {
      body.className = "inspector-empty";
      body.textContent = "Select a layer to inspect.";
      return;
    }
    body.className = "";

    const shape = layerShape(sel) || sel.kind;
    const author = sel.author || "agent";
    const color = sel.kind === "label"
      ? (labelStyle(sel).textColor || sel.color || "#4F7DFF")
      : (sel.color || "#4F7DFF");
    const sections = [];

    // Identity — author chip + shape name.
    sections.push(
      `<div class="insp-head">` +
        `<span class="insp-chip insp-chip-${author === "user" ? "user" : "agent"}">${escHtml(author)}</span>` +
        `<span class="insp-title">${escHtml(shape)}</span>` +
      `</div>`
    );

    const turnDetails = turnDetailsForInspector(sel);
    if (turnDetails) {
      sections.push(renderTurnDetails(turnDetails));
    }

    // Geometry — image pixels, in a small card grid. Frame layers get X/Y/W/H;
    // segment layers (arrow/line) get start/end points + length.
    let geo = "";
    if (sel.frame) {
      const p = frameImagePx(sel.frame);
      const cell = (k, v) => `<div class="insp-cell"><span class="ck">${k}</span><span class="cv">${v}</span></div>`;
      geo =
        `<div class="insp-geo">` +
          cell("X", Math.round(p.x)) +
          cell("Y", Math.round(p.y)) +
          cell("W", Math.round(p.w)) +
          cell("H", Math.round(p.h)) +
        `</div>`;
    } else if (sel.from && sel.to) {
      const a = pointImagePx(sel.from);
      const b = pointImagePx(sel.to);
      const len = Math.hypot(b.x - a.x, b.y - a.y);
      const cell = (k, v) => `<div class="insp-cell"><span class="ck">${k}</span><span class="cv">${v}</span></div>`;
      geo =
        `<div class="insp-geo insp-geo-seg">` +
          cell("START", `${Math.round(a.x)}, ${Math.round(a.y)}`) +
          cell("END", `${Math.round(b.x)}, ${Math.round(b.y)}`) +
          cell("LENGTH", `${Math.round(len)}<span class="cu">px</span>`) +
        `</div>`;
    }
    if (geo) {
      sections.push(`<div class="insp-section"><div class="insp-kicker">geometry · px</div>${geo}</div>`);
    }

    // Clone (patch): show where the pixels were copied from instead of style.
    if (sel.kind === "patch" && sel.source) {
      const s = pointImagePx({ x: sel.source.x, y: sel.source.y });
      sections.push(
        `<div class="insp-section"><div class="insp-kicker">source · px</div>` +
        `<div class="insp-geo insp-geo-seg">` +
          `<div class="insp-cell"><span class="ck">FROM</span><span class="cv">${Math.round(s.x)}, ${Math.round(s.y)}</span></div>` +
        `</div></div>`
      );
      body.innerHTML = sections.join("");
      return;
    }

    // Style — INTERACTIVE controls. The inspector is the per-layer editor now
    // (the toolbar is new-draw defaults only). Each control carries
    // data-insp-style / data-insp-value; a delegated handler on #inspector-body
    // applies it to the selected layer via applyStyleToSelection.
    const escAttr = (s) => escHtml(String(s == null ? "" : s)).replace(/"/g, "&quot;");
    const sameHex = (a, b) => String(a || "").toUpperCase() === String(b || "").toUpperCase();
    const COLORS = [["#232423", "Ink"], ["#D03A1C", "Alert"], ["#4F7DFF", "Accent"], ["#12A594", "Teal"], ["#FFFFFF", "White"]];
    const ctrl = (label, inner) => `<div class="insp-ctrl"><span class="insp-ctrl-k">${label}</span><div class="insp-ctrl-row">${inner}</div></div>`;
    const ctrlText = (label, inner) => `<div class="insp-ctrl insp-ctrl-text"><span class="insp-ctrl-k">${label}</span>${inner}</div>`;
    const ctrls = [];

    // Color — every layer kind.
    ctrls.push(ctrl("color", COLORS.map(([hex, name]) =>
      `<button type="button" class="style-btn swatch${hex === "#FFFFFF" ? " swatch-light" : ""}${sameHex(color, hex) ? " active" : ""}" data-insp-style="color" data-insp-value="${hex}" title="${name}" style="--c: ${hex}"></button>`
    ).join("")));

    // Stroke — shapes (not labels / blur).
    if (sel.kind !== "label" && shape !== "blur") {
      const w = typeof sel.strokeWidth === "number" ? sel.strokeWidth : 2;
      ctrls.push(ctrl("stroke", [1, 2, 3, 5].map((v) =>
        `<button type="button" class="style-btn stroke-pick${v === w ? " active" : ""}" data-insp-style="stroke" data-insp-value="${v}" title="${v} px"><span class="stroke-pip" style="height: ${v}px"></span></button>`
      ).join("")));
    }

    // Arrow endpoints — segment layers can be plain lines, one-ended arrows,
    // two-ended arrows, or diagram-ish dot/bar pointers.
    if (sel.from && sel.to) {
      const heads = arrowHeadsForLayer(sel);
      const tip = pointerStyleForLayer(sel);
      ctrls.push(ctrl("heads", [
        ["none", "--", "No pointers"],
        ["start", "<-", "Pointer at start"],
        ["end", "->", "Pointer at end"],
        ["both", "<>", "Pointers at both ends"],
      ].map(([v, glyph, title]) =>
        `<button type="button" class="style-btn arrow-head${v === heads ? " active" : ""}" data-insp-style="arrow-heads" data-insp-value="${v}" title="${title}">${glyph}</button>`
      ).join("")));
      ctrls.push(ctrl("tip", [
        ["open", "V", "Open arrow"],
        ["filled", "F", "Filled arrow"],
        ["dot", "O", "Dot pointer"],
        ["bar", "|", "Bar pointer"],
      ].map(([v, glyph, title]) =>
        `<button type="button" class="style-btn pointer-pick${v === tip ? " active" : ""}" data-insp-style="pointer-style" data-insp-value="${v}" title="${title}">${glyph}</button>`
      ).join("")));
      ctrls.push(ctrl("dir",
        `<button type="button" class="style-btn segment-action" data-insp-style="swap-arrow" data-insp-value="1" title="Reverse direction">swap</button>`
      ));
    }

    // Text typography — labels only.
    if (sel.kind === "label") {
      const preset = textPresetForLayer(sel);
      ctrls.push(ctrl("preset", [
        ["on-light", "L", "For light backgrounds"],
        ["on-dark", "D", "For dark backgrounds"],
        ["accent", "A", "Amber accent"],
        ["plain", "T", "Plain text"],
      ].map(([v, glyph, title]) =>
        `<button type="button" class="style-btn text-preset${v === preset ? " active" : ""}" data-insp-style="text-preset" data-insp-value="${v}" title="${title}">${glyph}</button>`
      ).join("")));
      const fs = typeof sel.fontSize === "number" ? sel.fontSize : 16;
      ctrls.push(ctrl("size", [[12, "S"], [16, "M"], [22, "L"]].map(([v, l]) =>
        `<button type="button" class="style-btn font-pick${v === fs ? " active" : ""}" data-insp-style="font-size" data-insp-value="${v}" title="${l}">${l}</button>`
      ).join("")));
      const fam = sel.fontFamily || "mono";
      const FAMS = [["sans", "-apple-system, system-ui, sans-serif"], ["serif", "ui-serif, Georgia, serif"], ["mono", "ui-monospace, monospace"]];
      ctrls.push(ctrl("font", FAMS.map(([v, css]) =>
        `<button type="button" class="style-btn font-fam${v === fam ? " active" : ""}" data-insp-style="font-family" data-insp-value="${v}" style="font-family: ${css}">Aa</button>`
      ).join("")));
      ctrls.push(ctrl("style",
        `<button type="button" class="style-btn deco${sel.bold ? " active" : ""}" data-insp-style="bold" data-insp-toggle style="font-weight: 700">B</button>` +
        `<button type="button" class="style-btn deco${sel.italic ? " active" : ""}" data-insp-style="italic" data-insp-toggle style="font-style: italic; font-family: ui-serif, Georgia, serif">I</button>`
      ));
      ctrls.push(ctrl("bg",
        `<button type="button" class="style-btn labelbg${!sel.plain ? " active" : ""}" data-insp-style="plain" data-insp-value="0" title="Pill background">▭</button>` +
        `<button type="button" class="style-btn labelbg${sel.plain ? " active" : ""}" data-insp-style="plain" data-insp-value="1" title="Plain text">T</button>`
      ));
      ctrls.push(ctrlText("text",
        `<input type="text" class="insp-text-input" data-insp-text data-insp-style="text" value="${escAttr(sel.text)}" placeholder="label text" />`
      ));
    }

    // Optional callout label — shapes that can carry one (arrow / rect / line).
    if (sel.kind !== "label" && sel.kind !== "patch" && shape !== "blur" && sel.label !== "BLUR") {
      ctrls.push(ctrlText("label",
        `<input type="text" class="insp-text-input" data-insp-text data-insp-style="label" value="${escAttr(calloutLabelForLayer(sel))}" placeholder="callout label" />`
      ));
    }

    sections.push(`<div class="insp-section"><div class="insp-kicker">style</div>${ctrls.join("")}</div>`);

    body.innerHTML = sections.join("");
  }

  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = url;
    });
  }

  function setActiveTool(tool) {
    state.activeTool = tool;
    syncToolbarState();
    // Cursor hint: crosshair while a create-tool is selected, default in select mode.
    updateCursor();
  }

  // ---------------------------------------------------------------------------
  // Toolbar state — reflects EITHER the active create-tool's defaults OR the
  // selected layer. When a layer is selected and no create-tool is active we
  // enter "editing selection" mode: the shape buttons highlight the layer's
  // current shape (and disable cross-family conversions), and the style stack
  // mirrors the layer's color / width / font.
  // ---------------------------------------------------------------------------
  function isEditingSelection() {
    // Selected-layer editing now lives in the inspector (see renderInspector).
    // The top toolbar stays purely tool-selection + new-draw defaults and never
    // morphs into a live "editing selection" restyle panel.
    return false;
  }

  function syncToolbarState() {
    const editing = isEditingSelection();
    const layer = editing ? selectedLayer() : null;
    const selShape = layer ? layerShape(layer) : null;

    // Shape buttons: in edit mode highlight the layer's shape and disable
    // conversions that don't map cleanly. In draw mode highlight the active
    // create-tool as before.
    // Document scope keeps every tool button in sync if a future surface
    // mirrors the primary toolbar controls.
    document.querySelectorAll(".tool-btn[data-tool]").forEach((btn) => {
      const tool = btn.getAttribute("data-tool");
      // Viewport / cursor tools are always enabled and reflect the current
      // mode: Select is on whenever no create-tool is armed; Hand when panning.
      if (tool === "select" || tool === "hand") {
        btn.disabled = false;
        btn.classList.toggle(
          "active",
          tool === "select" ? state.activeTool == null : state.activeTool === "hand"
        );
        return;
      }
      if (editing) {
        btn.classList.toggle("active", tool === selShape);
        // Text + the layer's own shape stay enabled; cross-family shape
        // conversions are disabled. (Text tool is left enabled so the user
        // can still drop a new label even while a layer is selected.)
        const allow = tool === "text" || tool === selShape || canConvertSelectionTo(tool);
        btn.disabled = !allow;
      } else {
        btn.classList.toggle("active", tool === state.activeTool);
        btn.disabled = false;
      }
    });

    // The "editing selection" affordance on the toolbar.
    toolToolbar.classList.toggle("editing-selection", editing);
    const badge = document.getElementById("selection-mode-badge");
    if (badge) {
      badge.classList.toggle("hidden", !editing);
      if (editing && layer) {
        badge.textContent = "Editing " + (selShape || layer.kind);
      }
    }

    updateStyleStackVisibility();
    syncStyleStackActive();
  }

  /** Reflect the active style values onto the style-stack buttons. In edit
   *  mode the values come from the selected layer; otherwise from the per-tool
   *  defaults in `state.style`. */
  function syncStyleStackActive() {
    if (!styleStack) return;
    const layer = isEditingSelection() ? selectedLayer() : null;
    const textToolColor = state.style.textColor || TEXT_PRESETS[normalizeTextPreset(state.style.textPreset)].textColor;
    const color = layer ? layer.color : (state.activeTool === "text" ? textToolColor : state.style.color);
    const stroke = layer
      ? (typeof layer.strokeWidth === "number" ? layer.strokeWidth : 2)
      : state.style.strokeWidth;
    const font = layer
      ? (typeof layer.fontSize === "number" ? layer.fontSize : 16)
      : state.style.fontSize;

    setGroupActiveByValue("color", color, true);
    setGroupActiveByValue("stroke", String(stroke), false);
    setGroupActiveByValue("font-size", String(font), false);

    // Text typography — family + pill/plain are single-select groups; bold and
    // italic are independent toggles.
    const family = layer ? (layer.fontFamily || "mono") : state.style.fontFamily;
    const plain = layer ? !!layer.plain : !!state.style.plain;
    const textPreset = layer ? textPresetForLayer(layer) : normalizeTextPreset(state.style.textPreset);
    const arrowHeads = layer && layer.from && layer.to ? arrowHeadsForLayer(layer) : state.style.arrowHeads;
    const pointerStyle = layer && layer.from && layer.to ? pointerStyleForLayer(layer) : state.style.pointerStyle;
    setGroupActiveByValue("font-family", family, false);
    setGroupActiveByValue("plain", plain ? "1" : "0", false);
    setGroupActiveByValue("text-preset", textPreset, false);
    setGroupActiveByValue("arrow-heads", arrowHeads, false);
    setGroupActiveByValue("pointer-style", pointerStyle, false);
    setToggleActive("bold", layer ? !!layer.bold : !!state.style.bold);
    setToggleActive("italic", layer ? !!layer.italic : !!state.style.italic);
  }

  /** Reflect a boolean toggle's state onto its button. */
  function setToggleActive(kind, on) {
    if (!styleStack) return;
    const btn = styleStack.querySelector(`.style-btn[data-style="${kind}"][data-toggle]`);
    if (btn) btn.classList.toggle("active", on);
  }

  /** Mark the button in `kind`'s group whose data-value matches `value`.
   *  `caseInsensitive` handles hex colors. Clears the rest of the group. */
  function setGroupActiveByValue(kind, value, caseInsensitive) {
    const buttons = styleStack.querySelectorAll(`.style-btn[data-style="${kind}"]`);
    const target = caseInsensitive ? String(value).toLowerCase() : String(value);
    buttons.forEach((b) => {
      const bv = caseInsensitive
        ? String(b.getAttribute("data-value")).toLowerCase()
        : b.getAttribute("data-value");
      b.classList.toggle("active", bv === target);
    });
  }

  // ---------------------------------------------------------------------------
  // Style stack — per-tool defaults editor
  //
  // The style stack lives on the right half of the top toolbar. Groups
  // are hidden/shown based on the active tool:
  //   · shape tools (rect/arrow/line/blur) → stroke + color
  //   · arrow tool                         → stroke + heads + tip + color
  //   · text tool                          → text color + text presets
  //   · null tool (select mode)            → compact stroke + color defaults
  //
  // Clicking a swatch / pip updates `state.style`, which is the source
  // of truth used by the layer factories when a new layer is created.
  // ---------------------------------------------------------------------------
  function updateStyleStackVisibility() {
    if (!styleStack) return;

    // The toolbar style stack is the NEW-DRAW defaults panel — it follows the
    // active create-tool. (Selected-layer editing lives in the inspector now.)
    const tool = state.activeTool;
    const isText = tool === "text";
    const isArrow = tool === "arrow";

    // Clone tool has no style controls — hide the whole stack.
    if (tool === "clone") {
      styleStack.querySelectorAll(".style-group, .style-divider").forEach((el) => el.classList.add("hidden"));
      return;
    }

    const strokeGroup = styleStack.querySelector('[data-group="stroke"]');
    const colorGroup = styleStack.querySelector('[data-group="color"]');
    // Stroke is meaningless for text; text-only groups belong to the Text
    // tool, and arrow endpoint controls belong to the Arrow tool. Select mode
    // stays compact so the toolbar does not horizontally overflow.
    if (strokeGroup) strokeGroup.classList.toggle("hidden", isText);
    if (colorGroup) colorGroup.classList.remove("hidden");
    styleStack.querySelectorAll(".style-group.text-only").forEach((el) => {
      el.classList.toggle("hidden", !isText);
    });
    styleStack.querySelectorAll(".style-group.arrow-only").forEach((el) => {
      el.classList.toggle("hidden", !isArrow);
    });

    collapseDividers();
  }

  // Hide dividers so none ever stack up empty: show exactly one divider
  // between each pair of consecutive VISIBLE groups, and none leading or
  // trailing. Operates only on the style-stack's own dividers.
  function collapseDividers() {
    if (!styleStack) return;
    const kids = Array.from(styleStack.children);
    kids.forEach((el) => {
      if (el.classList.contains("style-divider")) el.classList.add("hidden");
    });
    let prevGroupIdx = -1;
    for (let i = 0; i < kids.length; i++) {
      const el = kids[i];
      if (!el.classList.contains("style-group") || el.classList.contains("hidden")) continue;
      if (prevGroupIdx >= 0) {
        for (let j = prevGroupIdx + 1; j < i; j++) {
          if (kids[j].classList.contains("style-divider")) {
            kids[j].classList.remove("hidden");
            break;
          }
        }
      }
      prevGroupIdx = i;
    }
  }

  function applyStylePick(kind, value) {
    if (kind === "stroke") {
      state.style.strokeWidth = Number(value) || 2;
    } else if (kind === "color") {
      if (state.activeTool === "text") state.style.textColor = value;
      else state.style.color = value;
    } else if (kind === "font-size") {
      state.style.fontSize = Number(value) || 16;
    } else if (kind === "font-family") {
      state.style.fontFamily = value;
    } else if (kind === "bold") {
      state.style.bold = !!value;
    } else if (kind === "italic") {
      state.style.italic = !!value;
    } else if (kind === "plain") {
      applyTextPresetToStyle(value === "1" || value === true ? "plain" : DEFAULT_TEXT_PRESET);
    } else if (kind === "text-preset") {
      applyTextPresetToStyle(value);
    } else if (kind === "arrow-heads") {
      state.style.arrowHeads = normalizeArrowHeads(value);
    } else if (kind === "pointer-style") {
      state.style.pointerStyle = normalizePointerStyle(value);
    }
  }

  function markStyleButtonActive(btn) {
    if (!btn) return;
    const kind = btn.getAttribute("data-style");
    if (!kind) return;
    // Within a single group, exactly one button is active. Sibling
    // buttons in the same group share the same data-style attribute.
    styleStack
      .querySelectorAll(`.style-btn[data-style="${kind}"]`)
      .forEach((b) => b.classList.remove("active"));
    btn.classList.add("active");
  }

  if (styleStack) {
    styleStack.addEventListener("click", (e) => {
      const btn = e.target.closest(".style-btn");
      if (!btn) return;
      const kind = btn.getAttribute("data-style");
      if (!kind) return;

      // Toggles (bold / italic) flip independently; single-select groups
      // (color / stroke / font-size / font-family / plain) pick one of a set.
      if (btn.hasAttribute("data-toggle")) {
        const on = !btn.classList.contains("active");
        btn.classList.toggle("active", on);
        applyStylePick(kind, on);
        if (isEditingSelection()) applyStyleToSelection(kind, on);
        e.preventDefault();
        return;
      }

      const value = btn.getAttribute("data-value");
      if (value === null) return;
      // Always update the per-tool default so the next new shape inherits the
      // pick too. When a layer is selected (no create-tool active), also apply
      // it live to that layer and autosave.
      applyStylePick(kind, value);
      if (isEditingSelection()) {
        applyStyleToSelection(kind, value);
      }
      markStyleButtonActive(btn);
      syncStyleStackActive();
      e.preventDefault();
    });
  }

  // ---------------------------------------------------------------------------
  // External API used by native code via WKWebView
  // ---------------------------------------------------------------------------
  // ─── Work Thread (right rail · streamed run log) ───────────────────
  //
  // Swift owns the thread state and pushes whole snapshots via
  // window.talkieMarkup.thread(payload). This side is a dumb renderer +
  // a contextual-rail toggle: thread shows while/after a run, the layer
  // inspector takes over the moment something is selected.

  function updateRailMode() {
    const rail = document.getElementById("inspector-rail");
    const wt = document.getElementById("work-thread");
    if (!rail || !wt) return;
    const showThread = !!state.thread && (state.thread.live || !state.selectedLayerId);
    rail.classList.toggle("thread-active", showThread);
    wt.classList.toggle("hidden", !showThread);
  }

  function renderWorkThread() {
    const t = state.thread;
    const body = document.getElementById("wt-body");
    const foot = document.getElementById("wt-foot");
    if (!t || !body || !foot) { updateRailMode(); return; }

    const dot = document.querySelector("#work-thread .wt-dot");
    const stateLabel = document.querySelector("#work-thread .wt-state");
    if (dot) dot.className = "wt-dot" + (t.live ? " live" : "");
    if (stateLabel) stateLabel.textContent = t.live ? "live" : "done";

    const entries = t.entries || [];
    body.innerHTML = "";
    // Which pass/model is doing this — pinned at the top of the thread.
    if (t.model || t.pass != null || t.attachments) {
      const model = document.createElement("div");
      model.className = "wt-model";
      const passHTML = t.pass != null
        ? '<span class="wt-model-k">pass</span><span class="wt-model-v">' + escHtml(t.pass) + "</span>"
        : "";
      const modelHTML = t.model
        ? '<span class="wt-model-k">model</span><span class="wt-model-v">' + escHtml(t.model) + "</span>"
        : "";
      const taggedHTML = t.attachments
        ? '<span class="wt-model-k">tagged</span><span class="wt-model-v">' + escHtml(t.attachments) + "</span>"
        : "";
      model.innerHTML = passHTML + modelHTML + taggedHTML;
      body.appendChild(model);
    }
    if (t.instruction) {
      const prompt = document.createElement("div");
      prompt.className = "wt-prompt";
      prompt.innerHTML =
        '<span class="wt-prompt-mark">»</span>' +
        '<span class="wt-prompt-text">' + escHtml(t.instruction) + "</span>";
      body.appendChild(prompt);
    }
    // First meta row is the spine's top; first mark row gets an "· actions"
    // kicker so the model's actions read as a distinct section.
    const firstMeta = entries.findIndex((e) => e.kind !== "mark");
    const firstMark = entries.findIndex((e) => e.kind === "mark");
    entries.forEach((e, i) => {
      if (i === firstMark) {
        const kicker = document.createElement("div");
        kicker.className = "wt-kicker";
        kicker.textContent = "· actions";
        body.appendChild(kicker);
      }
      const row = document.createElement("div");
      const isLast = i === entries.length - 1;
      const classes = ["wt-row", e.kind || "meta", e.status || "pending"];
      if (i === firstMeta || i === firstMark) classes.push("first");
      if (isLast && !t.live) classes.push("last");
      // Only the newest mark (added on the current streamed push) animates
      // in — re-rendering the whole list shouldn't re-animate prior rows.
      if (isLast && t.live && e.kind === "mark") classes.push("enter");
      row.className = classes.join(" ");
      row.innerHTML =
        '<span class="wt-spine"></span>' +
        '<span class="wt-node"></span>' +
        '<span class="wt-verb">' + escHtml(e.verb || "") + "</span>" +
        '<span class="wt-detail">' + escHtml(e.detail || "") + "</span>";
      body.appendChild(row);
    });
    if (t.live) {
      const caret = document.createElement("div");
      caret.className = "wt-row caret";
      caret.innerHTML = '<span class="wt-spine half"></span><span class="wt-caret"></span>';
      body.appendChild(caret);
    }

    if (t.live) {
      foot.innerHTML =
        '<span class="wt-dot live"></span>' +
        '<span class="wt-foot-live">' + escHtml(t.statusText || "working…") + "</span>" +
        '<span class="wt-foot-elapsed">' + escHtml(t.elapsed || "") + "</span>";
    } else {
      const summary = t.summary || "";
      const dashIndex = summary.indexOf(" · ");
      const pass = dashIndex > 0 ? summary.slice(0, dashIndex) : summary;
      const rest = dashIndex > 0 ? summary.slice(dashIndex + 3) : "";
      foot.innerHTML =
        '<span class="wt-foot-pass">' + escHtml(pass) + "</span>" +
        (rest ? '<span class="wt-foot-summary">' + escHtml(rest) + "</span>" : "") +
        '<button type="button" class="wt-undo" data-action="undo">↶ undo <span class="kbd">⌘Z</span></button>';
    }
    updateRailMode();
  }

  // Undo from the thread footer reuses the universal pass undo.
  const wtFootEl = document.getElementById("wt-foot");
  if (wtFootEl) {
    wtFootEl.addEventListener("click", (e) => {
      if (e.target.closest('[data-action="undo"]')) undo();
    });
  }

  window.talkieMarkup = {
    thread(payload) {
      state.thread = payload || null;
      renderWorkThread();
    },
    init(payload) {
      state.sessionId = payload.sessionId;
      state.imageURL = payload.imageURL;
      const imageSource = payload.imageDataURL || payload.imageURL;
      loadImage(imageSource).then((img) => {
        state.image = img;
        installDocument(payload.document || state.document);
        resizeCanvasToHost();
        fitViewportToCanvas();
        render();
        post("markup.ready", { sessionId: state.sessionId });
      }).catch(() => {
        post("markup.ready", { sessionId: state.sessionId, error: "image_load_failed" });
      });
    },
    push(payload) {
      if (payload.document) {
        // Agent passes are mutations too — snapshot so the user can
        // undo the whole pass with one ⌘Z (or one tap on the global history
        // control).
        snapshotForUndo();
        installDocument(payload.document, { convertNewImageBasisLayers: true });
      }
      render();
    },
    exportDocument() { return attachViewportToDocument(state.document); },
    exportMessageLayers() {
      return state.document.layers.filter((layer) => state.messageLayerIds.has(layer.id));
    },
    clearSelection() { state.selectedLayerId = null; render(); },
    clearMessageLayers() { clearTaggedMessageLayers(); },
    removeMessageLayer(id) { removeTaggedMessageLayer(id); },
    save() { requestSave(); },
    undo() { return undo(); },
    redo() { return redo(); },
  };

  // Inspector editing — the inspector is the per-layer editor. Its controls
  // carry data-insp-style / data-insp-value; apply them to the selected layer.
  // Delegated on the body element so it survives renderInspector() rebuilds.
  const inspectorBodyEl = document.getElementById("inspector-body");
  if (inspectorBodyEl) {
    inspectorBodyEl.addEventListener("click", (e) => {
      const btn = e.target.closest("button[data-insp-style]");
      if (!btn) return;
      const kind = btn.getAttribute("data-insp-style");
      let value = btn.getAttribute("data-insp-value");
      if (btn.hasAttribute("data-insp-toggle")) {
        value = !btn.classList.contains("active");
      }
      if (applyStyleToSelection(kind, value)) renderInspector();
    });
    inspectorBodyEl.addEventListener("keydown", (e) => {
      const input = e.target.closest("input[data-insp-text]");
      if (!input) return;
      e.stopPropagation();
      if (e.key === "Enter") {
        e.preventDefault();
        applyStyleToSelection(input.getAttribute("data-insp-style") || "text", input.value);
        input.blur();
      } else if (e.key === "Escape") {
        e.preventDefault();
        renderInspector();
      }
    });
    // Text fields commit on change (blur / enter) so editing doesn't snapshot
    // per keystroke or steal focus on every character.
    inspectorBodyEl.addEventListener("change", (e) => {
      const input = e.target.closest("input[data-insp-text]");
      if (!input) return;
      applyStyleToSelection(input.getAttribute("data-insp-style") || "text", input.value);
    });
  }

  // ---------------------------------------------------------------------------
  // Toolbar — global history + tool selection
  // ---------------------------------------------------------------------------
  toolToolbar.addEventListener("click", (e) => {
    const saveButton = e.target.closest('[data-action="save"]');
    if (saveButton) {
      requestSave();
      e.preventDefault();
      return;
    }

    const historyButton = e.target.closest(".history-btn");
    if (historyButton && !historyButton.disabled) {
      const action = historyButton.getAttribute("data-action");
      if (action === "undo") undo();
      else if (action === "redo") redo();
      e.preventDefault();
      return;
    }

    const btn = e.target.closest(".tool-btn");
    if (!btn || btn.disabled) return;
    const tool = btn.getAttribute("data-tool");
    if (tool === null) return;

    // Viewport / cursor tools — always available, never shape conversions.
    if (tool === "select") {
      setActiveTool(null);
      return;
    }
    if (tool === "hand") {
      setActiveTool(state.activeTool === "hand" ? null : "hand");
      return;
    }

    // Editing-selection mode: a shape button restyles the SELECTED layer's
    // shape in place (rect⇄blur, arrow⇄line) instead of arming a draw tool.
    // Clicking the layer's current shape is a no-op; clicking the text tool
    // (or any non-convertible target) falls through to normal tool arming.
    if (isEditingSelection()) {
      const layer = selectedLayer();
      const current = layerShape(layer);
      if (tool === current) return; // already this shape
      if (canConvertSelectionTo(tool)) {
        convertSelectionTo(tool);
        syncToolbarState();
        return;
      }
      // Non-convertible (e.g. text): arming the tool drops the selection edit.
      state.selectedLayerId = null;
    }

    setActiveTool(state.activeTool === tool ? null : tool);
  });

  // ---------------------------------------------------------------------------
  // Canvas zoom cluster — viewport actions
  //
  // Lives over the canvas (floating bottom-right). Handles zoom in / out / fit.
  // ---------------------------------------------------------------------------
  if (zoomCluster) {
    zoomCluster.addEventListener("click", (e) => {
      const btn = e.target.closest(".zoom-btn");
      if (!btn) return;
      const action = btn.getAttribute("data-action");
      if (!action) return;
      if (action === "zoom-in") zoomAt(null, null, 1.2);
      else if (action === "zoom-out") zoomAt(null, null, 1 / 1.2);
      else if (action === "zoom-fit") {
        fitViewportToCanvas();
        render();
      }
      e.preventDefault();
    });
  }

  // ---------------------------------------------------------------------------
  // Inline text editor
  //
  // A real, focused <input> floated over the canvas at the click point. The
  // committed value becomes the label layer's text. Replaces window.prompt,
  // which silently no-ops inside WKWebView. While it's focused the global
  // keydown guard (target.tagName === "INPUT") keeps tool shortcuts from
  // firing, so typing "rect"/"text"/etc. lands as characters, not tools.
  // ---------------------------------------------------------------------------
  let activeTextEditor = null;

  function beginTextEdit(layer, screenX, screenY, isNew) {
    cancelTextEdit();

    const input = document.createElement("input");
    input.type = "text";
    input.value = layer.text || "";
    input.setAttribute("data-inline-text", "1");
    const fs = typeof layer.fontSize === "number" ? layer.fontSize : 16;
    const textStyle = labelStyle(layer);
    Object.assign(input.style, {
      position: "fixed",
      left: Math.round(screenX) + "px",
      top: Math.round(screenY) + "px",
      zIndex: "9999",
      minWidth: "120px",
      font:
        (layer.bold ? "600 " : "") +
        (layer.italic ? "italic " : "") +
        fs +
        "px " +
        fontFamilyCSS(layer.fontFamily),
      color: textStyle.textColor || layer.color || "#111",
      background: textStyle.plain
        ? "rgba(255,255,255,0.97)"
        : hexColor(textStyle.backgroundColor, Math.max(0.92, textStyle.backgroundAlpha)),
      border: "1px solid rgba(0,0,0,0.28)",
      borderRadius: "6px",
      boxShadow: "0 2px 10px rgba(0,0,0,0.18)",
      padding: "3px 7px",
      outline: "none",
    });
    document.body.appendChild(input);
    input.focus();
    input.select();

    let done = false;
    const commit = (keep) => {
      if (done) return;
      done = true;
      const val = input.value.trim();
      input.remove();
      activeTextEditor = null;
      if (keep && val) {
        layer.text = val;
        debouncedUpdate();
      } else {
        // Empty / cancelled — drop the placeholder layer so a stray click
        // with the text tool never litters the doc with empty labels.
        const idx = state.document.layers.findIndex((l) => l.id === layer.id);
        if (idx >= 0) state.document.layers.splice(idx, 1);
        if (state.selectedLayerId === layer.id) state.selectedLayerId = null;
        if (isNew) debouncedUpdate();
      }
      render();
    };

    input.addEventListener("keydown", (e) => {
      // Keep keystrokes out of the canvas/global handlers entirely.
      e.stopPropagation();
      if (e.key === "Enter") {
        e.preventDefault();
        commit(true);
      } else if (e.key === "Escape") {
        e.preventDefault();
        commit(false);
      }
    });
    input.addEventListener("blur", () => commit(true));
    activeTextEditor = { input, commit };
  }

  function cancelTextEdit() {
    if (activeTextEditor) activeTextEditor.commit(true);
  }

  // ---------------------------------------------------------------------------
  // Canvas interaction
  //
  // Three modes share the same mousedown→mousemove→mouseup path:
  //   1. Create  — activeTool ∈ DRAG_TOOLS → state.creating
  //   2. Click   — activeTool ∈ CLICK_TOOLS → fire once on mousedown
  //   3. Select  — activeTool == null → hit-test, then state.drag (move)
  // ---------------------------------------------------------------------------
  canvas.addEventListener("mousedown", (e) => {
    if (e.button !== 0) return;
    const norm = eventToNorm(e);

    // Pan on Space-drag (any tool) or with the Hand tool armed.
    if (state.isSpaceDown || state.activeTool === "hand") {
      state.panDrag = {
        startX: e.clientX,
        startY: e.clientY,
        panX: state.viewport.panX,
        panY: state.viewport.panY,
      };
      updateCursor();
      e.preventDefault();
      return;
    }

    // (2) Click tools
    if (state.activeTool && CLICK_TOOLS.has(state.activeTool)) {
      if (state.activeTool === "text") {
        // Drop an empty label at the click point and open an inline,
        // focused editor right there. (window.prompt is a no-op in
        // WKWebView — it returns null with no dialog, which is why the
        // text box and your typing never appeared.)
        const h = 0.05;
        const layer = newLabelLayer(
          { x: norm.nx, y: norm.ny - h, width: 0.12, height: h },
          "",
        );
        snapshotForUndo();
        state.document.layers.push(layer);
        state.selectedLayerId = layer.id;
        render();
        beginTextEdit(layer, e.clientX, e.clientY, /*isNew*/ true);
        e.preventDefault();
      }
      return;
    }

    // (1) Drag-to-create tools
    if (state.activeTool && DRAG_TOOLS.has(state.activeTool)) {
      state.creating = { tool: state.activeTool, start: norm, current: norm, startedAt: e.timeStamp };
      e.preventDefault();
      return;
    }

    // (3) Select / drag existing layer
    //
    // For an already-selected segment (arrow / line), an endpoint handle
    // takes priority so you can grab an end even when it's right on the body.
    const size = viewportSize();

    // Option/Alt + click on a layer duplicates it and drags the copy —
    // the original stays put (standard alt-drag-to-duplicate idiom). Takes
    // priority over endpoint/handle grabs so Option always means "clone".
    if (e.altKey) {
      const dupHit = hitTest(norm);
      if (dupHit) {
        snapshotForUndo();
        const copy = duplicateLayer(dupHit);
        state.document.layers.push(copy);
        state.selectedLayerId = copy.id;
        if (copy.frame) {
          state.drag = {
            layerId: copy.id,
            startX: e.clientX,
            startY: e.clientY,
            orig: Object.assign({}, copy.frame),
            zoom: state.viewport.zoom,
            w: state.viewport.width,
            h: state.viewport.height,
          };
        } else if (copy.from && copy.to) {
          state.segDrag = makeSegDrag(copy, "both", e, size);
        }
        debouncedUpdate();
        render();
        e.preventDefault();
        return;
      }
    }

    const already = selectedLayer();
    if (already && already.frame) {
      const handle = frameHandleAt(norm, already);
      if (handle) {
        state.frameResize = makeFrameResize(already, handle, e, size);
        canvas.style.cursor = cursorForFrameHandle(handle);
        e.preventDefault();
        return;
      }
    }
    if (already && already.from && already.to) {
      const handle = segmentEndpointAt(norm, already);
      if (handle) {
        state.segDrag = makeSegDrag(already, handle, e, size);
        e.preventDefault();
        return;
      }
    }

    const hit = hitTest(norm);
    state.selectedLayerId = hit ? hit.id : null;
    if (hit && hit.frame) {
      // Snapshot before the move; if the user doesn't actually drag,
      // the snapshot just becomes harmless redundancy. Undo will skip
      // identical states quickly enough at HISTORY_LIMIT = 50.
      snapshotForUndo();
      state.drag = {
        layerId: hit.id,
        startX: e.clientX,
        startY: e.clientY,
        orig: Object.assign({}, hit.frame),
        zoom: state.viewport.zoom,
        w: state.viewport.width,
        h: state.viewport.height,
      };
    } else if (hit && hit.from && hit.to) {
      // Whole-segment move — drag the body to translate both endpoints.
      // (An endpoint grab on the freshly-selected segment is also possible
      //  on this same press: prefer the handle if the cursor is on one.)
      const handle = segmentEndpointAt(norm, hit) || "both";
      state.segDrag = makeSegDrag(hit, handle, e, size);
    }
    render();
  });

  /** Build the frame-resize descriptor. Snapshot is lazy so clicking a handle
   *  without moving does not add an undo step. */
  function makeFrameResize(layer, handle, e, size) {
    return {
      layerId: layer.id,
      handle,
      startX: e.clientX,
      startY: e.clientY,
      zoom: state.viewport.zoom,
      w: size.w,
      h: size.h,
      orig: Object.assign({}, layer.frame),
      didSnapshot: false,
    };
  }

  /** Build the segment-edit drag descriptor. Snapshot is taken lazily on the
   *  first actual move (see mousemove) so a plain select-click on a segment
   *  doesn't push an undo state. */
  function makeSegDrag(layer, handle, e, size) {
    return {
      layerId: layer.id,
      handle, // "from" | "to" | "both"
      startX: e.clientX,
      startY: e.clientY,
      zoom: state.viewport.zoom,
      w: size.w,
      h: size.h,
      origFrom: Object.assign({}, layer.from),
      origTo: Object.assign({}, layer.to),
      didSnapshot: false,
    };
  }

  // Double-click an existing label to re-open the inline editor in place.
  canvas.addEventListener("dblclick", (e) => {
    const norm = eventToNorm(e);
    const hit = hitTest(norm);
    if (hit && hit.kind === "label") {
      setActiveTool(null);
      state.selectedLayerId = hit.id;
      render();
      beginTextEdit(hit, e.clientX, e.clientY, /*isNew*/ false);
      e.preventDefault();
    }
  });

  canvas.addEventListener("wheel", (e) => {
    if (e.metaKey || e.ctrlKey) {
      e.preventDefault();
      const factor = Math.exp(-e.deltaY * 0.0015);
      zoomAt(e.clientX, e.clientY, factor);
      return;
    }
    e.preventDefault();
    state.viewport.panX -= e.deltaX;
    state.viewport.panY -= e.deltaY;
    render();
  }, { passive: false });

  window.addEventListener("resize", () => {
    resizeCanvasToHost();
    render();
  });

  window.addEventListener("mousemove", (e) => {
    if (state.panDrag) {
      state.viewport.panX = state.panDrag.panX + (e.clientX - state.panDrag.startX);
      state.viewport.panY = state.panDrag.panY + (e.clientY - state.panDrag.startY);
      render();
      return;
    }
    if (state.creating) {
      let norm = eventToNorm(e);
      // Shift + arrow/line = axis snap (horizontal or vertical only).
      if (e.shiftKey && (state.creating.tool === "arrow" || state.creating.tool === "line")) {
        norm = snapToAxis(state.creating.start, norm);
      }
      state.creating.current = norm;
      render();
      return;
    }
    if (state.frameResize) {
      const resize = state.frameResize;
      const layer = state.document.layers.find((l) => l.id === resize.layerId);
      if (!layer || !layer.frame) return;
      if (!resize.didSnapshot) {
        snapshotForUndo();
        resize.didSnapshot = true;
      }
      const dx = (e.clientX - resize.startX) / resize.zoom / resize.w;
      const dy = (e.clientY - resize.startY) / resize.zoom / resize.h;
      layer.frame = resizeFrameFromHandle(
        resize.orig,
        resize.handle,
        dx,
        dy,
        { w: resize.w, h: resize.h }
      );
      layer.author = "user";
      canvas.style.cursor = cursorForFrameHandle(resize.handle);
      render();
      return;
    }
    if (state.segDrag) {
      const seg = state.segDrag;
      const layer = state.document.layers.find((l) => l.id === seg.layerId);
      if (!layer || !layer.from || !layer.to) return;
      // Lazy snapshot — only once movement actually begins, so selecting a
      // segment without dragging it doesn't pollute the undo stack.
      if (!seg.didSnapshot) {
        snapshotForUndo();
        seg.didSnapshot = true;
      }
      const dx = (e.clientX - seg.startX) / seg.zoom / seg.w;
      const dy = (e.clientY - seg.startY) / seg.zoom / seg.h;
      if (seg.handle === "from") {
        let pt = { x: seg.origFrom.x + dx, y: seg.origFrom.y + dy };
        if (e.shiftKey) pt = snapPointToAxis(seg.origTo, pt);
        layer.from = pt;
      } else if (seg.handle === "to") {
        let pt = { x: seg.origTo.x + dx, y: seg.origTo.y + dy };
        if (e.shiftKey) pt = snapPointToAxis(seg.origFrom, pt);
        layer.to = pt;
      } else {
        layer.from = { x: seg.origFrom.x + dx, y: seg.origFrom.y + dy };
        layer.to = { x: seg.origTo.x + dx, y: seg.origTo.y + dy };
      }
      layer.author = "user";
      render();
      return;
    }
    if (!state.drag) {
      updateSelectionHoverCursor(e);
      return;
    }
    const layer = state.document.layers.find((l) => l.id === state.drag.layerId);
    if (!layer || !layer.frame) return;
    const dx = (e.clientX - state.drag.startX) / state.drag.zoom / state.drag.w;
    const dy = (e.clientY - state.drag.startY) / state.drag.zoom / state.drag.h;
    layer.frame.x = state.drag.orig.x + dx;
    layer.frame.y = state.drag.orig.y + dy;
    layer.author = "user";
    render();
  });

  window.addEventListener("mouseup", () => {
    if (state.panDrag) {
      state.panDrag = null;
      updateCursor();
      return;
    }
    if (state.creating) {
      const c = state.creating;
      state.creating = null;
      const pxDist = Math.hypot(
        (c.current.nx - c.start.nx) * state.viewport.width,
        (c.current.ny - c.start.ny) * state.viewport.height,
      );
      if (pxDist < MIN_DRAG_PX) {
        render();
        return; // discard accidental tiny drags
      }
      let layer = null;
      if (c.tool === "rect") {
        layer = newRectLayer(normalizedFrame(c.start, c.current));
      } else if (c.tool === "arrow" || c.tool === "line") {
        layer = newArrowLayer(
          { x: c.start.nx, y: c.start.ny },
          { x: c.current.nx, y: c.current.ny },
          c.tool === "line",
        );
      } else if (c.tool === "blur") {
        layer = newBlurPlaceholderLayer(normalizedFrame(c.start, c.current));
      } else if (c.tool === "clone") {
        layer = newPatchLayer(normalizedFrame(c.start, c.current));
      }
      if (layer) {
        snapshotForUndo();
        state.document.layers.push(layer);
        state.selectedLayerId = layer.id;
        // Drop back to SELECT after creating a shape so the next
        // click on the canvas adjusts the shape that was just drawn
        // instead of stamping another one. Was: tool stayed sticky
        // and accidental double-creates were common.
        setActiveTool(null);
        debouncedUpdate();
        render();
      }
      return;
    }
    if (state.frameResize) {
      const moved = state.frameResize.didSnapshot;
      state.frameResize = null;
      if (moved) debouncedUpdate();
      updateCursor();
      return;
    }
    if (state.segDrag) {
      const moved = state.segDrag.didSnapshot;
      state.segDrag = null;
      if (moved) debouncedUpdate(); // only persist if the segment actually changed
      return;
    }
    if (state.drag) {
      state.drag = null;
      debouncedUpdate();
    }
  });

  function showLayerPopover(clientX, clientY) {
    const layer = selectedLayer();
    if (!layer) return;
    const attachButton = popover.querySelector('[data-action="attach"]');
    if (attachButton) {
      attachButton.textContent = state.messageLayerIds.has(layer.id)
        ? "Remove from next message"
        : "Add to next message";
    }
    popover.classList.remove("hidden");
    popover.style.left = clientX + "px";
    popover.style.top = clientY + "px";
  }

  canvas.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const hit = hitTest(eventToNorm(e));
    if (hit) {
      state.selectedLayerId = hit.id;
      setActiveTool(null);
      render();
    }
    if (!state.selectedLayerId) return;
    showLayerPopover(e.clientX, e.clientY);
  });

  // Right-click on a layer ROW in the sidebar opens the same menu — and we
  // suppress WebKit's default context menu (Reload / Inspect Element / the
  // text-edit menu) everywhere else, so the custom layer menu is the only
  // thing a right-click ever surfaces.
  document.addEventListener("contextmenu", (e) => {
    if (e.defaultPrevented) return; // canvas handler already handled this one
    e.preventDefault();
    const row = e.target.closest ? e.target.closest(".layer-row") : null;
    const id = row && row.dataset ? row.dataset.layerId : null;
    if (!id) return;
    state.selectedLayerId = id;
    setActiveTool(null);
    render();
    showLayerPopover(e.clientX, e.clientY);
  });

  popover.addEventListener("click", (e) => {
    const action = e.target.getAttribute("data-action");
    if (!action || !state.selectedLayerId) return;
    const idx = state.document.layers.findIndex((l) => l.id === state.selectedLayerId);
    if (idx < 0) return;
    if (action === "attach") {
      toggleMessageLayer(state.document.layers[idx]);
      popover.classList.add("hidden");
      return;
    }
    snapshotForUndo();
    if (action === "delete") {
      const removedAttachment = state.messageLayerIds.delete(state.document.layers[idx].id);
      state.document.layers.splice(idx, 1);
      state.selectedLayerId = null;
      if (removedAttachment) postMessageLayers();
    } else if (action === "toggle") {
      state.document.layers[idx].visible = !state.document.layers[idx].visible;
    }
    popover.classList.add("hidden");
    debouncedUpdate();
    render();
  });

  // Dismiss popover on outside click
  document.addEventListener("mousedown", (e) => {
    if (!popover.classList.contains("hidden") && !popover.contains(e.target)) {
      popover.classList.add("hidden");
    }
  });

  // ---------------------------------------------------------------------------
  // Keyboard shortcuts — V select · M toggle toolbar · Space pan · Backspace delete · Esc cancel
  // ---------------------------------------------------------------------------
  document.addEventListener("keydown", (e) => {
    // Skip when focus is inside an editable element (text labels, popovers).
    const target = e.target;
    if (target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)) {
      return;
    }

    // Standard macOS ⌘Z / ⇧⌘Z — universal undo/redo. Handled before the
    // modifier guard since this is the one bound shortcut that uses a modifier.
    if (e.metaKey && !e.ctrlKey && !e.altKey && (e.key === "z" || e.key === "Z")) {
      if (e.shiftKey) redo();
      else undo();
      e.preventDefault();
      return;
    }

    // ⌘S — explicit save. Fires when the WKWebView (canvas) has key focus;
    // the native SAVE button's ⌘S keyEquivalent covers the case where the
    // prompt field is focused instead. Either way Swift persists + confirms.
    if ((e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey && (e.key === "s" || e.key === "S")) {
      requestSave();
      e.preventDefault();
      return;
    }

    if (e.metaKey || e.ctrlKey || e.altKey) return;

    if (e.code === "Space") {
      state.isSpaceDown = true;
      updateCursor();
      e.preventDefault();
      return;
    }

    // Tab / Shift+Tab — step selection through the layers (the list nav that
    // used to eat Tab is suppressed in Swift while markup is active). Drops
    // any active tool so the cycled layer reads as selected.
    if (e.key === "Tab") {
      const layers = state.document.layers;
      if (layers.length) {
        const cur = layers.findIndex((l) => l.id === state.selectedLayerId);
        let next;
        if (e.shiftKey) next = cur <= 0 ? layers.length - 1 : cur - 1;
        else next = cur === -1 || cur === layers.length - 1 ? 0 : cur + 1;
        setActiveTool(null);
        state.selectedLayerId = layers[next].id;
        render();
      }
      e.preventDefault();
      return;
    }

    if (e.key === "v" || e.key === "V") {
      setActiveTool(null);
      e.preventDefault();
    } else if (e.key === "h" || e.key === "H") {
      setActiveTool(state.activeTool === "hand" ? null : "hand");
      e.preventDefault();
    } else if (e.key === "r" || e.key === "R") {
      setActiveTool("rect");
      e.preventDefault();
    } else if (e.key === "a" || e.key === "A") {
      setActiveTool("arrow");
      e.preventDefault();
    } else if (e.key === "l" || e.key === "L") {
      setActiveTool("line");
      e.preventDefault();
    } else if (e.key === "t" || e.key === "T") {
      setActiveTool("text");
      e.preventDefault();
    } else if (e.key === "b" || e.key === "B") {
      setActiveTool("blur");
      e.preventDefault();
    } else if (e.key === "c" || e.key === "C") {
      setActiveTool("clone");
      e.preventDefault();
    } else if (e.key === "m" || e.key === "M") {
      toolToolbar.classList.toggle("hidden");
      e.preventDefault();
    } else if (e.key === "Escape") {
      if (state.creating) {
        state.creating = null;
        render();
      } else if (state.activeTool) {
        setActiveTool(null);
      } else if (state.selectedLayerId) {
        state.selectedLayerId = null;
        render();
      }
    } else if (e.key === "Backspace" || e.key === "Delete") {
      if (!state.selectedLayerId) return;
      const idx = state.document.layers.findIndex((l) => l.id === state.selectedLayerId);
      if (idx >= 0) {
        snapshotForUndo();
        state.document.layers.splice(idx, 1);
        state.selectedLayerId = null;
        debouncedUpdate();
        render();
        e.preventDefault();
      }
    }
  });

  document.addEventListener("keyup", (e) => {
    if (e.code !== "Space") return;
    state.isSpaceDown = false;
    updateCursor();
    e.preventDefault();
  });

  // ---------------------------------------------------------------------------
  // Resizable rails — drag the splitter columns to size the Layers / Inspector
  // panels. Widths live in CSS vars on .bay-body and persist to localStorage so
  // the layout you tune sticks across sessions.
  // ---------------------------------------------------------------------------
  const bayBody = document.querySelector(".bay-body");
  const RAIL_VARS = { layers: "--layer-w", inspector: "--inspector-w" };
  const RAIL_LIMITS = { layers: [150, 380], inspector: [180, 460] };
  const RAIL_DEFAULT = { layers: 220, inspector: 240 };
  const RAIL_STORAGE_KEY = "talkie.markup.railWidths";
  let railResize = null;

  function railWidth(which) {
    const raw = getComputedStyle(bayBody).getPropertyValue(RAIL_VARS[which]);
    return parseInt(raw, 10) || RAIL_DEFAULT[which];
  }

  function clampRail(which, value) {
    const [min, max] = RAIL_LIMITS[which];
    return Math.max(min, Math.min(max, value));
  }

  function loadRailWidths() {
    try {
      const raw = localStorage.getItem(RAIL_STORAGE_KEY);
      if (!raw) return;
      const stored = JSON.parse(raw);
      ["layers", "inspector"].forEach((which) => {
        if (typeof stored[which] === "number") {
          bayBody.style.setProperty(RAIL_VARS[which], clampRail(which, stored[which]) + "px");
        }
      });
    } catch (e) { /* ignore corrupt prefs */ }
  }

  function persistRailWidths() {
    try {
      localStorage.setItem(RAIL_STORAGE_KEY, JSON.stringify({
        layers: railWidth("layers"),
        inspector: railWidth("inspector"),
      }));
    } catch (e) { /* storage may be unavailable */ }
  }

  if (bayBody) {
    document.querySelectorAll(".rail-resizer").forEach((el) => {
      el.addEventListener("mousedown", (e) => {
        const which = el.getAttribute("data-resize");
        railResize = { which, startX: e.clientX, startW: railWidth(which), el };
        el.classList.add("dragging");
        document.body.style.cursor = "col-resize";
        e.preventDefault();
      });
    });

    window.addEventListener("mousemove", (e) => {
      if (!railResize) return;
      const { which, startX, startW } = railResize;
      // Layers grows as you drag right; the inspector grows as you drag left.
      const delta = which === "layers" ? (e.clientX - startX) : (startX - e.clientX);
      bayBody.style.setProperty(RAIL_VARS[which], clampRail(which, startW + delta) + "px");
      render(); // re-fit the canvas to the new column width
    });

    window.addEventListener("mouseup", () => {
      if (!railResize) return;
      railResize.el.classList.remove("dragging");
      document.body.style.cursor = "";
      railResize = null;
      persistRailWidths();
    });

    loadRailWidths();
  }

  // Initial paint of the style-stack visibility + zoom badge. Both are
  // safe to call before init() — they read live state but write only
  // to the DOM, and start with a sane null-tool / 100% zoom default.
  updateStyleStackVisibility();
  updateHistoryButtons();
  updateZoomDisplay();

})();
