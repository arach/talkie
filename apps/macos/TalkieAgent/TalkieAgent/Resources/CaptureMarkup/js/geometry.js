(() => {
  const root = window.TalkieMarkup = window.TalkieMarkup || {};

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function viewportWidth() {
    return Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1);
  }

  function viewportHeight() {
    return Math.max(1, window.innerHeight || document.documentElement.clientHeight || 1);
  }

  function createGeometry({ canvas, ctx, state, render }) {
    function sanitizeDrawableRect(rect) {
      if (!rect) {
        return { x: 0, y: 0, width: viewportWidth(), height: viewportHeight() };
      }
      const x = clamp(Number(rect.x || 0), 0, viewportWidth() - 1);
      const y = clamp(Number(rect.y || 0), 0, viewportHeight() - 1);
      const maxWidth = Math.max(1, viewportWidth() - x);
      const maxHeight = Math.max(1, viewportHeight() - y);
      return {
        x,
        y,
        width: clamp(Number(rect.width || maxWidth), 1, maxWidth),
        height: clamp(Number(rect.height || maxHeight), 1, maxHeight),
      };
    }

    function drawableRect() {
      return sanitizeDrawableRect(state.drawableRect);
    }

    function drawableLeft() {
      return drawableRect().x;
    }

    function drawableTop() {
      return drawableRect().y;
    }

    function drawableWidth() {
      return drawableRect().width;
    }

    function drawableHeight() {
      return drawableRect().height;
    }

    function setDrawableRect(rect) {
      // Keep the host's requested geometry intact. During native live-resize,
      // WKWebView can receive this update before its viewport has caught up;
      // clamping here would permanently bake in the previous window size and
      // make normalized markup appear to float away from the resized image.
      state.drawableRect = rect ? {
        x: Number(rect.x || 0),
        y: Number(rect.y || 0),
        width: Number(rect.width || viewportWidth()),
        height: Number(rect.height || viewportHeight()),
      } : null;
      const drawable = drawableRect();
      const hasReservedControls = drawable.y + drawable.height < viewportHeight() - 4;
      document.body.dataset.protectedDock = hasReservedControls ? "true" : "false";
      render();
    }

    function eventInsideDrawable(event) {
      const rect = canvas.getBoundingClientRect();
      const drawable = drawableRect();
      const x = event.clientX - rect.left;
      const y = event.clientY - rect.top;
      return x >= drawable.x
        && x <= drawable.x + drawable.width
        && y >= drawable.y
        && y <= drawable.y + drawable.height;
    }

    function resizeCanvas() {
      const scale = window.devicePixelRatio || 1;
      canvas.width = Math.max(1, Math.round(viewportWidth() * scale));
      canvas.height = Math.max(1, Math.round(viewportHeight() * scale));
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      render();
    }

    function eventPoint(event) {
      const rect = canvas.getBoundingClientRect();
      const drawable = drawableRect();
      return {
        x: clamp((event.clientX - rect.left - drawable.x) / drawable.width, 0, 1),
        y: clamp((event.clientY - rect.top - drawable.y) / drawable.height, 0, 1),
      };
    }

    function pointToCanvas(point) {
      return {
        x: drawableLeft() + point.x * drawableWidth(),
        y: drawableTop() + point.y * drawableHeight(),
      };
    }

    function canvasToPoint(point) {
      return {
        x: clamp((point.x - drawableLeft()) / Math.max(1, drawableWidth()), 0, 1),
        y: clamp((point.y - drawableTop()) / Math.max(1, drawableHeight()), 0, 1),
      };
    }

    function rectToCanvas(rect) {
      return {
        x: drawableLeft() + rect.x * drawableWidth(),
        y: drawableTop() + rect.y * drawableHeight(),
        width: rect.width * drawableWidth(),
        height: rect.height * drawableHeight(),
      };
    }

    return {
      clamp,
      viewportWidth,
      viewportHeight,
      drawableRect,
      drawableLeft,
      drawableTop,
      drawableWidth,
      drawableHeight,
      setDrawableRect,
      eventInsideDrawable,
      resizeCanvas,
      eventPoint,
      pointToCanvas,
      canvasToPoint,
      rectToCanvas,
    };
  }

  root.Geometry = {
    clamp,
    viewportWidth,
    viewportHeight,
    createGeometry,
  };
})();
