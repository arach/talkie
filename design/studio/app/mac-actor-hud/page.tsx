"use client";

import { StudioPage } from "@/components/StudioPage";
import { ActorHoverDashboard } from "@/components/studies/ActorHoverDashboard";

export default function MacActorHUDStudy() {
  return (
    <StudioPage
      eyebrow="Actor HUD · macOS · hover dashboard"
      title="Floating Actor Dashboard"
      help="flat 2D WebView surface · icon-only hover target"
    >
      <ActorHoverDashboard />
    </StudioPage>
  );
}
