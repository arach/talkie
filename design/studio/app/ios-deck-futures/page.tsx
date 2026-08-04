import { EngMarkdown } from "@/components/EngMarkdown";
import { StudioPage } from "@/components/StudioPage";
import { DeckFuturesStudy } from "@/components/studies/DeckFuturesStudy";
import { IPadDesignConsolidation } from "@/components/studies/IPadDesignConsolidation";
import { IPadFullSizeExplorations } from "@/components/studies/IPadFullSizeExplorations";
import { loadRepoFile } from "@/lib/repo-file";

export default async function IOSDeckFuturesStudy() {
  const [modelFlight, critique, grokReview, kimiReview] = await Promise.all([
    loadRepoFile([
      "design",
      "studio",
      "app",
      "ios-deck-futures",
      "IPAD-MODEL-FLIGHT.md",
    ]),
    loadRepoFile([
      "design",
      "studio",
      "app",
      "ios-deck-futures",
      "IPAD-CRITIQUE.md",
    ]),
    loadRepoFile([
      "design",
      "studio",
      "app",
      "ios-deck-futures",
      "IPAD-CRITIQUE-grok.md",
    ]),
    loadRepoFile([
      "design",
      "studio",
      "app",
      "ios-deck-futures",
      "IPAD-CRITIQUE-kimi.md",
    ]),
  ]);

  return (
    <StudioPage
      eyebrow="Command Deck · visual at-bats"
      title="iPad · Full-size proposals"
      help="Two complete mocks · shared task · no IDE chrome"
    >
      <IPadFullSizeExplorations />

      <details className="group mx-auto mt-8 max-w-[1240px] border border-studio-edge bg-white">
        <summary className="flex min-h-14 cursor-pointer list-none items-center justify-between gap-5 px-5 py-3 font-sans text-[13px] font-semibold text-studio-ink marker:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-studio-ink">
          <span>Open the earlier research and synthesis board</span>
          <span aria-hidden className="font-mono text-[15px] font-normal text-studio-ink-faint group-open:rotate-45">+</span>
        </summary>
        <div className="border-t border-studio-edge p-3">
          <IPadDesignConsolidation />
        </div>
      </details>

      <section className="mx-auto mt-16 max-w-[1080px] border-t border-studio-edge pt-8">
        <div className="mb-5 font-display text-[24px] font-medium tracking-tight text-studio-ink">
          Review record
        </div>
        <p className="mb-6 max-w-[72ch] font-sans text-[13px] leading-[1.65] text-studio-ink-faint">
          The consolidated board above is the decision surface. Expand these records
          for the model-flight receipts, earlier critiques, and the first independent
          direction inventory.
        </p>
        <div className="space-y-3">
          {modelFlight ? (
            <ReviewRecord title="3×3 model flight · findings and receipts">
              <EngMarkdown body={modelFlight.content} />
            </ReviewRecord>
          ) : null}
          {critique ? (
            <ReviewRecord title="Claude Opus · initial iPad critique">
              <EngMarkdown body={critique.content} />
            </ReviewRecord>
          ) : null}
          {grokReview ? (
            <ReviewRecord title="Grok · initial product critique">
              <EngMarkdown body={grokReview.content} />
            </ReviewRecord>
          ) : null}
          {kimiReview ? (
            <ReviewRecord title="Kimi · initial interaction critique">
              <EngMarkdown body={kimiReview.content} />
            </ReviewRecord>
          ) : null}
          <ReviewRecord title="Earlier three-lens direction inventory">
            <DeckFuturesStudy />
          </ReviewRecord>
        </div>
      </section>
    </StudioPage>
  );
}

function ReviewRecord({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <details className="group border border-studio-edge bg-white">
      <summary className="flex min-h-12 cursor-pointer list-none items-center justify-between gap-5 px-4 py-3 font-sans text-[13px] font-semibold text-studio-ink marker:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-studio-ink">
        <span>{title}</span>
        <span aria-hidden className="font-mono text-[15px] font-normal text-studio-ink-faint group-open:rotate-45">+</span>
      </summary>
      <div className="border-t border-studio-edge p-5 sm:p-8">
        {children}
      </div>
    </details>
  );
}
