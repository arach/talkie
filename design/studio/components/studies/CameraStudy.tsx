"use client";

/**
 * Camera capture — full-screen preview + Done/Settings complications
 * + bottom shutter FAB. The preview is mocked as a grayscale gradient
 * with cropping marks; the actual surface uses AVCaptureVideoPreviewLayer
 * via UIViewRepresentable on iOS.
 *
 * Mirrors the iOS CameraCaptureNext.
 */

export type CameraVariant = "preview" | "captured" | "denied";

export const CAMERA_VARIANTS: { key: CameraVariant; label: string }[] = [
  { key: "preview", label: "Preview" },
  { key: "captured", label: "Captured" },
  { key: "denied", label: "Denied" },
];

export function CameraStudy({ variant }: { variant: CameraVariant }) {
  return (
    <div
      className="relative flex h-full flex-col"
      style={{ background: "#0a0a0a" }}
    >
      {variant === "denied" ? (
        <DeniedState />
      ) : (
        <>
          <PreviewSurface captured={variant === "captured"} />
          <Chrome captured={variant === "captured"} />
        </>
      )}
    </div>
  );
}

function PreviewSurface({ captured }: { captured: boolean }) {
  // Grayscale gradient stand-in for camera preview.
  return (
    <div
      className="absolute inset-0"
      style={{
        background:
          "radial-gradient(circle at 30% 25%, #3a3a3a 0%, #1c1c1c 55%, #0a0a0a 100%)",
      }}
    >
      {/* Cropping marks */}
      <div className="absolute inset-0">
        <CornerMark className="left-6 top-20" rotation={0} />
        <CornerMark className="right-6 top-20" rotation={90} />
        <CornerMark className="bottom-32 left-6" rotation={270} />
        <CornerMark className="bottom-32 right-6" rotation={180} />
      </div>

      {captured && (
        <div className="absolute inset-0 flex items-center justify-center bg-black/40">
          <div
            className="rounded-md px-3 py-2 text-[10px] font-medium uppercase"
            style={{
              background: "rgba(255,255,255,0.85)",
              color: "#0a0a0a",
              fontFamily: "var(--theme-font-mono)",
              letterSpacing: "0.22em",
            }}
          >
            OCR · 142 chars
          </div>
        </div>
      )}
    </div>
  );
}

function CornerMark({
  className,
  rotation,
}: {
  className?: string;
  rotation: number;
}) {
  return (
    <div
      className={`absolute h-6 w-6 ${className ?? ""}`}
      style={{ transform: `rotate(${rotation}deg)` }}
    >
      <div
        className="absolute left-0 top-0 h-2 w-px"
        style={{ background: "rgba(255,255,255,0.6)" }}
      />
      <div
        className="absolute left-0 top-0 h-px w-2"
        style={{ background: "rgba(255,255,255,0.6)" }}
      />
    </div>
  );
}

function Chrome({ captured }: { captured: boolean }) {
  return (
    <>
      <CornerSlot alignment="topLeading" kind="done" label="Done" />
      <CornerSlot alignment="topTrailing" kind="settings" label="Settings" />

      {/* Status pill */}
      <div className="absolute bottom-32 left-0 right-0 flex justify-center">
        <span
          className="rounded-full px-3 py-1.5 text-[11px]"
          style={{
            background: "rgba(255,255,255,0.78)",
            color: "#0a0a0a",
            fontFamily: "var(--theme-font-mono)",
          }}
        >
          {captured ? "Saved to Captures" : "Hold steady · auto-OCR"}
        </span>
      </div>

      {/* Bottom controls */}
      <div className="absolute bottom-6 left-0 right-0 flex items-center justify-center gap-6">
        <CircleControl />
        <Shutter />
        <span className="h-11 w-11" aria-hidden />
      </div>
    </>
  );
}

function CornerSlot({
  alignment,
  kind,
  label,
}: {
  alignment: "topLeading" | "topTrailing";
  kind: "done" | "settings";
  label: string;
}) {
  const positionStyle =
    alignment === "topLeading"
      ? { top: 14, left: 18 }
      : { top: 14, right: 18 };
  return (
    <button
      aria-label={label}
      className="absolute flex h-10 w-10 items-center justify-center rounded-full"
      style={{
        background: "rgba(255,255,255,0.78)",
        color: "#0a0a0a",
        ...positionStyle,
      }}
    >
      {kind === "done" ? (
        <svg viewBox="0 0 16 16" className="h-4 w-4" fill="none">
          <path
            d="M 10 3 L 5 8 L 10 13"
            stroke="currentColor"
            strokeWidth={1.5}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      ) : (
        <svg viewBox="0 0 16 16" className="h-4 w-4" fill="none">
          <circle cx={8} cy={8} r={2} stroke="currentColor" strokeWidth={1.2} />
          <path
            d="M 8 1.5 L 8 3.5 M 8 12.5 L 8 14.5 M 1.5 8 L 3.5 8 M 12.5 8 L 14.5 8 M 3.05 3.05 L 4.4 4.4 M 11.6 11.6 L 12.95 12.95 M 3.05 12.95 L 4.4 11.6 M 11.6 4.4 L 12.95 3.05"
            stroke="currentColor"
            strokeWidth={1.2}
            strokeLinecap="round"
          />
        </svg>
      )}
    </button>
  );
}

function CircleControl() {
  return (
    <button
      aria-label="Switch camera"
      className="flex h-11 w-11 items-center justify-center rounded-full"
      style={{
        background: "rgba(255,255,255,0.20)",
        color: "rgba(255,255,255,0.85)",
      }}
    >
      <svg viewBox="0 0 16 16" className="h-4 w-4" fill="none">
        <path
          d="M 4 8 a 4 4 0 1 1 1.2 2.85 M 4 11 L 4 8 L 7 8"
          stroke="currentColor"
          strokeWidth={1.2}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  );
}

function Shutter() {
  return (
    <button
      className="flex h-[72px] w-[72px] items-center justify-center rounded-full"
      style={{
        background: "var(--theme-amber)",
        color: "var(--theme-paper)",
        boxShadow: "0 0 18px 4px var(--theme-amber-faint, rgba(255,200,0,0.18))",
      }}
    >
      <svg viewBox="0 0 24 24" className="h-7 w-7" fill="currentColor">
        <circle cx={12} cy={12} r={6} />
      </svg>
    </button>
  );
}

function DeniedState() {
  return (
    <div className="flex h-full flex-col items-center justify-center gap-4 px-6 text-center">
      <svg viewBox="0 0 24 24" className="h-9 w-9" fill="none" style={{ color: "var(--theme-amber)" }}>
        <path
          d="M5 7 a 2 2 0 0 1 2 -2 h 3 l 2 -2 h 4 l 2 2 h 1 a 2 2 0 0 1 2 2 v 10 a 2 2 0 0 1 -2 2 H 4 a 2 2 0 0 1 -2 -2 V 7 z"
          stroke="currentColor"
          strokeWidth={1.2}
        />
        <line x1={4} y1={4} x2={20} y2={20} stroke="currentColor" strokeWidth={1.2} />
      </svg>
      <div className="text-[15px] font-medium" style={{ color: "rgba(255,255,255,0.9)" }}>
        Camera Access Needed
      </div>
      <div className="max-w-[24ch] text-[11px] leading-snug" style={{ color: "rgba(255,255,255,0.55)" }}>
        Allow Talkie to use the camera so scans can be captured and OCR’d.
      </div>
      <button
        className="mt-2 rounded-full px-4 py-2 text-[10px] font-medium uppercase"
        style={{
          background: "var(--theme-amber)",
          color: "var(--theme-paper)",
          fontFamily: "var(--theme-font-mono)",
          letterSpacing: "0.22em",
        }}
      >
        Open Settings ›
      </button>
    </div>
  );
}
