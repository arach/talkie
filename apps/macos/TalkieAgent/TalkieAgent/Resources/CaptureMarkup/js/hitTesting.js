(() => {
  const root = window.TalkieMarkup = window.TalkieMarkup || {};

  function createHitTesting({ state, layers, geometry }) {
    const {
      clamp,
      drawableWidth,
      drawableHeight,
      pointToCanvas,
      canvasToPoint,
      rectToCanvas,
    } = geometry;

    const frameHandleGrabPixels = 18;
    const segmentHandleGrabPixels = 20;

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
      return canvasToPoint(control);
    }

    function paddedRect(rect, pixels) {
      if (!rect) return null;
      const dx = pixels / Math.max(1, drawableWidth());
      const dy = pixels / Math.max(1, drawableHeight());
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
        const control = layers.arrowStyleForLayer(layer) === "curved" ? arrowControlPoint(layer) : null;
        if (control) points.push(control);
        return paddedRect(layers.normalizedRectFromPoints(points), 10);
      }
      if (layer.points && layer.points.length) {
        return paddedRect(layers.normalizedRectFromPoints(layer.points), Number(layer.strokeWidth || 4) + 6);
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
      const px = point.x * drawableWidth();
      const py = point.y * drawableHeight();
      const ax = a.x * drawableWidth();
      const ay = a.y * drawableHeight();
      const bx = b.x * drawableWidth();
      const by = b.y * drawableHeight();
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
      if (layers.arrowStyleForLayer(layer) === "curved") {
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
        const threshold = layers.arrowStyleForLayer(layer) === "shaped" ? Math.max(18, width * 4) : Math.max(14, width + 10);
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

    function frameHandlePoints(layer) {
      if (!layer || !layer.frame) return [];
      const frame = rectToCanvas(layer.frame);
      const left = frame.x;
      const top = frame.y;
      const right = frame.x + frame.width;
      const bottom = frame.y + frame.height;
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
      const canvasPoint = pointToCanvas(point);
      const px = canvasPoint.x;
      const py = canvasPoint.y;
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
      const handles = [
        { name: "from", x: from.x, y: from.y },
        { name: "to", x: to.x, y: to.y },
      ];
      if (layers.arrowStyleForLayer(layer) === "curved") {
        const control = arrowControlPointPixels(layer);
        if (control) handles.push({ name: "curve", x: control.x, y: control.y });
      }
      return handles;
    }

    function segmentHandleAt(point, layer) {
      const canvasPoint = pointToCanvas(point);
      const px = canvasPoint.x;
      const py = canvasPoint.y;
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
      const layer = layers.selectedLayer();
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

    return {
      arrowControlPointPixels,
      arrowControlPoint,
      paddedRect,
      layerBounds,
      rectContains,
      distanceToSegment,
      distanceToQuadraticCurve,
      distanceToArrowPath,
      layerContainsPoint,
      hitTestLayer,
      frameHandlePoints,
      frameHandleAt,
      segmentHandlePoints,
      segmentHandleAt,
      cursorForFrameHandle,
      selectedHandleAt,
      cursorForSelectPoint,
    };
  }

  root.HitTesting = {
    createHitTesting,
  };
})();
