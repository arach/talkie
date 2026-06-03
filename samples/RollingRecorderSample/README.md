# Rolling Recorder Sample

A tiny macOS Swift command-line app that demonstrates rolling audio rotation:

- records microphone input with `AVAudioEngine`
- writes PCM WAV chunks to `Segments/`
- rotates every `segmentDuration` seconds
- carries a small overlap into the next segment
- calls an async analysis hook whenever a completed segment is ready

Run it:

```bash
cd samples/RollingRecorderSample
swift run
```

Press Return to stop. macOS may ask Terminal, Xcode, or Codex for microphone
permission the first time it runs.

This is intentionally not a production recorder. It is a compact reference for
the moving parts Talkie would need if recording, transcription, and analysis
were decoupled into rolling chunks.
