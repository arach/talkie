"use client";

import { StudioPage } from "@/components/StudioPage";
import { TapeTransport } from "@/components/studies/TapeTransport";

/**
 * Tape Transport — Talkie's signature voice-waveform gesture.
 *
 * The magnetic-tape expression of a memo's voice: a permanent amber
 * Centerline + a Tape-head Needle, with two physically-true transport
 * models switched by phase. Recording = FIXED head · tape flows R→L
 * past it (newest sample at the head, history off-left). Transcribe +
 * Playback = TRAVELLING head · tape fixed (needle paces L→R). Crossing
 * a Peak fires a Crossing Tick (flash + rail marker + optional 40ms
 * tick; a soft haptic on device). Tune the look/timing here before
 * porting to Swift (the iOS recording waveform — replaces the cloud).
 *
 * Edit components/studies/TapeTransport.tsx.
 */
export default function TapeTransportStudy() {
  return (
    <StudioPage
      eyebrow="· Voice Waveform · Cross-platform · gesture"
      title="Tape Transport"
      help="edit components/studies/TapeTransport.tsx · tune before Swift port (iOS recording waveform)"
    >
      <TapeTransport />
    </StudioPage>
  );
}
