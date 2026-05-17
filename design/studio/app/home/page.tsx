import { StudioPage } from "@/components/StudioPage";
import { PhoneFrame } from "@/components/studies/PhoneFrame";
import { Home } from "@/components/studies/Home";
import { IOS_THEMES } from "@/lib/themes";

export default function HomeStudy() {
  return (
    <StudioPage
      eyebrow="Home · Theme study"
      title="Home"
      help="edit components/studies/Home.tsx · STATION + Live Action Bus + Recent"
    >
      <div className="flex flex-wrap gap-7">
        {IOS_THEMES.map((theme) => (
          <PhoneFrame key={theme.key} theme={theme}>
            <Home />
          </PhoneFrame>
        ))}
      </div>
    </StudioPage>
  );
}
