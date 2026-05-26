namespace Hudson.Tools {
  export const DEFAULT_COLOR = "#C47D1C";

  export type ToolKind = "rect" | "arrow" | "line" | "text" | "blur";

  export function uuid(): string {
    const cryptoLike = globalThis.crypto;
    if (cryptoLike && typeof cryptoLike.randomUUID === "function") return cryptoLike.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  export function normalizedFrame(a: Hudson.NormPoint, b: Hudson.NormPoint): Hudson.Rect {
    return {
      x: Math.min(a.nx, b.nx),
      y: Math.min(a.ny, b.ny),
      width: Math.abs(b.nx - a.nx),
      height: Math.abs(b.ny - a.ny),
    };
  }

  export function rect(frame: Hudson.Rect): Hudson.Layer {
    return base("rect", { frame });
  }

  export function arrow(from: Hudson.Point, to: Hudson.Point): Hudson.Layer {
    return base("arrow", { from, to });
  }

  export function line(from: Hudson.Point, to: Hudson.Point): Hudson.Layer {
    return base("arrow", { from, to, label: "line" });
  }

  export function text(frame: Hudson.Rect, value: string): Hudson.Layer {
    return base("label", { frame, text: value });
  }

  export function blurPlaceholder(frame: Hudson.Rect): Hudson.Layer {
    return base("highlight", { frame, color: "#646464", label: "BLUR" });
  }

  function base(kind: Hudson.LayerKind, extra: Partial<Hudson.Layer>): Hudson.Layer {
    return {
      id: uuid(),
      kind,
      color: DEFAULT_COLOR,
      visible: true,
      author: "user",
      ...extra,
    };
  }
}
