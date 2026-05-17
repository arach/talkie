# Design

Design artifacts for the Talkie macOS and iOS apps.

## studio/

A working space for visual exploration of native app treatments. Each
study is a self-contained HTML page that renders a component faithfully
enough to evaluate palette, material, and composition decisions before
they're committed to Swift.

The studio fills a real gap: Swift round-trips are 30–40 seconds and
the "must compile" constraint quietly nudges design toward safe
interpolations rather than committed material choices. The studio
removes that constraint — you crank N variants side-by-side, find the
winners, then port the survivors back to SwiftUI.

See [`studio/README.md`](studio/README.md) for the studio's conventions
and the current list of studies.
