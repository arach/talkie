import LivePage from '../../components/LivePage'

export const metadata = {
  title: 'Talkie Dictation — Voice to action',
  description: 'Talk to Talkie on Mac. Dictate anywhere and turn speech into tasks, summaries, and actions - local-first and private.',
  keywords: ['dictation', 'voice to text', 'macos', 'workflow', 'local', 'privacy', 'productivity'],
  openGraph: {
    title: 'Talkie Dictation — Voice to action',
    description: 'Talk to Talkie on Mac. Dictate anywhere and turn speech into tasks, summaries, and actions - local-first and private.',
    url: 'https://usetalkie.com/dictation',
    siteName: 'Talkie',
    images: [
      {
        url: '/og-live.png',
        width: 1200,
        height: 630,
        alt: 'Talkie Dictation',
      },
    ],
    locale: 'en_US',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Talkie Dictation — Voice to action',
    description: 'Talk to Talkie on Mac. Dictate anywhere and turn speech into tasks, summaries, and actions - local-first and private.',
    images: ['/og-live.png'],
  },
}

export default function Page() {
  return <LivePage />
}
