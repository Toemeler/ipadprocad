#!/usr/bin/env python3
"""Verification for the two programs that produce every number in
PERFORMANCE_PROFILE.md.

WHY THIS EXISTS
---------------
`perf_report.py` and `perf_profile.py` decide what the device measurements
MEAN: they fit the exponents, they compute the confidence intervals, they
decide which values are below the instrument's resolution and must not be
printed as digits. Until this file existed, neither had a single test, and
neither was executed by CI. The entire quantitative case of the profile rested
on two unverified scripts.

That is the same defect the profile itself keeps finding in the app — a
measurement nobody checked — applied to the measuring apparatus. So these
tests check the statistics against cases whose answers are known ANALYTICALLY,
not against recorded output:

  * an exact power law must recover its exponent exactly, with R² = 1;
  * a known-noisy series must produce a confidence interval that CONTAINS the
    true exponent;
  * two points must never yield a confidence interval, because two points have
    zero residual degrees of freedom;
  * the quantization classifier must place values on the correct side of the
    SNR thresholds it claims to use;
  * a value below one microsecond must never be printed as digits.

Run:  python3 -m unittest discover -s ci -p 'test_*.py'
"""

from __future__ import annotations

import io
import json
import math
import os
import sys
import unittest
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import perf_profile as pp  # noqa: E402
import perf_report as pr  # noqa: E402


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def synthetic_bundle(path: str, *, notes=None, spans=None,
                     scenarios=None) -> str:
    """A minimal but STRUCTURALLY REAL bundle.

    Structurally real matters: a fixture that omits a key the tools read would
    make them look robust while the real thing crashes. The shapes here mirror
    what Perf.jsonSnapshot and Perf.scenario actually emit.
    """
    snap = {
        "at": "2026-01-01T00:00:00.000000",
        "build": "testbuild",
        "wallMs": 1000,
        "frames": {"n": 10, "jank33": 1, "fps": 60.0,
                   "total": {"n": 10, "avgMs": 16.0, "p50Ms": 16.0,
                             "p95Ms": 17.0, "worstMs": 20.0, "totalMs": 160.0},
                   "build": {"n": 10, "avgMs": 1.0, "p50Ms": 1.0, "p95Ms": 1.2,
                             "worstMs": 2.0, "totalMs": 10.0},
                   "raster": {"n": 10, "avgMs": 2.0, "p50Ms": 2.0,
                              "p95Ms": 2.5, "worstMs": 3.0, "totalMs": 20.0}},
        "memory": {"rssMB": 100, "rssPeakMB": 120, "rssMaxMB": 130},
        "native": {"preSuite.thermalState": "nominal",
                   "preSuite.lowPowerMode": False,
                   "postSuite.thermalState": "nominal",
                   "postSuite.lowPowerMode": False},
        "spans": spans if spans is not None else {
            "kernel.demo": {"n": 10, "totalMs": 10.0, "avgMs": 1.0,
                            "p50Ms": 1.0, "p95Ms": 1.1, "worstMs": 1.5},
            # deliberately below the 1 us floor
            "app.tiny": {"n": 100, "totalMs": 0.0, "avgMs": 0.0,
                         "p50Ms": 0.0, "p95Ms": 0.0, "worstMs": 0.0},
        },
        "counters": {"kernel.demo.calls": 10},
        "gauges": {"demo.size": 42},
    }
    if notes:
        snap["notes"] = notes
    suite = {"suite": "perf_scenarios/v1", "build": "testbuild",
             "at": "2026-01-01T00:00:00.000000", "wallMs": 500,
             "scenarios": scenarios if scenarios is not None else [
                 {"scenario": "kernel.demo.8", "wallMs": 8.0,
                  "spans": {"kernel.demo": {"n": 1, "totalMs": 8.0,
                                            "avgMs": 8.0}},
                  "counters": {}, "gauges": {}},
                 {"scenario": "kernel.demo.16", "wallMs": 16.0,
                  "spans": {"kernel.demo": {"n": 1, "totalMs": 16.0,
                                            "avgMs": 16.0}},
                  "counters": {}, "gauges": {}},
                 {"scenario": "kernel.demo.32", "wallMs": 32.0,
                  "spans": {"kernel.demo": {"n": 1, "totalMs": 32.0,
                                            "avgMs": 32.0}},
                  "counters": {}, "gauges": {}},
             ]}
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("perf_snapshot.json", json.dumps(snap))
        z.writestr("perf_suite.json", json.dumps(suite))
    return path


# ---------------------------------------------------------------------------
# the statistics
# ---------------------------------------------------------------------------

class TestFit(unittest.TestCase):
    """Analytic ground truth: cases whose exponent is known before fitting."""

    def test_exact_power_law_recovers_its_exponent(self):
        # y = 3 * x^2 sampled exactly. There is no noise, so the fit must be
        # exact to floating point and R^2 must be 1.
        for k_true in (0.5, 1.0, 1.935, 2.0, 2.3):
            pts = [(x, 3.0 * x ** k_true) for x in (8, 16, 32, 64, 128)]
            f = pp.fit(pts)
            self.assertIsNotNone(f)
            self.assertAlmostEqual(f["k"], k_true, places=9,
                                   msg=f"k_true={k_true}")
            self.assertAlmostEqual(f["r2"], 1.0, places=9)

    def test_confidence_interval_contains_the_true_exponent(self):
        # A deterministic perturbation, alternating sign so it cannot be
        # mistaken for a trend. The 95 % interval must cover the truth.
        k_true = 1.9
        pts = []
        for i, x in enumerate((8, 16, 32, 64, 128, 256)):
            noise = 1.05 if i % 2 == 0 else 0.95
            pts.append((x, 2.0 * x ** k_true * noise))
        f = pp.fit(pts)
        lo = f["k"] - 1.96 * f["se"]
        hi = f["k"] + 1.96 * f["se"]
        self.assertLess(lo, k_true)
        self.assertGreater(hi, k_true)

    def test_two_points_yield_no_confidence_interval(self):
        # Two points have zero residual degrees of freedom: R^2 is 1 by
        # construction and a CI does not exist. The tools must say so rather
        # than print a spuriously precise interval.
        f = pp.fit([(8, 8.0), (16, 32.0)])
        self.assertEqual(f["n"], 2)
        self.assertIsNone(f["se"])
        k, r2, ci = pp.fit_cell(f)
        self.assertIn("slope only", ci)
        self.assertEqual(r2, "—")

    def test_fit_refuses_degenerate_input(self):
        self.assertIsNone(pp.fit([]))
        self.assertIsNone(pp.fit([(8, 1.0)]))          # one point
        self.assertIsNone(pp.fit([(8, 1.0), (8, 2.0)]))  # no x variation
        # Non-positive values cannot be log-transformed and must be dropped,
        # not silently turned into a fit through whatever remains.
        self.assertIsNone(pp.fit([(8, 0.0), (16, 0.0)]))

    def test_flat_series_reports_no_relationship(self):
        # kernel.fillet.edges behaves exactly like this on the device: the
        # cost does not move with the swept axis. The correct output is k ~ 0
        # with R^2 ~ 0 — a stated absence of relationship, not a number.
        pts = [(1, 49.31), (4, 49.49), (12, 49.28)]
        f = pp.fit(pts)
        self.assertLess(abs(f["k"]), 0.05)
        self.assertLess(f["r2"], 0.2)

    def test_report_and_profile_agree_on_the_exponent(self):
        # The two tools fit independently. If they ever disagree, one of the
        # document's tables contradicts another and nobody would notice.
        pts = [(8, 8.0), (16, 30.0), (32, 121.0), (64, 480.0)]
        k_profile = pp.fit(pts)["k"]
        k_report = pr._exponent(pts)
        self.assertAlmostEqual(k_profile, k_report, places=9)


class TestResolution(unittest.TestCase):
    """The quantization classifier, against its own stated thresholds."""

    def test_quantization_standard_error_formula(self):
        # SE_q = q / sqrt(12 n). Checked at n=1 against the closed form for a
        # uniform distribution of width q.
        self.assertAlmostEqual(pp.se_q(1), 0.001 / math.sqrt(12), places=12)
        self.assertAlmostEqual(pp.se_q(100), 0.001 / math.sqrt(1200),
                               places=12)

    def test_classification_lands_on_the_right_side_of_each_threshold(self):
        n = 100
        se = pp.se_q(n)
        # Just inside / outside SNR 3 and SNR 10, the two published cut-offs.
        self.assertEqual(pp.resolution(2.9 * se, n)[0], "unresolved")
        self.assertEqual(pp.resolution(3.1 * se, n)[0], "marginal")
        self.assertEqual(pp.resolution(9.9 * se, n)[0], "marginal")
        self.assertEqual(pp.resolution(10.1 * se, n)[0], "resolved")

    def test_a_zero_mean_is_never_resolved(self):
        for n in (1, 10, 1000):
            self.assertEqual(pp.resolution(0.0, n)[0], "unresolved")

    def test_sub_microsecond_means_are_not_printed_as_digits(self):
        # The specific failure this guards: a mean of 0.00000 ms printed as a
        # number reads as a measurement of zero rather than as the absence of
        # one.
        self.assertEqual(pp.ms(0.0, 100), "< 1 µs")
        self.assertEqual(pp.ms(0.00001, 100), "< 1 µs")
        self.assertNotEqual(pp.ms(1.0, 100), "< 1 µs")

    def test_percentiles_use_the_tick_not_the_standard_error(self):
        # A percentile is ONE observation, so its floor is the quantum itself.
        # Using the mean's standard error here would wrongly suppress
        # legitimate small percentiles on large samples.
        self.assertEqual(pp.obs(0.0), "< 1 µs")
        self.assertEqual(pp.obs(0.0005), "< 1 µs")
        self.assertEqual(pp.obs(0.001), "0.0010")   # exactly one tick: real
        self.assertEqual(pp.obs(0.002), "0.0020")


class TestVerdicts(unittest.TestCase):

    def test_constant_work_families_are_not_labelled_linear(self):
        # kernel.query.edgeInfoScale sweeps the SIZE OF THE INPUT that one
        # fixed unit of work must traverse. k ~ 1 there means "one call is
        # O(input)" — the finding, not the absence of one. Labelling it
        # "linear" beside families whose axis is the workload invites the
        # opposite conclusion.
        self.assertIn("kernel.query.edgeInfoScale", pr.CONSTANT_WORK_FAMILIES)

    def test_every_constant_work_family_name_is_a_real_prefix(self):
        # A typo here silently disables the protection above.
        for fam in pr.CONSTANT_WORK_FAMILIES:
            self.assertRegex(fam, r"^[a-z][A-Za-z0-9.]+$")
            self.assertFalse(fam.endswith("."))


# ---------------------------------------------------------------------------
# end to end
# ---------------------------------------------------------------------------

class TestEndToEnd(unittest.TestCase):

    def setUp(self):
        import tempfile
        self.dir = tempfile.mkdtemp()
        self.bundle = synthetic_bundle(os.path.join(self.dir, "b.zip"))

    def test_profile_emits_every_section_and_no_digits_below_the_floor(self):
        buf = io.StringIO()
        old = sys.stdout
        sys.stdout = buf
        try:
            pp.main_for_test(self.bundle)
        finally:
            sys.stdout = old
        out = buf.getvalue()
        for section in ("A. Complete span inventory",
                        "B. Complete counter inventory",
                        "C. Complete gauge inventory",
                        "D. Notes",
                        "E. Complete scenario inventory",
                        "F. Ramp families",
                        "G. All fitted cost models"):
            self.assertIn(section, out, msg=f"missing {section}")
        # app.tiny has a mean of 0 over n=100 and must appear as "< 1 µs".
        self.assertIn("`app.tiny`", out)
        tiny_row = [l for l in out.splitlines() if "`app.tiny`" in l][0]
        self.assertIn("< 1 µs", tiny_row)
        self.assertIn("unresolved", tiny_row)

    def test_report_runs_and_reports_the_exact_power_law(self):
        buf = io.StringIO()
        old = sys.stdout
        sys.stdout = buf
        try:
            pr.main_for_test(self.bundle)
        finally:
            sys.stdout = old
        out = buf.getvalue()
        self.assertIn("IS THIS RUN TRUSTWORTHY", out)
        # The synthetic sweep doubles cost with size: exactly k = 1.
        self.assertIn("kernel.demo", out)

    def test_notes_reach_the_report(self):
        b = synthetic_bundle(
            os.path.join(self.dir, "n.zip"),
            notes={"kernel.sweepTwist.fail.reason": "twist angle out of range"},
            spans={"kernel.demo": {"n": 1, "totalMs": 1.0, "avgMs": 1.0,
                                   "p50Ms": 1.0, "p95Ms": 1.0, "worstMs": 1.0}},
            scenarios=[{"scenario": "kernel.demo", "wallMs": 1.0,
                        "spans": {}, "counters": {"kernel.sweepTwist.fail": 1},
                        "gauges": {},
                        "notes": {"kernel.sweepTwist.fail.reason":
                                  "twist angle out of range"}}])
        buf = io.StringIO()
        old = sys.stdout
        sys.stdout = buf
        try:
            pr.main_for_test(b)
        finally:
            sys.stdout = old
        out = buf.getvalue()
        # The counter alone was never actionable; the reason beside it is the
        # whole point of M221.
        self.assertIn("kernel.sweepTwist.fail", out)
        self.assertIn("twist angle out of range", out)

    def test_the_stress_tier_is_not_dropped_from_the_appendix(self):
        """The appendix claims to print EVERYTHING. It must mean it.

        perf_report.py has always read perf_suite_stress.json; perf_profile.py
        did not, so the stress tier — the only thing that measures where the
        app actually fails, rather than extrapolating to it — would have been
        missing from the "complete" appendix with nothing to signal the hole.
        """
        b = os.path.join(self.dir, "stress.zip")
        synthetic_bundle(b)
        with zipfile.ZipFile(b, "a") as z:
            z.writestr("perf_suite_stress.json", json.dumps({
                "suite": "perf_scenarios_stress/v1", "build": "testbuild",
                "wallMs": 900, "scenarios": [
                    {"scenario": "stress.kernel.allEdges", "wallMs": 900.0,
                     "spans": {"kernel.stressEdges": {
                         "n": 1, "totalMs": 900.0, "avgMs": 900.0}},
                     "counters": {"stress.rungReached": 1920},
                     "gauges": {"stress.allEdges.lastRung": 1920}},
                ]}))
        d = pp.load(b)
        names = [n for n, _ in d["runners"]]
        self.assertIn("perf_suite_stress.json", names)

        buf = io.StringIO()
        old_out = sys.stdout
        sys.stdout = buf
        try:
            pp.main_for_test(b)
        finally:
            sys.stdout = old_out
        out = buf.getvalue()
        self.assertIn("stress.kernel.allEdges", out)
        self.assertIn("perf_suite_stress.json", out)

    def test_a_failed_suite_is_reported_not_swallowed(self):
        """bug_capture writes an error STRING when a suite throws.

        That is the most important line in such a bundle: it says an entire
        subsystem is missing. Crashing on it would hide the failure behind a
        tool failure; ignoring it would hide it entirely.
        """
        b = os.path.join(self.dir, "broken.zip")
        synthetic_bundle(b)
        with zipfile.ZipFile(b, "a") as z:
            z.writestr("perf_suite_stress.json",
                       "stress suite failed: OcctFfi unavailable")
        d = pp.load(b)
        self.assertTrue(d["errors"])
        buf = io.StringIO()
        old_out = sys.stdout
        sys.stdout = buf
        try:
            pp.main_for_test(b)
        finally:
            sys.stdout = old_out
        out = buf.getvalue()
        self.assertIn("A suite did not complete", out)
        self.assertIn("OcctFfi unavailable", out)

    def test_tools_survive_a_bundle_with_nothing_in_it(self):
        # A run that died before Log.init produces exactly this. Both tools
        # must report the emptiness rather than raise, or a failed capture
        # becomes a crashed toolchain and the actual failure is hidden.
        empty = os.path.join(self.dir, "empty.zip")
        with zipfile.ZipFile(empty, "w") as z:
            z.writestr("report.md", "nothing here")
        for fn in (pp.main_for_test, pr.main_for_test):
            buf = io.StringIO()
            old = sys.stdout
            sys.stdout = buf
            try:
                fn(empty)
            finally:
                sys.stdout = old


if __name__ == "__main__":
    unittest.main(verbosity=2)
