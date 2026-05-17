"use client";

import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { IOS_THEMES } from "@/lib/themes";

export default function IPhoneThemesStudy() {
  return (
    <StudioPage
      eyebrow="· iPhone Themes · Mock Shell"
      title="Theme study"
      help="drop mock content into PhoneFrame children · renders across all 4 themes"
    >
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme} />
        ))}
      </div>

      <section className="mt-12 border-t border-studio-edge pt-6">
        <div className="mb-3 text-[9px] font-semibold uppercase tracking-eyebrow text-studio-ink-faint">
          · How to use
        </div>
        <h2 className="font-display text-[19px] font-medium tracking-tight text-studio-ink">
          One mock, four themes
        </h2>
        <p className="mt-2 max-w-[700px] text-[13px] leading-relaxed text-studio-ink-faint">
          Author one iPhone mock as a React component, then drop it into each{" "}
          <code className="font-mono text-[11px] text-studio-ink">
            &lt;PhoneFrame&gt;
          </code>{" "}
          slot via children. Descendants read{" "}
          <code className="font-mono text-[11px] text-studio-ink">
            var(--theme-canvas)
          </code>
          ,{" "}
          <code className="font-mono text-[11px] text-studio-ink">
            var(--theme-ink)
          </code>
          ,{" "}
          <code className="font-mono text-[11px] text-studio-ink">
            var(--theme-amber)
          </code>
          ,{" "}
          <code className="font-mono text-[11px] text-studio-ink">
            var(--theme-screen-*)
          </code>{" "}
          etc., and the per-theme bundle in{" "}
          <code className="font-mono text-[11px] text-studio-ink">
            app/globals.css
          </code>{" "}
          remaps them on each subtree.
        </p>
        <p className="mt-2 max-w-[700px] text-[13px] leading-relaxed text-studio-ink-faint">
          Unlike the scheme-grid studies (
          <a href="/agent-bay" className="text-studio-ink underline-offset-4 hover:underline">
            Agent Bay
          </a>{" "}
          /{" "}
          <a href="/recording-sheet" className="text-studio-ink underline-offset-4 hover:underline">
            Recording Sheet
          </a>
          ), which compare one artifact across <em>materials</em>, this
          study verifies a mock survives across the iOS app's actual
          shipping <em>themes</em>.
        </p>
      </section>
    </StudioPage>
  );
}
