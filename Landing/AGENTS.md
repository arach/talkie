# AGENTS.md — Landing Page

Landing page specific instructions. See root `/AGENTS.md` for shared conventions.

---

## Overview

Marketing website for Talkie built with Next.js and React.

## Build

```bash
pnpm install
pnpm dev          # http://localhost:3000
pnpm build        # Production build
pnpm start        # Serve production build
```

## Stack

- **Framework**: Next.js 14+ (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Package Manager**: pnpm

## Project Structure

```
Landing/
├── app/
│   ├── layout.tsx
│   ├── page.tsx
│   └── privacy/
│       └── page.tsx
├── components/
│   ├── FeaturesPage.jsx
│   ├── Hero.tsx
│   └── ...
├── public/
│   ├── screenshots/
│   └── og-image.png
├── scripts/
│   └── generate-og-image.js
├── tailwind.config.js
└── package.json
```

## Commands

```bash
pnpm dev                      # Development server
pnpm build                    # Production build
pnpm lint                     # ESLint
node scripts/generate-og-image.js  # Regenerate OG image
```

## Conventions

### TypeScript

- Strict mode enabled
- Prefer interfaces over types for object shapes
- No `any` types

### Components

```tsx
// Functional components with TypeScript
interface FeatureCardProps {
  title: string;
  description: string;
  icon: React.ReactNode;
}

export function FeatureCard({ title, description, icon }: FeatureCardProps) {
  return (
    <div className="rounded-lg bg-white p-6 shadow-sm">
      {icon}
      <h3 className="mt-4 text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-gray-600">{description}</p>
    </div>
  );
}
```

### Tailwind

- Use design tokens from `tailwind.config.js`
- Prefer utility classes over custom CSS
- Extract repeated patterns to components

### Images

- Screenshots in `public/screenshots/`
- Use Next.js `Image` component for optimization
- Generate OG images with `scripts/generate-og-image.js`

## Pages

| Route | Purpose |
|-------|---------|
| `/` | Homepage with hero, features, screenshots |
| `/privacy` | Privacy policy |

## Deployment

Static export compatible. Deploy to Vercel, Netlify, or any static host.

```bash
pnpm build
# Output in .next/ or out/ depending on config
```

## Notes

- Keep bundle size minimal
- Optimize images before committing
- Test on mobile viewports
