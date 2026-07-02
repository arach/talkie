import { StudioPage } from "@/components/StudioPage";
import { IOSHomeLayout } from "@/components/studies/IOSHomeLayout";

export default function IOSHomeLayoutStudy() {
  return (
    <StudioPage
      eyebrow="Home · layout"
      title="iOS · Home Layout"
      help="edit components/studies/IOSHomeLayout.tsx · port target HomeNextView.swift"
    >
      <IOSHomeLayout />
    </StudioPage>
  );
}
