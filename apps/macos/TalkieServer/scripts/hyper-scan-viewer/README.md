# Hyper Scan Viewer

Tiny local viewer for Hyper Scan captures received by the Talkie bridge.

```bash
bun run server.ts
```

Open http://127.0.0.1:8787/.

The viewer reads retained captures from:

`~/Library/Application Support/Talkie/Bridge/HyperScan`

It also reads transient captures from:

`~/Library/Application Support/Talkie/Bridge/HyperScan/.transient`
