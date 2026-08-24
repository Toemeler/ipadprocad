/*
 * Lane C — per-operation allocation accounting.
 *
 * WHY THIS EXISTS. PERFORMANCE_PROFILE.md §6.5's mechanism claim is that each
 * occt_shape_edge_info call builds four whole-shape structures and THROWS THEM
 * AWAY. The device measured `stress.allEdges.rssDeltaMB` = 0 across the whole
 * ladder, which is consistent with that claim but cannot distinguish it from
 * "does no work at all with memory". The discriminating quantity is TRANSIENT
 * allocation volume: bytes requested during the call, most of which are handed
 * straight back. Net RSS cannot see it; a counter on malloc can.
 *
 * §5.5.2 is the precedent the plan cites — the case where the memory prediction
 * was the thing that confirmed the mechanism.
 *
 * HOW. Two mechanisms, because the two platforms this runs on need different
 * ones and neither is portable:
 *
 *   GNU ld (Linux CI, and every developer host)  -Wl,--wrap=malloc,...
 *      Symbol-level redirection applied across the whole link, static OCCT
 *      archives included. Calls made INSIDE libc (strdup and friends) resolve
 *      internally and are not counted; OCCT's are, which is what we measure.
 *
 *   Apple ld64 (macos runner)                    malloc/free defined here
 *      ld64 has no --wrap. A definition of _malloc in an object file on the
 *      link line outranks libSystem's export, so defining the four entry
 *      points here captures every reference from the static archives. Each
 *      forwards to malloc_zone_* on the zone that actually owns the pointer.
 *      Limitation, and it is inherent to two-level namespaces: a call made
 *      INSIDE libc++ or libSystem binds to their own malloc at dylib link
 *      time and is invisible here. OCCT's Standard::Allocate calls malloc
 *      from a static archive, so the allocations the mechanism claim is about
 *      are captured; a few libc++ container allocations are not.
 *
 * NEITHER IS TRUSTED WITHOUT PROOF. allocSelfTest() runs a known workload and
 * refuses the mechanism if the counters did not move by the expected amount.
 * A harness that silently reports zeroes because interposition stopped working
 * is worse than one that reports nothing, so when the self-test fails every
 * allocation column prints "n/a" and the JSON carries available:false. This is
 * the same discipline as §13.1's cautionary tale, applied before the fact.
 */
#ifndef BENCH_ALLOC_H
#define BENCH_ALLOC_H

namespace bench {

struct AllocSnapshot {
    long long calls = 0;      /* malloc + calloc + realloc calls, cumulative */
    long long bytes = 0;      /* bytes REQUESTED by those calls, cumulative  */
    long long live_bytes = 0; /* requested minus released, cumulative        */
};

/* Run once, before any measurement. Returns (and latches) whether the
 * counters may be believed. */
bool allocSelfTest();

bool allocCountingAvailable();

/* "ld --wrap", "apple zone" or "none" — printed in every report so a reader
 * knows which machinery produced the numbers. */
const char *allocCountingMechanism();

AllocSnapshot allocSnapshot();

/* Called by the benchmark when an end-to-end check shows the counters never
 * moved during real kernel work: the self-test can only prove that THIS
 * program's allocations are seen, not that the statically linked kernel's are.
 * After this, every allocation column reports "n/a". */
void allocMarkIneffective();

} /* namespace bench */

#endif /* BENCH_ALLOC_H */
