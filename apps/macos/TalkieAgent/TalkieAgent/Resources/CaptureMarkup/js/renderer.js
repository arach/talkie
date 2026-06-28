(() => {
  const root = window.TalkieMarkup = window.TalkieMarkup || {};

  function createRenderer({
    ctx,
    state,
    geometry,
    layers,
    hitTesting,
    colorWithAlpha,
  }) {
    const {
      viewportWidth,
      viewportHeight,
      drawableRect,
      drawableWidth,
      drawableHeight,
      pointToCanvas,
      rectToCanvas,
    } = geometry;
    const {
      isLineLayer,
      arrowStyleForLayer,
      previewLayer,
    } = layers;
    const {
      arrowControlPointPixels,
      layerBounds,
      frameHandlePoints,
      segmentHandlePoints,
    } = hitTesting;

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
          Math.max(1, frame.width * drawableWidth() / 2),
          Math.max(1, frame.height * drawableHeight() / 2),
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
          Math.max(1, frame.width * drawableWidth()),
          Math.max(1, frame.height * drawableHeight())
        );
        applyLayerShadow(layer);
        ctx.stroke();
      } else if (layer.kind === "arrow" && layer.from && layer.to) {
        drawArrowLayer(layer, width);
      } else if (layer.kind === "label" && layer.frame) {
        const rect = rectToCanvas(layer.frame);
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
      ctx.save();
      if (layer.from && layer.to) {
        ctx.setLineDash([]);
        ctx.fillStyle = "#FFFFFF";
        ctx.strokeStyle = "rgba(79, 125, 255, 0.95)";
        ctx.lineWidth = 1.4;
        for (const handle of segmentHandlePoints(layer)) {
          const isCurve = handle.name === "curve";
          ctx.beginPath();
          ctx.arc(handle.x, handle.y, isCurve ? 6 : 5.25, 0, Math.PI * 2);
          ctx.fillStyle = isCurve ? "rgba(79, 125, 255, 0.96)" : "#FFFFFF";
          ctx.strokeStyle = isCurve ? "#FFFFFF" : "rgba(79, 125, 255, 0.95)";
          ctx.fill();
          ctx.stroke();
        }
        ctx.restore();
        return;
      }

      const bounds = layerBounds(layer);
      if (!bounds) {
        ctx.restore();
        return;
      }
      const rect = rectToCanvas(bounds);
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
      }
      ctx.restore();
    }

    function render() {
      ctx.clearRect(0, 0, viewportWidth(), viewportHeight());
      const drawable = drawableRect();
      ctx.save();
      ctx.beginPath();
      ctx.rect(drawable.x, drawable.y, drawable.width, drawable.height);
      ctx.clip();
      for (const layer of state.layers) drawLayer(layer);
      const selectedLayer = state.layers.find((layer) => layer.id === state.selectedLayerId);
      if (state.tool === "select" && selectedLayer) drawSelection(selectedLayer);
      if (state.creating) drawLayer(previewLayer(state.creating));
      ctx.restore();
    }

    return {
      noteFont,
      wrapText,
      drawLayer,
      drawSelection,
      render,
    };
  }

  root.Renderer = {
    createRenderer,
  };
})();
