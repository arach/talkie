import { StudioPage } from "@/components/StudioPage";
import { HomeRecentsStudy } from "@/components/studies/HomeRecentsStudy";

export default function IOSHomeRecentsStudy() {
  return (
    <StudioPage
      eyebrow="Home · recent rows"
      title="iOS · Home Recents"
      help="edit components/studies/HomeRecentsStudy.tsx · port target HomeNextView.swift"
    >
      <HomeRecentsStudy />
    </StudioPage>
  );
}
