(() => {
  const canvas = document.getElementById("overlay-canvas");
  const ctx = canvas.getContext("2d");
  const dock = document.getElementById("markup-dock");
  const toolbar = document.getElementById("toolbar");
  const stylePanel = document.getElementById("style-panel");
  const windowChrome = document.querySelectorAll(".window-close, .surface-actions");
  const query = new URLSearchParams(window.location.search);
  const initialContext = query.get("context") === "desktopInk" ? "desktopInk" : "recording";

  const markup = window.TalkieMarkup;
  if (!markup || !markup.State || !markup.Geometry || !markup.Layers || !markup.HitTesting || !markup.Renderer || !markup.Bridge) {
    throw new Error("TalkieMarkup modules failed to load");
  }

  const state = markup.State.createMarkupState(initialContext);
  const nowSeconds = () => markup.State.nowSeconds(state);
  const uuid = markup.State.uuid;
  const cloneLayer = markup.State.cloneLayer;
  const { post, installAPI } = markup.Bridge;
  let render = () => {};
  const geometry = markup.Geometry.createGeometry({ canvas, ctx, state, render: () => render() });
  const {
    clamp,
    drawableLeft,
    drawableTop,
    drawableWidth,
    drawableHeight,
    setDrawableRect,
    eventInsideDrawable,
    resizeCanvas,
    eventPoint,
    pointToCanvas,
    rectToCanvas,
  } = geometry;

  const noteStylePresets = {
    sticky: {
      id: "sticky",
      textColor: "#24231F",
      backgroundColor: "#FFFDF8",
      backgroundAlpha: 0.96,
      borderColor: "#8E8067",
      borderAlpha: 0.22,
      borderWidth: 0.75,
      cornerRadius: 4,
      fontSize: 13.5,
      lineHeight: 19,
      paddingX: 11,
      paddingY: 8,
      bold: false,
      shadow: true,
      shadowColor: "rgba(7, 9, 13, 0.12)",
      shadowBlur: 8,
      shadowOffsetY: 2,
      editorBackground: "rgba(255, 253, 248, 0.96)",
      editorShadow: "0 3px 12px rgba(7, 9, 13, 0.14)",
    },
    bubble: {
      id: "bubble",
      textColor: "#1C2230",
      backgroundColor: "#F7FAFF",
      backgroundAlpha: 0.95,
      borderColor: "#8A9BB5",
      borderAlpha: 0.28,
      borderWidth: 0.75,
      cornerRadius: 12,
      fontSize: 14,
      lineHeight: 21,
      paddingX: 13,
      paddingY: 10,
      bold: false,
      shadow: true,
      shadowColor: "rgba(14, 18, 28, 0.10)",
      shadowBlur: 12,
      shadowOffsetY: 3,
    },
    glass: {
      id: "glass",
      textColor: "#F6F1E8",
      backgroundColor: "#17191E",
      backgroundAlpha: 0.62,
      borderColor: "#FFFFFF",
      borderAlpha: 0.26,
      borderWidth: 0.75,
      cornerRadius: 8,
      fontSize: 13.5,
      lineHeight: 19,
      paddingX: 11,
      paddingY: 8,
      bold: false,
      shadow: true,
      shadowColor: "rgba(0, 0, 0, 0.20)",
      shadowBlur: 12,
      shadowOffsetY: 3,
      backgroundBlur: 14,
    },
    caption: {
      id: "caption",
      textColor: "#111318",
      backgroundColor: "#FFFFFF",
      backgroundAlpha: 0.78,
      borderColor: "#FFFFFF",
      borderAlpha: 0.35,
      borderWidth: 0.5,
      cornerRadius: 2,
      fontSize: 13,
      lineHeight: 18,
      paddingX: 9,
      paddingY: 6,
      bold: true,
      shadow: true,
      shadowColor: "rgba(0, 0, 0, 0.18)",
      shadowBlur: 8,
      shadowOffsetY: 2,
    },
    signal: {
      id: "signal",
      textColor: "#0D213B",
      backgroundColor: "#DCEAFF",
      backgroundAlpha: 0.95,
      borderColor: "#4F7DFF",
      borderAlpha: 0.45,
      borderWidth: 0.75,
      cornerRadius: 6,
      fontSize: 13.5,
      lineHeight: 19,
      paddingX: 11,
      paddingY: 8,
      bold: false,
      shadow: true,
      shadowColor: "rgba(26, 55, 110, 0.14)",
      shadowBlur: 10,
      shadowOffsetY: 3,
    },
  };

  const lineStylePresets = {
    solid: {
      id: "solid",
      lineDash: [],
      shadow: false,
    },
    dashed: {
      id: "dashed",
      lineDash: [12, 9],
      shadow: false,
    },
    glow: {
      id: "glow",
      lineDash: [],
      shadow: true,
      shadowColor: "rgba(255, 255, 255, 0.42)",
      shadowBlur: 14,
      shadowOffsetY: 4,
    },
  };

  const fillStylePresets = {
    none: { id: "none", alpha: 0 },
    wash: { id: "wash", alpha: 0.10 },
    tint: { id: "tint", alpha: 0.22 },
    solid: { id: "solid", alpha: 0.82 },
  };

  const arrowStylePresets = {
    straight: {
      id: "straight",
    },
    curved: {
      id: "curved",
      curveOffset: 0.2,
    },
    elbow: {
      id: "elbow",
    },
    swoop: {
      id: "swoop",
      curveOffset: 0.22,
    },
    shaped: {
      id: "shaped",
    },
  };

  const pointerStylePresets = {
    open: { id: "open" },
    filled: { id: "filled" },
    grow: { id: "grow" },
    block: { id: "block" },
  };

  const noteStyleLabels = {
    sticky: "Paper",
    bubble: "Bubble",
    glass: "Glass",
    caption: "Caption",
    signal: "Signal",
  };

  const lineStyleLabels = {
    solid: "Solid",
    dashed: "Dash",
    glow: "Glow",
  };

  const fillStyleLabels = {
    none: "None",
    wash: "Wash",
    tint: "Tint",
    solid: "Solid",
  };

  const arrowStyleLabels = {
    straight: "Straight",
    curved: "Curve",
    elbow: "Elbow",
    swoop: "Swoop",
    shaped: "Block",
  };

  const pointerStyleLabels = {
    open: "Open",
    filled: "Fill",
    grow: "Grow",
    block: "Block",
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
  const frameMinSizePixels = 12;

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

  function currentNotePreset() {
    return noteStylePresets[state.noteStyle] || noteStylePresets.sticky;
  }

  function currentLinePreset() {
    return lineStylePresets[state.lineStyle] || lineStylePresets.solid;
  }

  function currentFillPreset() {
    return fillStylePresets[state.fillStyle] || fillStylePresets.wash;
  }

  function currentArrowPreset() {
    return arrowStylePresets[state.arrowStyle] || arrowStylePresets.straight;
  }

  function currentPointerPreset() {
    return pointerStylePresets[state.pointerStyle] || pointerStylePresets.open;
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
    element.style.backgroundImage = "none";
    element.style.backgroundSize = "cover";
    element.style.backgroundPosition = "center";
  }

  function materialStyleFromSample(sample) {
    return {
      textColor: sample.textColor,
      backgroundColor: sample.backgroundColor,
      backgroundAlpha: sample.backgroundAlpha,
      borderColor: sample.borderColor,
      borderAlpha: sample.borderAlpha,
      borderWidth: sample.borderWidth,
      backgroundBlur: sample.backgroundBlur,
      shadow: true,
      shadowColor: sample.shadowColor,
      shadowBlur: sample.shadowBlur,
      shadowOffsetY: sample.shadowOffsetY,
    };
  }

  function applyMaterialStyleToEditor(element, sample) {
    if (!element || !sample) return;
    element.style.color = sample.textColor;
    element.style.borderColor = colorWithAlpha(sample.borderColor, sample.borderAlpha);
    element.style.borderWidth = `${Number(sample.borderWidth || 0.75)}px`;
    element.style.boxShadow = `0 ${Number(sample.shadowOffsetY || 3)}px ${Number(sample.shadowBlur || 12)}px ${sample.shadowColor}`;
    const tint = colorWithAlpha(sample.backgroundColor, sample.backgroundAlpha);
    element.style.backgroundColor = tint;
    element.style.backgroundImage = sample.backdropDataURL
      ? `linear-gradient(${tint}, ${tint}), url(${JSON.stringify(sample.backdropDataURL)})`
      : "none";
  }

  function applyMaterialStyleToLayer(layer, sample) {
    if (!layer || !sample) return;
    Object.assign(layer, materialStyleFromSample(sample));
  }

  function installMaterialBackdrop(layerID, sample) {
    if (!layerID || !sample || !sample.backdropDataURL) return;
    const image = new Image();
    image.onload = () => {
      state.materialBackdrops.set(layerID, {
        image,
        blur: Number(sample.backgroundBlur || 0),
      });
      render();
    };
    image.src = sample.backdropDataURL;
  }

  function requestGlassMaterialForCanvasRect(rect, target) {
    if (!rect || rect.width < 1 || rect.height < 1) return null;
    state.materialRequestSequence += 1;
    const requestID = `glass-${state.materialRequestSequence}`;
    state.materialRequests.set(requestID, target);
    if (target.kind === "layer") {
      state.latestMaterialRequestByLayer.set(target.layerID, requestID);
    }
    post("liveMarkup.sampleMaterial", {
      requestID,
      rect: {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
      },
    });
    return requestID;
  }

  function requestGlassMaterialForLayer(layer) {
    if (!layer || layer.kind !== "label" || layer.noteStyle !== "glass" || !layer.frame) return null;
    return requestGlassMaterialForCanvasRect(rectToCanvas(layer.frame), {
      kind: "layer",
      layerID: layer.id,
    });
  }

  function requestGlassMaterialForEditor(active) {
    if (!active || active.noteStyle !== "glass" || !active.element.isConnected) return null;
    const rect = active.element.getBoundingClientRect();
    const requestID = requestGlassMaterialForCanvasRect(rect, { kind: "editor" });
    active.materialRequestID = requestID;
    return requestID;
  }

  function applyMaterialSample(sample) {
    if (!sample || !sample.requestID) return;
    const target = state.materialRequests.get(sample.requestID);
    state.materialRequests.delete(sample.requestID);
    if (!target) return;

    if (target.kind === "editor") {
      const active = state.noteEditor;
      if (!active || active.materialRequestID !== sample.requestID || active.noteStyle !== "glass") return;
      active.materialStyle = materialStyleFromSample(sample);
      active.backdropDataURL = sample.backdropDataURL;
      applyMaterialStyleToEditor(active.element, sample);
      return;
    }

    if (target.kind === "layer") {
      if (state.latestMaterialRequestByLayer.get(target.layerID) !== sample.requestID) return;
      state.latestMaterialRequestByLayer.delete(target.layerID);
      const layer = state.layers.find((candidate) => candidate.id === target.layerID);
      if (!layer || layer.noteStyle !== "glass") return;
      applyMaterialStyleToLayer(layer, sample);
      installMaterialBackdrop(layer.id, sample);
      render();
      sendUpdate();
    }
  }

  function isTypingTarget(target) {
    return target
      && (
        target.tagName === "TEXTAREA"
        || target.tagName === "INPUT"
        || target.isContentEditable
      );
  }

  function snappedSegmentPoint(start, point) {
    const dx = (point.x - start.x) * drawableWidth();
    const dy = (point.y - start.y) * drawableHeight();
    const distance = Math.hypot(dx, dy);
    if (distance < 0.0001) return point;

    const angle = Math.atan2(dy, dx);
    const snappedAngle = Math.round(angle / angleSnapStep) * angleSnapStep;
    return {
      x: clamp(start.x + Math.cos(snappedAngle) * distance / Math.max(1, drawableWidth()), 0, 1),
      y: clamp(start.y + Math.sin(snappedAngle) * distance / Math.max(1, drawableHeight()), 0, 1),
    };
  }

  function adjustedSegmentPoint(creating, point, event) {
    if (!creating || !["line", "arrow"].includes(creating.tool)) return point;
    if (!(event && event.shiftKey)) return point;
    return snappedSegmentPoint(creating.start, point);
  }

  const layers = markup.Layers.createLayers({
    state,
    arrowStylePresets,
    cloneLayer,
    uuid,
    noteFrameForText,
  });
  const {
    isStrokeEditableLayer,
    previewLayer,
    selectedLayer,
    duplicateLayer,
    applyNotePresetToLayer,
    applyLinePresetToLayer,
    applyFillPresetToLayer,
    applyArrowPresetToLayer,
    applyPointerPresetToLayer,
  } = layers;

  const hitTesting = markup.HitTesting.createHitTesting({ state, layers, geometry });
  const {
    arrowControlPoint,
    layerBounds,
    hitTestLayer,
    cursorForFrameHandle,
    selectedHandleAt,
    cursorForSelectPoint,
  } = hitTesting;

  const renderer = markup.Renderer.createRenderer({
    ctx,
    state,
    geometry,
    layers,
    hitTesting,
    colorWithAlpha,
  });
  const {
    noteFont,
    wrapText,
    render: renderMarkup,
  } = renderer;
  render = renderMarkup;

  function noteFrameForText(text, point, preset = currentNotePreset()) {
    ctx.save();
    ctx.font = noteFont({ fontSize: preset.fontSize || 15 });
    const maxWidth = Math.min(320, Math.max(180, drawableWidth() * 0.32));
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
      Math.max(point.x * drawableWidth(), 12),
      Math.max(12, drawableWidth() - width - 12)
    );
    const top = Math.min(
      Math.max(point.y * drawableHeight(), 12),
      Math.max(12, drawableHeight() - height - 12)
    );
    return {
      x: left / drawableWidth(),
      y: top / drawableHeight(),
      width: width / drawableWidth(),
      height: height / drawableHeight(),
    };
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
      imageWidth: drawableWidth(),
      imageHeight: drawableHeight(),
      mode: state.mode,
      layers: state.layers,
    };
  }

  canvas.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    if (dock && dock.contains(event.target)) return;
    if (!eventInsideDrawable(event)) return;
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
    const fillPreset = currentFillPreset();
    const arrowPreset = currentArrowPreset();
    const pointerPreset = currentPointerPreset();
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
      fillStyle: fillPreset.id,
      fillColor: state.color,
      fillAlpha: fillPreset.alpha,
      pointerStart: "none",
      pointerEnd: pointerPreset.id,
      pointerStyle: pointerPreset.id,
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
        resizeSegmentHandle(state.dragging.layerId, state.dragging.original, state.dragging.handle, dx, dy, event);
        canvas.style.cursor = "grabbing";
        render();
        return;
      }
      if (state.dragging.copyRequested && !state.dragging.copied) {
        const distance = Math.hypot(dx * drawableWidth(), dy * drawableHeight());
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
      if (Math.hypot(dx * drawableWidth(), dy * drawableHeight()) >= 2) {
        creating.points.push(point);
      }
    }
    render();
  });

  function finishPointer(event) {
    if (state.dragging) {
      const draggedLayerID = state.dragging.layerId;
      if (event && canvas.hasPointerCapture(event.pointerId)) {
        canvas.releasePointerCapture(event.pointerId);
      }
      state.dragging = null;
      document.body.classList.remove("dragging");
      const point = event ? eventPoint(event) : null;
      canvas.style.cursor = point ? cursorForSelectPoint(point) : "default";
      render();
      sendUpdate();
      const draggedLayer = state.layers.find((layer) => layer.id === draggedLayerID);
      if (draggedLayer && draggedLayer.noteStyle === "glass") {
        requestGlassMaterialForLayer(draggedLayer);
      }
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
        (creating.current.x - creating.start.x) * drawableWidth(),
        (creating.current.y - creating.start.y) * drawableHeight()
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
    const minWidth = frameMinSizePixels / Math.max(1, drawableWidth());
    const minHeight = frameMinSizePixels / Math.max(1, drawableHeight());
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

  function curveOffsetForControlPoint(layer, controlPoint) {
    if (!layer || !layer.from || !layer.to || !controlPoint) return 0.2;
    const from = pointToCanvas(layer.from);
    const to = pointToCanvas(layer.to);
    const control = pointToCanvas(controlPoint);
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const distance = Math.hypot(dx, dy);
    if (distance < 0.0001) return Number(layer.curveOffset || 0.2);

    const midX = (from.x + to.x) / 2;
    const midY = (from.y + to.y) / 2;
    const normalX = -dy / distance;
    const normalY = dx / distance;
    const offsetPixels = (control.x - midX) * normalX + (control.y - midY) * normalY;
    return clamp(offsetPixels / distance, -0.8, 0.8);
  }

  function resizeSegmentHandle(layerId, original, handle, dx, dy, event) {
    const index = state.layers.findIndex((layer) => layer.id === layerId);
    if (index < 0 || !original.from || !original.to) return;
    const next = cloneLayer(original);
    if (handle === "curve") {
      const control = arrowControlPoint(original);
      if (!control) return;
      next.arrowStyle = "curved";
      next.curveOffset = curveOffsetForControlPoint(original, movedPoint(control, dx, dy));
    } else if (handle === "from") {
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
    const style = active.materialStyle ? { ...preset, ...active.materialStyle } : preset;
    const noteStyle = active.noteStyle || state.noteStyle;
    const layer = {
      id: uuid(),
      kind: "label",
      frame: noteFrameForText(text, active.point, preset),
      text,
      label: text,
      color: state.color,
      textColor: style.textColor,
      backgroundColor: style.backgroundColor,
      backgroundAlpha: style.backgroundAlpha,
      borderColor: style.borderColor,
      borderAlpha: style.borderAlpha,
      borderWidth: style.borderWidth,
      cornerRadius: preset.cornerRadius,
      paddingX: preset.paddingX,
      paddingY: preset.paddingY,
      fontSize: preset.fontSize,
      lineHeight: preset.lineHeight,
      fontFamily: "sans",
      bold: preset.bold,
      backgroundBlur: style.backgroundBlur,
      shadow: style.shadow,
      shadowColor: style.shadowColor,
      shadowBlur: style.shadowBlur,
      shadowOffsetY: style.shadowOffsetY,
      intent: active.mode || state.mode,
      noteStyle,
      stylePreset: preset.id,
      author: "user",
      visible: true,
      startTime: active.startTime,
      endTime: nowSeconds(),
    };
    state.layers.push(layer);
    if (noteStyle === "glass" && active.backdropDataURL) {
      installMaterialBackdrop(layer.id, {
        backdropDataURL: active.backdropDataURL,
        backgroundBlur: style.backgroundBlur,
      });
    }
    state.redoStack = [];
    state.selectedLayerId = layer.id;
    render();
    sendUpdate();
    if (noteStyle === "glass") requestGlassMaterialForLayer(layer);
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
      Math.max(point.x * drawableWidth(), 12),
      Math.max(12, drawableWidth() - 320)
    );
    element.style.left = `${drawableLeft() + editorLeft}px`;
    element.style.top = `${drawableTop() + Math.min(Math.max(point.y * drawableHeight(), 12), drawableHeight() - 80)}px`;
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
    requestAnimationFrame(() => {
      if (state.noteEditor && state.noteEditor.element === element) {
        requestGlassMaterialForEditor(state.noteEditor);
      }
      element.focus();
    });
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

      const fillStyle = button.getAttribute("data-fill-style");
      if (fillStyle) {
        setFillStyle(fillStyle);
        return;
      }

      const arrowStyle = button.getAttribute("data-arrow-style");
      if (arrowStyle) {
        setArrowStyle(arrowStyle);
        return;
      }

      const pointerStyle = button.getAttribute("data-pointer-style");
      if (pointerStyle) {
        setPointerStyle(pointerStyle);
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
    controls.querySelectorAll(".fill-style").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-fill-style") === state.fillStyle);
    });
    controls.querySelectorAll(".arrow-style").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-arrow-style") === state.arrowStyle);
    });
    controls.querySelectorAll(".pointer-style").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-pointer-style") === state.pointerStyle);
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
      state.noteEditor.materialStyle = null;
      state.noteEditor.backdropDataURL = null;
      applyNotePresetToEditor(state.noteEditor.element, preset);
      if (noteStyle === "glass") requestGlassMaterialForEditor(state.noteEditor);
    }
    const layer = selectedLayer();
    if (applyNotePresetToLayer(layer, preset)) {
      if (layer && noteStyle !== "glass") {
        state.materialBackdrops.delete(layer.id);
        state.latestMaterialRequestByLayer.delete(layer.id);
      }
      render();
      sendUpdate();
      if (layer && noteStyle === "glass") requestGlassMaterialForLayer(layer);
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

  function setFillStyle(fillStyle) {
    if (!fillStylePresets[fillStyle]) return;
    state.fillStyle = fillStyle;
    document.body.dataset.fillStyle = fillStyle;
    if (applyFillPresetToLayer(selectedLayer(), currentFillPreset())) {
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

  function setPointerStyle(pointerStyle) {
    if (!pointerStylePresets[pointerStyle]) return;
    state.pointerStyle = pointerStyle;
    document.body.dataset.pointerStyle = pointerStyle;
    if (applyPointerPresetToLayer(selectedLayer(), currentPointerPreset())) {
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
    const fill = fillStyleLabels[state.fillStyle] || state.fillStyle;
    const arrow = arrowStyleLabels[state.arrowStyle] || state.arrowStyle;
    const pointer = pointerStyleLabels[state.pointerStyle] || state.pointerStyle;
    const width = `${Number(state.strokeWidth)}px`;
    switch (tool) {
    case "note":
      return note;
    case "arrow":
      return `${arrow} · ${pointer} · ${line} · ${width}`;
    case "line":
      return `${line} · ${width}`;
    case "ink":
      return `${line} · ${width}`;
    case "rect":
      return `${fill} · ${line} · ${width}`;
    case "ellipse":
      return `${fill} · ${line} · ${width}`;
    default:
      return "Move and reshape";
    }
  }

  function setColor(color) {
    state.color = color;
    const layer = selectedLayer();
    if (layer && isStrokeEditableLayer(layer)) {
      layer.color = color;
      if (["rect", "ellipse"].includes(layer.kind)) layer.fillColor = color;
      render();
      sendUpdate();
    }
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
    if (!event.metaKey && !event.ctrlKey && !event.altKey && key === "v") {
      setTool("select");
      event.preventDefault();
    } else if (event.key === "Escape" && state.tool !== "select") {
      setTool("select");
      event.preventDefault();
    } else if (event.key === "Escape" || key === "x") {
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

  installAPI({
    exportDocument,
    setTool,
    setColor,
    setStrokeWidth,
    setNoteStyle,
    setLineStyle,
    setFillStyle,
    setArrowStyle,
    setPointerStyle,
    applyMaterialSample,
    setStyleOpen,
    setContext,
    setDrawableRect,
    undo,
    redo,
    done,
    capture,
    cancel,
    clear() {
      state.layers = [];
      state.redoStack = [];
      state.materialBackdrops.clear();
      state.materialRequests.clear();
      state.latestMaterialRequestByLayer.clear();
      render();
      sendUpdate();
    },
  });

  window.addEventListener("resize", resizeCanvas);
  resizeCanvas();
  document.body.dataset.tool = state.tool;
  document.body.dataset.mode = state.mode;
  document.body.dataset.noteStyle = state.noteStyle;
  document.body.dataset.lineStyle = state.lineStyle;
  document.body.dataset.fillStyle = state.fillStyle;
  document.body.dataset.arrowStyle = state.arrowStyle;
  document.body.dataset.pointerStyle = state.pointerStyle;
  document.body.dataset.styleOpen = state.styleOpen ? "true" : "false";
  setContext(state.context);
  setStyleOpen(state.styleOpen);
  post("liveMarkup.ready", {});
})();
