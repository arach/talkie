import LivePage from '../../components/LivePage'

export const metadata = {
  title: 'Talkie Live — Capture Ideas Before They Disappear',
  description: 'Free menu bar app for instant voice-to-text. Hold a hotkey, speak, release — your words appear wherever you were typing. 100% local, no cloud, no account needed.',
  keywords: ['voice to text', 'dictation', 'macos', 'menu bar', 'transcription', 'whisper', 'local', 'privacy', 'productivity'],
  openGraph: {
    title: 'Talkie Live — Capture Ideas Before They Disappear',
    description: 'Your best ideas don\'t arrive when you\'re ready. Talkie Live captures them in one second flat. Free, local, private.',
    url: 'https://talkie.live/live',
    siteName: 'Talkie',
    images: [
      {
        url: '/og-live.png',
        width: 1200,
        height: 630,
        alt: 'Talkie Live - Instant Voice-to-Text for Mac',
      },
    ],
    locale: 'en_US',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Talkie Live — Capture Ideas Before They Disappear',
    description: 'Free menu bar app for instant voice-to-text. Hold a hotkey, speak, release. 100% local, no cloud.',
    images: ['/og-live.png'],
  },
}

export default function Page() {
  return <LivePage />
}
