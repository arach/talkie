import { StudioPage } from "@/components/StudioPage";
import { MacLearnKB } from "@/components/studies/MacLearnKB";

/**
 * Mac Learn KB — first-pass design for the article-detail body that
 * the macOS Learn KB will render inside a local WKWebView.
 *
 * The native app shell (search, sidebar, history) stays SwiftUI; the
 * web view's job is content only.
 *
 * See NOTES.md (token mapping) and SWIFT_PORT.md (handoff assumptions).
 */
export default function MacLearnKBStudy() {
  return (
    <StudioPage
      eyebrow="Learn KB · macOS · Article reader"
      title="Mac Learn KB"
      help="edit components/studies/MacLearnKB.tsx · embedded WKWebView article body — same component repaints under any data-theme bundle"
    >
      <p className="mb-6 max-w-[760px] text-[13px] leading-relaxed text-studio-ink-faint">
        Article-detail body rendered inside a local <code className="font-mono text-[11px] text-studio-ink">WKWebView</code>.
        Two sample articles below, paired across light + dark theme bundles. The component is theme-passive —
        it consumes <code className="font-mono text-[11px] text-studio-ink">--theme-*</code> CSS variables from{" "}
        <code className="font-mono text-[11px] text-studio-ink">app/globals.css</code>, so swapping
        <code className="mx-1 font-mono text-[11px] text-studio-ink">data-theme</code>
        on the wrapper repaints the entire reader. Bridge actions ({" "}
        <code className="font-mono text-[11px] text-studio-ink">talkie://...</code>{" "}
        ) are the explicit call to action; the article does not try to be the app.
      </p>
      <MacLearnKB />
    </StudioPage>
  );
}
