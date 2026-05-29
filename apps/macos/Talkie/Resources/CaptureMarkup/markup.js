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
    activeTool: null,
    image: null,
    /** Existing-layer move drag (the original behaviour) */
    drag: null,
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
      color: "#C47D1C",
      strokeWidth: 2,
      fontSize: 16,
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
  // Undo / redo live in the floating canvas zoom cluster now (the top bar
  // is pure drawing). Query both surfaces so a future relocation doesn't
  // silently lose the enabled-state wiring.
  const undoButton =
    (zoomCluster && zoomCluster.querySelector('[data-action="undo"]')) ||
    toolToolbar.querySelector('[data-action="undo"]');
  const redoButton =
    (zoomCluster && zoomCluster.querySelector('[data-action="redo"]')) ||
    toolToolbar.querySelector('[data-action="redo"]');

  const DEFAULT_COLOR = "#C47D1C";
  // Tools that create a new layer by click-dragging on the canvas
  const DRAG_TOOLS = new Set(["rect", "arrow", "line", "blur"]);
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

  function framePx(layer, w, h) {
    const f = layer.frame;
    if (!f) return null;
    return { x: f.x * w, y: f.y * h, w: f.width * w, h: f.height * h };
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
    } else if (state.isSpaceDown) {
      canvas.style.cursor = "grab";
    } else {
      canvas.style.cursor = state.activeTool == null ? "default" : "crosshair";
    }
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
    return {
      id: uuid(),
      kind: "arrow",
      from,
      to,
      color: state.style.color,
      strokeWidth: state.style.strokeWidth,
      // `label: "line"` is the sentinel the renderer reads to skip the arrowhead.
      // Schema-compliant — `label` is an optional string on CaptureMarkupLayer.
      label: asLine ? "line" : undefined,
      visible: true,
      author: "user",
    };
  }

  function newLabelLayer(frame, text) {
    return {
      id: uuid(),
      kind: "label",
      frame,
      text,
      color: state.style.color,
      fontSize: state.style.fontSize,
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
    if (layer.kind === "arrow") return layer.label === "line" ? "line" : "arrow";
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
        delete layer.label; // arrowhead on
        break;
      case "line":
        layer.kind = "arrow";
        layer.label = "line"; // arrowhead off
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
    } else if (kind === "stroke") {
      layer.strokeWidth = Number(value) || 2;
    } else if (kind === "font-size") {
      layer.fontSize = Number(value) || 16;
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
  function drawArrowhead(x1, y1, x2, y2, w) {
    const headLen = Math.max(8, w / 90);
    const angle = Math.atan2(y2 - y1, x2 - x1);
    ctx.beginPath();
    ctx.moveTo(x2, y2);
    ctx.lineTo(x2 - headLen * Math.cos(angle - Math.PI / 6), y2 - headLen * Math.sin(angle - Math.PI / 6));
    ctx.moveTo(x2, y2);
    ctx.lineTo(x2 - headLen * Math.cos(angle + Math.PI / 6), y2 - headLen * Math.sin(angle + Math.PI / 6));
    ctx.stroke();
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
        // Arrowhead unless the layer is flagged as a line (label === "line").
        if (layer.label !== "line") {
          drawArrowhead(x1, y1, x2, y2, w);
        }
        break;
      }
      case "label": {
        const r = framePx(layer, w, h);
        const text = layer.text || layer.label || "";
        if (!r || !text) break;
        ctx.fillStyle = "rgba(20,24,30,0.84)";
        ctx.fillRect(r.x, r.y, r.w, r.h);
        ctx.fillStyle = "#fff";
        ctx.font = `${Math.max(11, w / 140)}px ui-monospace, monospace`;
        ctx.fillText(text, r.x + 6, r.y + r.h - 6);
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
        ctx.strokeStyle = "#C47D1C";
        ctx.strokeRect(r.x - 2, r.y - 2, r.w + 4, r.h + 4);
        ctx.setLineDash([]);
      } else if (layer.from && layer.to) {
        // Selection marker for line/arrow: bracket the endpoints.
        const x1 = layer.from.x * w, y1 = layer.from.y * h;
        const x2 = layer.to.x * w, y2 = layer.to.y * h;
        ctx.strokeStyle = "#C47D1C";
        ctx.setLineDash([4, 3]);
        ctx.strokeRect(x1 - 4, y1 - 4, 8, 8);
        ctx.strokeRect(x2 - 4, y2 - 4, 8, 8);
        ctx.setLineDash([]);
      }
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
    if (c.tool === "rect" || c.tool === "blur") {
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
        drawArrowhead(x1, y1, x2, y2, w);
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

  /** Fire when the user clicks a layer-row's grip — Swift appends
   *  the layer as an attachment chip in the composer's
   *  attachments row. Explicit user gesture; selection alone
   *  does NOT attach. */
  function postAttach(layer) {
    post("markup.attach", {
      sessionId: state.sessionId,
      selection: {
        id: layer.id,
        kind: layer.kind,
        label: layer.label || layer.text || layer.kind,
      },
    });
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
      row.className = "layer-row" + (layer.id === state.selectedLayerId ? " selected" : "");
      // ⠿ grip is the explicit "attach this layer to the composer"
      // affordance. Click sends a `markup.attach` bridge message
      // (Swift inputBar appends it to the attachments row). The rest
      // of the row is a normal select click. File drag-out is owned by
      // the small native "DRAG PNG" handle over the canvas so it can
      // start an AppKit drag without stealing layer-move drags here.
      row.innerHTML = `<span class="grip" aria-hidden="true" title="Attach to message">⠿</span><span class="dot ${layer.author || "agent"}"></span><span class="layer-row-label">${layer.kind}${layer.label ? " · " + layer.label : ""}</span>`;
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

  function renderInspector() {
    const body = document.getElementById("inspector-body");
    if (!body) return;
    const selected = state.document.layers.find((l) => l.id === state.selectedLayerId);
    if (!selected) {
      body.className = "inspector-empty";
      body.textContent = "Select a layer to inspect.";
      return;
    }
    body.className = "";
    const shape = layerShape(selected);
    const rows = [
      ["shape", shape || selected.kind],
      ["author", selected.author || "agent"],
      ["color", selected.color || "—"],
    ];
    if (shape && shape !== "blur") {
      rows.push(["width", String(typeof selected.strokeWidth === "number" ? selected.strokeWidth : 2)]);
    }
    if (selected.kind === "label") {
      rows.push(["size", String(typeof selected.fontSize === "number" ? selected.fontSize : 16)]);
    }
    if (selected.label && selected.label !== "line" && selected.label !== "BLUR") {
      rows.push(["label", selected.label]);
    }
    if (selected.frame) {
      rows.push(["x", selected.frame.x.toFixed(3)]);
      rows.push(["y", selected.frame.y.toFixed(3)]);
      rows.push(["w", selected.frame.width.toFixed(3)]);
      rows.push(["h", selected.frame.height.toFixed(3)]);
    }
    body.innerHTML = rows
      .map(([k, v]) => `<div class="inspector-row"><span class="k">${k}</span><span class="v">${v}</span></div>`)
      .join("");
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
    return state.activeTool == null && !!selectedLayer();
  }

  function syncToolbarState() {
    const editing = isEditingSelection();
    const layer = editing ? selectedLayer() : null;
    const selShape = layer ? layerShape(layer) : null;

    // Shape buttons: in edit mode highlight the layer's shape and disable
    // conversions that don't map cleanly. In draw mode highlight the active
    // create-tool as before.
    toolToolbar.querySelectorAll(".tool-btn[data-tool]").forEach((btn) => {
      const tool = btn.getAttribute("data-tool");
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
    const color = layer ? layer.color : state.style.color;
    const stroke = layer
      ? (typeof layer.strokeWidth === "number" ? layer.strokeWidth : 2)
      : state.style.strokeWidth;
    const font = layer
      ? (typeof layer.fontSize === "number" ? layer.fontSize : 16)
      : state.style.fontSize;

    setGroupActiveByValue("color", color, true);
    setGroupActiveByValue("stroke", String(stroke), false);
    setGroupActiveByValue("font-size", String(font), false);
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
  //   · text tool                          → font-size + color
  //   · null tool (select mode)            → all groups visible
  //
  // Clicking a swatch / pip updates `state.style`, which is the source
  // of truth used by the layer factories when a new layer is created.
  // ---------------------------------------------------------------------------
  function updateStyleStackVisibility() {
    if (!styleStack) return;

    // In "editing selection" mode the relevant groups follow the selected
    // layer's kind; otherwise they follow the active create-tool.
    let isText;
    let isShape;
    if (isEditingSelection()) {
      const layer = selectedLayer();
      isText = layer && layer.kind === "label";
      isShape = !!layerShape(layer); // rect / arrow / line / blur
    } else {
      const tool = state.activeTool;
      isText = tool === "text";
      isShape = tool === "rect" || tool === "arrow" || tool === "line" || tool === "blur";
    }

    const strokeGroup = styleStack.querySelector('[data-group="stroke"]');
    const fontDivider = styleStack.querySelector('[data-group="font-divider"]');
    const fontGroup = styleStack.querySelector('[data-group="font-size"]');

    // Stroke width is meaningless for text labels; hide it for text.
    if (strokeGroup) strokeGroup.classList.toggle("hidden", !!isText);
    // Font size only applies to text labels; hide it for shapes. The null /
    // nothing-selected defaults panel keeps everything visible.
    if (fontGroup) fontGroup.classList.toggle("hidden", !!isShape);
    if (fontDivider) fontDivider.classList.toggle("hidden", !!isShape);
  }

  function applyStylePick(kind, value) {
    if (kind === "stroke") {
      state.style.strokeWidth = Number(value) || 2;
    } else if (kind === "color") {
      state.style.color = value;
    } else if (kind === "font-size") {
      state.style.fontSize = Number(value) || 16;
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
      const value = btn.getAttribute("data-value");
      if (!kind || value === null) return;
      // Always update the per-tool default so the next new shape inherits the
      // pick too. When a layer is selected (no create-tool active), also apply
      // it live to that layer and autosave.
      applyStylePick(kind, value);
      if (isEditingSelection()) {
        applyStyleToSelection(kind, value);
      }
      markStyleButtonActive(btn);
      e.preventDefault();
    });
  }

  // ---------------------------------------------------------------------------
  // External API used by native code via WKWebView
  // ---------------------------------------------------------------------------
  window.talkieMarkup = {
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
        // undo the whole pass with one ⌘Z (or one tap on the canvas
        // back button).
        snapshotForUndo();
        installDocument(payload.document, { convertNewImageBasisLayers: true });
      }
      render();
    },
    exportDocument() { return attachViewportToDocument(state.document); },
    clearSelection() { state.selectedLayerId = null; render(); },
    save() { requestSave(); },
    undo() { return undo(); },
    redo() { return redo(); },
  };

  // ---------------------------------------------------------------------------
  // Toolbar — tool selection
  // ---------------------------------------------------------------------------
  toolToolbar.addEventListener("click", (e) => {
    const btn = e.target.closest(".tool-btn");
    if (!btn || btn.disabled) return;
    const tool = btn.getAttribute("data-tool");
    if (tool === null) return;

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
  // Canvas zoom cluster — viewport + history actions
  //
  // Lives over the canvas (floating bottom-right) so the top toolbar
  // stays pure drawing. Handles zoom in / out / fit + undo + redo.
  // ---------------------------------------------------------------------------
  if (zoomCluster) {
    zoomCluster.addEventListener("click", (e) => {
      const btn = e.target.closest(".zoom-btn");
      if (!btn) return;
      const action = btn.getAttribute("data-action");
      if (!action) return;
      if (action === "undo") undo();
      else if (action === "redo") redo();
      else if (action === "zoom-in") zoomAt(null, null, 1.2);
      else if (action === "zoom-out") zoomAt(null, null, 1 / 1.2);
      else if (action === "zoom-fit") {
        fitViewportToCanvas();
        render();
      }
      e.preventDefault();
    });
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

    if (state.isSpaceDown) {
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
        const text = window.prompt("Label text", "");
        if (text && text.trim()) {
          const w = Math.min(0.25, Math.max(0.05, text.length * 0.012));
          const h = 0.05;
          const layer = newLabelLayer(
            { x: norm.nx, y: norm.ny - h, width: w, height: h },
            text.trim(),
          );
          snapshotForUndo();
          state.document.layers.push(layer);
          state.selectedLayerId = layer.id;
          debouncedUpdate();
          render();
        }
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
    }
    render();
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
    if (!state.drag) return;
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
    if (state.drag) {
      state.drag = null;
      debouncedUpdate();
    }
  });

  // ---------------------------------------------------------------------------
  // Context menu (existing — kept intact)
  // ---------------------------------------------------------------------------
  canvas.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    if (!state.selectedLayerId) return;
    popover.classList.remove("hidden");
    popover.style.left = e.clientX + "px";
    popover.style.top = e.clientY + "px";
  });

  popover.addEventListener("click", (e) => {
    const action = e.target.getAttribute("data-action");
    if (!action || !state.selectedLayerId) return;
    const idx = state.document.layers.findIndex((l) => l.id === state.selectedLayerId);
    if (idx < 0) return;
    snapshotForUndo();
    if (action === "delete") {
      state.document.layers.splice(idx, 1);
      state.selectedLayerId = null;
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

    // ⌘Z / ⌘⇧Z (and control variants) — universal undo/redo. Handled before the modifier guard
    // since this is the one bound shortcut that uses a modifier.
    if ((e.metaKey || e.ctrlKey) && !e.altKey && (e.key === "z" || e.key === "Z")) {
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

    if (e.key === "v" || e.key === "V") {
      setActiveTool(null);
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

  // Initial paint of the style-stack visibility + zoom badge. Both are
  // safe to call before init() — they read live state but write only
  // to the DOM, and start with a sane null-tool / 100% zoom default.
  updateStyleStackVisibility();
  updateZoomDisplay();

})();
