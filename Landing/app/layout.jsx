import './globals.css'
import Script from 'next/script'
import { Inter, JetBrains_Mono } from 'next/font/google'

const inter = Inter({ subsets: ['latin'], variable: '--font-sans', display: 'swap' })
const jetmono = JetBrains_Mono({ subsets: ['latin'], variable: '--font-mono', display: 'swap' })

export const metadata = {
  title: 'Talkie — Voice memos that think with you',
  description:
    'Record once. Talkie transcribes, summarizes, and turns memos into tasks — synced across iOS and macOS.',
  applicationName: 'Talkie',
  metadataBase: new URL('https://usetalkie.com'),
  openGraph: {
    title: 'Talkie — Voice memos that think with you',
    description:
      'Record once. Talkie transcribes, summarizes, and turns memos into tasks — synced across iOS and macOS.',
    url: 'https://usetalkie.com',
    siteName: 'Talkie',
    locale: 'en_US',
    type: 'website',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'Talkie — Voice memos that think with you',
      },
    ],
  },
  icons: {
    icon: [
      { url: '/favicon.svg', type: 'image/svg+xml' },
      { url: '/icon-512.png', sizes: '512x512', type: 'image/png' }
    ],
    apple: [
      { url: '/icon-1024.png', sizes: '1024x1024' }
    ],
    shortcut: ['/favicon.svg']
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Talkie — Voice memos that think with you',
    description:
      'Record once. Talkie transcribes, summarizes, and turns memos into tasks — synced across iOS and macOS.',
    images: ['/og-image.png'],
  },
}

export const viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#ffffff' },
    { media: '(prefers-color-scheme: dark)', color: '#0a0a0a' },
  ],
}

export default function RootLayout({ children }) {
  return (
    <html lang="en" className={`${inter.variable} ${jetmono.variable} dark`}>
      <head>
        {/* Apply saved/system theme before paint to prevent FOUC */}
        <Script id="theme-init" strategy="beforeInteractive">
          {`
            try {
              const stored = localStorage.getItem('theme');
              const useDark = stored ? stored === 'dark' : true; // default to dark first
              const root = document.documentElement;
              if (useDark) root.classList.add('dark'); else root.classList.remove('dark');
            } catch (e) {}
          `}
        </Script>
        {/* Google Analytics */}
        <Script
          src="https://www.googletagmanager.com/gtag/js?id=G-EP7F8TC801"
          strategy="afterInteractive"
        />
        <Script id="ga-gtag" strategy="afterInteractive">
          {`
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);} 
            gtag('js', new Date());
            gtag('config', 'G-EP7F8TC801');
          `}
        </Script>
      </head>
      <body className={`${inter.className} min-h-screen bg-white text-slate-800 antialiased`}>
        {children}
      </body>
    </html>
  )
}
