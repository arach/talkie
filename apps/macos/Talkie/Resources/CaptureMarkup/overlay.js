(() => {
  const canvas = document.getElementById("overlay-canvas");
  const ctx = canvas.getContext("2d");
  const dock = document.getElementById("markup-dock");
  const toolbar = document.getElementById("toolbar");
  const stylePanel = document.getElementById("style-panel");

  const state = {
    tool: "ink",
    mode: "agent",
    color: "#D03A1C",
    strokeWidth: 4,
    noteStyle: "sticky",
    lineStyle: "solid",
    styleOpen: false,
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
      textColor: "#17191F",
      backgroundColor: "#FFF7DF",
      backgroundAlpha: 0.96,
      borderColor: "#D9912B",
      borderAlpha: 0.52,
      borderWidth: 1,
      cornerRadius: 13,
      fontSize: 15,
      lineHeight: 21,
      paddingX: 14,
      paddingY: 11,
      bold: true,
      shadow: true,
      shadowColor: "rgba(0, 0, 0, 0.22)",
      shadowBlur: 18,
      shadowOffsetY: 8,
    },
    bubble: {
      id: "bubble",
      textColor: "#101826",
      backgroundColor: "#F3F7FF",
      backgroundAlpha: 0.95,
      borderColor: "#4F7DFF",
      borderAlpha: 0.42,
      borderWidth: 1.25,
      cornerRadius: 24,
      fontSize: 15,
      lineHeight: 21,
      paddingX: 16,
      paddingY: 12,
      bold: true,
      shadow: true,
      shadowColor: "rgba(23, 35, 64, 0.2)",
      shadowBlur: 18,
      shadowOffsetY: 8,
    },
    glass: {
      id: "glass",
      textColor: "#FFFFFF",
      backgroundColor: "#13161E",
      backgroundAlpha: 0.9,
      borderColor: "#FFFFFF",
      borderAlpha: 0.2,
      borderWidth: 1,
      cornerRadius: 16,
      fontSize: 16,
      lineHeight: 22,
      paddingX: 16,
      paddingY: 12,
      bold: true,
      shadow: true,
      shadowColor: "rgba(0, 0, 0, 0.34)",
      shadowBlur: 22,
      shadowOffsetY: 10,
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

  const toolChordTimeoutMs = 1600;
  let toolChordActive = false;
  let toolChordTimer = null;

  const angleSnapStep = Math.PI / 4;
  const angleSnapMagnet = Math.PI / 12;

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
    element.style.background = colorWithAlpha(preset.backgroundColor, preset.backgroundAlpha || 1);
    element.style.borderColor = colorWithAlpha(preset.borderColor, preset.borderAlpha || 1);
    element.style.borderWidth = `${Number(preset.borderWidth || 1)}px`;
    element.style.borderRadius = `${Number(preset.cornerRadius || 13)}px`;
    element.style.padding = `${Number(preset.paddingY || 11)}px ${Number(preset.paddingX || 14)}px`;
    element.style.font = noteFont(preset);
    element.style.boxShadow = preset.shadow
      ? `0 ${Number(preset.shadowOffsetY || 8)}px ${Number(preset.shadowBlur || 18) + 10}px rgba(0, 0, 0, 0.26)`
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

  function angleDistance(a, b) {
    return Math.atan2(Math.sin(a - b), Math.cos(a - b));
  }

  function snappedSegmentPoint(start, point, forceSnap = false) {
    const dx = (point.x - start.x) * window.innerWidth;
    const dy = (point.y - start.y) * window.innerHeight;
    const distance = Math.hypot(dx, dy);
    if (distance < 0.0001) return point;

    const angle = Math.atan2(dy, dx);
    const snappedAngle = Math.round(angle / angleSnapStep) * angleSnapStep;
    if (!forceSnap && Math.abs(angleDistance(angle, snappedAngle)) > angleSnapMagnet) {
      return point;
    }

    return {
      x: clamp(start.x + Math.cos(snappedAngle) * distance / Math.max(1, window.innerWidth), 0, 1),
      y: clamp(start.y + Math.sin(snappedAngle) * distance / Math.max(1, window.innerHeight), 0, 1),
    };
  }

  function adjustedSegmentPoint(creating, point, event) {
    if (!creating || !["line", "arrow"].includes(creating.tool)) return point;
    return snappedSegmentPoint(creating.start, point, Boolean(event && event.shiftKey));
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
    if (layer.from && layer.to) return paddedRect(frameFromPoints(layer.from, layer.to), 10);
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

  function layerContainsPoint(layer, point) {
    if (!layer || layer.visible === false) return false;
    if ((layer.kind === "label" || layer.kind === "ellipse" || layer.kind === "rect") && layer.frame) {
      return rectContains(paddedRect(layer.frame, 8), point);
    }
    if (layer.kind === "arrow" && layer.from && layer.to) {
      return distanceToSegment(point, layer.from, layer.to) <= 12;
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
      const first = pointToCanvas(layer.points[0]);
      ctx.beginPath();
      ctx.moveTo(first.x, first.y);
      for (const point of layer.points.slice(1)) {
        const p = pointToCanvas(point);
        ctx.lineTo(p.x, p.y);
      }
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
    } else if (layer.kind === "arrow" && layer.from && layer.to) {
      const from = pointToCanvas(layer.from);
      const to = pointToCanvas(layer.to);
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(to.x, to.y);
      applyLayerShadow(layer);
      ctx.stroke();
      ctx.setLineDash([]);
      drawArrowHead(to, from, width, pointerStyleForLayer(layer, "start"));
      drawArrowHead(from, to, width, pointerStyleForLayer(layer, "end"));
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
      ctx.fillStyle = layer.backgroundColor || "#FFF7DF";
      ctx.strokeStyle = layer.borderColor || "#D9912B";
      ctx.lineWidth = Number(layer.borderWidth || 1);
      ctx.beginPath();
      roundedRect(rect.x, rect.y, rect.width, rect.height, Number(layer.cornerRadius || 13));
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
    if (creating.tool === "ellipse") {
      return {
        id: "preview",
        kind: "ellipse",
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
      const layer = hitTestLayer(point);
      state.selectedLayerId = layer ? layer.id : null;
      state.dragging = layer ? {
        layerId: layer.id,
        start: point,
        original: cloneLayer(layer),
        copyRequested: Boolean(event.altKey),
        copied: false,
      } : null;
      if (state.dragging) {
        document.body.classList.add("dragging");
        canvas.style.cursor = "grabbing";
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
      pointerEnd: linePreset.pointerEnd,
      pointerStyle: linePreset.pointerStyle,
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
      canvas.style.cursor = hitTestLayer(point) ? "grab" : "default";
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
      canvas.style.cursor = point && hitTestLayer(point) ? "grab" : "default";
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
      if (action === "toggle-style") {
        setStyleOpen(!state.styleOpen);
      } else if (action === "undo") {
        undo();
      } else if (action === "done") {
        done();
      } else if (action === "cancel") {
        cancel();
      }
    });
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
    controls.querySelectorAll(".style-toggle").forEach((el) => {
      el.classList.toggle("active", state.styleOpen);
      el.setAttribute("aria-expanded", state.styleOpen ? "true" : "false");
      const swatch = el.querySelector(".style-chip-swatch");
      const label = el.querySelector(".style-chip-label");
      if (swatch) swatch.style.setProperty("--chip-color", state.color);
      if (label) {
        const note = noteStyleLabels[state.noteStyle] || state.noteStyle;
        const line = lineStyleLabels[state.lineStyle] || state.lineStyle;
        label.textContent = `${note} · ${line} · ${Number(state.strokeWidth)}px`;
      }
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
    if (!["select", "ink", "ellipse", "line", "arrow", "note"].includes(tool)) return;
    closeNoteEditor(true);
    state.dragging = null;
    document.body.classList.remove("dragging");
    canvas.style.cursor = "";
    state.tool = tool;
    document.body.dataset.tool = tool;
    setStyleOpen(false);
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
    if (event.key === "Escape") {
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
    setStyleOpen,
    undo,
    redo,
    done,
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
  document.body.dataset.styleOpen = "false";
  syncToolbarState();
  post("liveMarkup.ready", {});
})();
