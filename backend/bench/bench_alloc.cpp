#include "bench_alloc.h"

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <new>
#include <vector>

/* Relaxed atomics rather than plain longs: BRepMesh_IncrementalMesh can be
 * asked to run in parallel, and although this bench never asks, a counter that
 * is only correct single-threaded is a trap for whoever adds the flag. Relaxed
 * ordering is enough — nothing else is published through these. */
namespace {
std::atomic<long long> g_calls{0};
std::atomic<long long> g_bytes{0};
std::atomic<long long> g_live{0};
bool g_available = false;
const char *g_mechanism = "none";

inline void note_alloc(std::size_t n)
{
    g_calls.fetch_add(1, std::memory_order_relaxed);
    g_bytes.fetch_add(static_cast<long long>(n), std::memory_order_relaxed);
    g_live.fetch_add(static_cast<long long>(n), std::memory_order_relaxed);
}

inline void note_free(std::size_t n)
{
    g_live.fetch_sub(static_cast<long long>(n), std::memory_order_relaxed);
}
} /* namespace */

/* ------------------------------------------------------------------------ */
/* The raw allocator — the counted entry points below all route through these */
/* and these NEVER count, so a counted path calling another cannot double up. */
/* ------------------------------------------------------------------------ */

#if defined(BENCH_ALLOC_WRAP)

#include <malloc.h>

extern "C" {
void *__real_malloc(std::size_t);
void __real_free(void *);
void *__real_calloc(std::size_t, std::size_t);
void *__real_realloc(void *, std::size_t);
}

namespace {
inline void *raw_alloc(std::size_t n) { return __real_malloc(n); }
inline void raw_free(void *p) { __real_free(p); }
inline std::size_t raw_size(void *p) { return p ? malloc_usable_size(p) : 0; }
} /* namespace */

#define BENCH_ALLOC_MECHANISM "ld --wrap + operator new"

#elif defined(BENCH_ALLOC_APPLE_ZONE)

#include <malloc/malloc.h>

namespace {
/* malloc_zone_from_ptr returns null for a pointer no registered zone owns;
 * freeing such a pointer through the default zone would be undefined. */
inline malloc_zone_t *owner(void *p)
{
    malloc_zone_t *z = malloc_zone_from_ptr(p);
    return z ? z : malloc_default_zone();
}
inline void *raw_alloc(std::size_t n)
{
    return malloc_zone_malloc(malloc_default_zone(), n);
}
inline void raw_free(void *p)
{
    if (p)
        malloc_zone_free(owner(p), p);
}
inline std::size_t raw_size(void *p) { return p ? malloc_size(p) : 0; }
} /* namespace */

#define BENCH_ALLOC_MECHANISM "apple zone + operator new"

#else

namespace {
inline void *raw_alloc(std::size_t n) { return std::malloc(n); }
inline void raw_free(void *p) { std::free(p); }
inline std::size_t raw_size(void *) { return 0; }
} /* namespace */

#define BENCH_ALLOC_MECHANISM "none"

#endif

/* ------------------------------------------------------------------------ */
/* Counted entry point A — the C allocator                                   */
/*                                                                           */
/* This is the one that matters for the §6.5 mechanism claim. OCCT's classes  */
/* carry DEFINE_STANDARD_ALLOC, whose operator new calls Standard::Allocate,  */
/* which under the native memory manager this project configures             */
/* (-DUSE_TBB=OFF, "Info: Used native memory manager" at configure time)      */
/* reaches malloc inside TKernel. TKernel is a STATIC archive on our link     */
/* line, so those calls resolve here.                                        */
/* ------------------------------------------------------------------------ */
#if defined(BENCH_ALLOC_WRAP)
extern "C" {
void *__wrap_malloc(std::size_t n)
{
    void *p = raw_alloc(n);
    if (p)
        note_alloc(raw_size(p));
    return p;
}

void __wrap_free(void *p)
{
    if (!p)
        return;
    note_free(raw_size(p));
    raw_free(p);
}

void *__wrap_calloc(std::size_t nmemb, std::size_t size)
{
    void *p = __real_calloc(nmemb, size);
    if (p)
        note_alloc(raw_size(p));
    return p;
}

void *__wrap_realloc(void *old, std::size_t n)
{
    /* Measure the old block BEFORE the call: realloc may release it. */
    const std::size_t was = raw_size(old);
    void *p = __real_realloc(old, n);
    if (p) {
        if (was)
            note_free(was);
        note_alloc(raw_size(p));
    }
    return p;
}
} /* extern "C" */

#elif defined(BENCH_ALLOC_APPLE_ZONE)
extern "C" {
void *malloc(std::size_t n)
{
    void *p = raw_alloc(n);
    if (p)
        note_alloc(raw_size(p));
    return p;
}

void free(void *p)
{
    if (!p)
        return;
    note_free(raw_size(p));
    raw_free(p);
}

void *calloc(std::size_t nmemb, std::size_t size)
{
    void *p = malloc_zone_calloc(malloc_default_zone(), nmemb, size);
    if (p)
        note_alloc(raw_size(p));
    return p;
}

void *realloc(void *old, std::size_t n)
{
    const std::size_t was = raw_size(old);
    void *p = malloc_zone_realloc(old ? owner(old) : malloc_default_zone(), old,
                                  n);
    if (p) {
        if (was)
            note_free(was);
        note_alloc(raw_size(p));
    }
    return p;
}
} /* extern "C" */
#endif

/* ------------------------------------------------------------------------ */
/* Counted entry point B — the C++ allocator                                 */
/*                                                                           */
/* WHY BOTH ARE NEEDED, and it took a measurement to find out. Symbol         */
/* redirection (--wrap on GNU ld, a definition on Apple) only reaches calls   */
/* RESOLVED ON OUR LINK LINE. libstdc++ and libc++ are shared libraries whose */
/* operator new called their own malloc long before we linked, so every       */
/* std::vector, std::string and plain `new` in the program was invisible: a   */
/* 500-element vector<string> workload reported exactly zero allocations.     */
/*                                                                           */
/* Replacing the global operator new/delete fixes that, and is the one        */
/* interposition the C++ standard actually guarantees ([new.delete]) — a      */
/* definition in the program replaces the library's for the whole program,    */
/* libstdc++'s own uses included. Together the two entry points cover both    */
/* halves of what OCCT allocates.                                            */
/*                                                                           */
/* They route through raw_alloc/raw_free, NOT through malloc, so an           */
/* allocation cannot be counted twice on its way down.                        */
/*                                                                           */
/* The ALIGNED forms are deliberately left to the standard library. Their new */
/* and their delete are then both the library's, which is self-consistent;    */
/* replacing one without the other is how an interposer corrupts a heap.      */
/* ------------------------------------------------------------------------ */

void *operator new(std::size_t n)
{
    if (n == 0)
        n = 1;
    void *p = raw_alloc(n);
    if (!p)
        throw std::bad_alloc();
    note_alloc(raw_size(p));
    return p;
}

void *operator new[](std::size_t n) { return ::operator new(n); }

void *operator new(std::size_t n, const std::nothrow_t &) noexcept
{
    if (n == 0)
        n = 1;
    void *p = raw_alloc(n);
    if (p)
        note_alloc(raw_size(p));
    return p;
}

void *operator new[](std::size_t n, const std::nothrow_t &nt) noexcept
{
    return ::operator new(n, nt);
}

void operator delete(void *p) noexcept
{
    if (!p)
        return;
    note_free(raw_size(p));
    raw_free(p);
}

void operator delete[](void *p) noexcept { ::operator delete(p); }

void operator delete(void *p, std::size_t) noexcept { ::operator delete(p); }

void operator delete[](void *p, std::size_t) noexcept { ::operator delete(p); }

void operator delete(void *p, const std::nothrow_t &) noexcept
{
    ::operator delete(p);
}

void operator delete[](void *p, const std::nothrow_t &) noexcept
{
    ::operator delete(p);
}

/* ------------------------------------------------------------------------ */

namespace bench {

AllocSnapshot allocSnapshot()
{
    AllocSnapshot s;
    s.calls = g_calls.load(std::memory_order_relaxed);
    s.bytes = g_bytes.load(std::memory_order_relaxed);
    s.live_bytes = g_live.load(std::memory_order_relaxed);
    return s;
}

bool allocCountingAvailable() { return g_available; }

const char *allocCountingMechanism() { return g_mechanism; }

void allocMarkIneffective()
{
    g_available = false;
    g_mechanism = "none (counters saw no kernel allocation)";
}

bool allocSelfTest()
{
#if defined(BENCH_ALLOC_WRAP) || defined(BENCH_ALLOC_APPLE_ZONE)
    const int kBlocks = 1000;

    /* Leg 1 — the C allocator. Sizes vary so the allocator cannot serve them
     * all from one cached bin, and every block is written to so nothing can be
     * optimised away. */
    const AllocSnapshot c0 = allocSnapshot();
    std::vector<void *> ps;
    ps.reserve(kBlocks);
    long long asked = 0;
    for (int i = 0; i < kBlocks; ++i) {
        const std::size_t n = 32u + static_cast<std::size_t>(i % 97) * 16u;
        void *p = std::malloc(n);
        if (!p)
            return (g_available = false);
        std::memset(p, i & 0xff, n);
        asked += static_cast<long long>(n);
        ps.push_back(p);
    }
    const AllocSnapshot c1 = allocSnapshot();
    for (void *p : ps)
        std::free(p);
    const AllocSnapshot c2 = allocSnapshot();

    const bool c_counted = (c1.calls - c0.calls) >= kBlocks;
    const bool c_sized = (c1.bytes - c0.bytes) >= asked;
    /* A mechanism that counts allocations but not releases reports a heap that
     * only ever climbs, and would make every "transient" reading a leak. */
    const bool c_released = (c2.live_bytes - c1.live_bytes) <= -asked;

    /* Leg 2 — the C++ allocator, through the library's own containers. This is
     * the leg that failed before operator new was replaced, and it is the
     * whole reason this file has two entry points. */
    const AllocSnapshot n0 = allocSnapshot();
    {
        std::vector<char *> held;
        held.reserve(kBlocks);
        for (int i = 0; i < kBlocks; ++i) {
            char *b = new char[64];
            std::memset(b, i & 0xff, 64);
            held.push_back(b);
        }
        for (char *b : held)
            delete[] b;
    }
    const AllocSnapshot n1 = allocSnapshot();
    const bool n_counted = (n1.calls - n0.calls) >= kBlocks;
    const bool n_balanced = (n1.live_bytes - n0.live_bytes) <= 0;

    g_available = c_counted && c_sized && c_released && n_counted && n_balanced;
    g_mechanism = g_available ? BENCH_ALLOC_MECHANISM
                              : "none (self-test failed)";
    return g_available;
#else
    g_available = false;
    g_mechanism = "none (not compiled in)";
    return false;
#endif
}

} /* namespace bench */
