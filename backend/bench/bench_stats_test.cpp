/*
 * Lane C — self-tests for the harness's own arithmetic.
 *
 * ci/test_perf_tools.py exists because "the whole quantitative case rested on
 * two unverified scripts, which is the exact defect the profile keeps finding
 * in the app, applied to the apparatus" (sim-perf.yml, M222a). The same
 * argument applies here: this harness decides whether an optimisation worked,
 * so its statistics are checked against ANALYTIC ground truth rather than
 * against recorded output that would drift with them.
 *
 * Prints "BENCH STATS: PASS" / "BENCH STATS: FAIL (...)" and exits non-zero on
 * failure — the same log-readable contract as backend/occt/tests/smoke_occt.c.
 */
#include <cmath>
#include <cstdio>
#include <vector>

#include "bench_stats.h"

static int g_failures = 0;

static void fail(const char *what)
{
    std::printf("BENCH STATS: FAIL (%s)\n", what);
    ++g_failures;
}

static void check(bool cond, const char *what)
{
    if (!cond)
        fail(what);
}

static void near(double got, double want, double tol, const char *what)
{
    if (!(std::fabs(got - want) <= tol)) {
        std::printf("BENCH STATS: FAIL (%s: got %.6f, want %.6f +/- %.6f)\n",
                    what, got, want, tol);
        ++g_failures;
    }
}

int main()
{
    /* --- summarise ------------------------------------------------------- */
    {
        const bench::Stats s = bench::summarise({4.0, 1.0, 3.0, 2.0});
        near(s.mean, 2.5, 1e-12, "mean of 1..4");
        near(s.min, 1.0, 1e-12, "min");
        near(s.max, 4.0, 1e-12, "max");
        near(s.total, 10.0, 1e-12, "total");
        /* sample sd of {1,2,3,4} = sqrt(5/3) */
        near(s.sd, std::sqrt(5.0 / 3.0), 1e-12, "sample sd (n-1)");
        /* Nearest rank: p50 of 4 is the 2nd, p95 is the 4th. */
        near(s.p50, 2.0, 1e-12, "p50 nearest-rank");
        near(s.p95, 4.0, 1e-12, "p95 nearest-rank");
        check(s.n == 4, "n");
    }
    {
        const bench::Stats s = bench::summarise({});
        check(s.n == 0, "empty sample reports n = 0");
    }
    {
        /* One observation has no spread. Reporting a standard deviation for it
         * would be inventing a number, which is the failure mode §1.4 of the
         * profile is about. */
        const bench::Stats s = bench::summarise({7.0});
        near(s.mean, 7.0, 1e-12, "single-observation mean");
        near(s.sd, 0.0, 1e-12, "single observation has sd 0");
        near(s.cv, 0.0, 1e-12, "single observation has cv 0");
    }

    /* --- fitPowerLaw: an exact power law must recover its exponent -------- */
    {
        /* y = 3 * x^2 exactly */
        std::vector<std::pair<double, double>> pts;
        for (double x : {1.0, 2.0, 4.0, 8.0, 16.0})
            pts.emplace_back(x, 3.0 * x * x);
        const bench::Fit f = bench::fitPowerLaw(pts);
        check(f.ok, "exact quadratic fits");
        near(f.k, 2.0, 1e-9, "exact quadratic recovers k = 2");
        near(std::exp(f.b), 3.0, 1e-6, "exact quadratic recovers the constant");
        near(f.r2, 1.0, 1e-9, "exact quadratic has R2 = 1");
        /* The residual is floating-point dust rather than a hard zero, so an
         * interval IS produced — and it must be dust-wide and centred on the
         * truth. ci/perf_profile.py behaves identically (its `ss_res > 0`
         * guard fires on the same dust), and the two sides have to agree. */
        if (f.have_se) {
            check(f.lo <= 2.0 && 2.0 <= f.hi,
                  "the noiseless interval contains the true exponent");
            check(f.hi - f.lo < 1e-6,
                  "the noiseless interval is numerically degenerate");
        }
    }
    {
        /* y = x^1 exactly */
        std::vector<std::pair<double, double>> pts;
        for (double x : {2.0, 5.0, 11.0, 23.0})
            pts.emplace_back(x, 0.5 * x);
        const bench::Fit f = bench::fitPowerLaw(pts);
        near(f.k, 1.0, 1e-9, "exact linear recovers k = 1");
    }
    {
        /* Exactly flat: y constant against a swept x is exponent 0 — §6.3's
         * fillet finding. R2 is undefined here because the total sum of
         * squares is zero, and NaN is the honest report of that. */
        std::vector<std::pair<double, double>> pts;
        for (double x : {1.0, 4.0, 12.0})
            pts.emplace_back(x, 25.5);
        const bench::Fit f = bench::fitPowerLaw(pts);
        near(f.k, 0.0, 1e-12, "a flat cost fits k = 0");
        check(std::isnan(f.r2), "an exactly flat series has undefined R2");
    }
    {
        /* The device's actual fillet numbers (§10.2, kernel.fillet.edges at
         * 1/4/12 edges). The correct output is a stated absence of
         * relationship: k ~ 0 with R2 ~ 0, matching
         * ci/test_perf_tools.py::test_flat_series_reports_no_relationship
         * point for point. */
        const bench::Fit f =
            bench::fitPowerLaw({{1.0, 49.31}, {4.0, 49.49}, {12.0, 49.28}});
        check(std::fabs(f.k) < 0.05, "a near-flat series fits k ~ 0");
        check(f.r2 < 0.2, "a near-flat series has no explanatory power");
    }
    {
        /* Two points: a slope, and NO interval. */
        const bench::Fit f = bench::fitPowerLaw({{1.0, 1.0}, {2.0, 4.0}});
        check(f.ok, "two points give a slope");
        near(f.k, 2.0, 1e-12, "two-point slope");
        check(!f.have_se, "two points yield no confidence interval");
    }
    {
        const bench::Fit f = bench::fitPowerLaw({{1.0, 1.0}});
        check(!f.ok, "one point is not a fit");
        const bench::Fit g = bench::fitPowerLaw({});
        check(!g.ok, "no points is not a fit");
    }
    {
        /* Non-positive values cannot be logged; they are dropped, and if too
         * few survive there is no fit rather than a fit over what is left. */
        const bench::Fit f =
            bench::fitPowerLaw({{1.0, 0.0}, {2.0, -1.0}, {4.0, 16.0}});
        check(!f.ok, "non-positive samples are dropped, not logged");
    }
    {
        /* A constant x cannot support a fit: sxx is zero. */
        const bench::Fit f =
            bench::fitPowerLaw({{3.0, 1.0}, {3.0, 2.0}, {3.0, 4.0}});
        check(!f.ok, "a degenerate x axis is refused");
    }
    {
        /* With noise the interval must CONTAIN the truth. The perturbation is
         * deterministic so this test cannot flake. */
        const double truth = 2.0;
        const double noise[5] = {1.03, 0.97, 1.02, 0.98, 1.01};
        std::vector<std::pair<double, double>> pts;
        int i = 0;
        for (double x : {1.0, 2.0, 4.0, 8.0, 16.0})
            pts.emplace_back(x, std::pow(x, truth) * noise[i++]);
        const bench::Fit f = bench::fitPowerLaw(pts);
        check(f.have_se, "a noisy fit has an interval");
        check(f.lo <= truth && truth <= f.hi,
              "the 95 % interval contains the true exponent");
        check(f.lo < f.hi, "the interval is non-degenerate");
    }

    /* --- intervalsOverlap: the calibration test -------------------------- */
    check(bench::intervalsOverlap(1.9, 2.1, 2.0, 2.2), "overlapping intervals");
    check(!bench::intervalsOverlap(1.0, 1.5, 1.9, 2.1), "disjoint intervals");
    check(bench::intervalsOverlap(1.0, 2.0, 2.0, 3.0),
          "intervals that touch at one point overlap");
    check(bench::intervalsOverlap(1.9, 2.1, 1.95, 2.0),
          "a contained interval overlaps");

    if (g_failures) {
        std::printf("BENCH STATS: %d failure(s)\n", g_failures);
        return 1;
    }
    std::printf("BENCH STATS: PASS\n");
    return 0;
}
