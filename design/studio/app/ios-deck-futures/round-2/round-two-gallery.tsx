"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";

import s from "./round-two-gallery.module.css";

type LiveDesign = {
  id: "kimi" | "opus" | "grok";
  model: string;
  name: string;
  premise: string;
  image: string;
  route: string;
  tone: "paper" | "night";
};

const LIVE_DESIGNS: LiveDesign[] = [
  {
    id: "kimi",
    model: "Kimi",
    name: "The Tethered Table",
    premise:
      "One task lies open while the others wait at your thumb; a visible thread makes the destination of speech unmistakable.",
    image:
      "/studies/ios-deck-futures/round-2/live-kimi-artboard.png",
    route: "/ios-deck-futures/round-2/kimi",
    tone: "paper",
  },
  {
    id: "opus",
    model: "Claude Opus",
    name: "Standing Page",
    premise:
      "The useful result stands as the room’s one lit object, resting on a brass sill that is also the voice target.",
    image:
      "/studies/ios-deck-futures/round-2/live-opus-artboard-v2.png",
    route: "/ios-deck-futures/round-2/opus",
    tone: "night",
  },
  {
    id: "grok",
    model: "Grok",
    name: "The Aperture",
    premise:
      "Hanging task tags select one framed reading plate; its brass sill names the exact task and Mac that will receive your voice.",
    image:
      "/studies/ios-deck-futures/round-2/live-grok-artboard-v2.png",
    route: "/ios-deck-futures/round-2/grok",
    tone: "night",
  },
];

const PROBES = [
  {
    name: "Task as folio",
    note: "Spatial study 01",
    image:
      "/studies/ios-deck-futures/round-2/image-probe-spatial.png",
  },
  {
    name: "Result as evidence",
    note: "Speculative interface fiction",
    image:
      "/studies/ios-deck-futures/round-2/image-probe-artifact.png",
  },
  {
    name: "Recovery as material change",
    note: "Recovery study 03",
    image:
      "/studies/ios-deck-futures/round-2/image-probe-recovery.png",
  },
];

export function RoundTwoGallery() {
  const [selectedId, setSelectedId] = useState<LiveDesign["id"]>("kimi");
  const selected =
    LIVE_DESIGNS.find((design) => design.id === selectedId) ?? LIVE_DESIGNS[0];

  return (
    <div className={s.gallery}>
      <section className={s.liveField} data-tone={selected.tone}>
        <div className={s.liveRail} role="tablist" aria-label="Live design at-bats">
          <div className={s.railLabel}>Live proposals</div>
          {LIVE_DESIGNS.map((design) => (
            <button
              key={design.id}
              type="button"
              role="tab"
              id={`round-two-tab-${design.id}`}
              aria-controls="round-two-artboard"
              aria-selected={selected.id === design.id}
              tabIndex={selected.id === design.id ? 0 : -1}
              className={s.designTab}
              onClick={() => setSelectedId(design.id)}
            >
              <span>{design.model}</span>
              <span className={s.tabTitle}>{design.name}</span>
            </button>
          ))}
        </div>

        <div
          id="round-two-artboard"
          className={s.artboardWell}
          role="tabpanel"
          aria-labelledby={`round-two-tab-${selected.id}`}
        >
          <div className={s.artboard} key={selected.id}>
            <Image
              src={selected.image}
              alt={`${selected.name} iPad design proposal by ${selected.model}`}
              fill
              priority
              sizes="(max-width: 900px) 100vw, 1240px"
              className={s.artboardImage}
            />
          </div>
        </div>

        <div className={s.liveCaption}>
          <div>
            <div className={s.modelName}>{selected.model}</div>
            <h2 className={s.designName}>{selected.name}</h2>
          </div>
          <p>{selected.premise}</p>
          <Link className={s.openLink} href={selected.route}>
            Open the live study <span aria-hidden>↗</span>
          </Link>
        </div>
      </section>

      <section className={s.probeField}>
        <header className={s.probeHead}>
          <div>
            <div className={s.probeKicker}>Independent image passes · speculative</div>
            <h2>Composition probes</h2>
          </div>
          <p>Silhouette, material, recovery. Not product telemetry.</p>
        </header>

        <div className={s.probeRun}>
          {PROBES.map((probe) => (
            <figure key={probe.name} className={s.probe}>
              <div className={s.probeImage}>
                <Image
                  src={probe.image}
                  alt={`${probe.name} iPad composition probe`}
                  fill
                  sizes="(max-width: 760px) 92vw, (max-width: 1180px) 46vw, 390px"
                />
              </div>
              <figcaption>
                <strong>{probe.name}</strong>
                <span>{probe.note}</span>
              </figcaption>
            </figure>
          ))}
        </div>
      </section>
    </div>
  );
}
