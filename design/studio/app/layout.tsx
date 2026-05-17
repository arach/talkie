import type { Metadata } from "next";
import "./globals.css";
import { StudioNav } from "@/components/StudioNav";

export const metadata: Metadata = {
  title: "Talkie Studio",
  description:
    "Visual design exploration lab for the Talkie macOS and iOS apps.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin=""
        />
        {/* Display = Newsreader (editorial serif inspiration for the
         *  custom family). Body = Inter. Chrome = JetBrains Mono.
         *  These are proxies for the custom face that'll ship; until
         *  then they read as the design family Talkie's chasing. */}
        <link
          href="https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;0,6..72,600;1,6..72,400;1,6..72,500&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <StudioNav />
        {children}
      </body>
    </html>
  );
}
