(() => {
  const root = window.TalkieMarkup = window.TalkieMarkup || {};

  function createLayers({
    state,
    arrowStylePresets,
    cloneLayer,
    uuid,
    noteFrameForText,
  }) {
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

    return {
      isLineLayer,
      isStrokeEditableLayer,
      frameFromPoints,
      normalizedRectFromPoints,
      normalizedArrowStyle,
      arrowStyleForLayer,
      previewLayer,
      selectedLayer,
      duplicateLayer,
      applyNotePresetToLayer,
      applyLinePresetToLayer,
      applyArrowPresetToLayer,
    };
  }

  root.Layers = {
    createLayers,
  };
})();
