import Image from "next/image";
import { StudioPage } from "@/components/StudioPage";
import styles from "./round-four-gallery.module.css";

type Proposal = {
  model: "Opus" | "Kimi" | "Grok";
  title: string;
  note: string;
  image: string;
  href: string;
};

const CALM_PROPOSALS: Proposal[] = [
  {
    model: "Opus",
    title: "Direction runway",
    note: "One continuous console rail, then a full-width TALK edge.",
    image: "/artifacts/ios-deck-round-4/opus-direction-runway.jpg",
    href: "http://localhost:3479/ios-deck-futures/round-4/opus?variation=runway",
  },
  {
    model: "Kimi",
    title: "Console spine",
    note: "Permanent mechanics form a narrow vertical index inside the console.",
    image: "/artifacts/ios-deck-round-4/kimi-console-spine.jpg",
    href: "http://localhost:3497/ios-deck-futures/round-4/kimi/console-spine",
  },
  {
    model: "Grok",
    title: "Console ledger",
    note: "Task detail and recent history become a compact right-hand ledger.",
    image: "/artifacts/ios-deck-round-4/grok-console-ledger.png",
    href: "http://localhost:3480/ios-deck-futures/round-4/grok-r2?variation=console-ledger&scene=working",
  },
];

const VOICE_PROPOSALS: Proposal[] = [
  {
    model: "Opus",
    title: "Command bridge",
    note: "A tall central TALK target splits the command field into two wings.",
    image: "/artifacts/ios-deck-round-4/opus-command-bridge.jpg",
    href: "http://localhost:3479/ios-deck-futures/round-4/opus?variation=bridge",
  },
  {
    model: "Kimi",
    title: "Voice bay",
    note: "A voice-first keybed pairs with a persistent thread column.",
    image: "/artifacts/ios-deck-round-4/kimi-voice-bay.jpg",
    href: "http://localhost:3497/ios-deck-futures/round-4/kimi/voice-bay",
  },
  {
    model: "Grok",
    title: "Voice plinth",
    note: "History becomes a tape above two command wings and a central TALK plinth.",
    image: "/artifacts/ios-deck-round-4/grok-voice-plinth.png",
    href: "http://localhost:3480/ios-deck-futures/round-4/grok-r2?variation=voice-plinth&scene=working",
  },
];

export default function RoundFourGalleryPage() {
  return (
    <StudioPage
      eyebrow="iPad · Round 4 · three-model field"
      title="Six aesthetic variations"
      help="Grok · Opus · Kimi · implemented at 1180 × 820 pt"
    >
      <section className={styles.baseline}>
        <span>Revised baseline · Take 05</span>
        <p>
          The empty app header is gone. Thread, Details, History, and host state now
          occupy the console utility rail; the live direction dock owns the lower edge.
        </p>
        <a href="/ios-deck-futures/round-3">Open baseline</a>
      </section>

      <ProposalSection
        eyebrow="01 · Calm evolutions"
        title="The incumbent stays visually dominant"
        proposals={CALM_PROPOSALS}
      />
      <ProposalSection
        eyebrow="02 · Voice-first at-bats"
        title="TALK becomes the physical center of gravity"
        proposals={VOICE_PROPOSALS}
      />
    </StudioPage>
  );
}

function ProposalSection({
  eyebrow,
  title,
  proposals,
}: {
  eyebrow: string;
  title: string;
  proposals: Proposal[];
}) {
  return (
    <section className={styles.section}>
      <header className={styles.sectionHeader}>
        <span>{eyebrow}</span>
        <h2>{title}</h2>
      </header>
      <div className={styles.grid}>
        {proposals.map((proposal) => (
          <article className={styles.card} key={`${proposal.model}-${proposal.title}`}>
            <a className={styles.preview} href={proposal.href} aria-label={`Open ${proposal.model} ${proposal.title}`}>
              <Image
                src={proposal.image}
                alt={`${proposal.model} ${proposal.title} iPad command deck variation`}
                width={1180}
                height={820}
                sizes="(max-width: 900px) 100vw, 33vw"
                unoptimized
              />
            </a>
            <div className={styles.cardCopy}>
              <div>
                <span className={styles.model}>{proposal.model}</span>
                <h3>{proposal.title}</h3>
              </div>
              <p>{proposal.note}</p>
              <a href={proposal.href}>Open live <span aria-hidden>↗</span></a>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
