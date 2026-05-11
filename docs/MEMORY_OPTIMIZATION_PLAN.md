# Memory Optimization Plan - Talkie for Mac

## Problem Statement
Talkie 2.0.x showed ~150MB resident memory vs ~65MB in 1.9.0. Peak memory spiked to 1.3GB vs ~220MB baseline.

## Target Metrics
| Metric | 1.9.0 Baseline | Target | Unacceptable |
|--------|---------------|--------|--------------|
| Physical footprint | 63MB | <70MB | >100MB |
| Peak memory | 221MB | <300MB | >500MB |
| Startup time | - | <500ms to UI | >1s |
| Binary size | 24.5MB | <20MB | >30MB |

---

## Phase 1: Build Configuration Audit

### 1.1 Xcode Build Settings
- [ ] Verify `archive` workflow used (not direct `build`)
- [ ] Check Release configuration optimization level (`-Osize` vs `-O`)
- [ ] Verify dead code stripping enabled (`DEAD_CODE_STRIPPING=YES`)
- [ ] Check `DEPLOYMENT_POSTPROCESSING=YES`
- [ ] Verify bitcode/debug symbols stripped for release

### 1.2 Dependencies Audit
- [ ] List all Swift packages and their sizes
- [ ] Identify packages not used at startup (defer loading)
- [ ] Check for duplicate dependencies
- [ ] Verify static vs dynamic linking choices

**Removed Dependencies (2.0.8):**
- [x] mlx-swift (caused ~80MB memory overhead)
- [x] mlx-swift-lm
- [x] MLXLMCommon

### 1.3 Framework Linking
- [ ] Run `otool -L` on binary to list linked frameworks
- [ ] Compare framework count between versions
- [ ] Identify any unexpected framework loads

---

## Phase 2: Runtime Memory Analysis

### 2.1 Baseline Capture Script
```bash
# Run after app stabilizes (30s after launch)
vmmap $(pgrep -x Talkie) > /tmp/talkie-vmmap.txt
vmmap $(pgrep -x Talkie) | grep "Physical footprint"
vmmap $(pgrep -x Talkie) | grep "__TEXT" | wc -l  # Library count
```

### 2.2 Key Memory Regions to Monitor
| Region | What it indicates |
|--------|-------------------|
| Physical footprint | Actual RAM used |
| Peak | Maximum ever allocated |
| __TEXT | Code segments (libraries) |
| MALLOC | Heap allocations |
| mapped file | Memory-mapped files (DB, assets) |

### 2.3 Heap Analysis
```bash
# Check for large allocations
heap $(pgrep -x Talkie) | head -50
leaks $(pgrep -x Talkie) --noContent
```

### 2.4 Instruments Profiling
- [ ] Allocations instrument - track large allocs at startup
- [ ] Leaks instrument - verify no memory leaks
- [ ] VM Tracker - understand memory regions

---

## Phase 3: Code-Level Optimization Checklist

### 3.1 Startup Path
- [ ] Audit `StartupCoordinator` phases
- [ ] Verify lazy initialization for non-critical services
- [ ] Check `@MainActor` usage (can block main thread)
- [ ] Profile time spent in each startup phase

### 3.2 Data Loading
- [ ] Verify Core Data uses faulting (not eager loading)
- [ ] Check CloudKit sync doesn't load all records at once
- [ ] Audit any `fetchRequest` with no `fetchLimit`
- [ ] Check audio/binary data uses external storage

### 3.3 SwiftUI Views
- [ ] Check for views that load heavy content in `init`
- [ ] Verify images use lazy loading (`LazyVStack`, etc.)
- [ ] Look for `@State` holding large objects
- [ ] Check `@Observable` objects for retained data

### 3.4 Caching
- [ ] Audit image caches (NSCache with limits?)
- [ ] Check for unbounded in-memory collections
- [ ] Verify caches have eviction policies

### 3.5 Third-Party Libraries
- [ ] GRDB - check connection pooling, statement caching
- [ ] FluidAudio - verify lazy initialization
- [ ] Any ML/AI libraries - confirm not loading models at startup

---

## Phase 4: Binary Size Optimization

### 4.1 Asset Catalog
- [ ] Check for oversized images
- [ ] Verify asset slicing for device types
- [ ] Remove unused assets

### 4.2 Code Cleanup
- [ ] Remove dead code paths
- [ ] Check for debug-only code in release builds
- [ ] Audit large string literals or embedded data

### 4.3 Strip Analysis
```bash
# Check symbol table size
size /Applications/Talkie.app/Contents/MacOS/Talkie
nm -U /Applications/Talkie.app/Contents/MacOS/Talkie | wc -l
```

---

## Phase 5: Validation

### 5.1 Automated Memory Test
```bash
#!/bin/bash
# memory-check.sh - Run after each build

APP_PID=$(pgrep -x Talkie)
if [ -z "$APP_PID" ]; then
    echo "Talkie not running"
    exit 1
fi

FOOTPRINT=$(vmmap $APP_PID 2>/dev/null | grep "Physical footprint:" | head -1 | awk '{print $3}')
PEAK=$(vmmap $APP_PID 2>/dev/null | grep "Physical footprint (peak):" | awk '{print $4}')

echo "Footprint: $FOOTPRINT"
echo "Peak: $PEAK"

# Extract numeric value
FOOTPRINT_MB=$(echo $FOOTPRINT | sed 's/M//')
if (( $(echo "$FOOTPRINT_MB > 100" | bc -l) )); then
    echo "WARNING: Memory exceeds 100MB threshold!"
    exit 1
fi
```

### 5.2 Regression Test Matrix
| Scenario | Expected Memory | Test |
|----------|-----------------|------|
| Fresh launch | <70MB | Launch, wait 30s, measure |
| After browsing memos | <80MB | Open 10 memos, measure |
| After sync | <90MB | Trigger CloudKit sync, measure |
| After 1 hour idle | <70MB | Leave running, measure |

### 5.3 Comparison Checklist
Before each release:
- [ ] Compare vmmap with 1.9.0 baseline
- [ ] Verify library count similar (~1046)
- [ ] Check no new large frameworks loaded
- [ ] Confirm peak stays under 300MB

---

## Findings Log

### 2.0.8 Investigation
| Change | Impact |
|--------|--------|
| Removed MLX packages | -80MB resident, -1GB peak |
| Archive workflow | No impact (was already optimized) |
| STRIP_STYLE settings | No significant impact |

### Root Cause
MLX Swift packages (mlx-swift, mlx-swift-lm) loaded Metal and ML frameworks at app startup even when MLX features weren't used. This added ~80MB to resident memory and caused 1.3GB peak during framework initialization.

### Solution
Removed MLX from Talkie. Local LLM inference belongs in TalkieEngine (separation of concerns). Stubbed MLXProvider to maintain API compatibility.

---

## Future Recommendations

1. **Dependency Review Process**: Before adding any new Swift package, check its framework dependencies and measure memory impact.

2. **Memory Budget**: Set a 100MB hard limit for Talkie. Add CI check that fails if exceeded.

3. **Lazy Loading**: Any heavy framework (ML, media processing) should be loaded on-demand, not at startup.

4. **Regular Audits**: Run memory comparison against baseline before each release.
