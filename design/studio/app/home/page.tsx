import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { Home } from "@/components/studies/Home";
import { HOME_CONTENT_IDEAS, HOME_VARIANTS } from "@/components/studies/homeVariants";
import { IOS_THEMES } from "@/lib/themes";

const CONTENT_THEME_KEYS = new Set(["scope", "tactical", "lift"]);
const CONTENT_THEMES = IOS_THEMES.filter((theme) => CONTENT_THEME_KEYS.has(theme.key));

export default function HomeStudy() {
  return (
    <StudioPage
      eyebrow="Home · Studio board"
      title="Home content + layout"
      help="edit components/studies/Home.tsx · content ideas on de-duped quick, then layout/material variants"
    >
      <div className="space-y-14">
        <section className="space-y-5">
          <div className="max-w-3xl">
            <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-studio-muted">
              Content ideas · de-duped quick
            </p>
            <p className="mt-2 text-sm leading-6 text-studio-ink/70">
              Same component/alignment lane, compared only in Scope, Tactical, and Lift so the content model is the thing being judged.
            </p>
          </div>
          <div className="space-y-10">
            {HOME_CONTENT_IDEAS.map((idea) => (
              <div key={idea.key} className="space-y-4">
                <div className="max-w-2xl">
                  <p className="text-[11px] font-semibold uppercase tracking-[0.22em] text-studio-ink">
                    {idea.label}
                  </p>
                  <p className="mt-1 text-sm leading-6 text-studio-ink/60">{idea.intent}</p>
                </div>
                <div className="flex flex-wrap gap-7">
                  {CONTENT_THEMES.map((theme) => (
                    <PhoneFrame key={`${idea.key}-${theme.key}`} theme={theme}>
                      <Home variant="deduped-quick" contentIdea={idea.key} />
                    </PhoneFrame>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </section>

        {HOME_VARIANTS.map((variant) => (
          <section key={variant.key} className="space-y-5">
            <div className="max-w-3xl">
              <p className="text-[11px] font-semibold uppercase tracking-[0.24em] text-studio-muted">
                {variant.label}
              </p>
              <p className="mt-2 text-sm leading-6 text-studio-ink/70">{variant.intent}</p>
            </div>
            <div className="flex flex-wrap gap-7">
              {IOS_THEMES.map((theme) => (
                <PhoneFrame key={`${variant.key}-${theme.key}`} theme={theme}>
                  <Home variant={variant.key} />
                </PhoneFrame>
              ))}
            </div>
          </section>
        ))}
      </div>
    </StudioPage>
  );
}
