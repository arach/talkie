namespace Hudson.HitTest {
  export interface Options {
    segmentTolerance?: number;
  }

  export function layerAt(layers: Hudson.Layer[], point: Hudson.NormPoint, options: Options = {}): Hudson.Layer | null {
    const tolerance = options.segmentTolerance ?? 0.018;
    for (let i = layers.length - 1; i >= 0; i--) {
      const layer = layers[i];
      if (layer.visible === false) continue;
      if (layer.frame && contains(layer.frame, point)) return layer;
      if (layer.from && layer.to && distanceToSegment(point, layer.from, layer.to) < tolerance) return layer;
    }
    return null;
  }

  export function contains(rect: Hudson.Rect, point: Hudson.NormPoint): boolean {
    return point.nx >= rect.x
      && point.nx <= rect.x + rect.width
      && point.ny >= rect.y
      && point.ny <= rect.y + rect.height;
  }

  export function distanceToSegment(point: Hudson.NormPoint, from: Hudson.Point, to: Hudson.Point): number {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const len2 = dx * dx + dy * dy;
    if (len2 === 0) return Number.POSITIVE_INFINITY;
    const t = Math.max(0, Math.min(1, ((point.nx - from.x) * dx + (point.ny - from.y) * dy) / len2));
    const cx = from.x + t * dx;
    const cy = from.y + t * dy;
    return Math.hypot(point.nx - cx, point.ny - cy);
  }
}
