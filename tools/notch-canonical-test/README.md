# Notch Canonical Test

Small macOS SwiftUI app for testing notch path geometry.

## What it tests

- Canonical inner-top notch curve (`control: (t, 0)`)
- Hard-corner reference (no inner curve)
- Mirrored/wrong control reference
- Live tuning for poke-out, notch width, radii, and height

## Run

```bash
cd tools/notch-canonical-test
swift run

# non-blocking launch
./run.sh --detached
```
