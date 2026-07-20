#if os(macOS)
import Foundation

enum ScrollingCaptureMotion {
    /// Splits a scroll into a fast cubic ease-out burst. The first events move
    /// most of the distance and the final events settle gently at the exact
    /// requested offset.
    static func easeOutDeltas(totalDistance: Int, stepCount: Int = 9) -> [Int] {
        guard totalDistance != 0, stepCount > 0 else { return [] }

        var deltas: [Int] = []
        var previousTarget = 0

        for step in 1...stepCount {
            let progress = Double(step) / Double(stepCount)
            let easedProgress = 1 - pow(1 - progress, 3)
            let target = step == stepCount
                ? totalDistance
                : Int((Double(totalDistance) * easedProgress).rounded())
            let delta = target - previousTarget
            if delta != 0 {
                deltas.append(delta)
            }
            previousTarget = target
        }

        return deltas
    }
}
#endif
