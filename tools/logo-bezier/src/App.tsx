import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type MouseEvent as ReactMouseEvent,
  type PointerEvent as ReactPointerEvent,
} from "react";
import vectorRaw from "../Vector.svg?raw";
import controlsDataRaw from "../../../assets/logo-bezier/bowtie_bezier_e0_clean_right8.json";
import anchorsDataRaw from "../../../assets/logo-bezier/bowtie_bezier_e0_clean_right8_anchors.json";
import appIcon from "../../../Talkie-iOS-Default-1024x1024@1x.png?url";
import silhouettePng from "../../../assets/logo-primitives/bowtie_silhouette.png?url";

type Point = { x: number; y: number };

type Segment = {
  p0: Point;
  c1: Point;
  c2: Point;
  p3: Point;
};

type Subpath = {
  segments: Segment[];
  closed: boolean;
};

type GraphAnchor = {
  id: string;
  x: number;
  y: number;
  inHandle: Point;
  outHandle: Point;
};

type GraphSubpath = {
  id: string;
  closed: boolean;
  anchors: GraphAnchor[];
};

type Bounds = {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
  width: number;
  height: number;
  centerX: number;
  centerY: number;
};

type Transform = {
  scale: number;
  translateX: number;
  translateY: number;
};

type ControlPointKind = "p0" | "p3" | "c1" | "c2";

type ControlPointRef = {
  subpathIndex: number;
  segmentIndex: number;
  kind: ControlPointKind;
};

type ControlPoint = ControlPointRef & Point & { id: string };

type HandleLine = {
  id: string;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  anchorKey: string;
};

type NamedAnchor = {
  name: string;
  stroke: string;
  index: number;
  x: number;
  y: number;
};

type AnchorLabel = {
  id: string;
  name: string;
  x: number;
  y: number;
};

type AngleArc = {
  id: string;
  anchorKey: string;
  order: number;
  x: number;
  y: number;
  start: Point;
  end: Point;
  angle: number;
  sweep: 0 | 1;
  largeArc: 0 | 1;
  labelPoint: Point;
};

type DirectedNode = {
  id: string;
  point: Point;
  order: number;
};

type DirectedEdge = {
  id: string;
  from: string;
  to: string;
  fromPoint: Point;
  toPoint: Point;
  c1: Point;
  c2: Point;
};

type DirectedLoop = {
  nodes: DirectedNode[];
  edges: DirectedEdge[];
};

type ControlsData = {
  strokes: {
    p0: [number, number];
    c1: [number, number];
    c2: [number, number];
    p3: [number, number];
  }[][];
};

type AnchorsData = {
  anchors: NamedAnchor[];
};

type SaveState = {
  status: "idle" | "saving" | "saved" | "error";
  message: string;
  detail?: string;
};

type SavedVersion = {
  fileName: string;
  relativePath: string;
  absolutePath: string;
  size: number;
  lastModified: string;
};

const controlsData = controlsDataRaw as ControlsData;
const anchorsData = anchorsDataRaw as AnchorsData;

const fallbackViewBox = "0 0 929 539";

const extractPathData = (svg: string) => {
  const viewBoxMatch = svg.match(/viewBox=["']([^"']+)["']/i);
  const pathMatch = svg.match(/<path[^>]*d=["']([^"']+)["']/i);

  return {
    viewBox: viewBoxMatch?.[1] ?? fallbackViewBox,
    path: pathMatch?.[1] ?? "",
  };
};

const parseViewBox = (value: string): [number, number, number, number] => {
  const parts = value
    .split(/[\s,]+/)
    .map((part) => Number(part))
    .filter((part) => !Number.isNaN(part));

  if (parts.length !== 4) {
    return [0, 0, 929, 539];
  }

  return [parts[0], parts[1], parts[2], parts[3]];
};

const numberPattern = /-?\d*\.?\d+(?:e[-+]?\d+)?/gi;

const parseNumbers = (value: string) => {
  const matches = value.match(numberPattern);
  return matches ? matches.map((num) => Number(num)) : [];
};

const parsePath = (path: string): Subpath[] => {
  const subpaths: Subpath[] = [];
  let current: Subpath | null = null;
  let currentPoint: Point | null = null;

  const commandPattern = /([MCZ])([^MCZ]*)/gi;
  let match: RegExpExecArray | null;

  while ((match = commandPattern.exec(path))) {
    const command = match[1].toUpperCase();
    const raw = match[2];

    if (command === "M") {
      const nums = parseNumbers(raw);
      if (nums.length < 2) {
        continue;
      }
      const [x, y] = nums;
      currentPoint = { x, y };
      current = { segments: [], closed: false };
      subpaths.push(current);
      continue;
    }

    if (command === "C") {
      if (!current || !currentPoint) {
        continue;
      }
      const nums = parseNumbers(raw);
      for (let i = 0; i + 5 < nums.length; i += 6) {
        const segment: Segment = {
          p0: { ...currentPoint },
          c1: { x: nums[i], y: nums[i + 1] },
          c2: { x: nums[i + 2], y: nums[i + 3] },
          p3: { x: nums[i + 4], y: nums[i + 5] },
        };
        current.segments.push(segment);
        currentPoint = { ...segment.p3 };
      }
      continue;
    }

    if (command === "Z") {
      if (current) {
        current.closed = true;
      }
      currentPoint = null;
    }
  }

  return subpaths;
};

const buildSubpathsFromControls = (controls: ControlsData): Subpath[] =>
  controls.strokes.map((stroke) => ({
    closed: false,
    segments: stroke.map((segment) => ({
      p0: { x: segment.p0[0], y: segment.p0[1] },
      c1: { x: segment.c1[0], y: segment.c1[1] },
      c2: { x: segment.c2[0], y: segment.c2[1] },
      p3: { x: segment.p3[0], y: segment.p3[1] },
    })),
  }));

const cloneSubpaths = (subpaths: Subpath[]): Subpath[] =>
  subpaths.map((subpath) => ({
    closed: subpath.closed,
    segments: subpath.segments.map((segment) => ({
      p0: { ...segment.p0 },
      c1: { ...segment.c1 },
      c2: { ...segment.c2 },
      p3: { ...segment.p3 },
    })),
  }));

const graphToSubpaths = (graphSubpaths: GraphSubpath[]): Subpath[] =>
  graphSubpaths
    .map((subpath) => {
      const anchorCount = subpath.anchors.length;
      if (anchorCount < 2) {
        return { closed: subpath.closed, segments: [] };
      }
      const segmentCount = subpath.closed ? anchorCount : anchorCount - 1;
      const segments: Segment[] = [];
      for (let i = 0; i < segmentCount; i += 1) {
        const start = subpath.anchors[i];
        const end = subpath.anchors[(i + 1) % anchorCount];
        segments.push({
          p0: { x: start.x, y: start.y },
          c1: { x: start.outHandle.x, y: start.outHandle.y },
          c2: { x: end.inHandle.x, y: end.inHandle.y },
          p3: { x: end.x, y: end.y },
        });
      }
      return { closed: subpath.closed, segments };
    })
    .filter((subpath) => subpath.segments.length > 0);

const subpathsToGraph = (subpaths: Subpath[]): GraphSubpath[] =>
  subpaths
    .map((subpath, subpathIndex) => {
      if (subpath.segments.length === 0) {
        return { id: `subpath-${subpathIndex}`, closed: subpath.closed, anchors: [] };
      }

      const anchors: GraphAnchor[] = [];
      subpath.segments.forEach((segment, segmentIndex) => {
        if (segmentIndex === 0) {
          anchors.push({
            id: `subpath-${subpathIndex}-anchor-0`,
            x: segment.p0.x,
            y: segment.p0.y,
            inHandle: { x: segment.p0.x, y: segment.p0.y },
            outHandle: { x: segment.c1.x, y: segment.c1.y },
          });
        } else {
          anchors[segmentIndex].outHandle = { x: segment.c1.x, y: segment.c1.y };
        }

        anchors.push({
          id: `subpath-${subpathIndex}-anchor-${segmentIndex + 1}`,
          x: segment.p3.x,
          y: segment.p3.y,
          inHandle: { x: segment.c2.x, y: segment.c2.y },
          outHandle: { x: segment.p3.x, y: segment.p3.y },
        });
      });

      if (subpath.closed && anchors.length > 0) {
        const first = anchors[0];
        const last = subpath.segments[subpath.segments.length - 1];
        first.inHandle = { x: last.c2.x, y: last.c2.y };
        anchors.pop();
      }

      return {
        id: `subpath-${subpathIndex}`,
        closed: subpath.closed,
        anchors,
      };
    })
    .filter((subpath) => subpath.anchors.length > 0);

const formatNumber = (value: number) => {
  const rounded = Math.round(value * 1000) / 1000;
  return Number.isInteger(rounded) ? `${rounded}` : `${rounded}`;
};

const formatPathForDisplay = (subpaths: Subpath[]) =>
  subpaths
    .map((subpath) => {
      if (subpath.segments.length === 0) {
        return "";
      }
      const [first] = subpath.segments;
      const lines = [`M ${formatNumber(first.p0.x)} ${formatNumber(first.p0.y)}`];
      subpath.segments.forEach((segment) => {
        lines.push(
          `C ${formatNumber(segment.c1.x)} ${formatNumber(segment.c1.y)} ${formatNumber(segment.c2.x)} ${formatNumber(segment.c2.y)} ${formatNumber(segment.p3.x)} ${formatNumber(segment.p3.y)}`
        );
      });
      if (subpath.closed) {
        lines.push("Z");
      }
      return lines.join("\n");
    })
    .filter(Boolean)
    .join("\n\n");

const buildPath = (subpaths: Subpath[]) =>
  subpaths
    .map((subpath) => {
      if (subpath.segments.length === 0) {
        return "";
      }
      const [first] = subpath.segments;
      let d = `M ${formatNumber(first.p0.x)} ${formatNumber(first.p0.y)}`;
      subpath.segments.forEach((segment) => {
        d += ` C ${formatNumber(segment.c1.x)} ${formatNumber(segment.c1.y)} ${formatNumber(segment.c2.x)} ${formatNumber(segment.c2.y)} ${formatNumber(segment.p3.x)} ${formatNumber(segment.p3.y)}`;
      });
      if (subpath.closed) {
        d += " Z";
      }
      return d;
    })
    .join(" ");

const getPoint = (segment: Segment, kind: ControlPointKind) => segment[kind];

const applyDelta = (point: Point, dx: number, dy: number) => {
  point.x += dx;
  point.y += dy;
};

const updatePoint = (
  subpaths: Subpath[],
  target: ControlPointRef,
  next: Point
) => {
  const clone = cloneSubpaths(subpaths);
  const subpath = clone[target.subpathIndex];
  if (!subpath) {
    return clone;
  }

  const segment = subpath.segments[target.segmentIndex];
  if (!segment) {
    return clone;
  }

  const original = subpaths[target.subpathIndex]?.segments[target.segmentIndex];
  if (!original) {
    return clone;
  }

  const currentPoint = getPoint(original, target.kind);
  const dx = next.x - currentPoint.x;
  const dy = next.y - currentPoint.y;

  if (target.kind === "c1" || target.kind === "c2") {
    applyDelta(getPoint(segment, target.kind), dx, dy);
    return clone;
  }

  const isClosed = subpath.closed;
  const prevIndex = target.segmentIndex - 1;
  const nextIndex = target.segmentIndex + 1;
  const hasPrev = prevIndex >= 0;
  const hasNext = nextIndex < subpath.segments.length;
  const prevSegment = hasPrev
    ? subpath.segments[prevIndex]
    : isClosed
      ? subpath.segments[subpath.segments.length - 1]
      : null;
  const nextSegment = hasNext
    ? subpath.segments[nextIndex]
    : isClosed
      ? subpath.segments[0]
      : null;

  if (target.kind === "p0") {
    applyDelta(segment.p0, dx, dy);
    applyDelta(segment.c1, dx, dy);
    if (prevSegment) {
      applyDelta(prevSegment.p3, dx, dy);
      applyDelta(prevSegment.c2, dx, dy);
    }
    return clone;
  }

  if (target.kind === "p3") {
    applyDelta(segment.p3, dx, dy);
    applyDelta(segment.c2, dx, dy);
    if (nextSegment) {
      applyDelta(nextSegment.p0, dx, dy);
      applyDelta(nextSegment.c1, dx, dy);
    }
  }

  return clone;
};

const deleteSegment = (
  subpaths: Subpath[],
  subpathIndex: number,
  segmentIndex: number
) => {
  const clone = cloneSubpaths(subpaths);
  const subpath = clone[subpathIndex];
  if (!subpath) {
    return clone;
  }
  if (subpath.segments.length <= 1) {
    clone.splice(subpathIndex, 1);
    return clone;
  }

  const prevSegment =
    segmentIndex > 0 ? subpath.segments[segmentIndex - 1] : null;
  const nextSegment =
    segmentIndex < subpath.segments.length - 1
      ? subpath.segments[segmentIndex + 1]
      : null;

  subpath.segments.splice(segmentIndex, 1);

  if (prevSegment && nextSegment) {
    const dx = prevSegment.p3.x - nextSegment.p0.x;
    const dy = prevSegment.p3.y - nextSegment.p0.y;
    for (let i = segmentIndex; i < subpath.segments.length; i += 1) {
      applyDelta(subpath.segments[i].p0, dx, dy);
      applyDelta(subpath.segments[i].c1, dx, dy);
      applyDelta(subpath.segments[i].c2, dx, dy);
      applyDelta(subpath.segments[i].p3, dx, dy);
    }
  }

  if (subpath.segments.length === 0) {
    clone.splice(subpathIndex, 1);
  }

  return clone;
};

const createSegment = (start: Point, end: Point): Segment => {
  const c1 = {
    x: start.x + (end.x - start.x) / 3,
    y: start.y + (end.y - start.y) / 3,
  };
  const c2 = {
    x: start.x + ((end.x - start.x) * 2) / 3,
    y: start.y + ((end.y - start.y) * 2) / 3,
  };
  return {
    p0: { ...start },
    c1,
    c2,
    p3: { ...end },
  };
};

const splitSegmentAt = (segment: Segment, t: number): [Segment, Segment] => {
  const lerp = (a: Point, b: Point, tt: number): Point => ({
    x: a.x + (b.x - a.x) * tt,
    y: a.y + (b.y - a.y) * tt,
  });
  const p01 = lerp(segment.p0, segment.c1, t);
  const p12 = lerp(segment.c1, segment.c2, t);
  const p23 = lerp(segment.c2, segment.p3, t);
  const p012 = lerp(p01, p12, t);
  const p123 = lerp(p12, p23, t);
  const p0123 = lerp(p012, p123, t);
  return [
    { p0: segment.p0, c1: p01, c2: p012, p3: p0123 },
    { p0: p0123, c1: p123, c2: p23, p3: segment.p3 },
  ];
};

const normalize = (vector: Point): Point => {
  const length = Math.hypot(vector.x, vector.y);
  if (length === 0) {
    return { x: 0, y: 0 };
  }
  return { x: vector.x / length, y: vector.y / length };
};

const isEditableTarget = (target: EventTarget | null) => {
  if (!(target instanceof HTMLElement)) {
    return false;
  }
  const tag = target.tagName.toLowerCase();
  return tag === "input" || tag === "textarea" || target.isContentEditable;
};

const buildSelectionKeys = (
  subpaths: Subpath[],
  points: ControlPointRef[]
) => {
  const keys = new Set<string>();
  const addKey = (
    subpathIndex: number,
    segmentIndex: number,
    kind: ControlPointKind
  ) => {
    keys.add(`${subpathIndex}:${segmentIndex}:${kind}`);
  };

  points.forEach((point) => {
    addKey(point.subpathIndex, point.segmentIndex, point.kind);
    const subpath = subpaths[point.subpathIndex];
    if (!subpath) {
      return;
    }
    if (point.kind === "p0") {
      addKey(point.subpathIndex, point.segmentIndex, "c1");
      if (point.segmentIndex > 0) {
        addKey(point.subpathIndex, point.segmentIndex - 1, "p3");
        addKey(point.subpathIndex, point.segmentIndex - 1, "c2");
      }
    }
    if (point.kind === "p3") {
      addKey(point.subpathIndex, point.segmentIndex, "c2");
      if (point.segmentIndex < subpath.segments.length - 1) {
        addKey(point.subpathIndex, point.segmentIndex + 1, "p0");
        addKey(point.subpathIndex, point.segmentIndex + 1, "c1");
      }
    }
  });

  return Array.from(keys);
};

const applyDeltaToKeys = (
  subpaths: Subpath[],
  keys: string[],
  delta: Point
) => {
  const working = cloneSubpaths(subpaths);
  keys.forEach((key) => {
    const [subpathIndexRaw, segmentIndexRaw, kindRaw] = key.split(":");
    const subpathIndex = Number(subpathIndexRaw);
    const segmentIndex = Number(segmentIndexRaw);
    const kind = kindRaw as ControlPointKind;
    const segment = working[subpathIndex]?.segments[segmentIndex];
    if (!segment) {
      return;
    }
    applyDelta(getPoint(segment, kind), delta.x, delta.y);
  });
  return working;
};

const buildAnchors = (subpaths: Subpath[]): ControlPoint[] => {
  const points: ControlPoint[] = [];
  subpaths.forEach((subpath, subpathIndex) => {
    subpath.segments.forEach((segment, segmentIndex) => {
      if (segmentIndex === 0) {
        points.push({
          id: `${subpathIndex}-p0`,
          subpathIndex,
          segmentIndex,
          kind: "p0",
          x: segment.p0.x,
          y: segment.p0.y,
        });
      }
      points.push({
        id: `${subpathIndex}-${segmentIndex}-p3`,
        subpathIndex,
        segmentIndex,
        kind: "p3",
        x: segment.p3.x,
        y: segment.p3.y,
      });
    });
  });
  return points;
};

const buildHandles = (subpaths: Subpath[]): ControlPoint[] => {
  const points: ControlPoint[] = [];
  subpaths.forEach((subpath, subpathIndex) => {
    subpath.segments.forEach((segment, segmentIndex) => {
      points.push({
        id: `${subpathIndex}-${segmentIndex}-c1`,
        subpathIndex,
        segmentIndex,
        kind: "c1",
        x: segment.c1.x,
        y: segment.c1.y,
      });
      points.push({
        id: `${subpathIndex}-${segmentIndex}-c2`,
        subpathIndex,
        segmentIndex,
        kind: "c2",
        x: segment.c2.x,
        y: segment.c2.y,
      });
    });
  });
  return points;
};

const anchorKeyFor = (point: Point) =>
  `${point.x.toFixed(3)}:${point.y.toFixed(3)}`;

const buildDirectedLoop = (subpaths: Subpath[]): DirectedLoop => {
  const nodes: DirectedNode[] = [];
  const nodeMap = new Map<string, DirectedNode>();
  const edges: DirectedEdge[] = [];
  const closureTolerance = 10;

  const ensureNode = (point: Point) => {
    const id = anchorKeyFor(point);
    const existing = nodeMap.get(id);
    if (existing) {
      return existing;
    }
    const node: DirectedNode = {
      id,
      point: { x: point.x, y: point.y },
      order: nodes.length,
    };
    nodeMap.set(id, node);
    nodes.push(node);
    return node;
  };

  subpaths.forEach((subpath, subpathIndex) => {
    let subpathStartNode: DirectedNode | null = null;
    subpath.segments.forEach((segment, segmentIndex) => {
      const fromNode = ensureNode(segment.p0);
      if (segmentIndex === 0) {
        subpathStartNode = fromNode;
      }

      const isClosingSegment =
        subpath.closed &&
        segmentIndex === subpath.segments.length - 1 &&
        subpathStartNode !== null;
      const useStartNodeAsTarget =
        isClosingSegment &&
        Math.hypot(
          segment.p3.x - subpathStartNode.x,
          segment.p3.y - subpathStartNode.y
        ) <= closureTolerance;
      const toNode = useStartNodeAsTarget
        ? subpathStartNode
        : ensureNode(segment.p3);
      edges.push({
        id: `${subpathIndex}-${segmentIndex}`,
        from: fromNode.id,
        to: toNode.id,
        fromPoint: { x: segment.p0.x, y: segment.p0.y },
        toPoint: { x: segment.p3.x, y: segment.p3.y },
        c1: { x: segment.c1.x, y: segment.c1.y },
        c2: { x: segment.c2.x, y: segment.c2.y },
      });
    });
  });

  return { nodes, edges };
};

const buildHandleLines = (subpaths: Subpath[]): HandleLine[] => {
  const lines: HandleLine[] = [];
  subpaths.forEach((subpath, subpathIndex) => {
    subpath.segments.forEach((segment, segmentIndex) => {
      lines.push({
        id: `${subpathIndex}-${segmentIndex}-out`,
        x1: segment.p0.x,
        y1: segment.p0.y,
        x2: segment.c1.x,
        y2: segment.c1.y,
        anchorKey: anchorKeyFor(segment.p0),
      });
      lines.push({
        id: `${subpathIndex}-${segmentIndex}-in`,
        x1: segment.p3.x,
        y1: segment.p3.y,
        x2: segment.c2.x,
        y2: segment.c2.y,
        anchorKey: anchorKeyFor(segment.p3),
      });
    });
  });
  return lines;
};

const computeBoundsFromSubpaths = (subpaths: Subpath[]): Bounds => {
  const xs: number[] = [];
  const ys: number[] = [];

  subpaths.forEach((subpath) => {
    subpath.segments.forEach((segment) => {
      xs.push(segment.p0.x, segment.c1.x, segment.c2.x, segment.p3.x);
      ys.push(segment.p0.y, segment.c1.y, segment.c2.y, segment.p3.y);
    });
  });

  const minX = Math.min(...xs);
  const maxX = Math.max(...xs);
  const minY = Math.min(...ys);
  const maxY = Math.max(...ys);

  return {
    minX,
    maxX,
    minY,
    maxY,
    width: maxX - minX,
    height: maxY - minY,
    centerX: (minX + maxX) / 2,
    centerY: (minY + maxY) / 2,
  };
};

const createTransform = (from: Bounds, to: Bounds): Transform => {
  const scale = Math.min(to.width / from.width, to.height / from.height);
  return {
    scale,
    translateX: to.centerX - from.centerX * scale,
    translateY: to.centerY - from.centerY * scale,
  };
};

const applyTransform = (point: Point, transform: Transform): Point => ({
  x: point.x * transform.scale + transform.translateX,
  y: point.y * transform.scale + transform.translateY,
});

const transformAnchors = (
  anchors: NamedAnchor[],
  transform: Transform
): NamedAnchor[] =>
  anchors.map((anchor) => ({
    ...anchor,
    ...applyTransform({ x: anchor.x, y: anchor.y }, transform),
  }));

const normalizeVector = (vector: Point) => {
  const length = Math.hypot(vector.x, vector.y);
  if (length === 0) {
    return { x: 0, y: 0 };
  }
  return { x: vector.x / length, y: vector.y / length };
};

const buildAngleArcs = (loop: DirectedLoop): AngleArc[] => {
  const nodeMap = new Map<
    string,
    { node: DirectedNode; incoming?: Point; outgoing?: Point }
  >();
  loop.nodes.forEach((node) => {
    nodeMap.set(node.id, { node });
  });

  loop.edges.forEach((edge) => {
    const fromEntry = nodeMap.get(edge.from);
    if (fromEntry) {
      fromEntry.outgoing = {
        x: edge.c1.x - edge.fromPoint.x,
        y: edge.c1.y - edge.fromPoint.y,
      };
    }
    const toEntry = nodeMap.get(edge.to);
    if (toEntry) {
      toEntry.incoming = {
        x: edge.c2.x - edge.toPoint.x,
        y: edge.c2.y - edge.toPoint.y,
      };
    }
  });

  const arcs: AngleArc[] = [];
  const radius = 22;
  loop.nodes.forEach((node, index) => {
    const entry = nodeMap.get(node.id);
    if (!entry) {
      return;
    }
    if (!entry.incoming || !entry.outgoing) {
      return;
    }

    const incoming = normalizeVector(entry.incoming);
    const outgoing = normalizeVector(entry.outgoing);
    const dot = Math.max(
      -1,
      Math.min(1, incoming.x * outgoing.x + incoming.y * outgoing.y)
    );
    const angle = Math.acos(dot);
    const startAngle = Math.atan2(incoming.y, incoming.x);
    const endAngle = Math.atan2(outgoing.y, outgoing.x);
    let delta = endAngle - startAngle;
    while (delta <= -Math.PI) {
      delta += Math.PI * 2;
    }
    while (delta > Math.PI) {
      delta -= Math.PI * 2;
    }

    const sweep: 0 | 1 = delta >= 0 ? 1 : 0;
    const largeArc: 0 | 1 = Math.abs(delta) > Math.PI ? 1 : 0;

    const start = {
      x: entry.node.point.x + Math.cos(startAngle) * radius,
      y: entry.node.point.y + Math.sin(startAngle) * radius,
    };
    const end = {
      x: entry.node.point.x + Math.cos(endAngle) * radius,
      y: entry.node.point.y + Math.sin(endAngle) * radius,
    };
    const midAngle = startAngle + delta / 2;
    const labelPoint = {
      x: entry.node.point.x + Math.cos(midAngle) * (radius + 12),
      y: entry.node.point.y + Math.sin(midAngle) * (radius + 12),
    };

    arcs.push({
      id: `angle-${index}`,
      anchorKey: entry.node.id,
      order: entry.node.order,
      x: entry.node.point.x,
      y: entry.node.point.y,
      start,
      end,
      angle,
      sweep,
      largeArc,
      labelPoint,
    });
  });

  return arcs.sort((a, b) => a.order - b.order);
};

const { viewBox, path: rawPath } = extractPathData(vectorRaw);
const initialEditableSubpaths = parsePath(rawPath);
const editableBounds = computeBoundsFromSubpaths(initialEditableSubpaths);
const controlSubpaths = buildSubpathsFromControls(controlsData);
const controlBounds = computeBoundsFromSubpaths(controlSubpaths);
const controlTransform = createTransform(controlBounds, editableBounds);
const namedAnchors = transformAnchors(anchorsData.anchors, controlTransform);
const [viewBoxX, viewBoxY, viewBoxWidth, viewBoxHeight] = parseViewBox(viewBox);
const viewBoxCenterX = viewBoxX + viewBoxWidth / 2;
const viewBoxCenterY = viewBoxY + viewBoxHeight / 2;
const logoCenterX = viewBoxCenterX;
const logoCenterY = viewBoxCenterY;

const logoOptions = [
  { id: "appIcon", label: "App icon PNG", src: appIcon },
  { id: "silhouette", label: "Silhouette PNG", src: silhouettePng },
];

const copyToClipboard = async (value: string) => {
  if (!navigator.clipboard) {
    return false;
  }
  await navigator.clipboard.writeText(value);
  return true;
};

const hasSegments = (subpaths: Subpath[]) =>
  subpaths.some((subpath) => subpath.segments.length > 0);

const formatTime = (seconds: number) => {
  const totalSeconds = Math.max(0, seconds);
  const minutes = Math.floor(totalSeconds / 60);
  const remainder = totalSeconds - minutes * 60;
  const secondsLabel =
    remainder % 1 === 0 ? remainder.toFixed(0) : remainder.toFixed(1);
  const padded = remainder < 10 ? `0${secondsLabel}` : secondsLabel;
  return `${minutes}:${padded}`;
};

const formatTimestamp = (value: string) => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }
  return date.toLocaleString();
};

const clamp01 = (value: number) => Math.max(0, Math.min(1, value));

const findClosestLength = (
  path: SVGPathElement,
  point: Point,
  totalLength: number
) => {
  const samples = 200;
  let bestLength = 0;
  let bestDist = Number.POSITIVE_INFINITY;
  for (let i = 0; i <= samples; i += 1) {
    const length = (totalLength * i) / samples;
    const sample = path.getPointAtLength(length);
    const dx = sample.x - point.x;
    const dy = sample.y - point.y;
    const dist = dx * dx + dy * dy;
    if (dist < bestDist) {
      bestDist = dist;
      bestLength = length;
    }
  }

  let start = Math.max(0, bestLength - totalLength / samples);
  let end = Math.min(totalLength, bestLength + totalLength / samples);
  for (let i = 0; i < 16; i += 1) {
    const m1 = start + (end - start) / 3;
    const m2 = end - (end - start) / 3;
    const p1 = path.getPointAtLength(m1);
    const p2 = path.getPointAtLength(m2);
    const d1 = (p1.x - point.x) ** 2 + (p1.y - point.y) ** 2;
    const d2 = (p2.x - point.x) ** 2 + (p2.y - point.y) ** 2;
    if (d1 < d2) {
      end = m2;
    } else {
      start = m1;
    }
  }
  return (start + end) / 2;
};

type SerializedSubpath = {
  closed: boolean;
  segments: {
    p0: Point;
    c1: Point;
    c2: Point;
    p3: Point;
  }[];
};

type SerializedGraphSubpath = {
  id: string;
  closed: boolean;
  anchors: GraphAnchor[];
};

const serializeSubpaths = (paths: Subpath[]): SerializedSubpath[] =>
  paths.map((subpath) => ({
    closed: subpath.closed,
    segments: subpath.segments.map((segment) => ({
      p0: { x: segment.p0.x, y: segment.p0.y },
      c1: { x: segment.c1.x, y: segment.c1.y },
      c2: { x: segment.c2.x, y: segment.c2.y },
      p3: { x: segment.p3.x, y: segment.p3.y },
    })),
  }));

const deserializeSubpaths = (paths: SerializedSubpath[]): Subpath[] =>
  paths.map((subpath) => ({
    closed: subpath.closed,
    segments: subpath.segments.map((segment) => ({
      p0: { x: segment.p0.x, y: segment.p0.y },
      c1: { x: segment.c1.x, y: segment.c1.y },
      c2: { x: segment.c2.x, y: segment.c2.y },
      p3: { x: segment.p3.x, y: segment.p3.y },
    })),
  }));

const serializeGraphSubpaths = (
  graphSubpaths: GraphSubpath[]
): SerializedGraphSubpath[] =>
  graphSubpaths.map((subpath) => ({
    id: subpath.id,
    closed: subpath.closed,
    anchors: subpath.anchors.map((anchor) => ({
      id: anchor.id,
      x: anchor.x,
      y: anchor.y,
      inHandle: { x: anchor.inHandle.x, y: anchor.inHandle.y },
      outHandle: { x: anchor.outHandle.x, y: anchor.outHandle.y },
    })),
  }));

const deserializeGraphSubpaths = (
  graphSubpaths: SerializedGraphSubpath[]
): GraphSubpath[] =>
  graphSubpaths.map((subpath) => ({
    id: subpath.id,
    closed: subpath.closed,
    anchors: subpath.anchors.map((anchor) => ({
      id: anchor.id,
      x: anchor.x,
      y: anchor.y,
      inHandle: { x: anchor.inHandle.x, y: anchor.inHandle.y },
      outHandle: { x: anchor.outHandle.x, y: anchor.outHandle.y },
    })),
  }));

export default function App() {
  const [graphSubpaths, setGraphSubpaths] = useState(() =>
    subpathsToGraph(initialEditableSubpaths)
  );
  const subpaths = useMemo(() => graphToSubpaths(graphSubpaths), [graphSubpaths]);
  const setSubpaths = (
    next: Subpath[] | ((prev: Subpath[]) => Subpath[])
  ) => {
    setGraphSubpaths((prevGraph) => {
      const prevSubpaths = graphToSubpaths(prevGraph);
      const resolved =
        typeof next === "function"
          ? (next as (prev: Subpath[]) => Subpath[])(prevSubpaths)
          : next;
      return subpathsToGraph(resolved);
    });
  };
  const [showLogo, setShowLogo] = useState(true);
  const [showRaw, setShowRaw] = useState(true);
  const [showScaffold, setShowScaffold] = useState(true);
  const [showAnchorLabels, setShowAnchorLabels] = useState(true);
  const [showAngles, setShowAngles] = useState(false);
  const [animateDraw, setAnimateDraw] = useState(false);
  const [canvasZoom, setCanvasZoom] = useState(1);
  const [viewCenterX, setViewCenterX] = useState(viewBoxCenterX);
  const [viewCenterY, setViewCenterY] = useState(viewBoxCenterY);
  const [logoChoice, setLogoChoice] = useState(logoOptions[0].id);
  const [logoScale, setLogoScale] = useState(1);
  const [logoOffsetX, setLogoOffsetX] = useState(0);
  const [logoOffsetY, setLogoOffsetY] = useState(0);
  const [logoOpacity, setLogoOpacity] = useState(0.8);
  const [copied, setCopied] = useState(false);
  const [dashLength, setDashLength] = useState(0);
  const [dragging, setDragging] = useState<ControlPointRef | null>(null);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [selectionMode, setSelectionMode] = useState(false);
  const [drawMode, setDrawMode] = useState(false);
  const [drawStart, setDrawStart] = useState<Point | null>(null);
  const [showShortcuts, setShowShortcuts] = useState(false);
  const [roundness, setRoundness] = useState(0.45);
  const [selectionBox, setSelectionBox] = useState<{
    x: number;
    y: number;
    width: number;
    height: number;
  } | null>(null);
  const [isSelecting, setIsSelecting] = useState(false);
  const [pathMode, setPathMode] = useState<"view" | "edit">("view");
  const [pathDraft, setPathDraft] = useState("");
  const [pathError, setPathError] = useState("");
  const [pathDirty, setPathDirty] = useState(false);
  const [saveState, setSaveState] = useState<SaveState>({
    status: "idle",
    message: "Not saved yet.",
  });
  const [savedVersions, setSavedVersions] = useState<SavedVersion[]>([]);
  const [pathVersions, setPathVersions] = useState(() => [
    {
      id: "original",
      name: "Original",
      path: buildPath(initialEditableSubpaths),
      subpaths: cloneSubpaths(initialEditableSubpaths),
    },
  ]);
  const [activeVersionId, setActiveVersionId] = useState("original");
  const [versionName, setVersionName] = useState("");
  const [timelinePlaying, setTimelinePlaying] = useState(false);
  const [timelineProgress, setTimelineProgress] = useState(1);
  const [drawProgress, setDrawProgress] = useState(1);
  const [anchorProgress, setAnchorProgress] = useState<Record<string, number>>({});
  const [history, setHistory] = useState(() => [
    {
      subpaths: cloneSubpaths(initialEditableSubpaths),
      path: buildPath(initialEditableSubpaths),
    },
  ]);
  const [historyIndex, setHistoryIndex] = useState(0);

  const timelineDuration = 6.5;
  const drawDuration = 6;
  const angleRevealWindow = 0.08;
  const tangentRevealWindow = 0.06;
  const tangentDelay = 0.04;

  const svgRef = useRef<SVGSVGElement | null>(null);
  const editablePathRef = useRef<SVGPathElement | null>(null);
  const progressRef = useRef(timelineProgress);
  const selectionStartRef = useRef<Point | null>(null);
  const selectionAdditiveRef = useRef(false);
  const selectionBaseRef = useRef<string[]>([]);
  const groupDragRef = useRef<{
    start: Point;
    base: Subpath[];
    keys: string[];
  } | null>(null);
  const logoDragRef = useRef<{
    start: Point;
    offsetX: number;
    offsetY: number;
  } | null>(null);
  const historyIndexRef = useRef(historyIndex);

  const currentPath = useMemo(() => buildPath(subpaths), [subpaths]);
  const prettyPath = useMemo(() => formatPathForDisplay(subpaths), [subpaths]);
  const anchors = useMemo(() => buildAnchors(subpaths), [subpaths]);
  const handles = useMemo(() => buildHandles(subpaths), [subpaths]);
  const handleLines = useMemo(() => buildHandleLines(subpaths), [subpaths]);
  const directedLoop = useMemo(() => buildDirectedLoop(subpaths), [subpaths]);
  const angleArcs = useMemo(() => buildAngleArcs(directedLoop), [directedLoop]);
  const loopStartAnchorKey = directedLoop.nodes[0]?.id ?? null;
  const angleCount = Math.max(1, angleArcs.length);
  const allPoints = useMemo(() => [...anchors, ...handles], [anchors, handles]);
  const pointMap = useMemo(() => {
    const map = new Map<string, ControlPoint>();
    allPoints.forEach((point) => {
      map.set(point.id, point);
    });
    return map;
  }, [allPoints]);
  const selectedPoints = useMemo(() => {
    return selectedIds
      .map((id) => pointMap.get(id))
      .filter((value): value is ControlPoint => Boolean(value));
  }, [pointMap, selectedIds]);
  const currentTimeLabel = useMemo(
    () => formatTime(timelineProgress * timelineDuration),
    [timelineProgress, timelineDuration]
  );
  const totalTimeLabel = useMemo(
    () => formatTime(timelineDuration),
    [timelineDuration]
  );
  const canUndo = historyIndex > 0;
  const canRedo = historyIndex < history.length - 1;

  const anchorLabels = useMemo<AnchorLabel[]>(() => {
    if (directedLoop.nodes.length === 0) {
      return [];
    }

    return directedLoop.nodes.map((node) => ({
      id: node.id,
      name: `draw_${node.order.toString().padStart(2, "0")}`,
      x: node.point.x,
      y: node.point.y,
    }));
  }, [directedLoop]);
  const nodeLabelById = useMemo(() => {
    const map = new Map<string, string>();
    anchorLabels.forEach((label) => {
      map.set(label.id, label.name);
    });
    return map;
  }, [anchorLabels]);
  const structurePaths = useMemo(
    () =>
      graphSubpaths.map((subpath, index) => ({
        id: subpath.id,
        index,
        anchorCount: subpath.anchors.length,
        segmentCount: subpath.closed
          ? subpath.anchors.length
          : Math.max(0, subpath.anchors.length - 1),
        closed: subpath.closed,
      })),
    [graphSubpaths]
  );
  const structureNodes = useMemo(
    () =>
      directedLoop.nodes.map((node) => ({
        id: node.id,
        label: nodeLabelById.get(node.id) ?? `draw_${node.order.toString().padStart(2, "0")}`,
        x: node.point.x,
        y: node.point.y,
      })),
    [directedLoop.nodes, nodeLabelById]
  );
  const structureEdges = useMemo(
    () =>
      directedLoop.edges.map((edge, index) => ({
        ...edge,
        order: index,
        fromLabel: nodeLabelById.get(edge.from) ?? edge.from,
        toLabel: nodeLabelById.get(edge.to) ?? edge.to,
      })),
    [directedLoop.edges, nodeLabelById]
  );
  const selectedSubpathIndices = useMemo(
    () => new Set(selectedPoints.map((point) => point.subpathIndex)),
    [selectedPoints]
  );
  const selectedAnchorKeys = useMemo(
    () =>
      new Set(
        selectedPoints
          .filter((point) => point.kind === "p0" || point.kind === "p3")
          .map((point) => anchorKeyFor(point))
      ),
    [selectedPoints]
  );

  const timelineLayers = useMemo(() => {
    const p = timelineProgress;
    const showLogoLayer = p >= 0;
    const showRawLayer = p >= 0.16;
    const showScaffoldLayer = p >= 0.46;
    const showLabelLayer = p >= 0.56;
    const showAngleLayer = p >= 0.72;
    const animateLayer = p >= 0.16;
    const logoOpacityLayer = p < 0.16 ? 1 : 0.35;
    const rawOpacityLayer = p < 0.16 ? 0 : 1;
    const scaffoldOpacityLayer = p < 0.46 ? 0 : 1;

    return {
      showLogo: showLogoLayer,
      showRaw: showRawLayer,
      showScaffold: showScaffoldLayer,
      showAnchorLabels: showLabelLayer,
      showAngles: showAngleLayer,
      animateDraw: animateLayer,
      logoOpacity: logoOpacityLayer,
      rawOpacity: rawOpacityLayer,
      scaffoldOpacity: scaffoldOpacityLayer,
    };
  }, [timelineProgress]);

  const effectiveLayers = {
    showLogo: showLogo && (timelineLayers?.showLogo ?? true),
    showRaw: showRaw && (timelineLayers?.showRaw ?? true),
    showScaffold: showScaffold && (timelineLayers?.showScaffold ?? true),
    showAnchorLabels: showAnchorLabels && (timelineLayers?.showAnchorLabels ?? true),
    showAngles: showAngles && (timelineLayers?.showAngles ?? true),
    animateDraw: animateDraw && (timelineLayers?.animateDraw ?? true),
    logoOpacity: timelineLayers?.logoOpacity ?? 1,
    rawOpacity: timelineLayers?.rawOpacity ?? 1,
    scaffoldOpacity: timelineLayers?.scaffoldOpacity ?? 1,
  };
  const structureLayerRows = useMemo(
    () => [
      {
        id: "logo",
        label: "Logo image",
        enabled: showLogo,
        visible: effectiveLayers.showLogo,
      },
      {
        id: "raw",
        label: "Raw vector",
        enabled: showRaw,
        visible: effectiveLayers.showRaw,
      },
      {
        id: "scaffold",
        label: "Scaffold",
        enabled: showScaffold,
        visible: effectiveLayers.showScaffold,
      },
      {
        id: "labels",
        label: "Anchor labels",
        enabled: showAnchorLabels,
        visible: effectiveLayers.showAnchorLabels,
      },
      {
        id: "angles",
        label: "Angles",
        enabled: showAngles,
        visible: effectiveLayers.showAngles,
      },
      {
        id: "animate",
        label: "Animate draw",
        enabled: animateDraw,
        visible: effectiveLayers.animateDraw,
      },
    ],
    [
      animateDraw,
      effectiveLayers.animateDraw,
      effectiveLayers.showAnchorLabels,
      effectiveLayers.showAngles,
      effectiveLayers.showLogo,
      effectiveLayers.showRaw,
      effectiveLayers.showScaffold,
      showAnchorLabels,
      showAngles,
      showLogo,
      showRaw,
      showScaffold,
    ]
  );

  const activeLogo = useMemo(() => {
    return logoOptions.find((option) => option.id === logoChoice) ?? logoOptions[0];
  }, [logoChoice]);

  const logoTransform = useMemo(() => {
    return `translate(${logoOffsetX} ${logoOffsetY}) translate(${logoCenterX} ${logoCenterY}) scale(${logoScale}) translate(${-logoCenterX} ${-logoCenterY})`;
  }, [logoOffsetX, logoOffsetY, logoScale]);

  const zoomedViewBox = useMemo(() => {
    const zoom = Math.max(0.25, canvasZoom);
    const width = viewBoxWidth / zoom;
    const height = viewBoxHeight / zoom;
    const x = viewCenterX - width / 2;
    const y = viewCenterY - height / 2;
    return `${x} ${y} ${width} ${height}`;
  }, [canvasZoom, viewCenterX, viewCenterY, viewBoxWidth, viewBoxHeight]);

  useEffect(() => {
    if (!editablePathRef.current) {
      return;
    }
    const length = editablePathRef.current.getTotalLength();
    setDashLength(length);
  }, [currentPath]);

  useEffect(() => {
    const pathEl = editablePathRef.current;
    if (!pathEl) {
      return;
    }
    const total = pathEl.getTotalLength();
    if (!Number.isFinite(total) || total <= 0) {
      return;
    }
    const next: Record<string, number> = {};
    angleArcs.forEach((arc) => {
      const lengthAt = findClosestLength(pathEl, { x: arc.x, y: arc.y }, total);
      next[arc.anchorKey] = lengthAt / total;
    });
    setAnchorProgress(next);
  }, [currentPath, angleArcs]);

  useEffect(() => {
    if (!effectiveLayers.animateDraw) {
      setDrawProgress(1);
      return;
    }
    let raf = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const elapsed = (now - start) / 1000;
      const next = (elapsed % drawDuration) / drawDuration;
      setDrawProgress(next);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [drawDuration, effectiveLayers.animateDraw]);


  useEffect(() => {
    if (pathMode === "view") {
      setPathDraft(prettyPath);
      setPathDirty(false);
      return;
    }
    if (!pathDirty) {
      setPathDraft(prettyPath);
    }
  }, [pathMode, pathDirty, prettyPath]);

  useEffect(() => {
    progressRef.current = timelineProgress;
  }, [timelineProgress]);

  useEffect(() => {
    historyIndexRef.current = historyIndex;
  }, [historyIndex]);

  useEffect(() => {
    void fetchSavedVersions();
  }, []);

  useEffect(() => {
    if (!timelinePlaying) {
      return;
    }

    let raf = 0;
    const durationMs = timelineDuration * 1000;
    const start = performance.now() - progressRef.current * durationMs;

    const tick = (now: number) => {
      const next = Math.min((now - start) / durationMs, 1);
      setTimelineProgress(next);
      if (next < 1) {
        raf = requestAnimationFrame(tick);
      } else {
        setTimelinePlaying(false);
      }
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [timelinePlaying, timelineDuration]);

  const onReset = () => {
    const next = cloneSubpaths(initialEditableSubpaths);
    setSubpaths(next);
    setSelectedIds([]);
    commitHistory(next);
  };

  const onCopy = async () => {
    try {
      const ok = await copyToClipboard(currentPath);
      if (ok) {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1200);
      }
    } catch {
      setCopied(false);
    }
  };

  const startEdit = () => {
    setPathMode("edit");
    setPathDraft(prettyPath);
    setPathError("");
    setPathDirty(false);
  };

  const cancelEdit = () => {
    setPathMode("view");
    setPathError("");
    setPathDirty(false);
  };

  const applyEdit = () => {
    const next = parsePath(pathDraft);
    if (!hasSegments(next)) {
      setPathError("Could not parse path. Only M/C/Z commands are supported.");
      return;
    }
    setSubpaths(next);
    commitHistory(next);
    setPathMode("view");
    setPathError("");
    setPathDirty(false);
    setSelectedIds([]);
  };

  const resetLogoTransform = () => {
    setLogoScale(1);
    setLogoOffsetX(0);
    setLogoOffsetY(0);
    setLogoOpacity(0.8);
  };

  const buildSavePayloadFrom = (paths: Subpath[]) => {
    const graph = subpathsToGraph(paths);
    const payload = {
      updatedAt: new Date().toISOString(),
      viewBox,
      path: buildPath(paths),
      subpaths: serializeSubpaths(paths),
      graphSubpaths: serializeGraphSubpaths(graph),
    };
    return JSON.stringify(payload, null, 2);
  };

  const recordSavedVersion = (version: SavedVersion) => {
    setSavedVersions((prev) => {
      const next = [version, ...prev.filter((item) => item.fileName !== version.fileName)];
      next.sort(
        (a, b) =>
          new Date(b.lastModified).getTime() - new Date(a.lastModified).getTime()
      );
      return next;
    });
  };

  const fetchSavedVersions = async () => {
    try {
      const response = await fetch("/api/list-bezier-versions");
      if (!response.ok) {
        throw new Error(`Failed to list saved versions (${response.status})`);
      }
      const data = (await response.json()) as SavedVersion[];
      setSavedVersions(
        data.sort(
          (a, b) =>
            new Date(b.lastModified).getTime() -
            new Date(a.lastModified).getTime()
        )
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setSaveState({
        status: "error",
        message: "Could not load saved versions.",
        detail: message,
      });
    }
  };

  const saveVersionToRepo = async (paths: Subpath[], label: string) => {
    try {
      setSaveState({ status: "saving", message: "Saving…" });
      const contents = buildSavePayloadFrom(paths);
      const response = await fetch("/api/save-bezier", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contents, label }),
      });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Save failed (${response.status})`);
      }
      const data = (await response.json()) as SavedVersion & { ok: boolean };
      setSaveState({
        status: data.ok ? "saved" : "error",
        message: data.ok ? "Saved and verified." : "Saved, but verification failed.",
        detail: `${data.relativePath} • ${data.size} bytes • ${data.lastModified}\n${data.absolutePath}`,
      });
      recordSavedVersion(data);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setSaveState({
        status: "error",
        message: "Save failed.",
        detail: message,
      });
    }
  };

  const handleLoadSavedVersion = async (version: SavedVersion) => {
    try {
      const response = await fetch(
        `/api/load-bezier?file=${encodeURIComponent(version.fileName)}`
      );
      if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `Load failed (${response.status})`);
      }
      const data = (await response.json()) as {
        subpaths?: SerializedSubpath[];
        graphSubpaths?: SerializedGraphSubpath[];
        path?: string;
      };
      let nextSubpaths: Subpath[] | null = null;
      if (data.graphSubpaths && data.graphSubpaths.length > 0) {
        const nextGraph = deserializeGraphSubpaths(data.graphSubpaths);
        setGraphSubpaths(nextGraph);
        nextSubpaths = graphToSubpaths(nextGraph);
      } else if (data.subpaths && data.subpaths.length > 0) {
        nextSubpaths = deserializeSubpaths(data.subpaths);
        setSubpaths(nextSubpaths);
      }

      if (!nextSubpaths || nextSubpaths.length === 0) {
        throw new Error("Saved file did not contain subpaths.");
      }
      commitHistory(nextSubpaths);
      setSelectedIds([]);
      const versionId = `file:${version.fileName}`;
      setPathVersions((prev) => {
        const existing = prev.find((entry) => entry.id === versionId);
        if (existing) {
          return prev.map((entry) =>
            entry.id === versionId
              ? { ...entry, path: buildPath(nextSubpaths), subpaths: nextSubpaths }
              : entry
          );
        }
        return [
          ...prev,
          {
            id: versionId,
            name: `Saved ${version.fileName}`,
            path: buildPath(nextSubpaths),
            subpaths: nextSubpaths,
          },
        ];
      });
      setActiveVersionId(versionId);
      setPathMode("view");
      setPathError("");
      setPathDirty(false);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setSaveState({
        status: "error",
        message: "Failed to load saved file.",
        detail: message,
      });
    }
  };

  const handleVersionSelect = (id: string) => {
    const version = pathVersions.find((entry) => entry.id === id);
    if (!version) {
      return;
    }
    setActiveVersionId(id);
    setSubpaths(cloneSubpaths(version.subpaths));
    commitHistory(version.subpaths);
    setSelectedIds([]);
    setPathMode("view");
    setPathError("");
    setPathDirty(false);
  };

  const resolveDraftSubpaths = () => {
    if (pathMode !== "edit" || !pathDirty) {
      return null;
    }
    const next = parsePath(pathDraft);
    if (!hasSegments(next)) {
      setPathError("Could not parse path. Only M/C/Z commands are supported.");
      return null;
    }
    return next;
  };

  const handleVersionSave = () => {
    const draftSubpaths = resolveDraftSubpaths();
    const nextSubpaths = cloneSubpaths(draftSubpaths ?? subpaths);
    if (draftSubpaths) {
      setSubpaths(nextSubpaths);
      setPathMode("view");
      setPathError("");
      setPathDirty(false);
    }
    const trimmed = versionName.trim();
    const name =
      trimmed.length > 0 ? trimmed : `Version ${pathVersions.length + 1}`;
    const nextVersion = {
      id: `version-${Date.now()}`,
      name,
      path: buildPath(nextSubpaths),
      subpaths: nextSubpaths,
    };
    setPathVersions((prev) => [...prev, nextVersion]);
    setActiveVersionId(nextVersion.id);
    setVersionName("");
    void saveVersionToRepo(nextSubpaths, name);
  };

  const handleVersionUpdate = () => {
    const draftSubpaths = resolveDraftSubpaths();
    const nextSubpaths = cloneSubpaths(draftSubpaths ?? subpaths);
    if (draftSubpaths) {
      setSubpaths(nextSubpaths);
      setPathMode("view");
      setPathError("");
      setPathDirty(false);
    }
    setPathVersions((prev) =>
      prev.map((entry) =>
        entry.id === activeVersionId
          ? {
              ...entry,
              path: buildPath(nextSubpaths),
              subpaths: nextSubpaths,
            }
          : entry
      )
    );
    const currentName =
      pathVersions.find((entry) => entry.id === activeVersionId)?.name ??
      "Version";
    void saveVersionToRepo(nextSubpaths, currentName);
  };

  const resetCanvasView = () => {
    setCanvasZoom(1);
    setViewCenterX(viewBoxCenterX);
    setViewCenterY(viewBoxCenterY);
  };

  const commitHistory = (nextSubpaths: Subpath[]) => {
    const nextPath = buildPath(nextSubpaths);
    let appended = false;
    setHistory((prev) => {
      const base = prev.slice(0, historyIndexRef.current + 1);
      const last = base[base.length - 1];
      if (last && last.path === nextPath) {
        return base;
      }
      appended = true;
      return [
        ...base,
        {
          subpaths: cloneSubpaths(nextSubpaths),
          path: nextPath,
        },
      ];
    });
    setHistoryIndex((prev) => (appended ? prev + 1 : prev));
  };

  const handleUndo = () => {
    if (historyIndexRef.current <= 0) {
      return;
    }
    const nextIndex = historyIndexRef.current - 1;
    const snapshot = history[nextIndex];
    if (!snapshot) {
      return;
    }
    setHistoryIndex(nextIndex);
    historyIndexRef.current = nextIndex;
    setSubpaths(cloneSubpaths(snapshot.subpaths));
    setSelectedIds([]);
  };

  const handleRedo = () => {
    if (historyIndexRef.current >= history.length - 1) {
      return;
    }
    const nextIndex = historyIndexRef.current + 1;
    const snapshot = history[nextIndex];
    if (!snapshot) {
      return;
    }
    setHistoryIndex(nextIndex);
    historyIndexRef.current = nextIndex;
    setSubpaths(cloneSubpaths(snapshot.subpaths));
    setSelectedIds([]);
  };

  const handleLogoPointerDown = (event: ReactPointerEvent<SVGImageElement>) => {
    if (event.button === 2) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const point = toSvgPoint(event);
    if (!point) {
      return;
    }
    if (drawMode) {
      if (!drawStart) {
        setDrawStart(point);
      } else {
        const nextSubpaths = cloneSubpaths(subpaths);
        const lastSubpath = nextSubpaths[nextSubpaths.length - 1];
        const lastSegment =
          lastSubpath?.segments[lastSubpath.segments.length - 1] ?? null;
        if (
          lastSegment &&
          Math.abs(lastSegment.p3.x - drawStart.x) < 0.001 &&
          Math.abs(lastSegment.p3.y - drawStart.y) < 0.001
        ) {
          lastSubpath.segments.push(createSegment(drawStart, point));
        } else {
          nextSubpaths.push({
            closed: false,
            segments: [createSegment(drawStart, point)],
          });
        }
        setSubpaths(nextSubpaths);
        commitHistory(nextSubpaths);
        setDrawStart(point);
      }
      return;
    }
    if (selectionMode || event.shiftKey) {
      selectionAdditiveRef.current =
        selectionMode && (event.shiftKey || event.metaKey || event.ctrlKey);
      selectionBaseRef.current = selectionAdditiveRef.current ? selectedIds : [];
      selectionStartRef.current = point;
      setSelectionBox({ x: point.x, y: point.y, width: 0, height: 0 });
      setIsSelecting(true);
      if (!selectionAdditiveRef.current) {
        setSelectedIds([]);
      }
      return;
    }
    setDragging(null);
    selectionStartRef.current = null;
    setIsSelecting(false);
    event.currentTarget.setPointerCapture(event.pointerId);
    logoDragRef.current = {
      start: point,
      offsetX: logoOffsetX,
      offsetY: logoOffsetY,
    };
  };

  const handleTimelinePlay = () => {
    if (timelineProgress >= 1) {
      setTimelineProgress(0);
      progressRef.current = 0;
    }
    setTimelinePlaying(true);
  };

  const handleTimelinePause = () => {
    setTimelinePlaying(false);
  };

  const handleTimelineReset = () => {
    setTimelineProgress(0);
    setTimelinePlaying(false);
  };

  const handleTimelineChange = (value: number) => {
    setTimelineProgress(value);
    setTimelinePlaying(false);
  };

  const handleCanvasWheel = (event: React.WheelEvent<SVGSVGElement>) => {
    if (!(event.altKey || event.metaKey || event.ctrlKey)) {
      return;
    }
    event.preventDefault();
    const svg = svgRef.current;
    if (!svg) {
      return;
    }
    const rect = svg.getBoundingClientRect();
    const vx = (event.clientX - rect.left) / rect.width;
    const vy = (event.clientY - rect.top) / rect.height;
    const nextZoom = Math.min(
      5,
      Math.max(0.25, canvasZoom * (event.deltaY > 0 ? 0.9 : 1.1))
    );
    if (nextZoom === canvasZoom) {
      return;
    }
    const width = viewBoxWidth / canvasZoom;
    const height = viewBoxHeight / canvasZoom;
    const x = viewCenterX - width / 2;
    const y = viewCenterY - height / 2;
    const point = {
      x: x + vx * width,
      y: y + vy * height,
    };
    const nextWidth = viewBoxWidth / nextZoom;
    const nextHeight = viewBoxHeight / nextZoom;
    setCanvasZoom(nextZoom);
    setViewCenterX(point.x + (0.5 - vx) * nextWidth);
    setViewCenterY(point.y + (0.5 - vy) * nextHeight);
  };

  const toSvgPoint = (event: ReactPointerEvent<SVGSVGElement>) => {
    const svg = svgRef.current;
    if (!svg) {
      return null;
    }
    const point = svg.createSVGPoint();
    point.x = event.clientX;
    point.y = event.clientY;
    const matrix = svg.getScreenCTM();
    if (!matrix) {
      return null;
    }
    const transformed = point.matrixTransform(matrix.inverse());
    return { x: transformed.x, y: transformed.y };
  };

  const handlePointerDown = (
    event: ReactPointerEvent<SVGCircleElement>,
    point: ControlPoint
  ) => {
    event.preventDefault();
    event.stopPropagation();
    if (event.button === 2) {
      return;
    }
    const wantsMulti =
      selectionMode || event.shiftKey || event.metaKey || event.ctrlKey;
    const isSelected = selectedIds.includes(point.id);
    let nextSelected = selectedIds;

    if (wantsMulti) {
      nextSelected = isSelected
        ? selectedIds.filter((id) => id !== point.id)
        : [...selectedIds, point.id];
      setSelectedIds(nextSelected);
    } else if (!isSelected || selectedIds.length > 1) {
      nextSelected = [point.id];
      setSelectedIds(nextSelected);
    }

    if (nextSelected.includes(point.id) && nextSelected.length > 1) {
      const start = toSvgPoint(event);
      if (!start) {
        return;
      }
      groupDragRef.current = {
        start,
        base: cloneSubpaths(subpaths),
        keys: buildSelectionKeys(subpaths, selectedPoints),
      };
      event.currentTarget.setPointerCapture(event.pointerId);
      return;
    }
    setDragging(point);
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const handlePointerMove = (event: ReactPointerEvent<SVGSVGElement>) => {
    if (logoDragRef.current) {
      const next = toSvgPoint(event);
      if (!next) {
        return;
      }
      const delta = {
        x: next.x - logoDragRef.current.start.x,
        y: next.y - logoDragRef.current.start.y,
      };
      setLogoOffsetX(logoDragRef.current.offsetX + delta.x);
      setLogoOffsetY(logoDragRef.current.offsetY + delta.y);
      return;
    }
    if (isSelecting && selectionStartRef.current) {
      const next = toSvgPoint(event);
      if (!next) {
        return;
      }
      const start = selectionStartRef.current;
      const x = Math.min(start.x, next.x);
      const y = Math.min(start.y, next.y);
      const width = Math.abs(next.x - start.x);
      const height = Math.abs(next.y - start.y);
      setSelectionBox({ x, y, width, height });
      return;
    }
    if (groupDragRef.current && groupDragRef.current.keys.length > 0) {
      const nextPoint = toSvgPoint(event);
      if (!nextPoint) {
        return;
      }
      const delta = {
        x: nextPoint.x - groupDragRef.current.start.x,
        y: nextPoint.y - groupDragRef.current.start.y,
      };
      const working = applyDeltaToKeys(
        groupDragRef.current.base,
        groupDragRef.current.keys,
        delta
      );
      setSubpaths(working);
      return;
    }
    if (!dragging) {
      return;
    }
    const next = toSvgPoint(event);
    if (!next) {
      return;
    }
    setSubpaths((prev) => updatePoint(prev, dragging, next));
  };

  const handlePointerUp = (
    event?: ReactPointerEvent<SVGSVGElement | SVGImageElement>
  ) => {
    if (event?.pointerId != null) {
      try {
        svgRef.current?.releasePointerCapture(event.pointerId);
      } catch {
        // no-op
      }
    }
    if (logoDragRef.current) {
      logoDragRef.current = null;
      return;
    }
    if (isSelecting) {
      if (selectionBox) {
        const nextSelected = allPoints
          .filter(
            (point) =>
              point.x >= selectionBox.x &&
              point.x <= selectionBox.x + selectionBox.width &&
              point.y >= selectionBox.y &&
              point.y <= selectionBox.y + selectionBox.height
          )
          .map((point) => point.id);
        if (selectionAdditiveRef.current) {
          const merged = new Set([...selectionBaseRef.current, ...nextSelected]);
          setSelectedIds(Array.from(merged));
        } else {
          setSelectedIds(nextSelected);
        }
      }
      setIsSelecting(false);
      setSelectionBox(null);
      selectionStartRef.current = null;
      selectionAdditiveRef.current = false;
      selectionBaseRef.current = [];
      return;
    }

    if (groupDragRef.current && groupDragRef.current.keys.length > 0) {
      groupDragRef.current = null;
      commitHistory(subpaths);
      return;
    }

    if (dragging) {
      setDragging(null);
      commitHistory(subpaths);
    }
  };

  const deleteControlPoint = (
    nextSubpaths: Subpath[],
    point: ControlPoint
  ): Subpath[] => {
    if (point.kind === "c1" || point.kind === "c2") {
      const segment = nextSubpaths[point.subpathIndex]?.segments[point.segmentIndex];
      if (!segment) {
        return nextSubpaths;
      }
      if (point.kind === "c1") {
        segment.c1 = { ...segment.p0 };
      } else {
        segment.c2 = { ...segment.p3 };
      }
      return nextSubpaths;
    }
    return deleteSegment(nextSubpaths, point.subpathIndex, point.segmentIndex);
  };

  const getAnchorSelection = () => {
    if (selectedPoints.length !== 1) {
      return null;
    }
    const point = selectedPoints[0];
    if (point.kind === "c1" || point.kind === "c2") {
      return null;
    }
    return point;
  };

  const handleAddPoint = () => {
    const anchor = getAnchorSelection();
    if (!anchor) {
      return;
    }
    const nextSubpaths = cloneSubpaths(subpaths);
    const subpath = nextSubpaths[anchor.subpathIndex];
    if (!subpath) {
      return;
    }
    const segment = subpath.segments[anchor.segmentIndex];
    if (!segment) {
      return;
    }
    const [left, right] = splitSegmentAt(segment, 0.5);
    subpath.segments.splice(anchor.segmentIndex, 1, left, right);
    setSubpaths(nextSubpaths);
    setSelectedIds([]);
    commitHistory(nextSubpaths);
  };

  const handleRoundAnchor = () => {
    const anchor = getAnchorSelection();
    if (!anchor) {
      return;
    }
    const nextSubpaths = cloneSubpaths(subpaths);
    const subpath = nextSubpaths[anchor.subpathIndex];
    if (!subpath) {
      return;
    }

    const isClosed = subpath.closed;
    const anchorIndex = anchor.segmentIndex;
    const prevIndex = anchorIndex - (anchor.kind === "p0" ? 1 : 0);
    const nextIndex = anchorIndex + (anchor.kind === "p3" ? 1 : 0);

    const prevSegment =
      prevIndex >= 0
        ? subpath.segments[prevIndex]
        : isClosed
          ? subpath.segments[subpath.segments.length - 1]
          : null;
    const nextSegment =
      nextIndex < subpath.segments.length
        ? subpath.segments[nextIndex]
        : isClosed
          ? subpath.segments[0]
          : null;

    const anchorPoint =
      anchor.kind === "p0"
        ? subpath.segments[anchorIndex]?.p0
        : subpath.segments[anchorIndex]?.p3;
    if (!anchorPoint) {
      return;
    }
    const prevAnchor = prevSegment?.p0 ?? anchorPoint;
    const nextAnchor = nextSegment?.p3 ?? anchorPoint;
    const direction = normalize({
      x: nextAnchor.x - prevAnchor.x,
      y: nextAnchor.y - prevAnchor.y,
    });
    const distancePrev = Math.hypot(anchorPoint.x - prevAnchor.x, anchorPoint.y - prevAnchor.y);
    const distanceNext = Math.hypot(nextAnchor.x - anchorPoint.x, nextAnchor.y - anchorPoint.y);
    const handleLength = Math.max(4, Math.min(distancePrev, distanceNext) * roundness * 0.45);

    if (prevSegment) {
      prevSegment.c2 = {
        x: anchorPoint.x - direction.x * handleLength,
        y: anchorPoint.y - direction.y * handleLength,
      };
    }
    if (nextSegment) {
      nextSegment.c1 = {
        x: anchorPoint.x + direction.x * handleLength,
        y: anchorPoint.y + direction.y * handleLength,
      };
    }
    setSubpaths(nextSubpaths);
    commitHistory(nextSubpaths);
  };

  const handleStructureSubpathSelect = (subpathIndex: number) => {
    const preferredAnchor =
      anchors.find(
        (anchor) => anchor.subpathIndex === subpathIndex && anchor.kind === "p0"
      ) ?? anchors.find((anchor) => anchor.subpathIndex === subpathIndex);
    if (!preferredAnchor) {
      return;
    }
    setSelectedIds([preferredAnchor.id]);
  };

  const handleStructureNodeSelect = (nodeId: string) => {
    const candidates = anchors.filter((anchor) => anchorKeyFor(anchor) === nodeId);
    const preferredAnchor =
      candidates.find((anchor) => anchor.kind === "p0") ?? candidates[0];
    if (!preferredAnchor) {
      return;
    }
    setSelectedIds([preferredAnchor.id]);
  };

  const handleStructureEdgeSelect = (edge: DirectedEdge) => {
    handleStructureNodeSelect(edge.to);
  };

  const applyCapturePreset = (
    preset: "path-only" | "path-scaffold" | "path-scaffold-angles" | "path-full"
  ) => {
    setShowLogo(false);
    setShowRaw(true);
    setAnimateDraw(true);
    if (preset === "path-only") {
      setShowScaffold(false);
      setShowAngles(false);
      setShowAnchorLabels(false);
      return;
    }
    if (preset === "path-scaffold") {
      setShowScaffold(true);
      setShowAngles(false);
      setShowAnchorLabels(false);
      return;
    }
    if (preset === "path-scaffold-angles") {
      setShowScaffold(true);
      setShowAngles(true);
      setShowAnchorLabels(false);
      return;
    }
    setShowScaffold(true);
    setShowAngles(true);
    setShowAnchorLabels(true);
  };

  const handlePointDelete = (
    event: ReactMouseEvent<SVGCircleElement>,
    point: ControlPoint
  ) => {
    event.preventDefault();
    event.stopPropagation();
    const next = deleteControlPoint(cloneSubpaths(subpaths), point);
    setSubpaths(next);
    setSelectedIds((prev) => prev.filter((id) => id !== point.id));
    commitHistory(next);
  };

  const handleCanvasPointerDown = (event: ReactPointerEvent<SVGSVGElement>) => {
    if (event.button !== 0) {
      return;
    }
    const isControlPoint = event.target instanceof SVGCircleElement;
    if (!selectionMode && event.target !== svgRef.current) {
      return;
    }
    if (selectionMode && isControlPoint) {
      return;
    }
    const point = toSvgPoint(event);
    if (!point) {
      return;
    }
    if (drawMode) {
      if (!drawStart) {
        setDrawStart(point);
      } else {
        const nextSubpaths = cloneSubpaths(subpaths);
        const lastSubpath = nextSubpaths[nextSubpaths.length - 1];
        const lastSegment =
          lastSubpath?.segments[lastSubpath.segments.length - 1] ?? null;
        if (
          lastSegment &&
          Math.abs(lastSegment.p3.x - drawStart.x) < 0.001 &&
          Math.abs(lastSegment.p3.y - drawStart.y) < 0.001
        ) {
          lastSubpath.segments.push(createSegment(drawStart, point));
        } else {
          nextSubpaths.push({
            closed: false,
            segments: [createSegment(drawStart, point)],
          });
        }
        setSubpaths(nextSubpaths);
        commitHistory(nextSubpaths);
        setDrawStart(point);
      }
      return;
    }
    selectionAdditiveRef.current =
      selectionMode && (event.shiftKey || event.metaKey || event.ctrlKey);
    selectionBaseRef.current = selectionAdditiveRef.current ? selectedIds : [];
    selectionStartRef.current = point;
    setSelectionBox({ x: point.x, y: point.y, width: 0, height: 0 });
    setIsSelecting(true);
    if (!selectionAdditiveRef.current) {
      setSelectedIds([]);
    }
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (isEditableTarget(event.target)) {
        return;
      }

      const key = event.key.toLowerCase();
      const isMeta = event.metaKey || event.ctrlKey;

      if (isMeta && key === "z") {
        event.preventDefault();
        if (event.shiftKey) {
          handleRedo();
        } else {
          handleUndo();
        }
        return;
      }

      if (key === "d") {
        event.preventDefault();
        setDrawMode((prev) => {
          const next = !prev;
          if (!next) {
            setDrawStart(null);
          }
          return next;
        });
        return;
      }

      if (key === "m") {
        event.preventDefault();
        setSelectionMode((prev) => !prev);
        return;
      }

      if (key === "escape") {
        event.preventDefault();
        setDrawStart(null);
        setIsSelecting(false);
        setSelectionBox(null);
        selectionStartRef.current = null;
        setSelectedIds([]);
        setShowShortcuts(false);
        return;
      }

      if (key === "?") {
        event.preventDefault();
        setShowShortcuts((prev) => !prev);
        return;
      }

      if (key === "delete" || key === "backspace") {
        if (selectedPoints.length === 0) {
          return;
        }
        event.preventDefault();
        const nextSubpaths = cloneSubpaths(subpaths);
        const toDelete = [...selectedPoints].sort((a, b) => {
          if (a.subpathIndex !== b.subpathIndex) {
            return b.subpathIndex - a.subpathIndex;
          }
          return b.segmentIndex - a.segmentIndex;
        });
        toDelete.forEach((point) => {
          deleteControlPoint(nextSubpaths, point);
        });
        setSubpaths(nextSubpaths);
        setSelectedIds([]);
        commitHistory(nextSubpaths);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedPoints, subpaths]);

  return (
    <div className="page">
      <header className="header">
        <span className="eyebrow">Talkie Design Lab</span>
        <h1>Bezier Logo Playground</h1>
        <p>Vector editing and motion sequencing for the Talkie mark.</p>
      </header>

      <main className="layout">
        <aside className="panel panel-left">
          <section className="card nav-card">
            <h2>Navigation</h2>
            <h3>Canvas</h3>
            <label className="toggle">
              <input
                type="checkbox"
                checked={showLogo}
                onChange={(event) => setShowLogo(event.target.checked)}
              />
              Show logo image
            </label>
            <label className="toggle">
              <input
                type="checkbox"
                checked={showRaw}
                onChange={(event) => setShowRaw(event.target.checked)}
              />
              Show raw path
            </label>
            <label className="toggle">
              <input
                type="checkbox"
                checked={showScaffold}
                onChange={(event) => setShowScaffold(event.target.checked)}
              />
              Show scaffold
            </label>
            <label className="toggle">
              <input
                type="checkbox"
                checked={animateDraw}
                onChange={(event) => setAnimateDraw(event.target.checked)}
              />
              Animate draw
            </label>
            <div className="divider" />
            <h3>Overlays</h3>
            <label className="toggle">
              <input
                type="checkbox"
                checked={showAnchorLabels}
                onChange={(event) => setShowAnchorLabels(event.target.checked)}
              />
              Anchor names
            </label>
            <label className="toggle">
              <input
                type="checkbox"
                checked={showAngles}
                onChange={(event) => setShowAngles(event.target.checked)}
              />
              Angle overlay
            </label>
            <div className="divider" />
            <h3>Capture Takes</h3>
            <div className="preset-grid">
              <button type="button" onClick={() => applyCapturePreset("path-only")}>
                Path
              </button>
              <button type="button" onClick={() => applyCapturePreset("path-scaffold")}>
                Path + Scaffold
              </button>
              <button
                type="button"
                onClick={() => applyCapturePreset("path-scaffold-angles")}
              >
                Path + Scaffold + Angle
              </button>
              <button type="button" onClick={() => applyCapturePreset("path-full")}>
                Path + Scaffold + Angle + Names
              </button>
            </div>
          </section>

          <section className="card structure-card">
            <h2>Structure</h2>

            <div className="structure-section">
              <h3>Layers</h3>
              <div className="structure-list">
                {structureLayerRows.map((layer) => (
                  <div key={layer.id} className="structure-row">
                    <span
                      className={`structure-dot ${layer.visible ? "is-on" : "is-off"}`}
                      aria-hidden="true"
                    />
                    <span>{layer.label}</span>
                    <span className="structure-state">
                      {layer.enabled ? (layer.visible ? "shown" : "staged") : "off"}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            <div className="structure-section">
              <h3>Paths</h3>
              <div className="structure-list">
                {structurePaths.map((subpath) => (
                  <button
                    key={subpath.id}
                    type="button"
                    className={`structure-item ${selectedSubpathIndices.has(subpath.index) ? "is-selected" : ""}`}
                    onClick={() => handleStructureSubpathSelect(subpath.index)}
                  >
                    <span className="structure-item-title">{subpath.id}</span>
                    <span className="structure-item-meta">
                      {subpath.anchorCount} nodes, {subpath.segmentCount} segments,{" "}
                      {subpath.closed ? "closed" : "open"}
                    </span>
                  </button>
                ))}
                {structurePaths.length === 0 && (
                  <p className="structure-empty">No paths available.</p>
                )}
              </div>
            </div>

            <div className="structure-section">
              <h3>Nodes</h3>
              <div className="structure-list">
                {structureNodes.map((node) => (
                  <button
                    key={node.id}
                    type="button"
                    className={`structure-item ${selectedAnchorKeys.has(node.id) ? "is-selected" : ""}`}
                    onClick={() => handleStructureNodeSelect(node.id)}
                  >
                    <span className="structure-item-title">{node.label}</span>
                    <span className="structure-item-meta">
                      ({formatNumber(node.x)}, {formatNumber(node.y)})
                    </span>
                  </button>
                ))}
                {structureNodes.length === 0 && (
                  <p className="structure-empty">No nodes available.</p>
                )}
              </div>
            </div>

            <div className="structure-section">
              <h3>Edges</h3>
              <div className="structure-list">
                {structureEdges.map((edge) => (
                  <button
                    key={edge.id}
                    type="button"
                    className={`structure-item ${selectedAnchorKeys.has(edge.from) || selectedAnchorKeys.has(edge.to) ? "is-selected" : ""}`}
                    onClick={() => handleStructureEdgeSelect(edge)}
                  >
                    <span className="structure-item-title">
                      edge_{edge.order.toString().padStart(2, "0")}
                    </span>
                    <span className="structure-item-meta">
                      {edge.fromLabel} {"->"} {edge.toLabel}
                    </span>
                  </button>
                ))}
                {structureEdges.length === 0 && (
                  <p className="structure-empty">No directed edges available.</p>
                )}
              </div>
            </div>
          </section>
        </aside>

        <section className="canvas-panel">
          <section className="card canvas-card">
            <div className="canvas">
              <svg
                ref={svgRef}
                viewBox={zoomedViewBox}
                preserveAspectRatio="xMidYMid meet"
                style={
                  {
                    "--angle-count": angleCount,
                    "--draw-duration": `${drawDuration}s`,
                  } as CSSProperties
                }
                onPointerMove={handlePointerMove}
                onPointerUp={handlePointerUp}
                onPointerLeave={handlePointerUp}
                onPointerCancel={handlePointerUp}
                onPointerDown={handleCanvasPointerDown}
                onWheel={handleCanvasWheel}
              >
                {effectiveLayers.showLogo && (
                  <image
                    href={activeLogo.src}
                    x={viewBoxX}
                    y={viewBoxY}
                    width={viewBoxWidth}
                    height={viewBoxHeight}
                    preserveAspectRatio="xMidYMid meet"
                    className="logo-image"
                    transform={logoTransform}
                    style={{ opacity: logoOpacity * effectiveLayers.logoOpacity }}
                    onPointerDown={handleLogoPointerDown}
                  />
                )}

                {effectiveLayers.showRaw && (
                  <path
                    ref={editablePathRef}
                    d={currentPath}
                    className={`path raw ${effectiveLayers.animateDraw ? "animate" : ""}`}
                    style={
                      {
                        "--dash-length": dashLength,
                        opacity: effectiveLayers.rawOpacity,
                        strokeDasharray: effectiveLayers.animateDraw
                          ? `${dashLength}`
                          : undefined,
                        strokeDashoffset: effectiveLayers.animateDraw
                          ? `${dashLength * (1 - drawProgress)}`
                          : "0",
                      } as CSSProperties
                    }
                    vectorEffect="non-scaling-stroke"
                  />
                )}

                {effectiveLayers.showScaffold && (
                  <g className="scaffold" style={{ opacity: effectiveLayers.scaffoldOpacity }}>
                    {handleLines.map((line) => {
                      const baseRevealAt = anchorProgress[line.anchorKey] ?? 0;
                      const revealAt =
                        line.anchorKey === loopStartAnchorKey
                          ? Math.max(
                              baseRevealAt,
                              1 - tangentDelay - tangentRevealWindow * 0.25
                            )
                          : baseRevealAt;
                      const revealPhase = effectiveLayers.animateDraw
                        ? clamp01((drawProgress - revealAt - tangentDelay) / tangentRevealWindow)
                        : 1;
                      return (
                        <line
                          key={line.id}
                          x1={line.x1}
                          y1={line.y1}
                          x2={line.x2}
                          y2={line.y2}
                          className="handle-line"
                          style={
                            effectiveLayers.animateDraw
                              ? ({
                                  strokeDasharray: "1",
                                  strokeDashoffset: `${1 - revealPhase}`,
                                  opacity: revealPhase,
                                } as CSSProperties)
                              : undefined
                          }
                          pathLength={1}
                          vectorEffect="non-scaling-stroke"
                        />
                      );
                    })}
                    {handles.map((point) => (
                      (() => {
                        const segment =
                          subpaths[point.subpathIndex]?.segments[point.segmentIndex];
                        const anchorKey =
                          segment && point.kind === "c1"
                            ? anchorKeyFor(segment.p0)
                            : segment
                              ? anchorKeyFor(segment.p3)
                              : null;
                        const baseRevealAt = anchorKey ? (anchorProgress[anchorKey] ?? 0) : 0;
                        const revealAt =
                          anchorKey === loopStartAnchorKey
                            ? Math.max(
                                baseRevealAt,
                                1 - tangentDelay - tangentRevealWindow * 0.25
                              )
                            : baseRevealAt;
                        const revealPhase = effectiveLayers.animateDraw
                          ? clamp01((drawProgress - revealAt - tangentDelay) / tangentRevealWindow)
                          : 1;
                        return (
                          <circle
                            key={point.id}
                            cx={point.x}
                            cy={point.y}
                            r={5}
                            className={`control-point handle ${selectedIds.includes(point.id) ? "is-selected" : ""}`}
                            style={{
                              opacity: revealPhase,
                              pointerEvents: revealPhase > 0.02 ? "auto" : "none",
                            }}
                            onPointerDown={(event) => handlePointerDown(event, point)}
                            onContextMenu={(event) => handlePointDelete(event, point)}
                          />
                        );
                      })()
                    ))}
                    {anchors.map((point) => (
                      (() => {
                        const anchorKey = anchorKeyFor(point);
                        const revealAt = anchorProgress[anchorKey] ?? 0;
                        const revealPhase = effectiveLayers.animateDraw
                          ? clamp01((drawProgress - revealAt) / angleRevealWindow)
                          : 1;
                        return (
                          <circle
                            key={point.id}
                            cx={point.x}
                            cy={point.y}
                            r={7}
                            className={`control-point anchor ${selectedIds.includes(point.id) ? "is-selected" : ""}`}
                            style={{
                              opacity: revealPhase,
                              pointerEvents: revealPhase > 0.02 ? "auto" : "none",
                            }}
                            onPointerDown={(event) => handlePointerDown(event, point)}
                            onContextMenu={(event) => handlePointDelete(event, point)}
                          />
                        );
                      })()
                    ))}
                  </g>
                )}

                {effectiveLayers.showScaffold &&
                  (effectiveLayers.showAngles || effectiveLayers.animateDraw) && (
                  <g className={`angles ${effectiveLayers.animateDraw ? "animate" : ""}`}>
                    {angleArcs.map((arc) => {
                      const revealAt = anchorProgress[arc.anchorKey] ?? 0;
                      const anglePhase = effectiveLayers.animateDraw
                        ? clamp01((drawProgress - revealAt) / angleRevealWindow)
                        : 1;
                      return (
                      <g key={arc.id}>
                        <circle
                          cx={arc.x}
                          cy={arc.y}
                          r={4.5}
                          className="angle-dot"
                          style={{ opacity: anglePhase } as CSSProperties}
                        />
                        <path
                          d={`M ${arc.start.x} ${arc.start.y} A 22 22 0 ${arc.largeArc} ${arc.sweep} ${arc.end.x} ${arc.end.y}`}
                          className="angle-arc"
                          pathLength={1}
                          style={
                            effectiveLayers.animateDraw
                              ? ({
                                  strokeDasharray: "1",
                                  strokeDashoffset: `${1 - anglePhase}`,
                                  opacity: anglePhase,
                                } as CSSProperties)
                              : undefined
                          }
                          vectorEffect="non-scaling-stroke"
                        />
                        <text
                          x={arc.labelPoint.x}
                          y={arc.labelPoint.y}
                          className="angle-label"
                          style={{ opacity: anglePhase } as CSSProperties}
                        >
                          {Math.round((arc.angle * 180) / Math.PI)}°
                        </text>
                      </g>
                      );
                    })}
                  </g>
                )}


                {effectiveLayers.showScaffold && effectiveLayers.showAnchorLabels && (
                  <g className="labels">
                    {anchorLabels.map((label) => (
                      <text
                        key={label.id}
                        x={label.x + 10}
                        y={label.y - 10}
                        className="anchor-label"
                      >
                        {label.name}
                      </text>
                    ))}
                  </g>
                )}
                {selectionBox && (
                  <rect
                    x={selectionBox.x}
                    y={selectionBox.y}
                    width={selectionBox.width}
                    height={selectionBox.height}
                    className="selection-rect"
                  />
                )}
              </svg>
              <div className="canvas-hud">
                <span className="hud-label">Zoom</span>
                <button
                  type="button"
                  className="hud-btn"
                  onClick={() =>
                    setCanvasZoom((value) => Math.max(0.25, Number((value - 0.1).toFixed(2))))
                  }
                >
                  -
                </button>
                <input
                  className="hud-slider"
                  type="range"
                  min={0.25}
                  max={5}
                  step={0.01}
                  value={canvasZoom}
                  onChange={(event) => setCanvasZoom(Number(event.target.value))}
                />
                <button
                  type="button"
                  className="hud-btn"
                  onClick={() =>
                    setCanvasZoom((value) => Math.min(5, Number((value + 0.1).toFixed(2))))
                  }
                >
                  +
                </button>
                <span className="hud-value">{Math.round(canvasZoom * 100)}%</span>
              </div>
              <div className="canvas-toolbar">
                <button type="button" onClick={handleUndo} disabled={!canUndo}>
                  Undo
                </button>
                <button type="button" onClick={handleRedo} disabled={!canRedo}>
                  Redo
                </button>
                <button type="button" onClick={resetCanvasView}>
                  Reset view
                </button>
                <button type="button" onClick={() => setShowShortcuts(true)}>
                  ?
                </button>
              </div>
            </div>
          </section>

          <section className="card timeline-card">
            <div className="timeline-header">
              <h2>Timeline</h2>
              <div className="timecode">
                {currentTimeLabel} / {totalTimeLabel}
              </div>
            </div>
            <div className="timeline-controls">
              <button
                type="button"
                className="player-btn"
                onClick={timelinePlaying ? handleTimelinePause : handleTimelinePlay}
              >
                {timelinePlaying ? "⏸" : "▶︎"}
              </button>
              <button type="button" className="player-btn ghost" onClick={handleTimelineReset}>
                ⟲
              </button>
            </div>
            <div className="timeline-track">
              <input
                className="timeline-slider"
                type="range"
                min={0}
                max={1}
                step={0.001}
                value={timelineProgress}
                onChange={(event) => handleTimelineChange(Number(event.target.value))}
                style={{ "--progress": `${timelineProgress * 100}%` } as CSSProperties}
              />
            </div>
          </section>

          <section className="card path-card">
            <div className="path-header">
              <h2>Path d</h2>
              <div className="path-actions">
                {pathMode === "view" ? (
                  <button type="button" onClick={startEdit}>
                    Edit
                  </button>
                ) : (
                  <>
                    <button type="button" onClick={applyEdit}>
                      Apply
                    </button>
                    <button type="button" onClick={cancelEdit}>
                      Cancel
                    </button>
                  </>
                )}
                <button type="button" onClick={onCopy}>
                  {copied ? "Copied" : "Copy path"}
                </button>
              </div>
            </div>
            <div className="path-versions">
              <label>
                Version
                <select
                  value={activeVersionId}
                  onChange={(event) => handleVersionSelect(event.target.value)}
                >
                  {pathVersions.map((version) => (
                    <option key={version.id} value={version.id}>
                      {version.name}
                    </option>
                  ))}
                </select>
              </label>
              <div className="path-save">
                <input
                  type="text"
                  placeholder="Name this version"
                  value={versionName}
                  onChange={(event) => setVersionName(event.target.value)}
                />
                <button type="button" onClick={handleVersionSave}>
                  Save new
                </button>
                <button type="button" onClick={handleVersionUpdate}>
                  Update selected
                </button>
              </div>
            </div>
            <div className={`save-status ${saveState.status}`}>
              <strong>{saveState.message}</strong>
              {saveState.detail && <span>{saveState.detail}</span>}
            </div>
            <div className="saved-versions">
              <div className="saved-versions-header">
                <strong>Saved files</strong>
                <button type="button" onClick={fetchSavedVersions}>
                  Refresh
                </button>
              </div>
              {savedVersions.length === 0 ? (
                <p className="saved-versions-empty">No saved files yet.</p>
              ) : (
                <div className="saved-versions-list">
                  {savedVersions.map((version) => (
                    <button
                      key={version.fileName}
                      type="button"
                      className="saved-version"
                      onClick={() => handleLoadSavedVersion(version)}
                    >
                      <span className="saved-version-title">{version.fileName}</span>
                      <span className="saved-version-meta">{version.relativePath}</span>
                      <span className="saved-version-meta">
                        {formatTimestamp(version.lastModified)}
                      </span>
                    </button>
                  ))}
                </div>
              )}
            </div>
            {pathError && <p className="path-error">{pathError}</p>}
            <textarea
              readOnly={pathMode === "view"}
              value={pathMode === "view" ? prettyPath : pathDraft}
              onChange={(event) => {
                setPathDraft(event.target.value);
                setPathDirty(true);
              }}
            />
          </section>
        </section>

        <aside className="panel panel-right">
          <section className="card inspector-card">
            <h2>Inspector</h2>

            <h3>Logo Source</h3>
            <label className="toggle select-row">
              <span>Reference image</span>
              <select
                value={logoChoice}
                onChange={(event) => setLogoChoice(event.target.value)}
              >
                {logoOptions.map((option) => (
                  <option key={option.id} value={option.id}>
                    {option.label}
                  </option>
                ))}
              </select>
            </label>

            <div className="divider" />
            <h3>Selection</h3>
            <label className="toggle">
              <input
                type="checkbox"
                checked={selectionMode}
                onChange={(event) => setSelectionMode(event.target.checked)}
              />
              Multi-select mode
            </label>
            <label className="toggle">
              <input
                type="checkbox"
                checked={drawMode}
                onChange={(event) => {
                  setDrawMode(event.target.checked);
                  if (!event.target.checked) {
                    setDrawStart(null);
                  }
                }}
              />
              Draw segment
            </label>

            <div className="divider" />
            <h3>Selected Anchor</h3>
            <div className="control-group">
              <label>
                Roundness <span>{roundness.toFixed(2)}</span>
              </label>
              <input
                type="range"
                min={0.1}
                max={1}
                step={0.01}
                value={roundness}
                onChange={(event) => setRoundness(Number(event.target.value))}
              />
            </div>
            <div className="actions">
              <button
                type="button"
                onClick={handleRoundAnchor}
                disabled={!getAnchorSelection()}
              >
                Round selected
              </button>
              <button
                type="button"
                onClick={handleAddPoint}
                disabled={!getAnchorSelection()}
              >
                Add point
              </button>
            </div>

            <div className="divider" />
            <h3>Logo Fit</h3>
            <div className="control-group">
              <label>
                Scale <span>{logoScale.toFixed(2)}x</span>
              </label>
              <input
                type="range"
                min={0.3}
                max={6}
                step={0.01}
                value={logoScale}
                onChange={(event) => setLogoScale(Number(event.target.value))}
              />
            </div>
            <div className="control-group">
              <label>
                Opacity <span>{Math.round(logoOpacity * 100)}%</span>
              </label>
              <input
                type="range"
                min={0}
                max={1}
                step={0.01}
                value={logoOpacity}
                onChange={(event) => setLogoOpacity(Number(event.target.value))}
              />
            </div>
            <div className="actions">
              <button type="button" onClick={resetLogoTransform}>
                Reset logo fit
              </button>
              <button type="button" onClick={onReset}>
                Reset path
              </button>
            </div>

            <div className="divider" />
            <h3>Stats</h3>
            <div className="stat">
              <span>ViewBox</span>
              <strong>{viewBox}</strong>
            </div>
            <div className="stat">
              <span>Subpaths</span>
              <strong>{subpaths.length}</strong>
            </div>
            <div className="stat">
              <span>Segments</span>
              <strong>
                {subpaths.reduce((total, subpath) => total + subpath.segments.length, 0)}
              </strong>
            </div>
            <div className="stat">
              <span>Anchors</span>
              <strong>{anchors.length}</strong>
            </div>
            <div className="stat">
              <span>Handles</span>
              <strong>{handles.length}</strong>
            </div>
          </section>
        </aside>
      </main>
      {showShortcuts && (
        <div className="shortcuts-overlay" onClick={() => setShowShortcuts(false)}>
          <div
            className="shortcuts-card"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="shortcuts-header">
              <h2>Shortcuts</h2>
              <button type="button" onClick={() => setShowShortcuts(false)}>
                Close
              </button>
            </div>
            <div className="shortcuts-grid">
              <div className="shortcut-row">
                <span className="shortcut-key">?</span>
                <span className="shortcut-desc">Toggle this panel</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">Cmd/Ctrl + Z</span>
                <span className="shortcut-desc">Undo</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">Cmd/Ctrl + Shift + Z</span>
                <span className="shortcut-desc">Redo</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">M</span>
                <span className="shortcut-desc">Toggle multi-select</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">D</span>
                <span className="shortcut-desc">Toggle draw segment</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">Delete / Backspace</span>
                <span className="shortcut-desc">Delete selected points</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">Esc</span>
                <span className="shortcut-desc">Clear selection</span>
              </div>
              <div className="shortcut-row">
                <span className="shortcut-key">Alt/Cmd/Ctrl + Scroll</span>
                <span className="shortcut-desc">Zoom at cursor</span>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
