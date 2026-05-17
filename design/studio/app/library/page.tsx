import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { Library } from "@/components/studies/Library";
import { IOS_THEMES } from "@/lib/themes";

export default function LibraryStudy() {
  return (
    <StudioPage
      eyebrow="· Library · Theme study"
      title="Library across themes"
      help="edit components/studies/Library.tsx · hot-reload across all 4 themes"
    >
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <Library />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
