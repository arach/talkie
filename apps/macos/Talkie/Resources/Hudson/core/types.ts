namespace Hudson {
  export type LayerKind = "rect" | "arrow" | "label" | "guide" | "highlight";
  export type Author = "agent" | "user";

  export interface Point {
    x: number;
    y: number;
  }

  export interface Rect {
    x: number;
    y: number;
    width: number;
    height: number;
  }

  export interface Layer {
    id: string;
    kind: LayerKind;
    frame?: Rect;
    from?: Point;
    to?: Point;
    text?: string;
    color?: string;
    label?: string;
    orientation?: "h" | "v" | "both" | string;
    interval?: number;
    visible?: boolean;
    author?: Author;
  }

  /** Logical design surface. Layer geometry is normalized against width/height. */
  export interface ViewportState {
    width: number;
    height: number;
    zoom: number;
    panX: number;
    panY: number;
    minZoom?: number;
    maxZoom?: number;
  }

  /** Optional image binding used by Capture Markup; not required by core math. */
  export interface ImagePlacement {
    imageX: number;
    imageY: number;
    imageScale: number;
  }

  export interface CaptureViewport extends ImagePlacement {
    width: number;
    height: number;
  }

  export interface Document {
    version: number;
    imageWidth?: number;
    imageHeight?: number;
    viewport?: CaptureViewport;
    layers: Layer[];
  }

  export interface NormPoint {
    nx: number;
    ny: number;
    px: number;
    py: number;
  }

  export interface SelectionPayload {
    id: string;
    label: string;
    kind: LayerKind | string;
  }

  export interface Host<DocumentT extends Document = Document> {
    exportDocument(): DocumentT;
    onDocumentChanged?(document: DocumentT): void;
    onSelectionChanged?(selection: SelectionPayload | null): void;
    onAttach?(layer: Layer): void;
  }

  export type DrawLayerHandler = (
    ctx: CanvasRenderingContext2D,
    layer: Layer,
    viewport: ViewportState,
  ) => void;
}
