import { useEffect, useMemo, useRef, useState } from "react";
import vectorRaw from "../Vector.svg?raw";

type Point = { x: number; y: number };
type Vec3 = { x: number; y: number; z: number };
type Segment = { p0: Point; c1: Point; c2: Point; p3: Point };
type Subpath = { segments: Segment[]; closed: boolean };
type ContourSample = { s: number; point: Point };
type PolylineData = { points: Point[]; distances: number[]; totalLength: number };
type FeelMode = "calm" | "balanced" | "energetic";
type PostMode = "spin-return-flat" | "spin-keep-shape";
type OverlayLayer = "background" | "foreground";

type FeelProfile = {
  label: string;
  description: string;
  waveDepth: number;
  waveFrequency: number;
  pinchStrength: number;
  torsion: number;
  waveComplexity: number;
  spinTurns: number;
  tilt: number;
  yaw: number;
  perspective: number;
  lineOpacity: number;
  postMode: PostMode;
};

type FeedbackEntry = {
  id: string;
  createdAt: string;
  stage: string;
  playhead: number;
  feel: FeelMode;
  planarity: number;
  tags: string[];
  note: string;
  screenshot?: string;
  logoOverlay: { enabled: boolean; layer: OverlayLayer; opacity: number };
  bezierOverlay: { enabled: boolean; layer: OverlayLayer; opacity: number };
};

const clamp01 = (value: number) => Math.max(0, Math.min(1, value));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const normalizePhase = (start: number, end: number, value: number) =>
  clamp01((value - start) / Math.max(0.0001, end - start));

const smoothstep = (edge0: number, edge1: number, value: number) => {
  const x = clamp01((value - edge0) / (edge1 - edge0));
  return x * x * (3 - 2 * x);
};

const numberPattern = /-?\d*\.?\d+(?:e[-+]?\d+)?/gi;

const parseNumbers = (value: string) => {
  const matches = value.match(numberPattern);
  return matches ? matches.map((part) => Number(part)) : [];
};

const extractPathData = (svg: string) => {
  const pathMatch = svg.match(/<path[^>]*d=["']([^"']+)["']/i);
  return pathMatch?.[1] ?? "";
};

const parsePath = (path: string): Subpath[] => {
  const subpaths: Subpath[] = [];
  let current: Subpath | null = null;
  let currentPoint: Point | null = null;
  let subpathStart: Point | null = null;

  const commandPattern = /([MCZ])([^MCZ]*)/gi;
  let match: RegExpExecArray | null;

  while ((match = commandPattern.exec(path))) {
    const command = match[1].toUpperCase();
    const raw = match[2];
    if (command === "M") {
      const numbers = parseNumbers(raw);
      if (numbers.length < 2) {
        continue;
      }
      currentPoint = { x: numbers[0], y: numbers[1] };
      subpathStart = { ...currentPoint };
      current = { segments: [], closed: false };
      subpaths.push(current);
      continue;
    }
    if (command === "C") {
      if (!current || !currentPoint) {
        continue;
      }
      const numbers = parseNumbers(raw);
      for (let index = 0; index + 5 < numbers.length; index += 6) {
        const segment: Segment = {
          p0: { ...currentPoint },
          c1: { x: numbers[index], y: numbers[index + 1] },
          c2: { x: numbers[index + 2], y: numbers[index + 3] },
          p3: { x: numbers[index + 4], y: numbers[index + 5] },
        };
        current.segments.push(segment);
        currentPoint = { ...segment.p3 };
      }
      continue;
    }
    if (command === "Z" && current) {
      current.closed = true;
      if (
        subpathStart &&
        currentPoint &&
        (Math.abs(subpathStart.x - currentPoint.x) > 0.001 ||
          Math.abs(subpathStart.y - currentPoint.y) > 0.001)
      ) {
        current.segments.push({
          p0: { ...currentPoint },
          c1: { ...currentPoint },
          c2: { ...subpathStart },
          p3: { ...subpathStart },
        });
      }
      currentPoint = subpathStart ? { ...subpathStart } : currentPoint;
    }
  }

  return subpaths.filter((subpath) => subpath.segments.length > 0);
};

const cubicPoint = (segment: Segment, t: number): Point => {
  const mt = 1 - t;
  const mt2 = mt * mt;
  const t2 = t * t;
  const a = mt2 * mt;
  const b = 3 * mt2 * t;
  const c = 3 * mt * t2;
  const d = t2 * t;
  return {
    x: a * segment.p0.x + b * segment.c1.x + c * segment.c2.x + d * segment.p3.x,
    y: a * segment.p0.y + b * segment.c1.y + c * segment.c2.y + d * segment.p3.y,
  };
};

const length = (a: Point, b: Point) => Math.hypot(b.x - a.x, b.y - a.y);

const buildPolyline = (subpath: Subpath, samplesPerSegment = 32): PolylineData => {
  const points: Point[] = [];
  subpath.segments.forEach((segment, segmentIndex) => {
    for (let step = 0; step <= samplesPerSegment; step += 1) {
      if (segmentIndex > 0 && step === 0) {
        continue;
      }
      points.push(cubicPoint(segment, step / samplesPerSegment));
    }
  });

  if (
    subpath.closed &&
    points.length > 1 &&
    length(points[points.length - 1], points[0]) > 0.001
  ) {
    points.push({ ...points[0] });
  }

  const distances: number[] = [];
  let totalLength = 0;
  points.forEach((point, index) => {
    if (index === 0) {
      distances.push(0);
      return;
    }
    totalLength += length(points[index - 1], point);
    distances.push(totalLength);
  });

  return { points, distances, totalLength };
};

const pointAtDistance = (polyline: PolylineData, distance: number, closed: boolean): Point => {
  if (polyline.points.length === 0 || polyline.totalLength <= 0) {
    return { x: 0, y: 0 };
  }
  const target = closed
    ? ((distance % polyline.totalLength) + polyline.totalLength) % polyline.totalLength
    : Math.max(0, Math.min(polyline.totalLength, distance));

  let low = 0;
  let high = polyline.distances.length - 1;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    if (polyline.distances[mid] < target) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }

  const rightIndex = Math.max(1, low);
  const leftIndex = rightIndex - 1;
  const leftDistance = polyline.distances[leftIndex];
  const rightDistance = polyline.distances[rightIndex];
  const span = Math.max(1e-6, rightDistance - leftDistance);
  const alpha = (target - leftDistance) / span;
  const left = polyline.points[leftIndex];
  const right = polyline.points[rightIndex];
  return {
    x: left.x + (right.x - left.x) * alpha,
    y: left.y + (right.y - left.y) * alpha,
  };
};

const buildContourSamples = (
  polyline: PolylineData,
  sampleCount: number,
  closed: boolean
): ContourSample[] => {
  if (polyline.totalLength <= 0 || sampleCount < 4) {
    return [];
  }
  const samples: ContourSample[] = [];
  const divisor = closed ? sampleCount : sampleCount - 1;
  for (let index = 0; index < sampleCount; index += 1) {
    const s = index / Math.max(1, divisor);
    const distance = s * polyline.totalLength;
    samples.push({
      s,
      point: pointAtDistance(polyline, distance, closed),
    });
  }
  return samples;
};

const rotateY = (point: Vec3, radians: number): Vec3 => {
  const cos = Math.cos(radians);
  const sin = Math.sin(radians);
  return {
    x: point.x * cos + point.z * sin,
    y: point.y,
    z: -point.x * sin + point.z * cos,
  };
};

const rotateX = (point: Vec3, radians: number): Vec3 => {
  const cos = Math.cos(radians);
  const sin = Math.sin(radians);
  return {
    x: point.x,
    y: point.y * cos - point.z * sin,
    z: point.y * sin + point.z * cos,
  };
};

const choosePrimarySubpath = (subpaths: Subpath[]) => {
  if (subpaths.length === 0) {
    return null;
  }
  return subpaths.reduce((best, current) => {
    const bestLength = best.segments.reduce(
      (sum, segment) => sum + length(segment.p0, segment.p3),
      0
    );
    const currentLength = current.segments.reduce(
      (sum, segment) => sum + length(segment.p0, segment.p3),
      0
    );
    return currentLength > bestLength ? current : best;
  });
};

const formatNumber = (value: number) => {
  const rounded = Math.round(value * 1000) / 1000;
  return Number.isInteger(rounded) ? `${rounded}` : `${rounded}`;
};

const subpathToPath = (subpath: Subpath | null) => {
  if (!subpath || subpath.segments.length === 0) {
    return "";
  }
  const [first] = subpath.segments;
  let d = `M ${formatNumber(first.p0.x)} ${formatNumber(first.p0.y)}`;
  subpath.segments.forEach((segment) => {
    d += ` C ${formatNumber(segment.c1.x)} ${formatNumber(segment.c1.y)} ${formatNumber(
      segment.c2.x
    )} ${formatNumber(segment.c2.y)} ${formatNumber(segment.p3.x)} ${formatNumber(
      segment.p3.y
    )}`;
  });
  if (subpath.closed) {
    d += " Z";
  }
  return d;
};

const feelProfiles: Record<FeelMode, FeelProfile> = {
  calm: {
    label: "Calm",
    description: "Gentle reveal for clarity review.",
    waveDepth: 0.24,
    waveFrequency: 1.95,
    pinchStrength: 0.42,
    torsion: 0.12,
    waveComplexity: 0.22,
    spinTurns: 0.85,
    tilt: 0.56,
    yaw: 0.12,
    perspective: 860,
    lineOpacity: 0.82,
    postMode: "spin-return-flat",
  },
  balanced: {
    label: "Balanced",
    description: "Default bowtie wave and clean spin return.",
    waveDepth: 0.5,
    waveFrequency: 2.45,
    pinchStrength: 0.62,
    torsion: 0.24,
    waveComplexity: 0.56,
    spinTurns: 1.35,
    tilt: 0.64,
    yaw: 0.18,
    perspective: 930,
    lineOpacity: 0.9,
    postMode: "spin-return-flat",
  },
  energetic: {
    label: "Energetic",
    description: "High-energy spinner behavior for reactive moments.",
    waveDepth: 0.66,
    waveFrequency: 2.92,
    pinchStrength: 0.74,
    torsion: 0.34,
    waveComplexity: 0.72,
    spinTurns: 2.6,
    tilt: 0.72,
    yaw: 0.22,
    perspective: 990,
    lineOpacity: 0.95,
    postMode: "spin-keep-shape",
  },
};

const feedbackTagOptions = [
  "Feels Right",
  "Too Flat",
  "Too Busy",
  "Logo Not Clear",
  "Great Spinner",
  "Need Slower",
];

const choreographyDuration = 9.2;

export default function ThreeDMode() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const playheadRef = useRef(0);

  const [feel, setFeel] = useState<FeelMode>("balanced");
  const [playhead, setPlayhead] = useState(0);
  const [autoPlay, setAutoPlay] = useState(true);
  const [loopPlayback, setLoopPlayback] = useState(true);
  const [playbackSpeed, setPlaybackSpeed] = useState(1);
  const [planarity, setPlanarity] = useState(0.8);
  const [showLogoOverlay, setShowLogoOverlay] = useState(false);
  const [logoOverlayLayer, setLogoOverlayLayer] = useState<OverlayLayer>("background");
  const [logoOverlayOpacity, setLogoOverlayOpacity] = useState(0.26);
  const [showBezierOverlay, setShowBezierOverlay] = useState(false);
  const [bezierOverlayLayer, setBezierOverlayLayer] = useState<OverlayLayer>("foreground");
  const [bezierOverlayOpacity, setBezierOverlayOpacity] = useState(0.62);

  const [selectedTags, setSelectedTags] = useState<string[]>([]);
  const [note, setNote] = useState("");
  const [snapshot, setSnapshot] = useState<string | null>(null);
  const [entries, setEntries] = useState<FeedbackEntry[]>([]);
  const [copyState, setCopyState] = useState<"idle" | "copied" | "error">("idle");

  const contour = useMemo(() => {
    const path = extractPathData(vectorRaw);
    const subpaths = parsePath(path);
    const primary = choosePrimarySubpath(subpaths);
    if (!primary) {
      return {
        samples: [] as ContourSample[],
        closed: true,
        segments: [] as Segment[],
        pathData: "",
      };
    }
    const polyline = buildPolyline(primary, 40);
    return {
      samples: buildContourSamples(polyline, 220, primary.closed),
      closed: primary.closed,
      segments: primary.segments,
      pathData: subpathToPath(primary),
    };
  }, []);

  const contourPath2D = useMemo(
    () => (contour.pathData ? new Path2D(contour.pathData) : null),
    [contour.pathData]
  );

  const bounds = useMemo(() => {
    if (contour.samples.length === 0) {
      return {
        minX: 0,
        minY: 0,
        maxX: 1,
        maxY: 1,
        width: 1,
        height: 1,
        centerX: 0.5,
        centerY: 0.5,
      };
    }
    const xs = contour.samples.map((sample) => sample.point.x);
    const ys = contour.samples.map((sample) => sample.point.y);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    return {
      minX,
      minY,
      maxX,
      maxY,
      width: Math.max(1, maxX - minX),
      height: Math.max(1, maxY - minY),
      centerX: (minX + maxX) / 2,
      centerY: (minY + maxY) / 2,
    };
  }, [contour.samples]);

  const profile = feelProfiles[feel];

  useEffect(() => {
    playheadRef.current = playhead;
  }, [playhead]);

  useEffect(() => {
    if (!autoPlay) {
      return;
    }
    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const deltaSeconds = (now - last) / 1000;
      last = now;
      let next = playheadRef.current + (deltaSeconds * playbackSpeed) / choreographyDuration;
      if (next >= 1) {
        if (loopPlayback) {
          next %= 1;
        } else {
          next = 1;
          setAutoPlay(false);
        }
      }
      playheadRef.current = next;
      setPlayhead(next);
      raf = requestAnimationFrame(tick);
    };

    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [autoPlay, loopPlayback, playbackSpeed]);

  const sequenceProgress = useMemo(() => {
    const t = clamp01(playhead);
    const logoLockPhase = smoothstep(0, 1, normalizePhase(0.25, 0.4, t));
    const modulationPhase = smoothstep(0, 1, normalizePhase(0.4, 0.6, t));
    const spinRampPhase = smoothstep(0, 1, normalizePhase(0.6, 0.7, t));
    const spinRunPhase = smoothstep(0, 1, normalizePhase(0.7, 0.9, t));
    const flattenPhase = smoothstep(0, 1, normalizePhase(0.9, 1.0, t));

    let sequence = lerp(0, 0.74, logoLockPhase);
    sequence = lerp(sequence, 1.08, modulationPhase);
    sequence = lerp(sequence, 1.35, spinRampPhase);
    sequence = lerp(sequence, 1.74, spinRunPhase);
    sequence = lerp(sequence, 2, flattenPhase);
    return sequence;
  }, [playhead]);

  const stageLabel = useMemo(() => {
    if (playhead < 0.25) {
      return "Distorted Flat Plane";
    }
    if (playhead < 0.4) {
      return "Logo Lock-In";
    }
    if (playhead < 0.6) {
      return "Audio Modulation";
    }
    if (playhead < 0.9) {
      return "Horizontal Infinity Spin";
    }
    return "Flattening";
  }, [playhead]);

  const effectiveWaveDepth = useMemo(() => {
    const modulationWindow =
      smoothstep(0.4, 0.45, playhead) * (1 - smoothstep(0.6, 0.68, playhead));
    const modulationT = normalizePhase(0.4, 0.6, playhead);
    const impact1 = Math.exp(-Math.pow((modulationT - 0.16) / 0.1, 2));
    const impact2 = Math.exp(-Math.pow((modulationT - 0.48) / 0.11, 2)) * 0.82;
    const impact3 = Math.exp(-Math.pow((modulationT - 0.76) / 0.12, 2)) * 0.64;
    const beatEnvelope = (impact1 + impact2 + impact3) / 2.46;
    const spinResidual = smoothstep(0.6, 0.75, playhead) * (1 - smoothstep(0.88, 1.0, playhead));
    const flattenPhase = smoothstep(0.9, 1.0, playhead);
    const envelope =
      modulationWindow * (0.22 + beatEnvelope * 0.9) + spinResidual * (0.1 + (1 - planarity) * 0.12);
    return profile.waveDepth * Math.max(0, envelope) * (1 - flattenPhase * 0.95);
  }, [planarity, playhead, profile.waveDepth]);

  const loopTurns = useMemo(
    () => Math.max(1, Math.round(profile.spinTurns + 0.35)),
    [profile.spinTurns]
  );

  const effectiveTilt = useMemo(() => {
    const motionWindow =
      smoothstep(0.38, 0.86, playhead) * (1 - smoothstep(0.9, 1.0, playhead));
    return (
      profile.tilt +
      motionWindow * (0.03 + (1 - planarity) * 0.03) +
      Math.sin(playhead * Math.PI * 2) * 0.04 * motionWindow
    );
  }, [planarity, playhead, profile.tilt]);

  const effectiveYaw = useMemo(() => {
    const yawWindow =
      smoothstep(0.2, 0.6, playhead) * (1 - smoothstep(0.78, 0.95, playhead));
    return (
      profile.yaw * (0.3 + yawWindow * 0.7) +
      Math.sin(playhead * Math.PI * 2.2) * 0.03 * yawWindow * (1 - planarity * 0.5)
    );
  }, [planarity, playhead, profile.yaw]);

  const toggleTag = (tag: string) => {
    setSelectedTags((prev) =>
      prev.includes(tag) ? prev.filter((item) => item !== tag) : [...prev, tag]
    );
  };

  const handleCapture = () => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }
    setSnapshot(canvas.toDataURL("image/png"));
  };

  const handleDownloadSnapshot = () => {
    if (!snapshot) {
      return;
    }
    const anchor = document.createElement("a");
    anchor.href = snapshot;
    anchor.download = `talkie-logo-frame-${Date.now()}.png`;
    anchor.click();
  };

  const handleSaveFeedback = () => {
    const trimmedNote = note.trim();
    if (trimmedNote.length === 0 && selectedTags.length === 0 && !snapshot) {
      return;
    }

    const entry: FeedbackEntry = {
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      createdAt: new Date().toISOString(),
      stage: stageLabel,
      playhead,
      feel,
      planarity: Number(planarity.toFixed(2)),
      tags: selectedTags,
      note: trimmedNote,
      screenshot: snapshot ?? undefined,
      logoOverlay: {
        enabled: showLogoOverlay,
        layer: logoOverlayLayer,
        opacity: Number(logoOverlayOpacity.toFixed(2)),
      },
      bezierOverlay: {
        enabled: showBezierOverlay,
        layer: bezierOverlayLayer,
        opacity: Number(bezierOverlayOpacity.toFixed(2)),
      },
    };

    setEntries((prev) => [entry, ...prev]);
    setSelectedTags([]);
    setNote("");
  };

  const copyLatestFeedback = async () => {
    const latest = entries[0];
    if (!latest || !navigator.clipboard) {
      setCopyState("error");
      return;
    }

    const payload = {
      createdAt: latest.createdAt,
      stage: latest.stage,
      playhead: Number(latest.playhead.toFixed(3)),
      feel: latest.feel,
      planarity: latest.planarity,
      tags: latest.tags,
      note: latest.note,
      hasScreenshot: Boolean(latest.screenshot),
      logoOverlay: latest.logoOverlay,
      bezierOverlay: latest.bezierOverlay,
    };

    try {
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      setCopyState("copied");
      window.setTimeout(() => setCopyState("idle"), 1200);
    } catch {
      setCopyState("error");
      window.setTimeout(() => setCopyState("idle"), 1200);
    }
  };

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }

    const draw = () => {
      const cssWidth = Math.max(1, canvas.clientWidth);
      const cssHeight = Math.max(1, canvas.clientHeight);
      const pixelRatio = window.devicePixelRatio || 1;
      const targetWidth = Math.round(cssWidth * pixelRatio);
      const targetHeight = Math.round(cssHeight * pixelRatio);
      if (canvas.width !== targetWidth || canvas.height !== targetHeight) {
        canvas.width = targetWidth;
        canvas.height = targetHeight;
      }
      ctx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);

      const bg = ctx.createLinearGradient(0, 0, 0, cssHeight);
      bg.addColorStop(0, "rgba(5, 7, 16, 1)");
      bg.addColorStop(1, "rgba(2, 3, 10, 1)");
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, cssWidth, cssHeight);

      if (contour.samples.length < 4) {
        ctx.fillStyle = "rgba(255,255,255,0.7)";
        ctx.font = "600 14px Space Grotesk, sans-serif";
        ctx.fillText("No path data found.", 24, 32);
        return;
      }

      const centerX = cssWidth * 0.5;
      const centerY = cssHeight * 0.53;
      const minSide = Math.min(cssWidth, cssHeight);
      const fitScale = Math.min((cssWidth * 0.7) / bounds.width, (cssHeight * 0.68) / bounds.height);
      const overlayTranslateX = centerX - bounds.centerX * fitScale;
      const overlayTranslateY = centerY - bounds.centerY * fitScale;
      const logoLockPhase = smoothstep(0.25, 0.4, playhead);
      const loopReturnPhase = smoothstep(0.9, 1.0, playhead);
      const planeDistortionPhase = clamp01(
        (1 - logoLockPhase) * (1 - loopReturnPhase) + loopReturnPhase
      );
      const modulationWindow =
        smoothstep(0.4, 0.45, playhead) * (1 - smoothstep(0.6, 0.68, playhead));
      const modulationT = normalizePhase(0.4, 0.6, playhead);
      const impact1 = Math.exp(-Math.pow((modulationT - 0.16) / 0.1, 2));
      const impact2 = Math.exp(-Math.pow((modulationT - 0.48) / 0.11, 2)) * 0.82;
      const impact3 = Math.exp(-Math.pow((modulationT - 0.76) / 0.12, 2)) * 0.64;
      const beatEnvelope = (impact1 + impact2 + impact3) / 2.46;
      const beatOsc = Math.sin(modulationT * Math.PI * 2 * 3.0);
      const spinRampPhase = smoothstep(0.6, 0.7, playhead);
      const spinRunPhase = smoothstep(0.7, 0.82, playhead);
      const spinBurstPhase = smoothstep(0.82, 0.9, playhead);
      const spinWindow = spinRampPhase * 0.2 + spinRunPhase * 0.78 + spinBurstPhase * 0.96;
      const spinPlanar = smoothstep(0.68, 0.9, playhead);
      const lateSpinSettle = 1 - smoothstep(0.86, 0.96, playhead);
      const flattenPhase = smoothstep(0.9, 1.0, playhead);
      const returnFlatBlend = flattenPhase;
      const logoBlend = logoLockPhase * (1 - returnFlatBlend);
      const rippleBlend = (modulationWindow + spinWindow * 0.14) * (1 - returnFlatBlend);
      const waveAmplitude =
        minSide *
        0.24 *
        effectiveWaveDepth *
        rippleBlend *
        (0.35 + beatEnvelope * 0.65) *
        (1 + modulationWindow * 0.18 * beatOsc) *
        (1 - spinPlanar * (0.78 + planarity * 0.18));
      const baseRadiusX = bounds.width * fitScale * 0.46;
      const baseRadiusY = bounds.height * fitScale * 0.46;
      const spinProgress = smoothstep(0.6, 0.9, playhead);
      const acceleratedSpin = clamp01(
        Math.pow(spinProgress, 1.75 - planarity * 0.35) + smoothstep(0.79, 0.88, playhead) * 0.05
      );
      const spinAngle = acceleratedSpin * Math.PI * 2 * loopTurns;
      const yawDuringSpin = effectiveYaw * (1 - spinWindow * 0.95);
      const posedYaw = yawDuringSpin;
      const spinSmoothing = clamp01(1 - spinWindow * (0.8 + planarity * 0.08));

      const drawLogoOverlayLayer = () => {
        if (!showLogoOverlay || !contourPath2D) {
          return;
        }
        ctx.save();
        ctx.translate(overlayTranslateX, overlayTranslateY);
        ctx.scale(fitScale, fitScale);
        ctx.globalAlpha = logoOverlayOpacity;
        ctx.fillStyle = "rgba(255,255,255,0.18)";
        ctx.strokeStyle = "rgba(255,255,255,0.68)";
        ctx.lineWidth = 1.4 / fitScale;
        ctx.fill(contourPath2D, "evenodd");
        ctx.stroke(contourPath2D);
        ctx.restore();
      };

      const drawBezierOverlayLayer = () => {
        if (!showBezierOverlay || contour.segments.length === 0 || !contourPath2D) {
          return;
        }
        ctx.save();
        ctx.translate(overlayTranslateX, overlayTranslateY);
        ctx.scale(fitScale, fitScale);
        ctx.globalAlpha = bezierOverlayOpacity;
        ctx.strokeStyle = "rgba(136, 203, 255, 0.95)";
        ctx.lineWidth = 1.25 / fitScale;
        ctx.setLineDash([4 / fitScale, 4 / fitScale]);
        ctx.stroke(contourPath2D);
        ctx.setLineDash([]);

        ctx.strokeStyle = "rgba(136, 203, 255, 0.45)";
        ctx.lineWidth = 1 / fitScale;
        contour.segments.forEach((segment) => {
          if (length(segment.p0, segment.c1) > 0.001) {
            ctx.beginPath();
            ctx.moveTo(segment.p0.x, segment.p0.y);
            ctx.lineTo(segment.c1.x, segment.c1.y);
            ctx.stroke();
          }
          if (length(segment.p3, segment.c2) > 0.001) {
            ctx.beginPath();
            ctx.moveTo(segment.p3.x, segment.p3.y);
            ctx.lineTo(segment.c2.x, segment.c2.y);
            ctx.stroke();
          }
        });

        const radius = 3.2 / fitScale;
        const anchorMap = new Map<string, Point>();
        contour.segments.forEach((segment) => {
          anchorMap.set(`${segment.p0.x.toFixed(3)}:${segment.p0.y.toFixed(3)}`, segment.p0);
          anchorMap.set(`${segment.p3.x.toFixed(3)}:${segment.p3.y.toFixed(3)}`, segment.p3);
        });
        ctx.fillStyle = "rgba(136, 203, 255, 0.9)";
        anchorMap.forEach((point) => {
          ctx.beginPath();
          ctx.arc(point.x, point.y, radius, 0, Math.PI * 2);
          ctx.fill();
        });
        ctx.restore();
      };

      if (logoOverlayLayer === "background") {
        drawLogoOverlayLayer();
      }
      if (bezierOverlayLayer === "background") {
        drawBezierOverlayLayer();
      }

      const rows = 26;
      const columns = contour.samples.length;
      const points: Array<Array<{ x: number; y: number; z: number }>> = [];

      for (let row = 0; row <= rows; row += 1) {
        const rowPoints: Array<{ x: number; y: number; z: number }> = [];
        const t = row / rows;
        const radial = Math.pow(t, 0.9);
        const rowEnvelope = Math.pow(1 - Math.abs(radial * 2 - 1), 1.2);

        for (let column = 0; column < columns; column += 1) {
          const sample = contour.samples[column];
          const angle = sample.s * Math.PI * 2;
          const planeX = Math.cos(angle) * baseRadiusX;
          const planeY = Math.sin(angle) * baseRadiusY;
          const planeDistortX =
            Math.sin(angle * 2.2 + radial * 3.2) *
            baseRadiusX *
            planeDistortionPhase *
            rowEnvelope *
            0.11;
          const planeDistortY =
            Math.cos(angle * 1.7 - radial * 2.6) *
            baseRadiusY *
            planeDistortionPhase *
            rowEnvelope *
            0.09;
          const distortedPlaneX = planeX + planeDistortX;
          const distortedPlaneY = planeY + planeDistortY;
          const logoX = (sample.point.x - bounds.centerX) * fitScale;
          const logoY = (sample.point.y - bounds.centerY) * fitScale;
          const shapeX = distortedPlaneX * (1 - logoBlend) + logoX * logoBlend;
          const shapeY = distortedPlaneY * (1 - logoBlend) + logoY * logoBlend;
          const flatX = shapeX * radial;
          const flatY = shapeY * radial;
          const bowtiePinch =
            1 - profile.pinchStrength * rowEnvelope * Math.cos(angle * 2) * rippleBlend;
          const warpedX = flatX * bowtiePinch;
          const warpedY = flatY * (2 - bowtiePinch);
          const twistDamping = Math.max(0.1, 1 - spinWindow * (0.8 + planarity * 0.16));
          const twist =
            profile.torsion *
            twistDamping *
            (radial - 0.5) *
            (0.8 + rowEnvelope * 0.2) *
            rippleBlend;
          const cosTwist = Math.cos(twist);
          const sinTwist = Math.sin(twist);
          const twistedX = warpedX * cosTwist - warpedY * sinTwist;
          const twistedY = warpedX * sinTwist + warpedY * cosTwist;

          const phase = sample.s * Math.PI * 2 * profile.waveFrequency;
          const baseWave = Math.sin(phase);
          const sideWave =
            Math.sin(phase * (0.61 + profile.waveComplexity * 0.08) + radial * 2.5) *
            (0.14 + profile.waveComplexity * 0.09) *
            spinSmoothing;
          const detailWave =
            Math.sin((angle * 2 - radial * 4.4) * (1 + profile.waveComplexity * 0.18)) *
            0.05 *
            profile.waveComplexity *
            spinSmoothing *
            (1 - spinPlanar) *
            (1 - planarity * 0.7) *
            lateSpinSettle;
          const beatNudge = modulationWindow * 0.12 * beatOsc;
          const interference = baseWave + sideWave + detailWave + beatNudge;
          const z = waveAmplitude * rowEnvelope * interference * (1 - spinPlanar * (0.6 + planarity * 0.2));

          const cadenceBase = 0.92 + rowEnvelope * 0.12;
          const cadenceNoise =
            Math.sin(angle * 2 + playhead * Math.PI * 2.8) *
            0.035 *
            (1 - spinPlanar * 0.7) *
            (1 - planarity * 0.7);
          const cadenceField = 1 + (cadenceBase + cadenceNoise - 1) * lateSpinSettle;
          const localSpinAngle = spinAngle * cadenceField;
          const spun = rotateX({ x: twistedX, y: twistedY, z }, localSpinAngle);
          const precession =
            spinWindow *
            0.01 *
            Math.sin(angle + playhead * Math.PI * 2.0) *
            rowEnvelope *
            (1 - planarity * 0.8) *
            lateSpinSettle;
          const revolved = rotateY(spun, precession);
          const posed = rotateX(rotateY(revolved, posedYaw), effectiveTilt);
          const depth = profile.perspective / Math.max(180, profile.perspective - posed.z + 220);
          rowPoints.push({
            x: centerX + posed.x * depth,
            y: centerY + posed.y * depth,
            z: posed.z,
          });
        }

        points.push(rowPoints);
      }

      const depthWindow = Math.max(1, waveAmplitude * 1.7);
      const drawSegment = (
        a: { x: number; y: number; z: number },
        b: { x: number; y: number; z: number },
        width: number
      ) => {
        const meanDepth = (a.z + b.z) * 0.5;
        const depthFactor = clamp01((meanDepth + depthWindow) / (depthWindow * 2));
        const alpha = (0.22 + depthFactor * 0.78) * profile.lineOpacity;
        const cool = Math.round(lerp(120, 242, depthFactor));
        ctx.strokeStyle = `rgba(${cool},${Math.round(cool * 0.98)},255,${alpha.toFixed(3)})`;
        ctx.lineWidth = width;
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      };

      for (let row = 0; row <= rows; row += 1) {
        for (let column = 0; column < columns; column += 1) {
          const current = points[row][column];
          const nextColumn = column + 1;
          if (nextColumn < columns) {
            drawSegment(current, points[row][nextColumn], row === rows ? 1.3 : 0.95);
          } else if (contour.closed) {
            drawSegment(current, points[row][0], row === rows ? 1.3 : 0.95);
          }
          if (row < rows) {
            drawSegment(current, points[row + 1][column], 0.85);
          }
        }
      }

      if (logoOverlayLayer === "foreground") {
        drawLogoOverlayLayer();
      }
      if (bezierOverlayLayer === "foreground") {
        drawBezierOverlayLayer();
      }
    };

    draw();
    const resizeObserver = new ResizeObserver(() => draw());
    resizeObserver.observe(canvas);
    window.addEventListener("resize", draw);

    return () => {
      resizeObserver.disconnect();
      window.removeEventListener("resize", draw);
    };
  }, [
    bounds.centerX,
    bounds.centerY,
    bounds.height,
    bounds.width,
    contour.closed,
    contour.segments,
    contour.samples,
    contourPath2D,
    bezierOverlayLayer,
    bezierOverlayOpacity,
    effectiveTilt,
    effectiveWaveDepth,
    effectiveYaw,
    loopTurns,
    logoOverlayLayer,
    logoOverlayOpacity,
    planarity,
    profile.lineOpacity,
    profile.perspective,
    profile.pinchStrength,
    profile.postMode,
    profile.torsion,
    profile.waveComplexity,
    profile.waveFrequency,
    sequenceProgress,
    showBezierOverlay,
    showLogoOverlay,
  ]);

  return (
    <div className="mode3d-page">
      <header className="mode3d-header">
        <span className="eyebrow">Talkie Design Lab</span>
        <h1>3D Review Tool</h1>
        <p>Play, pause, capture a frame, and leave quick feedback. No parameter micromanagement.</p>
      </header>

      <main className="mode3d-layout">
        <section className="card mode3d-stage">
          <canvas ref={canvasRef} className="mode3d-canvas" />
          <div className="mode3d-stage-footer">
            <span>Arc</span>
            <input
              type="range"
              min={0}
              max={1}
              step={0.001}
              value={playhead}
              onChange={(event) => {
                const next = Number(event.target.value);
                setPlayhead(next);
                playheadRef.current = next;
                setAutoPlay(false);
              }}
            />
            <span>{Math.round(playhead * 100)}%</span>
          </div>
        </section>

        <aside className="panel">
          <section className="card mode3d-controls">
            <h2>Playback</h2>
            <p>
              Stage: <strong>{stageLabel}</strong>
            </p>
            <div className="actions">
              <button type="button" onClick={() => setAutoPlay((prev) => !prev)}>
                {autoPlay ? "Pause" : "Play"}
              </button>
              <button
                type="button"
                onClick={() => {
                  setPlayhead(0);
                  playheadRef.current = 0;
                  setAutoPlay(false);
                }}
              >
                Restart
              </button>
              <button type="button" onClick={() => setLoopPlayback((prev) => !prev)}>
                Loop: {loopPlayback ? "On" : "Off"}
              </button>
            </div>
            <div className="control-group">
              <label>
                Speed <span>{playbackSpeed.toFixed(2)}x</span>
              </label>
              <input
                type="range"
                min={0.35}
                max={2}
                step={0.01}
                value={playbackSpeed}
                onChange={(event) => setPlaybackSpeed(Number(event.target.value))}
              />
            </div>

            <div className="divider" />
            <h2>Feel</h2>
            <p>{profile.description}</p>
            <div className="actions">
              {(Object.keys(feelProfiles) as FeelMode[]).map((mode) => (
                <button
                  key={mode}
                  type="button"
                  onClick={() => setFeel(mode)}
                  disabled={feel === mode}
                >
                  {feelProfiles[mode].label}
                </button>
              ))}
            </div>
            <div className="control-group">
              <label>
                Planarity <span>{Math.round(planarity * 100)}%</span>
              </label>
              <input
                type="range"
                min={0}
                max={1}
                step={0.01}
                value={planarity}
                onChange={(event) => setPlanarity(Number(event.target.value))}
              />
            </div>

            <div className="divider" />
            <h2>Compare Layers</h2>
            <label className="toggle">
              <input
                type="checkbox"
                checked={showLogoOverlay}
                onChange={(event) => setShowLogoOverlay(event.target.checked)}
              />
              Show logo overlay
            </label>
            {showLogoOverlay && (
              <>
                <div className="actions">
                  <button
                    type="button"
                    onClick={() => setLogoOverlayLayer("background")}
                    disabled={logoOverlayLayer === "background"}
                  >
                    Logo behind
                  </button>
                  <button
                    type="button"
                    onClick={() => setLogoOverlayLayer("foreground")}
                    disabled={logoOverlayLayer === "foreground"}
                  >
                    Logo front
                  </button>
                </div>
                <div className="control-group">
                  <label>
                    Logo opacity <span>{Math.round(logoOverlayOpacity * 100)}%</span>
                  </label>
                  <input
                    type="range"
                    min={0.05}
                    max={0.95}
                    step={0.01}
                    value={logoOverlayOpacity}
                    onChange={(event) => setLogoOverlayOpacity(Number(event.target.value))}
                  />
                </div>
              </>
            )}

            <label className="toggle">
              <input
                type="checkbox"
                checked={showBezierOverlay}
                onChange={(event) => setShowBezierOverlay(event.target.checked)}
              />
              Show 2D bezier guide
            </label>
            {showBezierOverlay && (
              <>
                <div className="actions">
                  <button
                    type="button"
                    onClick={() => setBezierOverlayLayer("background")}
                    disabled={bezierOverlayLayer === "background"}
                  >
                    Guide behind
                  </button>
                  <button
                    type="button"
                    onClick={() => setBezierOverlayLayer("foreground")}
                    disabled={bezierOverlayLayer === "foreground"}
                  >
                    Guide front
                  </button>
                </div>
                <div className="control-group">
                  <label>
                    Guide opacity <span>{Math.round(bezierOverlayOpacity * 100)}%</span>
                  </label>
                  <input
                    type="range"
                    min={0.05}
                    max={0.95}
                    step={0.01}
                    value={bezierOverlayOpacity}
                    onChange={(event) => setBezierOverlayOpacity(Number(event.target.value))}
                  />
                </div>
              </>
            )}

            <div className="divider" />
            <h2>Feedback</h2>
            <div className="tag-grid">
              {feedbackTagOptions.map((tag) => (
                <button
                  key={tag}
                  type="button"
                  className={selectedTags.includes(tag) ? "tag-button is-selected" : "tag-button"}
                  onClick={() => toggleTag(tag)}
                >
                  {tag}
                </button>
              ))}
            </div>
            <textarea
              className="feedback-note"
              placeholder="What do you want changed?"
              value={note}
              onChange={(event) => setNote(event.target.value)}
            />
            <div className="actions">
              <button type="button" onClick={handleCapture}>
                Capture Frame
              </button>
              <button type="button" onClick={handleSaveFeedback}>
                Save Feedback
              </button>
              <button type="button" onClick={copyLatestFeedback} disabled={entries.length === 0}>
                {copyState === "copied"
                  ? "Copied"
                  : copyState === "error"
                    ? "Copy Failed"
                    : "Copy Latest"}
              </button>
            </div>

            {snapshot && (
              <div className="snapshot-card">
                <div className="snapshot-header">
                  <strong>Captured frame</strong>
                  <button type="button" onClick={handleDownloadSnapshot}>
                    Download PNG
                  </button>
                </div>
                <img src={snapshot} alt="Captured logo frame" className="snapshot-preview" />
              </div>
            )}

            <div className="divider" />
            <h2>Recent Notes</h2>
            <div className="feedback-list">
              {entries.length === 0 ? (
                <p className="feedback-empty">No feedback saved yet.</p>
              ) : (
                entries.slice(0, 5).map((entry) => (
                  <article key={entry.id} className="feedback-item">
                    <div className="feedback-meta">
                      <strong>{new Date(entry.createdAt).toLocaleString()}</strong>
                      <span>
                        {entry.stage} · {Math.round(entry.playhead * 100)}% · {feelProfiles[entry.feel].label} · planarity {Math.round(entry.planarity * 100)}%
                      </span>
                    </div>
                    {entry.tags.length > 0 && <p className="feedback-tags">{entry.tags.join(" · ")}</p>}
                    {entry.note && <p className="feedback-text">{entry.note}</p>}
                    {entry.screenshot && <img src={entry.screenshot} alt="Saved frame" className="feedback-thumb" />}
                  </article>
                ))
              )}
            </div>
          </section>
        </aside>
      </main>
    </div>
  );
}
