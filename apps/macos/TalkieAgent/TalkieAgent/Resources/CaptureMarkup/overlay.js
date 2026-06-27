(() => {
  const canvas = document.getElementById("overlay-canvas");
  const ctx = canvas.getContext("2d");
  const dock = document.getElementById("markup-dock");
  const toolbar = document.getElementById("toolbar");
  const stylePanel = document.getElementById("style-panel");
  const windowChrome = document.querySelectorAll(".window-close, .surface-actions");
  const query = new URLSearchParams(window.location.search);
  const initialContext = query.get("context") === "desktopInk" ? "desktopInk" : "recording";

  const state = {
    tool: "ink",
    mode: "agent",
    color: "#D03A1C",
    strokeWidth: 4,
    noteStyle: "sticky",
    lineStyle: "solid",
    arrowStyle: "straight",
    styleOpen: true,
    context: initialContext,
    layers: [],
    redoStack: [],
    creating: null,
    noteEditor: null,
    selectedLayerId: null,
    dragging: null,
    lastPointer: { x: 0.5, y: 0.5 },
    startedAt: performance.now(),
  };

  const noteStylePresets = {
    sticky: {
      id: "sticky",
      textColor: "#1C1D21",
      backgroundColor: "#F8F6F2",
      backgroundAlpha: 0.97,
      borderColor: "#DFA13A",
      borderAlpha: 0.30,
      borderWidth: 1,
      cornerRadius: 5,
      fontSize: 14,
      lineHeight: 20,
      paddingX: 11,
      paddingY: 9,
      bold: false,
      shadow: true,
      shadowColor: "rgba(7, 9, 13, 0.16)",
      shadowBlur: 10,
      shadowOffsetY: 3,
      editorBackground: "rgba(248, 246, 242, 0.97)",
      editorShadow: "0 4px 14px rgba(7, 9, 13, 0.18)",
    },
    bubble: {
      id: "bubble",
      textColor: "#1A1D26",
      backgroundColor: "#FFFFFF",
      backgroundAlpha: 0.96,
      borderColor: "#C5CCD6",
      borderAlpha: 0.55,
      borderWidth: 1,
      cornerRadius: 8,
      fontSize: 14,
      lineHeight: 20,
      paddingX: 12,
      paddingY: 9,
      bold: false,
      shadow: true,
      shadowColor: "rgba(14, 18, 28, 0.12)",
      shadowBlur: 10,
      shadowOffsetY: 3,
    },
    glass: {
      id: "glass",
      textColor: "#F2F3F5",
      backgroundColor: "#16181D",
      backgroundAlpha: 0.92,
      borderColor: "#FFFFFF",
      borderAlpha: 0.12,
      borderWidth: 1,
      cornerRadius: 6,
      fontSize: 14,
      lineHeight: 20,
      paddingX: 12,
      paddingY: 9,
      bold: false,
      shadow: true,
      shadowColor: "rgba(0, 0, 0, 0.22)",
      shadowBlur: 12,
      shadowOffsetY: 4,
    },
  };

  const lineStylePresets = {
    solid: {
      id: "solid",
      lineDash: [],
      pointerEnd: "open",
      pointerStyle: "open",
      shadow: false,
    },
    dashed: {
      id: "dashed",
      lineDash: [12, 9],
      pointerEnd: "open",
      pointerStyle: "open",
      shadow: false,
    },
    glow: {
      id: "glow",
      lineDash: [],
      pointerEnd: "filled",
      pointerStyle: "filled",
      shadow: true,
      shadowColor: "rgba(255, 255, 255, 0.42)",
      shadowBlur: 14,
      shadowOffsetY: 4,
    },
  };

  const arrowStylePresets = {
    straight: {
      id: "straight",
    },
    curved: {
      id: "curved",
      curveOffset: 0.2,
    },
    shaped: {
      id: "shaped",
      pointerEnd: "filled",
      pointerStyle: "filled",
    },
  };

  const noteStyleLabels = {
    sticky: "Sticky",
    bubble: "Bubble",
    glass: "Glass",
  };

  const lineStyleLabels = {
    solid: "Solid",
    dashed: "Dash",
    glow: "Glow",
  };

  const arrowStyleLabels = {
    straight: "Straight",
    curved: "Curve",
    shaped: "Block",
  };

  const toolLabels = {
    select: "Select",
    ink: "Pen",
    rect: "Rectangle",
    ellipse: "Circle",
    line: "Line",
    arrow: "Arrow",
    note: "Note",
  };

  const optionTools = new Set(["ink", "rect", "ellipse", "line", "arrow", "note"]);

  const toolChordTimeoutMs = 1600;
  let toolChordActive = false;
  let toolChordTimer = null;

  const angleSnapStep = Math.PI / 12;

  function shortcutToken(event) {
    if (event.code && event.code.startsWith("Key")) {
      return event.code.slice(3).toLowerCase();
    }
    if (event.code && event.code.startsWith("Digit")) {
      return event.code.slice(5);
    }
    switch (event.code || event.key) {
    case "Tab":
      return "tab";
    case "Space":
      return "space";
    case "Escape":
      return "escape";
    default:
      return String(event.key || "").toLowerCase();
    }
  }

  function beginToolChord() {
    toolChordActive = true;
    if (toolChordTimer) window.clearTimeout(toolChordTimer);
    toolChordTimer = window.setTimeout(clearToolChord, toolChordTimeoutMs);
  }

  function clearToolChord() {
    toolChordActive = false;
    if (toolChordTimer) {
      window.clearTimeout(toolChordTimer);
      toolChordTimer = null;
    }
  }

  function isToolChordStart(event) {
    return event.altKey && !event.metaKey && !event.ctrlKey && shortcutToken(event) === "t";
  }

  function post(name, payload = {}) {
    const handler = window.webkit
      && window.webkit.messageHandlers
      && window.webkit.messageHandlers.talkie;
    if (!handler) return;
    handler.postMessage(Object.assign({ name }, payload));
  }

  function resizeCanvas() {
    const scale = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(window.innerWidth * scale));
    canvas.height = Math.max(1, Math.round(window.innerHeight * scale));
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    render();
  }

  function nowSeconds() {
    return Math.max(0, (performance.now() - state.startedAt) / 1000);
  }

  function uuid() {
    if (window.crypto && window.crypto.randomUUID) {
      return window.crypto.randomUUID();
    }
    return "layer-" + Math.random().toString(16).slice(2) + Date.now().toString(16);
  }

  function eventPoint(event) {
    const rect = canvas.getBoundingClientRect();
    return {
      x: Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width)),
      y: Math.min(1, Math.max(0, (event.clientY - rect.top) / rect.height)),
    };
  }

  function currentNotePreset() {
    return noteStylePresets[state.noteStyle] || noteStylePresets.sticky;
  }

  function currentLinePreset() {
    return lineStylePresets[state.lineStyle] || lineStylePresets.solid;
  }

  function currentArrowPreset() {
    return arrowStylePresets[state.arrowStyle] || arrowStylePresets.straight;
  }

  function colorWithAlpha(hexColor, alpha) {
    const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hexColor || "");
    if (!match) return hexColor || "transparent";
    const r = parseInt(match[1], 16);
    const g = parseInt(match[2], 16);
    const b = parseInt(match[3], 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  function applyNotePresetToEditor(element, preset) {
    if (!element || !preset) return;
    element.style.color = preset.textColor;
    element.style.background = preset.editorBackground || colorWithAlpha(preset.backgroundColor, preset.backgroundAlpha || 1);
    element.style.borderColor = colorWithAlpha(preset.borderColor, preset.borderAlpha || 1);
    element.style.borderWidth = `${Number(preset.borderWidth || 1)}px`;
    element.style.borderRadius = `${Number(preset.cornerRadius || 5)}px`;
    element.style.padding = `${Number(preset.paddingY || 11)}px ${Number(preset.paddingX || 14)}px`;
    element.style.font = noteFont(preset);
    element.style.boxShadow = preset.shadow
      ? preset.editorShadow || `0 ${Number(preset.shadowOffsetY || 8)}px ${Number(preset.shadowBlur || 18) + 10}px ${preset.shadowColor || "rgba(0, 0, 0, 0.26)"}`
      : "none";
  }

  function isTypingTarget(target) {
    return target
      && (
        target.tagName === "TEXTAREA"
        || target.tagName === "INPUT"
        || target.isContentEditable
      );
  }

  function pointToCanvas(point) {
    return {
      x: point.x * window.innerWidth,
      y: point.y * window.innerHeight,
    };
  }

  function cloneLayer(layer) {
    return JSON.parse(JSON.stringify(layer));
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function snappedSegmentPoint(start, point) {
    const dx = (point.x - start.x) * window.innerWidth;
    const dy = (point.y - start.y) * window.innerHeight;
    const distance = Math.hypot(dx, dy);
    if (distance < 0.0001) return point;

    const angle = Math.atan2(dy, dx);
    const snappedAngle = Math.round(angle / angleSnapStep) * angleSnapStep;
    return {
      x: clamp(start.x + Math.cos(snappedAngle) * distance / Math.max(1, window.innerWidth), 0, 1),
      y: clamp(start.y + Math.sin(snappedAngle) * distance / Math.max(1, window.innerHeight), 0, 1),
    };
  }

  function adjustedSegmentPoint(creating, point, event) {
    if (!creating || !["line", "arrow"].includes(creating.tool)) return point;
    if (!(event && event.shiftKey)) return point;
    return snappedSegmentPoint(creating.start, point);
  }

  function isLineLayer(layer) {
    return Boolean(
      layer
      && layer.kind === "arrow"
      && (
        layer.label === "line"
        || (layer.pointerStart === "none" && layer.pointerEnd === "none")
      )
    );
  }

  function isStrokeEditableLayer(layer) {
    return Boolean(layer && ["ink", "rect", "ellipse", "arrow"].includes(layer.kind));
  }

  function frameFromPoints(a, b) {
    const x = Math.min(a.x, b.x);
    const y = Math.min(a.y, b.y);
    return {
      x,
      y,
      width: Math.abs(a.x - b.x),
      height: Math.abs(a.y - b.y),
    };
  }

  function normalizedRectFromPoints(points) {
    if (!points || !points.length) return null;
    let minX = 1;
    let minY = 1;
    let maxX = 0;
    let maxY = 0;
    for (const point of points) {
      minX = Math.min(minX, point.x);
      minY = Math.min(minY, point.y);
      maxX = Math.max(maxX, point.x);
      maxY = Math.max(maxY, point.y);
    }
    return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
  }

  function normalizedArrowStyle(value) {
    return arrowStylePresets[value] ? value : "straight";
  }

  function arrowStyleForLayer(layer) {
    if (!layer || isLineLayer(layer)) return "straight";
    return normalizedArrowStyle(layer.arrowStyle);
  }

  function arrowControlPointPixels(layer) {
    if (!layer || !layer.from || !layer.to) return null;
    const from = pointToCanvas(layer.from);
    const to = pointToCanvas(layer.to);
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const distance = Math.hypot(dx, dy);
    if (distance < 0.0001) return {
      x: (from.x + to.x) / 2,
      y: (from.y + to.y) / 2,
    };
    const offset = Number(layer.curveOffset || 0.2);
    return {
      x: (from.x + to.x) / 2 - (dy / distance) * distance * offset,
      y: (from.y + to.y) / 2 + (dx / distance) * distance * offset,
    };
  }

  function arrowControlPoint(layer) {
    const control = arrowControlPointPixels(layer);
    if (!control) return null;
    return {
      x: clamp(control.x / Math.max(1, window.innerWidth), 0, 1),
      y: clamp(control.y / Math.max(1, window.innerHeight), 0, 1),
    };
  }

  function paddedRect(rect, pixels) {
    if (!rect) return null;
    const dx = pixels / Math.max(1, window.innerWidth);
    const dy = pixels / Math.max(1, window.innerHeight);
    const x = clamp(rect.x - dx, 0, 1);
    const y = clamp(rect.y - dy, 0, 1);
    const maxX = clamp(rect.x + rect.width + dx, 0, 1);
    const maxY = clamp(rect.y + rect.height + dy, 0, 1);
    return { x, y, width: maxX - x, height: maxY - y };
  }

  function layerBounds(layer) {
    if (!layer || layer.visible === false) return null;
    if (layer.frame) return paddedRect(layer.frame, 6);
    if (layer.from && layer.to) {
      const points = [layer.from, layer.to];
      const control = arrowStyleForLayer(layer) === "curved" ? arrowControlPoint(layer) : null;
      if (control) points.push(control);
      return paddedRect(normalizedRectFromPoints(points), 10);
    }
    if (layer.points && layer.points.length) {
      return paddedRect(normalizedRectFromPoints(layer.points), Number(layer.strokeWidth || 4) + 6);
    }
    return null;
  }

  function rectContains(rect, point) {
    return rect
      && point.x >= rect.x
      && point.x <= rect.x + rect.width
      && point.y >= rect.y
      && point.y <= rect.y + rect.height;
  }

  function distanceToSegment(point, a, b) {
    const px = point.x * window.innerWidth;
    const py = point.y * window.innerHeight;
    const ax = a.x * window.innerWidth;
    const ay = a.y * window.innerHeight;
    const bx = b.x * window.innerWidth;
    const by = b.y * window.innerHeight;
    const dx = bx - ax;
    const dy = by - ay;
    const lengthSq = dx * dx + dy * dy;
    if (lengthSq <= 0.0001) return Math.hypot(px - ax, py - ay);
    const t = clamp(((px - ax) * dx + (py - ay) * dy) / lengthSq, 0, 1);
    return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
  }

  function distanceToQuadraticCurve(point, layer) {
    if (!layer || !layer.from || !layer.to) return Infinity;
    const control = arrowControlPoint(layer);
    if (!control) return Infinity;
    let minDistance = Infinity;
    let previous = layer.from;
    for (let step = 1; step <= 24; step += 1) {
      const t = step / 24;
      const inv = 1 - t;
      const current = {
        x: inv * inv * layer.from.x + 2 * inv * t * control.x + t * t * layer.to.x,
        y: inv * inv * layer.from.y + 2 * inv * t * control.y + t * t * layer.to.y,
      };
      minDistance = Math.min(minDistance, distanceToSegment(point, previous, current));
      previous = current;
    }
    return minDistance;
  }

  function distanceToArrowPath(point, layer) {
    if (arrowStyleForLayer(layer) === "curved") {
      return distanceToQuadraticCurve(point, layer);
    }
    return distanceToSegment(point, layer.from, layer.to);
  }

  function layerContainsPoint(layer, point) {
    if (!layer || layer.visible === false) return false;
    if ((layer.kind === "label" || layer.kind === "ellipse" || layer.kind === "rect") && layer.frame) {
      return rectContains(paddedRect(layer.frame, 8), point);
    }
    if (layer.kind === "arrow" && layer.from && layer.to) {
      const width = Number(layer.strokeWidth || 4);
      const threshold = arrowStyleForLayer(layer) === "shaped" ? Math.max(18, width * 4) : Math.max(14, width + 10);
      return distanceToArrowPath(point, layer) <= threshold;
    }
    if (layer.kind === "ink" && layer.points && layer.points.length > 1) {
      const threshold = Math.max(10, Number(layer.strokeWidth || 4) + 6);
      for (let index = 1; index < layer.points.length; index += 1) {
        if (distanceToSegment(point, layer.points[index - 1], layer.points[index]) <= threshold) {
          return true;
        }
      }
    }
    return rectContains(layerBounds(layer), point);
  }

  function hitTestLayer(point) {
    for (let index = state.layers.length - 1; index >= 0; index -= 1) {
      const layer = state.layers[index];
      if (layerContainsPoint(layer, point)) return layer;
    }
    return null;
  }

  const frameHandleGrabPixels = 18;
  const segmentHandleGrabPixels = 20;
  const frameMinSizePixels = 12;

  function frameHandlePoints(layer) {
    if (!layer || !layer.frame) return [];
    const frame = layer.frame;
    const left = frame.x * window.innerWidth;
    const top = frame.y * window.innerHeight;
    const right = (frame.x + frame.width) * window.innerWidth;
    const bottom = (frame.y + frame.height) * window.innerHeight;
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

  function frameHandleAt(point, layer) {
    const px = point.x * window.innerWidth;
    const py = point.y * window.innerHeight;
    for (const handle of frameHandlePoints(layer)) {
      if (Math.abs(px - handle.x) <= frameHandleGrabPixels && Math.abs(py - handle.y) <= frameHandleGrabPixels) {
        return handle.name;
      }
    }
    return null;
  }

  function segmentHandlePoints(layer) {
    if (!layer || !layer.from || !layer.to) return [];
    const from = pointToCanvas(layer.from);
    const to = pointToCanvas(layer.to);
    return [
      { name: "from", x: from.x, y: from.y },
      { name: "to", x: to.x, y: to.y },
    ];
  }

  function segmentHandleAt(point, layer) {
    const px = point.x * window.innerWidth;
    const py = point.y * window.innerHeight;
    for (const handle of segmentHandlePoints(layer)) {
      if (Math.hypot(px - handle.x, py - handle.y) <= segmentHandleGrabPixels) {
        return handle.name;
      }
    }
    return null;
  }

  function cursorForFrameHandle(handle) {
    if (handle === "n" || handle === "s") return "ns-resize";
    if (handle === "e" || handle === "w") return "ew-resize";
    if (handle === "nw" || handle === "se") return "nwse-resize";
    if (handle === "ne" || handle === "sw") return "nesw-resize";
    return "default";
  }

  function selectedHandleAt(point) {
    const layer = selectedLayer();
    if (!layer) return null;
    if (layer.frame) {
      const handle = frameHandleAt(point, layer);
      return handle ? { kind: "frame", handle, layer } : null;
    }
    if (layer.from && layer.to) {
      const handle = segmentHandleAt(point, layer);
      return handle ? { kind: "segment", handle, layer } : null;
    }
    return null;
  }

  function cursorForSelectPoint(point) {
    const handle = selectedHandleAt(point);
    if (handle && handle.kind === "frame") return cursorForFrameHandle(handle.handle);
    if (handle && handle.kind === "segment") return "grab";
    return hitTestLayer(point) ? "grab" : "default";
  }

  function drawArrowHead(from, to, width, style = "open") {
    if (!style || style === "none") return;
    const angle = Math.atan2(to.y - from.y, to.x - from.x);
    const length = Math.max(12, width * 3.2);
    if (style === "filled") {
      ctx.beginPath();
      ctx.moveTo(to.x, to.y);
      ctx.lineTo(
        to.x - length * Math.cos(angle - Math.PI / 6),
        to.y - length * Math.sin(angle - Math.PI / 6)
      );
      ctx.lineTo(
        to.x - length * Math.cos(angle + Math.PI / 6),
        to.y - length * Math.sin(angle + Math.PI / 6)
      );
      ctx.closePath();
      ctx.fillStyle = ctx.strokeStyle;
      ctx.fill();
      return;
    }
    if (style === "dot") {
      const radius = Math.max(3.5, length * 0.32);
      ctx.beginPath();
      ctx.arc(to.x, to.y, radius, 0, Math.PI * 2);
      ctx.fillStyle = ctx.strokeStyle;
      ctx.fill();
      return;
    }
    if (style === "bar") {
      const barLength = length * 0.74;
      const px = Math.cos(angle + Math.PI / 2) * barLength;
      const py = Math.sin(angle + Math.PI / 2) * barLength;
      ctx.beginPath();
      ctx.moveTo(to.x - px, to.y - py);
      ctx.lineTo(to.x + px, to.y + py);
      ctx.stroke();
      return;
    }
    ctx.beginPath();
    ctx.moveTo(to.x, to.y);
    ctx.lineTo(
      to.x - length * Math.cos(angle - Math.PI / 6),
      to.y - length * Math.sin(angle - Math.PI / 6)
    );
    ctx.moveTo(to.x, to.y);
    ctx.lineTo(
      to.x - length * Math.cos(angle + Math.PI / 6),
      to.y - length * Math.sin(angle + Math.PI / 6)
    );
    ctx.stroke();
  }

  function drawStraightArrow(layer, from, to, width) {
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    applyLayerShadow(layer);
    ctx.stroke();
    clearLayerShadow();
    ctx.setLineDash([]);
    drawArrowHead(to, from, width, pointerStyleForLayer(layer, "start"));
    drawArrowHead(from, to, width, pointerStyleForLayer(layer, "end"));
  }

  function drawCurvedArrow(layer, from, to, width) {
    const control = arrowControlPointPixels(layer);
    if (!control) {
      drawStraightArrow(layer, from, to, width);
      return;
    }
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.quadraticCurveTo(control.x, control.y, to.x, to.y);
    applyLayerShadow(layer);
    ctx.stroke();
    clearLayerShadow();
    ctx.setLineDash([]);
    drawArrowHead(control, from, width, pointerStyleForLayer(layer, "start"));
    drawArrowHead(control, to, width, pointerStyleForLayer(layer, "end"));
  }

  function drawShapedArrow(layer, from, to, width) {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const distance = Math.hypot(dx, dy);
    if (distance < 2) return;
    if (distance < Math.max(24, width * 8)) {
      drawStraightArrow(layer, from, to, width);
      return;
    }

    const ux = dx / distance;
    const uy = dy / distance;
    const px = -uy;
    const py = ux;
    const tailHalf = Math.max(5, width * 1.35);
    const headHalf = Math.max(tailHalf * 2.2, width * 3.2);
    const headLength = Math.min(Math.max(18, width * 5.2), distance * 0.48);
    const neckX = distance - headLength;

    function pointAlong(x, half) {
      return {
        x: from.x + ux * x + px * half,
        y: from.y + uy * x + py * half,
      };
    }

    const tailTop = pointAlong(0, tailHalf);
    const neckTop = pointAlong(neckX, tailHalf);
    const headTop = pointAlong(neckX, headHalf);
    const tip = pointAlong(distance, 0);
    const headBottom = pointAlong(neckX, -headHalf);
    const neckBottom = pointAlong(neckX, -tailHalf);
    const tailBottom = pointAlong(0, -tailHalf);

    ctx.save();
    ctx.setLineDash([]);
    ctx.lineJoin = "round";
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(tailTop.x, tailTop.y);
    ctx.lineTo(neckTop.x, neckTop.y);
    ctx.lineTo(headTop.x, headTop.y);
    ctx.lineTo(tip.x, tip.y);
    ctx.lineTo(headBottom.x, headBottom.y);
    ctx.lineTo(neckBottom.x, neckBottom.y);
    ctx.lineTo(tailBottom.x, tailBottom.y);
    ctx.closePath();
    applyLayerShadow(layer);
    ctx.globalAlpha = 0.94;
    ctx.fillStyle = ctx.strokeStyle;
    ctx.fill();
    clearLayerShadow();
    ctx.globalAlpha = 1;
    ctx.strokeStyle = colorWithAlpha(layer.color || "#D03A1C", 0.92);
    ctx.lineWidth = Math.max(1, width * 0.38);
    ctx.stroke();
    ctx.restore();
  }

  function drawArrowLayer(layer, width) {
    const from = pointToCanvas(layer.from);
    const to = pointToCanvas(layer.to);
    switch (arrowStyleForLayer(layer)) {
    case "curved":
      drawCurvedArrow(layer, from, to, width);
      break;
    case "shaped":
      drawShapedArrow(layer, from, to, width);
      break;
    default:
      drawStraightArrow(layer, from, to, width);
      break;
    }
  }

  function normalizedPointerStyle(value) {
    return ["none", "open", "filled", "dot", "bar"].includes(value) ? value : "open";
  }

  function pointerStyleForLayer(layer, endpoint) {
    const raw = endpoint === "start" ? layer.pointerStart : layer.pointerEnd;
    if (raw) return normalizedPointerStyle(raw);
    if (layer.pointerStart || layer.pointerEnd || isLineLayer(layer)) return "none";
    return endpoint === "end" ? normalizedPointerStyle(layer.pointerStyle || "open") : "none";
  }

  function applyLayerShadow(layer) {
    if (!layer || layer.shadow !== true) return;
    ctx.shadowColor = layer.shadowColor || "rgba(0, 0, 0, 0.28)";
    ctx.shadowBlur = Number(layer.shadowBlur || 12);
    ctx.shadowOffsetY = Number(layer.shadowOffsetY || 5);
  }

  function clearLayerShadow() {
    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
  }

  function roundedRect(x, y, width, height, radius) {
    const r = Math.max(0, Math.min(radius, width / 2, height / 2));
    if (ctx.roundRect) {
      ctx.roundRect(x, y, width, height, r);
      return;
    }
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + width, y, x + width, y + height, r);
    ctx.arcTo(x + width, y + height, x, y + height, r);
    ctx.arcTo(x, y + height, x, y, r);
    ctx.arcTo(x, y, x + width, y, r);
  }

  function noteFont(layer = {}) {
    const size = Number(layer.fontSize || 15);
    const weight = layer.bold === false ? "500" : "650";
    return `${weight} ${size}px -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif`;
  }

  function wrapText(text, maxWidth) {
    const lines = [];
    const paragraphs = String(text || "").split(/\n/);
    for (const paragraph of paragraphs) {
      const words = paragraph.trim().split(/\s+/).filter(Boolean);
      if (!words.length) {
        lines.push("");
        continue;
      }
      let line = "";
      for (const word of words) {
        const test = line ? `${line} ${word}` : word;
        if (line && ctx.measureText(test).width > maxWidth) {
          lines.push(line);
          line = word;
        } else {
          line = test;
        }
      }
      lines.push(line);
    }
    return lines;
  }

  function noteFrameForText(text, point, preset = currentNotePreset()) {
    ctx.save();
    ctx.font = noteFont({ fontSize: preset.fontSize || 15 });
    const maxWidth = Math.min(320, Math.max(180, window.innerWidth * 0.32));
    const minWidth = 160;
    const paddingX = Number(preset.paddingX || 14);
    const paddingY = Number(preset.paddingY || 11);
    const lineHeight = Number(preset.lineHeight || 21);
    const lines = wrapText(text, maxWidth - paddingX * 2);
    const textWidth = lines.reduce((value, line) => Math.max(value, ctx.measureText(line).width), 0);
    ctx.restore();

    const width = Math.min(maxWidth, Math.max(minWidth, textWidth + paddingX * 2));
    const height = Math.max(46, lines.length * lineHeight + paddingY * 2);
    const left = Math.min(
      Math.max(point.x * window.innerWidth, 12),
      Math.max(12, window.innerWidth - width - 12)
    );
    const top = Math.min(
      Math.max(point.y * window.innerHeight, 12),
      Math.max(12, window.innerHeight - height - 12)
    );
    return {
      x: left / window.innerWidth,
      y: top / window.innerHeight,
      width: width / window.innerWidth,
      height: height / window.innerHeight,
    };
  }

  function smoothedInkPoints(points) {
    if (!Array.isArray(points) || points.length < 3) return points || [];
    const smoothed = [points[0]];
    for (let index = 1; index < points.length - 1; index += 1) {
      const previous = points[index - 1];
      const point = points[index];
      const next = points[index + 1];
      smoothed.push({
        x: point.x * 0.5 + (previous.x + next.x) * 0.25,
        y: point.y * 0.5 + (previous.y + next.y) * 0.25,
      });
    }
    smoothed.push(points[points.length - 1]);
    return smoothed;
  }

  function drawSmoothedInkPath(points) {
    const smoothed = smoothedInkPoints(points);
    if (smoothed.length < 2) return;
    const first = pointToCanvas(smoothed[0]);
    ctx.moveTo(first.x, first.y);
    if (smoothed.length === 2) {
      const last = pointToCanvas(smoothed[1]);
      ctx.lineTo(last.x, last.y);
      return;
    }
    for (let index = 1; index < smoothed.length - 1; index += 1) {
      const current = pointToCanvas(smoothed[index]);
      const next = pointToCanvas(smoothed[index + 1]);
      ctx.quadraticCurveTo(
        current.x,
        current.y,
        (current.x + next.x) / 2,
        (current.y + next.y) / 2
      );
    }
    const last = pointToCanvas(smoothed[smoothed.length - 1]);
    ctx.lineTo(last.x, last.y);
  }

  function drawLayer(layer) {
    if (layer.visible === false) return;
    const width = Number(layer.strokeWidth || 4);
    ctx.save();
    ctx.strokeStyle = layer.color || "#D03A1C";
    ctx.lineWidth = width;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.setLineDash(Array.isArray(layer.lineDash) ? layer.lineDash : []);

    if (layer.kind === "ink" && layer.points && layer.points.length > 1) {
      ctx.beginPath();
      drawSmoothedInkPath(layer.points);
      applyLayerShadow(layer);
      ctx.stroke();
    } else if (layer.kind === "ellipse" && layer.frame) {
      const frame = layer.frame;
      const center = pointToCanvas({
        x: frame.x + frame.width / 2,
        y: frame.y + frame.height / 2,
      });
      ctx.beginPath();
      ctx.ellipse(
        center.x,
        center.y,
        Math.max(1, frame.width * window.innerWidth / 2),
        Math.max(1, frame.height * window.innerHeight / 2),
        0,
        0,
        Math.PI * 2
      );
      applyLayerShadow(layer);
      ctx.stroke();
    } else if (layer.kind === "rect" && layer.frame) {
      const frame = layer.frame;
      const origin = pointToCanvas({ x: frame.x, y: frame.y });
      ctx.beginPath();
      ctx.rect(
        origin.x,
        origin.y,
        Math.max(1, frame.width * window.innerWidth),
        Math.max(1, frame.height * window.innerHeight)
      );
      applyLayerShadow(layer);
      ctx.stroke();
    } else if (layer.kind === "arrow" && layer.from && layer.to) {
      drawArrowLayer(layer, width);
    } else if (layer.kind === "label" && layer.frame) {
      const frame = layer.frame;
      const rect = {
        x: frame.x * window.innerWidth,
        y: frame.y * window.innerHeight,
        width: frame.width * window.innerWidth,
        height: frame.height * window.innerHeight,
      };
      const text = layer.text || layer.label || "";
      const paddingX = Number(layer.paddingX || 14);
      const paddingY = Number(layer.paddingY || 11);
      const lineHeight = Number(layer.lineHeight || 21);
      ctx.font = noteFont(layer);
      const lines = wrapText(text, Math.max(10, rect.width - paddingX * 2));
      const backgroundAlpha = layer.backgroundColor ? Number(layer.backgroundAlpha || 0.96) : 1;
      ctx.fillStyle = layer.backgroundColor || "#F8F6F2";
      ctx.strokeStyle = layer.borderColor || "#DFA13A";
      ctx.lineWidth = Number(layer.borderWidth || 1);
      ctx.beginPath();
      roundedRect(rect.x, rect.y, rect.width, rect.height, Number(layer.cornerRadius || 5));
      ctx.globalAlpha = backgroundAlpha;
      applyLayerShadow(layer);
      ctx.fill();
      clearLayerShadow();
      ctx.globalAlpha = 1;
      ctx.globalAlpha = Number(layer.borderAlpha || 0.52);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = layer.textColor || "#17191F";
      ctx.textBaseline = "top";
      lines.forEach((line, index) => {
        ctx.fillText(line, rect.x + paddingX, rect.y + paddingY + index * lineHeight);
      });
    }

    ctx.restore();
  }

  function drawSelection(layer) {
    const bounds = layerBounds(layer);
    if (!bounds) return;
    const rect = {
      x: bounds.x * window.innerWidth,
      y: bounds.y * window.innerHeight,
      width: bounds.width * window.innerWidth,
      height: bounds.height * window.innerHeight,
    };
    ctx.save();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.78)";
    ctx.lineWidth = 1;
    ctx.setLineDash([6, 5]);
    ctx.strokeRect(rect.x, rect.y, Math.max(1, rect.width), Math.max(1, rect.height));
    ctx.setLineDash([]);
    ctx.fillStyle = "#FFFFFF";
    ctx.strokeStyle = "rgba(79, 125, 255, 0.95)";
    ctx.lineWidth = 1.4;
    if (layer.frame) {
      const handleSize = 8;
      for (const handle of frameHandlePoints(layer)) {
        ctx.beginPath();
        ctx.rect(handle.x - handleSize / 2, handle.y - handleSize / 2, handleSize, handleSize);
        ctx.fill();
        ctx.stroke();
      }
    } else if (layer.from && layer.to) {
      for (const handle of segmentHandlePoints(layer)) {
        ctx.beginPath();
        ctx.arc(handle.x, handle.y, 5.25, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  function render() {
    ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    for (const layer of state.layers) drawLayer(layer);
    const selectedLayer = state.layers.find((layer) => layer.id === state.selectedLayerId);
    if (state.tool === "select" && selectedLayer) drawSelection(selectedLayer);
    if (state.creating) drawLayer(previewLayer(state.creating));
  }

  function previewLayer(creating) {
    if (creating.tool === "ink") {
      return {
        id: "preview",
        kind: "ink",
        points: creating.points,
        color: creating.color,
        strokeWidth: creating.strokeWidth,
        lineStyle: creating.lineStyle,
        lineDash: creating.lineDash,
        shadow: creating.shadow,
        shadowColor: creating.shadowColor,
        shadowBlur: creating.shadowBlur,
        shadowOffsetY: creating.shadowOffsetY,
        intent: creating.mode,
        stylePreset: creating.stylePreset,
      };
    }
    if (creating.tool === "ellipse" || creating.tool === "rect") {
      return {
        id: "preview",
        kind: creating.tool,
        frame: frameFromPoints(creating.start, creating.current),
        color: creating.color,
        strokeWidth: creating.strokeWidth,
        lineStyle: creating.lineStyle,
        lineDash: creating.lineDash,
        shadow: creating.shadow,
        shadowColor: creating.shadowColor,
        shadowBlur: creating.shadowBlur,
        shadowOffsetY: creating.shadowOffsetY,
        intent: creating.mode,
        stylePreset: creating.stylePreset,
      };
    }
    const isLine = creating.tool === "line";
    const layer = {
      id: "preview",
      kind: "arrow",
      from: creating.start,
      to: creating.current,
      color: creating.color,
      strokeWidth: creating.strokeWidth,
      pointerStart: isLine ? "none" : (creating.pointerStart || "none"),
      pointerEnd: isLine ? "none" : (creating.pointerEnd || "open"),
      pointerStyle: isLine ? "none" : (creating.pointerStyle || "open"),
      arrowStyle: isLine ? "straight" : (creating.arrowStyle || "straight"),
      curveOffset: creating.curveOffset,
      lineStyle: creating.lineStyle,
      lineDash: creating.lineDash,
      shadow: creating.shadow,
      shadowColor: creating.shadowColor,
      shadowBlur: creating.shadowBlur,
      shadowOffsetY: creating.shadowOffsetY,
      intent: creating.mode,
      stylePreset: creating.stylePreset,
    };
    if (isLine) layer.label = "line";
    return layer;
  }

  function sendUpdate() {
    post("liveMarkup.update", {
      layers: state.layers,
      document: exportDocument(),
    });
  }

  function exportDocument() {
    return {
      version: 3,
      imageWidth: window.innerWidth,
      imageHeight: window.innerHeight,
      mode: state.mode,
      layers: state.layers,
    };
  }

  canvas.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    if (dock && dock.contains(event.target)) return;
    if (state.styleOpen) setStyleOpen(false);
    const point = eventPoint(event);
    state.lastPointer = point;
    if (state.tool === "select") {
      closeNoteEditor(true);
      const selectedHandle = event.altKey ? null : selectedHandleAt(point);
      if (selectedHandle) {
        state.selectedLayerId = selectedHandle.layer.id;
        state.dragging = {
          kind: selectedHandle.kind === "frame" ? "resizeFrame" : "resizeSegment",
          layerId: selectedHandle.layer.id,
          handle: selectedHandle.handle,
          start: point,
          original: cloneLayer(selectedHandle.layer),
          copyRequested: false,
          copied: false,
        };
      } else {
        const layer = hitTestLayer(point);
        state.selectedLayerId = layer ? layer.id : null;
        state.dragging = layer ? {
          kind: "move",
          layerId: layer.id,
          start: point,
          original: cloneLayer(layer),
          copyRequested: Boolean(event.altKey),
          copied: false,
        } : null;
      }
      if (state.dragging) {
        document.body.classList.add("dragging");
        canvas.style.cursor = state.dragging.kind === "resizeFrame"
          ? cursorForFrameHandle(state.dragging.handle)
          : "grabbing";
        canvas.setPointerCapture(event.pointerId);
      }
      render();
      event.preventDefault();
      return;
    }
    if (state.tool === "note") {
      startNoteEditor(point);
      event.preventDefault();
      return;
    }
    const linePreset = currentLinePreset();
    const arrowPreset = currentArrowPreset();
    const base = {
      tool: state.tool,
      start: point,
      current: point,
      points: [point],
      color: state.color,
      strokeWidth: state.strokeWidth,
      mode: state.mode,
      lineStyle: state.lineStyle,
      lineDash: linePreset.lineDash,
      pointerStart: "none",
      pointerEnd: arrowPreset.pointerEnd || linePreset.pointerEnd,
      pointerStyle: arrowPreset.pointerStyle || linePreset.pointerStyle,
      arrowStyle: arrowPreset.id,
      curveOffset: arrowPreset.curveOffset,
      shadow: linePreset.shadow,
      shadowColor: linePreset.shadowColor,
      shadowBlur: linePreset.shadowBlur,
      shadowOffsetY: linePreset.shadowOffsetY,
      stylePreset: linePreset.id,
      startTime: nowSeconds(),
    };
    if (state.tool === "line") {
      base.pointerEnd = "none";
      base.pointerStyle = "none";
      base.label = "line";
      base.arrowStyle = "straight";
      delete base.curveOffset;
    }
    state.creating = base;
    canvas.setPointerCapture(event.pointerId);
    event.preventDefault();
  });

  canvas.addEventListener("pointermove", (event) => {
    state.lastPointer = eventPoint(event);
    if (state.dragging) {
      const point = state.lastPointer;
      const dx = point.x - state.dragging.start.x;
      const dy = point.y - state.dragging.start.y;
      if (state.dragging.kind === "resizeFrame") {
        resizeLayerFrame(state.dragging.layerId, state.dragging.original, state.dragging.handle, dx, dy);
        canvas.style.cursor = cursorForFrameHandle(state.dragging.handle);
        render();
        return;
      }
      if (state.dragging.kind === "resizeSegment") {
        resizeSegmentEndpoint(state.dragging.layerId, state.dragging.original, state.dragging.handle, dx, dy, event);
        canvas.style.cursor = "grabbing";
        render();
        return;
      }
      if (state.dragging.copyRequested && !state.dragging.copied) {
        const distance = Math.hypot(dx * window.innerWidth, dy * window.innerHeight);
        if (distance < 2) return;
        const source = state.layers.find((layer) => layer.id === state.dragging.layerId);
        if (!source) return;
        const copy = duplicateLayer(source);
        state.layers.push(copy);
        state.redoStack = [];
        state.dragging.layerId = copy.id;
        state.dragging.original = cloneLayer(copy);
        state.dragging.copied = true;
        state.selectedLayerId = copy.id;
      }
      moveLayer(state.dragging.layerId, state.dragging.original, dx, dy);
      render();
      return;
    }

    if (state.tool === "select") {
      const point = state.lastPointer;
      canvas.style.cursor = cursorForSelectPoint(point);
      return;
    }

    const creating = state.creating;
    if (!creating) return;
    const point = state.lastPointer;
    creating.current = adjustedSegmentPoint(creating, point, event);
    if (creating.tool === "ink") {
      const last = creating.points[creating.points.length - 1];
      const dx = point.x - last.x;
      const dy = point.y - last.y;
      if (Math.hypot(dx * window.innerWidth, dy * window.innerHeight) >= 2) {
        creating.points.push(point);
      }
    }
    render();
  });

  function finishPointer(event) {
    if (state.dragging) {
      if (event && canvas.hasPointerCapture(event.pointerId)) {
        canvas.releasePointerCapture(event.pointerId);
      }
      state.dragging = null;
      document.body.classList.remove("dragging");
      const point = event ? eventPoint(event) : null;
      canvas.style.cursor = point ? cursorForSelectPoint(point) : "default";
      render();
      sendUpdate();
      return;
    }

    const creating = state.creating;
    if (!creating) return;
    if (event) {
      creating.current = adjustedSegmentPoint(creating, eventPoint(event), event);
    }
    state.creating = null;
    if (event && canvas.hasPointerCapture(event.pointerId)) {
      canvas.releasePointerCapture(event.pointerId);
    }
    const endTime = nowSeconds();
    const layer = previewLayer(creating);
    layer.id = uuid();
    layer.author = "user";
    layer.visible = true;
    layer.startTime = creating.startTime;
    layer.endTime = endTime;
    if (creating.tool === "ink" && (!layer.points || layer.points.length < 2)) {
      render();
      return;
    }
    if (creating.tool !== "ink") {
      const dist = Math.hypot(
        (creating.current.x - creating.start.x) * window.innerWidth,
        (creating.current.y - creating.start.y) * window.innerHeight
      );
      if (dist < 8) {
        render();
        return;
      }
    }
    state.layers.push(layer);
    state.redoStack = [];
    state.selectedLayerId = layer.id;
    render();
    sendUpdate();
  }

  canvas.addEventListener("pointerup", finishPointer);
  canvas.addEventListener("pointercancel", finishPointer);

  function constrainDelta(bounds, dx, dy) {
    if (!bounds) return { dx, dy };
    let nextDx = dx;
    let nextDy = dy;
    if (bounds.x + nextDx < 0) nextDx = -bounds.x;
    if (bounds.x + bounds.width + nextDx > 1) nextDx = 1 - bounds.x - bounds.width;
    if (bounds.y + nextDy < 0) nextDy = -bounds.y;
    if (bounds.y + bounds.height + nextDy > 1) nextDy = 1 - bounds.y - bounds.height;
    return { dx: nextDx, dy: nextDy };
  }

  function movedPoint(point, dx, dy) {
    return {
      x: clamp(point.x + dx, 0, 1),
      y: clamp(point.y + dy, 0, 1),
    };
  }

  function movedFrame(frame, dx, dy) {
    return {
      x: clamp(frame.x + dx, 0, 1 - frame.width),
      y: clamp(frame.y + dy, 0, 1 - frame.height),
      width: frame.width,
      height: frame.height,
    };
  }

  function resizedFrame(frame, handle, dx, dy) {
    const minWidth = frameMinSizePixels / Math.max(1, window.innerWidth);
    const minHeight = frameMinSizePixels / Math.max(1, window.innerHeight);
    let left = frame.x;
    let top = frame.y;
    let right = frame.x + frame.width;
    let bottom = frame.y + frame.height;

    if (handle.includes("w")) left = clamp(Math.min(frame.x + dx, right - minWidth), 0, right - minWidth);
    if (handle.includes("e")) right = clamp(Math.max(frame.x + frame.width + dx, left + minWidth), left + minWidth, 1);
    if (handle.includes("n")) top = clamp(Math.min(frame.y + dy, bottom - minHeight), 0, bottom - minHeight);
    if (handle.includes("s")) bottom = clamp(Math.max(frame.y + frame.height + dy, top + minHeight), top + minHeight, 1);

    return {
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    };
  }

  function resizeLayerFrame(layerId, original, handle, dx, dy) {
    const index = state.layers.findIndex((layer) => layer.id === layerId);
    if (index < 0 || !original.frame) return;
    const next = cloneLayer(original);
    next.frame = resizedFrame(original.frame, handle, dx, dy);
    state.layers[index] = next;
  }

  function adjustedEndpointPoint(anchor, point, event) {
    if (!(event && event.shiftKey)) return point;
    return snappedSegmentPoint(anchor, point);
  }

  function resizeSegmentEndpoint(layerId, original, handle, dx, dy, event) {
    const index = state.layers.findIndex((layer) => layer.id === layerId);
    if (index < 0 || !original.from || !original.to) return;
    const next = cloneLayer(original);
    if (handle === "from") {
      const moving = movedPoint(original.from, dx, dy);
      next.from = adjustedEndpointPoint(original.to, moving, event);
    } else {
      const moving = movedPoint(original.to, dx, dy);
      next.to = adjustedEndpointPoint(original.from, moving, event);
    }
    state.layers[index] = next;
  }

  function movedLayer(layer, dx, dy) {
    const moved = cloneLayer(layer);
    const constrained = constrainDelta(layerBounds(layer), dx, dy);
    if (moved.frame) moved.frame = movedFrame(moved.frame, constrained.dx, constrained.dy);
    if (moved.from) moved.from = movedPoint(moved.from, constrained.dx, constrained.dy);
    if (moved.to) moved.to = movedPoint(moved.to, constrained.dx, constrained.dy);
    if (moved.points) {
      moved.points = moved.points.map((point) => movedPoint(point, constrained.dx, constrained.dy));
    }
    return moved;
  }

  function moveLayer(layerId, original, dx, dy) {
    const index = state.layers.findIndex((layer) => layer.id === layerId);
    if (index < 0) return;
    state.layers[index] = movedLayer(original, dx, dy);
  }

  function selectedLayer() {
    return state.layers.find((layer) => layer.id === state.selectedLayerId) || null;
  }

  function duplicateLayer(layer) {
    const copy = cloneLayer(layer);
    copy.id = uuid();
    copy.author = "user";
    copy.visible = true;
    return copy;
  }

  function applyNotePresetToLayer(layer, preset) {
    if (!layer || layer.kind !== "label" || !preset) return false;
    layer.noteStyle = preset.id;
    layer.stylePreset = preset.id;
    layer.textColor = preset.textColor;
    layer.backgroundColor = preset.backgroundColor;
    layer.backgroundAlpha = preset.backgroundAlpha;
    layer.borderColor = preset.borderColor;
    layer.borderAlpha = preset.borderAlpha;
    layer.borderWidth = preset.borderWidth;
    layer.cornerRadius = preset.cornerRadius;
    layer.paddingX = preset.paddingX;
    layer.paddingY = preset.paddingY;
    layer.fontSize = preset.fontSize;
    layer.lineHeight = preset.lineHeight;
    layer.bold = preset.bold;
    layer.shadow = preset.shadow;
    layer.shadowColor = preset.shadowColor;
    layer.shadowBlur = preset.shadowBlur;
    layer.shadowOffsetY = preset.shadowOffsetY;
    if (layer.frame) {
      const origin = { x: layer.frame.x, y: layer.frame.y };
      layer.frame = noteFrameForText(layer.text || layer.label || "", origin, preset);
    }
    return true;
  }

  function applyLinePresetToLayer(layer, preset) {
    if (!layer || !["ink", "rect", "ellipse", "arrow"].includes(layer.kind) || !preset) return false;
    const lineLayer = isLineLayer(layer);
    layer.lineStyle = preset.id;
    layer.lineDash = preset.lineDash;
    layer.stylePreset = preset.id;
    layer.shadow = preset.shadow;
    layer.shadowColor = preset.shadowColor;
    layer.shadowBlur = preset.shadowBlur;
    layer.shadowOffsetY = preset.shadowOffsetY;
    if (layer.kind === "arrow") {
      layer.pointerStart = "none";
      layer.pointerEnd = lineLayer ? "none" : preset.pointerEnd;
      layer.pointerStyle = lineLayer ? "none" : preset.pointerStyle;
      if (lineLayer) layer.label = "line";
    }
    return true;
  }

  function applyArrowPresetToLayer(layer, preset) {
    if (!layer || layer.kind !== "arrow" || isLineLayer(layer) || !preset) return false;
    layer.arrowStyle = preset.id;
    layer.curveOffset = preset.curveOffset;
    if (preset.pointerEnd) {
      layer.pointerEnd = preset.pointerEnd;
      layer.pointerStyle = preset.pointerStyle || preset.pointerEnd;
    }
    return true;
  }

  function closeNoteEditor(commit) {
    const active = state.noteEditor;
    if (!active) return;
    state.noteEditor = null;
    const text = active.element.value.trim();
    active.element.remove();
    if (!commit || !text) {
      render();
      return;
    }
    const preset = noteStylePresets[active.noteStyle || state.noteStyle] || noteStylePresets.sticky;
    const layer = {
      id: uuid(),
      kind: "label",
      frame: noteFrameForText(text, active.point, preset),
      text,
      label: text,
      color: state.color,
      textColor: preset.textColor,
      backgroundColor: preset.backgroundColor,
      backgroundAlpha: preset.backgroundAlpha,
      borderColor: preset.borderColor,
      borderAlpha: preset.borderAlpha,
      borderWidth: preset.borderWidth,
      cornerRadius: preset.cornerRadius,
      paddingX: preset.paddingX,
      paddingY: preset.paddingY,
      fontSize: preset.fontSize,
      lineHeight: preset.lineHeight,
      fontFamily: "sans",
      bold: preset.bold,
      shadow: preset.shadow,
      shadowColor: preset.shadowColor,
      shadowBlur: preset.shadowBlur,
      shadowOffsetY: preset.shadowOffsetY,
      intent: active.mode || state.mode,
      noteStyle: active.noteStyle || state.noteStyle,
      stylePreset: preset.id,
      author: "user",
      visible: true,
      startTime: active.startTime,
      endTime: nowSeconds(),
    };
    state.layers.push(layer);
    state.redoStack = [];
    state.selectedLayerId = layer.id;
    render();
    sendUpdate();
  }

  function startNoteEditor(point) {
    closeNoteEditor(true);
    const element = document.createElement("textarea");
    element.className = "note-editor";
    element.dataset.noteStyle = state.noteStyle;
    element.placeholder = "Note";
    element.spellcheck = true;
    applyNotePresetToEditor(element, currentNotePreset());
    const editorLeft = Math.min(
      Math.max(point.x * window.innerWidth, 12),
      Math.max(12, window.innerWidth - 320)
    );
    element.style.left = `${editorLeft}px`;
    element.style.top = `${Math.min(Math.max(point.y * window.innerHeight, 12), window.innerHeight - 80)}px`;
    document.body.appendChild(element);
    state.noteEditor = {
      element,
      point,
      mode: state.mode,
      noteStyle: state.noteStyle,
      startTime: nowSeconds(),
    };

    element.addEventListener("pointerdown", (event) => event.stopPropagation());
    element.addEventListener("keydown", (event) => {
      event.stopPropagation();
      if (event.key === "Escape") {
        event.preventDefault();
        closeNoteEditor(false);
      } else if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        closeNoteEditor(true);
      }
    });
    element.addEventListener("blur", () => closeNoteEditor(true));
    requestAnimationFrame(() => element.focus());
  }

  if (dock) {
    dock.addEventListener("pointerdown", (event) => {
      event.stopPropagation();
    });

    dock.addEventListener("click", (event) => {
      const button = event.target.closest("button");
      if (!button) return;

      const tool = button.getAttribute("data-tool");
      if (tool) {
        setTool(tool);
        return;
      }

      const noteStyle = button.getAttribute("data-note-style");
      if (noteStyle) {
        setNoteStyle(noteStyle);
        return;
      }

      const lineStyle = button.getAttribute("data-line-style");
      if (lineStyle) {
        setLineStyle(lineStyle);
        return;
      }

      const arrowStyle = button.getAttribute("data-arrow-style");
      if (arrowStyle) {
        setArrowStyle(arrowStyle);
        return;
      }

      const color = button.getAttribute("data-color");
      if (color) {
        setColor(color);
        return;
      }

      const width = button.getAttribute("data-width");
      if (width) {
        setStrokeWidth(Number(width));
        return;
      }

      const action = button.getAttribute("data-action");
      performAction(action);
    });
  }

  windowChrome.forEach((element) => {
    element.addEventListener("pointerdown", (event) => {
      event.stopPropagation();
    });
  });

  document.addEventListener("click", (event) => {
    const button = event.target.closest(".window-close, .surface-actions button");
    if (!button) return;
    event.stopPropagation();
    performAction(button.getAttribute("data-action"));
  });

  function performAction(action) {
    if (action === "toggle-style") {
      if (optionTools.has(state.tool)) setStyleOpen(!state.styleOpen);
    } else if (action === "undo") {
      undo();
    } else if (action === "redo") {
      redo();
    } else if (action === "capture") {
      capture();
    } else if (action === "done") {
      done();
    } else if (action === "cancel") {
      cancel();
    }
  }

  function syncToolbarState() {
    const controls = dock || toolbar;
    if (!controls) return;
    controls.querySelectorAll(".tool").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-tool") === state.tool);
    });
    controls.querySelectorAll(".swatch").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-color") === state.color);
    });
    controls.querySelectorAll(".width").forEach((el) => {
      el.classList.toggle("active", Number(el.getAttribute("data-width")) === state.strokeWidth);
    });
    controls.querySelectorAll(".note-style").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-note-style") === state.noteStyle);
    });
    controls.querySelectorAll(".line-style").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-line-style") === state.lineStyle);
    });
    controls.querySelectorAll(".arrow-style").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-arrow-style") === state.arrowStyle);
    });
    controls.querySelectorAll(".style-toggle").forEach((el) => {
      el.classList.toggle("active", state.styleOpen);
      el.setAttribute("aria-expanded", state.styleOpen ? "true" : "false");
      el.title = state.styleOpen ? `Hide ${toolOptionsLabel()}` : `Show ${toolOptionsLabel()}`;
      const summary = el.querySelector(".style-summary");
      if (summary) summary.textContent = styleSummaryForTool();
    });
  }

  function setStyleOpen(open) {
    state.styleOpen = Boolean(open);
    if (stylePanel) {
      stylePanel.hidden = !state.styleOpen;
      stylePanel.classList.toggle("open", state.styleOpen);
    }
    document.body.dataset.styleOpen = state.styleOpen ? "true" : "false";
    syncToolbarState();
  }

  function setTool(tool) {
    if (!["select", "ink", "rect", "ellipse", "line", "arrow", "note"].includes(tool)) return;
    closeNoteEditor(true);
    state.dragging = null;
    document.body.classList.remove("dragging");
    canvas.style.cursor = "";
    state.tool = tool;
    document.body.dataset.tool = tool;
    setStyleOpen(optionTools.has(tool));
    syncToolbarState();
  }

  function setNoteStyle(noteStyle) {
    if (!noteStylePresets[noteStyle]) return;
    state.noteStyle = noteStyle;
    document.body.dataset.noteStyle = noteStyle;
    const preset = currentNotePreset();
    if (state.noteEditor) {
      state.noteEditor.noteStyle = noteStyle;
      state.noteEditor.element.dataset.noteStyle = noteStyle;
      applyNotePresetToEditor(state.noteEditor.element, preset);
    }
    if (applyNotePresetToLayer(selectedLayer(), preset)) {
      render();
      sendUpdate();
    }
    syncToolbarState();
  }

  function setLineStyle(lineStyle) {
    if (!lineStylePresets[lineStyle]) return;
    state.lineStyle = lineStyle;
    document.body.dataset.lineStyle = lineStyle;
    if (applyLinePresetToLayer(selectedLayer(), currentLinePreset())) {
      render();
      sendUpdate();
    }
    syncToolbarState();
  }

  function setArrowStyle(arrowStyle) {
    if (!arrowStylePresets[arrowStyle]) return;
    state.arrowStyle = arrowStyle;
    document.body.dataset.arrowStyle = arrowStyle;
    if (applyArrowPresetToLayer(selectedLayer(), currentArrowPreset())) {
      render();
      sendUpdate();
    }
    syncToolbarState();
  }

  function cyclePreset(keys, current, delta = 1) {
    const index = Math.max(0, keys.indexOf(current));
    return keys[(index + delta + keys.length) % keys.length];
  }

  function cycleNoteStyle() {
    setNoteStyle(cyclePreset(Object.keys(noteStylePresets), state.noteStyle));
  }

  function cycleLineStyle() {
    setLineStyle(cyclePreset(Object.keys(lineStylePresets), state.lineStyle));
  }

  function toolOptionsLabel(tool = state.tool) {
    const label = toolLabels[tool] || "Tool";
    return optionTools.has(tool) ? `${label} options` : label;
  }

  function styleSummaryForTool(tool = state.tool) {
    const note = noteStyleLabels[state.noteStyle] || state.noteStyle;
    const line = lineStyleLabels[state.lineStyle] || state.lineStyle;
    const arrow = arrowStyleLabels[state.arrowStyle] || state.arrowStyle;
    const width = `${Number(state.strokeWidth)}px`;
    switch (tool) {
    case "note":
      return `Note · ${note} · ${width}`;
    case "arrow":
      return `Arrow · ${arrow} · ${line} · ${width}`;
    case "line":
      return `Line · ${line} · ${width}`;
    case "ink":
      return `Pen · ${line} · ${width}`;
    case "rect":
      return `Rect · ${line} · ${width}`;
    case "ellipse":
      return `Circle · ${line} · ${width}`;
    default:
      return "Move and reshape";
    }
  }

  function setColor(color) {
    state.color = color;
    syncToolbarState();
  }

  function setStrokeWidth(width) {
    const next = Number(width);
    if (Number.isFinite(next) && next > 0) {
      state.strokeWidth = next;
      const layer = selectedLayer();
      if (isStrokeEditableLayer(layer)) {
        layer.strokeWidth = next;
        render();
        sendUpdate();
      }
      syncToolbarState();
    }
  }

  function quickNoteAtPointer() {
    setTool("note");
    startNoteEditor(state.lastPointer || { x: 0.5, y: 0.5 });
  }

  function handleToolChord(event) {
    const key = shortcutToken(event);
    switch (key) {
    case "s":
      setTool("select");
      break;
    case "p":
      setTool("ink");
      break;
    case "r":
      setTool("rect");
      break;
    case "c":
      setTool("ellipse");
      break;
    case "l":
      if (event.shiftKey) cycleLineStyle();
      else setTool("line");
      break;
    case "a":
      setTool("arrow");
      break;
    case "n":
      quickNoteAtPointer();
      break;
    case "t":
      cycleNoteStyle();
      break;
    case "escape":
      clearToolChord();
      break;
    default:
      return false;
    }
    return true;
  }

  function undo() {
    closeNoteEditor(false);
    const layer = state.layers.pop();
    if (layer) state.redoStack.push(layer);
    if (!state.layers.some((layer) => layer.id === state.selectedLayerId)) {
      state.selectedLayerId = null;
    }
    render();
    sendUpdate();
  }

  function redo() {
    closeNoteEditor(false);
    const layer = state.redoStack.pop();
    if (!layer) return;
    state.layers.push(layer);
    state.selectedLayerId = layer.id;
    render();
    sendUpdate();
  }

  function done() {
    closeNoteEditor(true);
    post("liveMarkup.done", {
      layers: state.layers,
      document: exportDocument(),
    });
  }

  // Desktop ink: ask the host to start a screenshot. The host flips this overlay
  // to passthrough, runs region selection, bakes these strokes into the shot,
  // then tears the overlay down — so there's nothing to commit from here.
  function capture() {
    closeNoteEditor(true);
    post("liveMarkup.capture", {});
  }

  // Toggle the toolbar between the recording-markup variant (default, shows
  // "Done") and the desktop-ink variant (shows the screenshot button instead).
  function setContext(context) {
    state.context = context === "desktopInk" ? "desktopInk" : "recording";
    document.body.dataset.context = state.context;
    const isInk = state.context === "desktopInk";
    document.querySelectorAll('[data-action="capture"]').forEach((el) => {
      el.hidden = !isInk;
    });
    document.querySelectorAll('[data-action="done"]').forEach((el) => {
      el.hidden = isInk;
    });
  }

  function cancel() {
    closeNoteEditor(false);
    post("liveMarkup.cancel", {});
  }

  window.addEventListener("keydown", (event) => {
    if (isToolChordStart(event)) {
      beginToolChord();
      event.preventDefault();
      return;
    }
    if (toolChordActive) {
      const handled = handleToolChord(event);
      clearToolChord();
      event.preventDefault();
      if (handled) return;
      return;
    }
    if (isTypingTarget(event.target)) return;
    const key = event.key.toLowerCase();
    if (event.key === "Escape" || key === "x") {
      post("liveMarkup.cancel", {});
    } else if (event.key === "Enter") {
      post("liveMarkup.done", {
        layers: state.layers,
        document: exportDocument(),
      });
    } else if ((event.metaKey || event.ctrlKey) && event.shiftKey && key === "z") {
      redo();
    } else if ((event.metaKey || event.ctrlKey) && key === "z") {
      undo();
    } else if (event.metaKey || event.ctrlKey || event.altKey) {
      return;
    }
  });

  window.talkieLiveMarkup = {
    exportDocument,
    setTool,
    setColor,
    setStrokeWidth,
    setNoteStyle,
    setLineStyle,
    setArrowStyle,
    setStyleOpen,
    setContext,
    undo,
    redo,
    done,
    capture,
    cancel,
    clear() {
      state.layers = [];
      state.redoStack = [];
      render();
      sendUpdate();
    },
  };

  window.addEventListener("resize", resizeCanvas);
  resizeCanvas();
  document.body.dataset.tool = state.tool;
  document.body.dataset.mode = state.mode;
  document.body.dataset.noteStyle = state.noteStyle;
  document.body.dataset.lineStyle = state.lineStyle;
  document.body.dataset.arrowStyle = state.arrowStyle;
  document.body.dataset.styleOpen = state.styleOpen ? "true" : "false";
  setContext(state.context);
  setStyleOpen(state.styleOpen);
  post("liveMarkup.ready", {});
})();
