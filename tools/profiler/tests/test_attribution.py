"""The attribution arithmetic, against cases whose answer is known by hand.

`ci/test_perf_tools.py` sets the standard these follow: check the statistics
against ANALYTIC ground truth, never against recorded output, so the tests
cannot drift with the code they guard.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import attribution as attrib  # noqa: E402
from samples import Frame, Sample, SampleSet  # noqa: E402


def build(names, stacks, *, kinds=None, tags=None):
    ss = SampleSet(sample_period_us=1000, pid=1,
                   isolate_names={"iso": "main"})
    ss.frames = [Frame(key=n, name=n, owner="", kind=(kinds or {}).get(n, "Dart"),
                       url=f"file:///x/{n}.dart", line=100 + i)
                 for i, n in enumerate(names)]
    idx = {n: i for i, n in enumerate(names)}
    for k, stack in enumerate(stacks):
        ss.samples.append(Sample(
            tid=1, timestamp=1000 * (k + 1), isolate="iso",
            stack=tuple(idx[n] for n in stack),
            user_tag=(tags or {}).get(k, "")))
    return ss


class WilsonTest(unittest.TestCase):
    def test_contains_the_point_estimate(self):
        lo, hi = attrib.wilson(30, 100)
        self.assertLess(lo, 0.30)
        self.assertGreater(hi, 0.30)

    def test_never_leaves_the_unit_interval(self):
        for k, n in ((0, 10), (10, 10), (1, 3), (999, 1000)):
            lo, hi = attrib.wilson(k, n)
            self.assertGreaterEqual(lo, 0.0)
            self.assertLessEqual(hi, 1.0)

    def test_narrows_as_the_square_root_of_n(self):
        # Quadrupling n should roughly halve the width.
        w1 = attrib.wilson(250, 1000)
        w2 = attrib.wilson(1000, 4000)
        width1 = w1[1] - w1[0]
        width2 = w2[1] - w2[0]
        self.assertAlmostEqual(width1 / width2, 2.0, delta=0.1)

    def test_an_empty_sample_has_no_interval(self):
        self.assertEqual(attrib.wilson(0, 0), (0.0, 0.0))


class FlatProfileTest(unittest.TestCase):
    def test_self_counts_only_the_leaf(self):
        ss = build(["root", "a", "b"],
                   [["b", "a", "root"], ["b", "a", "root"], ["a", "root"]])
        rows = {r.frame.name: r for r in attrib.flat(ss)}
        self.assertEqual(rows["b"].self_n, 2)
        self.assertEqual(rows["a"].self_n, 1)
        self.assertEqual(rows["root"].self_n, 0)

    def test_total_counts_a_frame_once_per_sample(self):
        ss = build(["root", "a"], [["a", "root"], ["a", "root"]])
        rows = {r.frame.name: r for r in attrib.flat(ss)}
        self.assertEqual(rows["root"].total_n, 2)

    def test_recursion_cannot_push_an_inclusive_share_over_one(self):
        # `a` appears three times in one stack; inclusive is a SHARE of samples,
        # so it must be 1, not 3.
        ss = build(["root", "a"], [["a", "a", "a", "root"]])
        rows = {r.frame.name: r for r in attrib.flat(ss)}
        self.assertEqual(rows["a"].total_n, 1)


class WithinTest(unittest.TestCase):
    def setUp(self):
        # root -> analyze -> {elim, jac -> residuals}, plus one sample outside
        self.ss = build(
            ["root", "analyze", "elim", "jac", "residuals", "elsewhere"],
            [["elim", "analyze", "root"]] * 6 +
            [["residuals", "jac", "analyze", "root"]] * 3 +
            [["analyze", "root"]] +
            [["elsewhere", "root"]] * 5)

    def test_the_denominator_is_the_root_not_the_capture(self):
        res = attrib.within(self.ss, "analyze",
                            [("elimination", ["elim"]), ("jacobian", ["jac"])])
        self.assertEqual(res["samplesInRoot"], 10)
        self.assertEqual(res["samplesTotal"], 15)

    def test_buckets_split_the_root_exactly(self):
        res = attrib.within(self.ss, "analyze",
                            [("elimination", ["elim"]), ("jacobian", ["jac"])])
        b = res["buckets"]
        self.assertEqual(b["elimination"]["samples"], 6)
        self.assertEqual(b["jacobian"]["samples"], 3)
        self.assertEqual(b["other"]["samples"], 1)
        self.assertAlmostEqual(
            sum(x["share"] for x in b.values()), 1.0, places=9)

    def test_the_outer_phase_wins_over_the_leaf(self):
        # `residuals` is reachable under `jac`. Asked to choose between them,
        # the walk from the root outward must pick `jac` — the phase — and not
        # whichever leaf the sampler happened to catch.
        res = attrib.within(self.ss, "analyze",
                            [("leafish", ["residuals"]), ("jacobian", ["jac"])])
        self.assertEqual(res["buckets"]["jacobian"]["samples"], 3)
        self.assertEqual(res["buckets"]["leafish"]["samples"], 0)

    def test_regex_patterns(self):
        res = attrib.within(self.ss, "analyze",
                            [("both", ["re:^(elim|jac)$"])])
        self.assertEqual(res["buckets"]["both"]["samples"], 9)

    def test_unmatched_samples_are_reported_not_hidden(self):
        res = attrib.within(self.ss, "analyze", [("elimination", ["elim"])])
        self.assertEqual(res["buckets"]["other"]["samples"], 4)
        self.assertTrue(res["otherLeaves"])


class SelectionTest(unittest.TestCase):
    def test_dart_only_drops_stacks_with_no_dart_frame(self):
        ss = build(["dartfn", "nativefn"],
                   [["dartfn"], ["nativefn"], ["nativefn"]],
                   kinds={"nativefn": "Native"})
        self.assertEqual(len(attrib.select(ss, dart_only=True)), 1)
        self.assertEqual(len(attrib.select(ss, dart_only=False)), 3)

    def test_tag_selection(self):
        ss = build(["a"], [["a"]] * 4, tags={0: "measure", 1: "measure"})
        self.assertEqual(len(attrib.select(ss, tag="measure")), 2)

    def test_census_counts_what_the_sampler_caught(self):
        ss = build(["dartfn", "nativefn"],
                   [["dartfn"], ["nativefn"]], kinds={"nativefn": "Native"})
        c = attrib.census(ss)
        self.assertEqual(c["samples"], 2)
        self.assertEqual(c["withDartFrames"], 1)
        self.assertEqual(c["nativeOnly"], 1)


class CoverageTest(unittest.TestCase):
    def test_a_uniform_capture_is_fully_observed(self):
        ss = build(["a"], [["a"]] * 10)          # 1 ms apart, 1 ms period
        cov = ss.coverage()
        self.assertEqual(cov["gaps"], 0)
        self.assertAlmostEqual(cov["observedFraction"], 1.0)

    def test_a_silent_stretch_is_counted_as_unobserved(self):
        ss = build(["a"], [["a"]] * 4)
        ss.samples[3].timestamp = 100000          # 96 ms after the third
        cov = ss.coverage()
        self.assertEqual(cov["gaps"], 1)
        self.assertLess(cov["observedFraction"], 0.05)

    def test_the_effective_period_is_measured_not_believed(self):
        ss = build(["a"], [["a"]] * 5)
        for i, s in enumerate(ss.samples):
            s.timestamp = 1000 + i * 2500          # 2.5 ms apart
        ss.sample_period_us = 2500
        self.assertEqual(ss.coverage()["effectivePeriodUs"], 2500)
        self.assertEqual(ss.coverage()["nominalPeriodUs"], 2500)


if __name__ == "__main__":
    unittest.main()
