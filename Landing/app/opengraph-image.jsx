import { ImageResponse } from 'next/og'

export const runtime = 'edge'
export const alt = 'Talkie — Voice memos that think with you'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default async function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          height: '100%',
          width: '100%',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: '#0a0a0a',
          backgroundImage: 'radial-gradient(circle at 25% 25%, #1a1a1a 0%, #0a0a0a 50%)',
        }}
      >
        {/* Grid pattern overlay */}
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundImage: 'linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px)',
            backgroundSize: '40px 40px',
          }}
        />

        {/* Corner accents */}
        <div style={{ position: 'absolute', top: 40, left: 40, width: 24, height: 24, borderTop: '2px solid #22c55e', borderLeft: '2px solid #22c55e' }} />
        <div style={{ position: 'absolute', top: 40, right: 40, width: 24, height: 24, borderTop: '2px solid #22c55e', borderRight: '2px solid #22c55e' }} />
        <div style={{ position: 'absolute', bottom: 40, left: 40, width: 24, height: 24, borderBottom: '2px solid #22c55e', borderLeft: '2px solid #22c55e' }} />
        <div style={{ position: 'absolute', bottom: 40, right: 40, width: 24, height: 24, borderBottom: '2px solid #22c55e', borderRight: '2px solid #22c55e' }} />

        {/* Content */}
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            textAlign: 'center',
            padding: '0 80px',
          }}
        >
          {/* Status indicator */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              marginBottom: 32,
            }}
          >
            <div
              style={{
                width: 8,
                height: 8,
                borderRadius: '50%',
                backgroundColor: '#22c55e',
              }}
            />
            <span
              style={{
                fontSize: 14,
                fontFamily: 'monospace',
                fontWeight: 700,
                letterSpacing: '0.2em',
                color: '#22c55e',
                textTransform: 'uppercase',
              }}
            >
              Now Available
            </span>
          </div>

          {/* Logo/Title */}
          <h1
            style={{
              fontSize: 96,
              fontWeight: 800,
              color: '#fafafa',
              margin: 0,
              letterSpacing: '-0.02em',
              textTransform: 'uppercase',
            }}
          >
            TALKIE
          </h1>

          {/* Tagline */}
          <p
            style={{
              fontSize: 28,
              color: '#a1a1aa',
              margin: '24px 0 0 0',
              fontFamily: 'monospace',
              maxWidth: 700,
            }}
          >
            Voice memos that think with you
          </p>

          {/* Features */}
          <div
            style={{
              display: 'flex',
              gap: 40,
              marginTop: 48,
            }}
          >
            {['Transcribe', 'Summarize', 'Sync'].map((feature) => (
              <div
                key={feature}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                }}
              >
                <div
                  style={{
                    width: 6,
                    height: 6,
                    backgroundColor: '#3f3f46',
                    borderRadius: '50%',
                  }}
                />
                <span
                  style={{
                    fontSize: 18,
                    color: '#71717a',
                    fontFamily: 'monospace',
                  }}
                >
                  {feature}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Bottom bar */}
        <div
          style={{
            position: 'absolute',
            bottom: 40,
            display: 'flex',
            alignItems: 'center',
            gap: 16,
          }}
        >
          <span
            style={{
              fontSize: 14,
              fontFamily: 'monospace',
              color: '#52525b',
              letterSpacing: '0.1em',
            }}
          >
            iOS + macOS
          </span>
          <span style={{ color: '#3f3f46' }}>•</span>
          <span
            style={{
              fontSize: 14,
              fontFamily: 'monospace',
              color: '#52525b',
            }}
          >
            talkie.arach.dev
          </span>
        </div>
      </div>
    ),
    { ...size }
  )
}
