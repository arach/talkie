namespace Hudson.Viewport {
  export function clampZoom(viewport: Hudson.ViewportState, zoom: number): number {
    const min = viewport.minZoom ?? 0.25;
    const max = viewport.maxZoom ?? 4;
    return Math.max(min, Math.min(max, zoom));
  }

  export function screenToWorld(viewport: Hudson.ViewportState, x: number, y: number): Hudson.Point {
    return {
      x: (x - viewport.panX) / viewport.zoom,
      y: (y - viewport.panY) / viewport.zoom,
    };
  }

  export function worldToNorm(viewport: Hudson.ViewportState, point: Hudson.Point): Hudson.NormPoint {
    return {
      nx: point.x / Math.max(1, viewport.width),
      ny: point.y / Math.max(1, viewport.height),
      px: point.x,
      py: point.y,
    };
  }

  export function screenToNorm(viewport: Hudson.ViewportState, x: number, y: number): Hudson.NormPoint {
    return worldToNorm(viewport, screenToWorld(viewport, x, y));
  }

  export function fit(viewport: Hudson.ViewportState, boundsWidth: number, boundsHeight: number, allowUpscale = false): Hudson.ViewportState {
    const width = Math.max(1, viewport.width);
    const height = Math.max(1, viewport.height);
    const fitZoom = Math.min(boundsWidth / width, boundsHeight / height);
    const zoom = clampZoom(viewport, allowUpscale ? fitZoom : Math.min(1, fitZoom));
    return {
      ...viewport,
      zoom,
      panX: (boundsWidth - width * zoom) / 2,
      panY: (boundsHeight - height * zoom) / 2,
    };
  }

  export function zoomAt(viewport: Hudson.ViewportState, screenX: number, screenY: number, factor: number): Hudson.ViewportState {
    const before = screenToWorld(viewport, screenX, screenY);
    const zoom = clampZoom(viewport, viewport.zoom * factor);
    return {
      ...viewport,
      zoom,
      panX: screenX - before.x * zoom,
      panY: screenY - before.y * zoom,
    };
  }

  export function panBy(viewport: Hudson.ViewportState, dx: number, dy: number): Hudson.ViewportState {
    return { ...viewport, panX: viewport.panX + dx, panY: viewport.panY + dy };
  }

  export function defaultCaptureViewport(imageWidth: number, imageHeight: number): Hudson.CaptureViewport {
    const margin = Math.max(96, Math.min(imageWidth, imageHeight) * 0.18);
    return {
      width: Math.ceil(imageWidth + margin * 2),
      height: Math.ceil(imageHeight + margin * 2),
      imageX: margin,
      imageY: margin,
      imageScale: 1,
    };
  }
}
