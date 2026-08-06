import Foundation

/// Timing for the work that happens PAST the Dart boundary.
///
/// WHY
/// ---
/// `3d.push` on the Dart side measures how long the platform-channel call takes
/// to return. That is not how long the scene took to apply: the channel is
/// asynchronous, so a Dart-side reading can be a fraction of a millisecond
/// while RealityKit spends thirty on the same payload. Everything past that
/// boundary has been unmeasurable from Dart by construction — the last blind
/// spot in the report, and the one that turns "the 3D view feels heavy" into a
/// shrug.
///
/// This closes it as far as it can be closed from the app's own code: the time
/// spent INSIDE `setScene` / `setOverlays` / `setCamera`, plus the sub-steps of
/// a scene rebuild. What still cannot be seen from here is RealityKit's own
/// render loop, which runs on its own schedule and belongs to the OS.
///
/// DESIGN
/// ------
/// Accumulate, do not report. A callback per measurement would put a
/// platform-channel round trip inside the very thing being measured — the
/// classic mistake of a probe that shows up in its own numbers. Dart PULLS the
/// accumulated table when it wants it (the bug bundle does, once), and the
/// pull resets it, so two consecutive drains describe two disjoint intervals
/// rather than overlapping totals.
///
/// Deliberately plain Swift: `CFAbsoluteTimeGetCurrent`, a dictionary and a
/// lock. The previous native probe cost two CI round trips to a C macro Swift
/// does not import, and this file is not the place to relearn that.
enum RvPerf {

    private struct Stat {
        var n: Int = 0
        var totalMs: Double = 0
        var worstMs: Double = 0
    }

    private static var stats: [String: Stat] = [:]
    // The channel handler runs on the platform thread, but the drain can be
    // requested from anywhere; a dictionary mutated from two threads is a
    // crash, and crashing while collecting diagnostics is the worst possible
    // failure for this particular feature.
    private static let lock = NSLock()

    /// Runs [body], recording how long it took under [name].
    @discardableResult
    static func time<T>(_ name: String, _ body: () -> T) -> T {
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = body()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        lock.lock()
        var s = stats[name] ?? Stat()
        s.n += 1
        s.totalMs += ms
        if ms > s.worstMs { s.worstMs = ms }
        stats[name] = s
        lock.unlock()
        return r
    }

    /// Everything measured since the last drain, then forgets it.
    ///
    /// Shaped like the Dart side's span table (`n` / `totalMs` / `worstMs`) so
    /// a reader does not have to learn a second format for the same idea.
    static func drain() -> [String: Any] {
        lock.lock()
        let snap = stats
        stats = [:]
        lock.unlock()
        var out: [String: Any] = [:]
        for (k, v) in snap {
            out[k] = ["n": v.n, "totalMs": v.totalMs, "worstMs": v.worstMs]
        }
        return out
    }
}
