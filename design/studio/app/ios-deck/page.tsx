import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { IOSDeck } from "@/components/studies/IOSDeck";
import { IOS_THEMES } from "@/lib/themes";

export default function IOSDeckStudy() {
  return (
    <StudioPage
      eyebrow="Command Deck · cleanup pass"
      title="iOS · Deck"
      help="edit components/studies/IOSDeck.tsx · port of DeckMirrorNext.swift"
    >
      <div className="flex flex-col gap-10">
        <Section label="Idle — last result echoes inside the playback surface">
          {IOS_THEMES.map((theme) => (
            <PhoneFrame key={theme.key} theme={theme}>
              <IOSDeck state="idle" />
            </PhoneFrame>
          ))}
        </Section>
        <Section label="Dictating — transcript inline, top-left tile flips to enter to commit">
          {IOS_THEMES.map((theme) => (
            <PhoneFrame key={theme.key} theme={theme}>
              <IOSDeck state="dictating" />
            </PhoneFrame>
          ))}
        </Section>
      </div>
    </StudioPage>
  );
}

function Section({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3">
      <div className="text-[11px] uppercase tracking-[0.18em] text-stone-500">
        {label}
      </div>
      <div className="flex flex-wrap gap-7">{children}</div>
    </div>
  );
}
