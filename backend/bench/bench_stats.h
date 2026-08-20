/*
 * Lane C — summary statistics and the log-log power-law fit.
 *
 * The arithmetic here is a deliberate TRANSLATION of ci/perf_profile.py's
 * `fit()` and its N=2 rule, not a fresh implementation: every exponent in
 * PERFORMANCE_PROFILE.md came out of that function, and a harness whose
 * exponents are computed differently cannot be compared against it. If one
 * side changes, both must (backend/bench/README.md says so too).
 *
 *   k, b   : ordinary least squares of log(y) on log(x)
 *   r2     : 1 - ss_res/ss_tot, NaN when ss_tot is 0
 *   se     : sqrt(ss_res / (n-2) / sxx), only when n > 2 and ss_res > 0
 *   CI     : k +/- 1.96 * se — the same 95 % normal interval the profile
 *            prints. With n == 2 there is no interval and the fit reports
 *            "slope only", exactly as fit_cell() does.
 */
#ifndef BENCH_STATS_H
#define BENCH_STATS_H

#include <utility>
#include <vector>

namespace bench {

/* Summary of one operation's timing sample, in milliseconds. */
struct Stats {
    int n = 0;
    double mean = 0.0;
    double sd = 0.0;   /* sample standard deviation (n-1), 0 when n < 2 */
    double p50 = 0.0;
    double p95 = 0.0;
    double min = 0.0;
    double max = 0.0;
    double total = 0.0;
    double cv = 0.0;   /* sd / mean, the profile's repeatability measure */
};

Stats summarise(std::vector<double> xs);

/* Result of the log-log fit. `have_se` false means n == 2 (slope only) or a
 * residual of exactly zero — in both cases no interval may be printed. */
struct Fit {
    bool ok = false;
    int n = 0;
    double k = 0.0;
    double b = 0.0;
    double r2 = 0.0;
    bool have_se = false;
    double se = 0.0;
    double lo = 0.0;
    double hi = 0.0;
};

Fit fitPowerLaw(const std::vector<std::pair<double, double>> &points);

/* Do two 95 % intervals overlap? This is the harness-validation test: the
 * bench agrees with the device when the intervals intersect. Comparing point
 * estimates alone would call a 2.01 against a 2.012 "different". */
bool intervalsOverlap(double a_lo, double a_hi, double b_lo, double b_hi);

} /* namespace bench */

#endif /* BENCH_STATS_H */
