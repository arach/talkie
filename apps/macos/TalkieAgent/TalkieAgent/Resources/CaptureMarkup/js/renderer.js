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

    function drawElbowArrow(layer, from, to, width) {
      const dx = to.x - from.x;
      const dy = to.y - from.y;
      if (Math.abs(dx) < 8 || Math.abs(dy) < 8) {
        drawStraightArrow(layer, from, to, width);
        return;
      }
      const corner = { x: to.x, y: from.y };
      const radius = Math.min(18, Math.abs(dx) * 0.28, Math.abs(dy) * 0.28);
      const before = { x: corner.x - Math.sign(dx) * radius, y: corner.y };
      const after = { x: corner.x, y: corner.y + Math.sign(dy) * radius };
      ctx.beginPath();
      ctx.moveTo(from.x, from.y);
      ctx.lineTo(before.x, before.y);
      ctx.quadraticCurveTo(corner.x, corner.y, after.x, after.y);
      ctx.lineTo(to.x, to.y);
      applyLayerShadow(layer);
      ctx.stroke();
      clearLayerShadow();
      ctx.setLineDash([]);
      drawArrowHead(before, from, width, pointerStyleForLayer(layer, "start"));
      drawArrowHead(after, to, width, pointerStyleForLayer(layer, "end"));
    }

    function swoopControlPoints(layer, from, to) {
      const dx = to.x - from.x;
      const dy = to.y - from.y;
      const distance = Math.hypot(dx, dy);
      if (distance < 0.0001) return { first: from, second: to };
      const normalX = -dy / distance;
      const normalY = dx / distance;
      const offset = distance * Number(layer.curveOffset || 0.18);
      return {
        first: {
          x: from.x + dx * 0.28 + normalX * offset,
          y: from.y + dy * 0.28 + normalY * offset,
        },
        second: {
          x: from.x + dx * 0.72 - normalX * offset * 0.75,
          y: from.y + dy * 0.72 - normalY * offset * 0.75,
        },
      };
    }

    function addSwoopPath(layer, from, to) {
      const controls = swoopControlPoints(layer, from, to);
      ctx.moveTo(from.x, from.y);
      ctx.bezierCurveTo(
        controls.first.x,
        controls.first.y,
        controls.second.x,
        controls.second.y,
        to.x,
        to.y
      );
      return controls;
    }

    function drawSwoopArrow(layer, from, to, width) {
      ctx.save();
      ctx.setLineDash([]);
      ctx.globalAlpha = 0.12;
      ctx.lineWidth = Math.max(width + 3, width * 2.4);
      ctx.beginPath();
      addSwoopPath(layer, from, to);
      ctx.stroke();
      ctx.restore();

      ctx.beginPath();
      const controls = addSwoopPath(layer, from, to);
      applyLayerShadow(layer);
      ctx.stroke();
      clearLayerShadow();
      ctx.setLineDash([]);
      drawArrowHead(controls.first, from, width, pointerStyleForLayer(layer, "start"));
      drawArrowHead(controls.second, to, width, pointerStyleForLayer(layer, "end"));
    }

    function sampledArrowPath(layer, from, to, steps = 40) {
      const style = arrowStyleForLayer(layer);
      if (style === "curved") {
        const control = arrowControlPointPixels(layer);
        if (!control) return [from, to];
        return Array.from({ length: steps + 1 }, (_, index) => {
          const t = index / steps;
          const inv = 1 - t;
          return {
            x: inv * inv * from.x + 2 * inv * t * control.x + t * t * to.x,
            y: inv * inv * from.y + 2 * inv * t * control.y + t * t * to.y,
          };
        });
      }
      if (style === "swoop") {
        const controls = swoopControlPoints(layer, from, to);
        return Array.from({ length: steps + 1 }, (_, index) => {
          const t = index / steps;
          const inv = 1 - t;
          return {
            x: inv * inv * inv * from.x
              + 3 * inv * inv * t * controls.first.x
              + 3 * inv * t * t * controls.second.x
              + t * t * t * to.x,
            y: inv * inv * inv * from.y
              + 3 * inv * inv * t * controls.first.y
              + 3 * inv * t * t * controls.second.y
              + t * t * t * to.y,
          };
        });
      }
      return [from, to];
    }

    function ribbonBodyPoints(points, headLength) {
      if (points.length < 2) return null;
      const lengths = [0];
      for (let index = 1; index < points.length; index += 1) {
        lengths.push(lengths[index - 1] + Math.hypot(
          points[index].x - points[index - 1].x,
          points[index].y - points[index - 1].y
        ));
      }
      const total = lengths[lengths.length - 1];
      if (total < 18) return null;
      const neckDistance = Math.max(total * 0.52, total - Math.min(headLength, total * 0.38));
      let index = 1;
      while (index < lengths.length && lengths[index] < neckDistance) index += 1;
      const beforeIndex = Math.max(0, index - 1);
      const afterIndex = Math.min(points.length - 1, index);
      const span = Math.max(0.0001, lengths[afterIndex] - lengths[beforeIndex]);
      const t = (neckDistance - lengths[beforeIndex]) / span;
      const neck = {
        x: points[beforeIndex].x + (points[afterIndex].x - points[beforeIndex].x) * t,
        y: points[beforeIndex].y + (points[afterIndex].y - points[beforeIndex].y) * t,
      };
      return {
        points: points.slice(0, afterIndex).concat(neck),
        neck,
        tip: points[points.length - 1],
      };
    }

    function normalAt(points, index) {
      const previous = points[Math.max(0, index - 1)];
      const next = points[Math.min(points.length - 1, index + 1)];
      const dx = next.x - previous.x;
      const dy = next.y - previous.y;
      const distance = Math.max(0.0001, Math.hypot(dx, dy));
      return { x: -dy / distance, y: dx / distance };
    }

    function drawRibbonArrow(layer, from, to, width, style) {
      const block = style === "block";
      const headLength = Math.max(block ? 20 : 22, width * (block ? 5.2 : 5.4));
      const body = ribbonBodyPoints(sampledArrowPath(layer, from, to), headLength);
      if (!body) {
        drawStraightArrow(layer, from, to, width);
        return;
      }

      const startHalf = block ? Math.max(2.6, width * 0.95) : Math.max(0.55, width * 0.16);
      const endHalf = block ? startHalf : Math.max(1.7, width * 0.88);
      const headHalf = block
        ? Math.max(7, endHalf * 2.05, width * 2.2)
        : Math.max(7, endHalf * 1.75, width * 1.9);
      const left = [];
      const right = [];
      body.points.forEach((point, index) => {
        const progress = index / Math.max(1, body.points.length - 1);
        const half = startHalf + (endHalf - startHalf) * Math.pow(progress, 0.78);
        const normal = normalAt(body.points, index);
        left.push({ x: point.x + normal.x * half, y: point.y + normal.y * half });
        right.push({ x: point.x - normal.x * half, y: point.y - normal.y * half });
      });
      const neckNormal = normalAt(body.points.concat(body.tip), body.points.length - 1);
      const headLeft = {
        x: body.neck.x + neckNormal.x * headHalf,
        y: body.neck.y + neckNormal.y * headHalf,
      };
      const headRight = {
        x: body.neck.x - neckNormal.x * headHalf,
        y: body.neck.y - neckNormal.y * headHalf,
      };

      ctx.save();
      ctx.setLineDash([]);
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(left[0].x, left[0].y);
      left.slice(1).forEach((point) => ctx.lineTo(point.x, point.y));
      ctx.lineTo(headLeft.x, headLeft.y);
      ctx.lineTo(body.tip.x, body.tip.y);
      ctx.lineTo(headRight.x, headRight.y);
      right.slice().reverse().forEach((point) => ctx.lineTo(point.x, point.y));
      ctx.closePath();
      applyLayerShadow(layer);
      ctx.globalAlpha = 0.95;
      ctx.fillStyle = ctx.strokeStyle;
      ctx.fill();
      clearLayerShadow();
      ctx.globalAlpha = 1;
      ctx.strokeStyle = colorWithAlpha(layer.color || "#D03A1C", 0.9);
      ctx.lineWidth = Math.max(0.8, width * 0.22);
      ctx.stroke();
      ctx.restore();
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
      const endPointer = pointerStyleForLayer(layer, "end");
      if (endPointer === "grow" || endPointer === "block") {
        drawRibbonArrow(layer, from, to, width, endPointer);
        return;
      }
      switch (arrowStyleForLayer(layer)) {
      case "curved":
        drawCurvedArrow(layer, from, to, width);
        break;
      case "elbow":
        drawElbowArrow(layer, from, to, width);
        break;
      case "swoop":
        drawSwoopArrow(layer, from, to, width);
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
      return ["none", "open", "filled", "dot", "bar", "grow", "block"].includes(value) ? value : "open";
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

    function drawPrivacyBlur(layer) {
      const rect = rectToCanvas(layer.frame);
      if (rect.width < 1 || rect.height < 1) return;

      const source = state.sourceImage;
      if (source && source.naturalWidth > 0 && source.naturalHeight > 0) {
        const sample = document.createElement("canvas");
        sample.width = Math.max(1, Math.ceil(rect.width / 12));
        sample.height = Math.max(1, Math.ceil(rect.height / 12));
        const sampleContext = sample.getContext("2d");
        const frame = layer.frame;
        sampleContext.drawImage(
          source,
          frame.x * source.naturalWidth,
          frame.y * source.naturalHeight,
          frame.width * source.naturalWidth,
          frame.height * source.naturalHeight,
          0,
          0,
          sample.width,
          sample.height
        );
        ctx.imageSmoothingEnabled = false;
        ctx.drawImage(sample, rect.x, rect.y, rect.width, rect.height);
      } else {
        const cell = Math.max(6, Math.min(14, Math.floor(Math.min(rect.width, rect.height) / 4)));
        for (let y = 0; y < rect.height; y += cell) {
          for (let x = 0; x < rect.width; x += cell) {
            const shade = 72 + ((Math.floor(x / cell) * 17 + Math.floor(y / cell) * 29) % 46);
            ctx.fillStyle = `rgb(${shade}, ${shade}, ${shade})`;
            ctx.fillRect(rect.x + x, rect.y + y, Math.min(cell, rect.width - x), Math.min(cell, rect.height - y));
          }
        }
      }

      ctx.strokeStyle = "rgba(255, 255, 255, 0.24)";
      ctx.lineWidth = 1;
      ctx.strokeRect(rect.x + 0.5, rect.y + 0.5, Math.max(0, rect.width - 1), Math.max(0, rect.height - 1));
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
        const fillAlpha = Number(layer.fillAlpha || 0);
        if (fillAlpha > 0) {
          ctx.save();
          ctx.globalAlpha = Math.min(1, Math.max(0, fillAlpha));
          ctx.fillStyle = layer.fillColor || layer.color || "#D03A1C";
          ctx.fill();
          ctx.restore();
        }
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
        const fillAlpha = Number(layer.fillAlpha || 0);
        if (fillAlpha > 0) {
          ctx.save();
          ctx.globalAlpha = Math.min(1, Math.max(0, fillAlpha));
          ctx.fillStyle = layer.fillColor || layer.color || "#D03A1C";
          ctx.fill();
          ctx.restore();
        }
        applyLayerShadow(layer);
        ctx.stroke();
      } else if (layer.kind === "highlight" && layer.frame && layer.label === "BLUR") {
        drawPrivacyBlur(layer);
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
        const materialBackdrop = state.materialBackdrops.get(layer.id);
        if (layer.noteStyle === "glass" && materialBackdrop && materialBackdrop.image) {
          ctx.save();
          ctx.beginPath();
          roundedRect(rect.x, rect.y, rect.width, rect.height, Number(layer.cornerRadius || 8));
          ctx.clip();
          ctx.drawImage(materialBackdrop.image, rect.x, rect.y, rect.width, rect.height);
          ctx.restore();
        }
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
      const frameHandles = frameHandlePoints(layer);
      if (frameHandles.length) {
        const handleSize = 8;
        for (const handle of frameHandles) {
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
