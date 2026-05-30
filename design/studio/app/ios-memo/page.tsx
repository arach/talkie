import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { IOSMemo } from "@/components/studies/IOSMemo";
import { IOS_THEMES } from "@/lib/themes";

export default function IOSMemoStudy() {
  return (
    <StudioPage
      eyebrow="Memo detail · cleanup pass"
      title="iOS · Memo"
      help="edit components/studies/IOSMemo.tsx · port of VoiceMemoDetailNext.swift"
    >
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <IOSMemo />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
