"""The trace writer, checked by reading its own output back.

These tests exist because the alternative was to trust the converter. A folded
sampled profile is an INTERPRETATION of the samples — slice boundaries were
never observed — so the interpretation has to be pinned: which slices appear,
where they start, how long they last, and what happens across a gap the sampler
did not cover.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import perfetto  # noqa: E402
from samples import Frame, Sample, SampleSet  # noqa: E402


def frames(*names):
    return [Frame(key=n, name=n, owner="", kind="Dart",
                  url=f"file:///{n}.dart", line=10 + i)
            for i, n in enumerate(names)]


def sset(period=1000, stacks=()):
    ss = SampleSet(frames=frames("root", "mid", "leaf", "other"),
                   sample_period_us=period, pid=42,
                   isolate_names={"iso": "main"})
    for i, (ts, stack) in enumerate(stacks):
        ss.samples.append(Sample(tid=7, timestamp=ts, isolate="iso",
                                 stack=tuple(stack)))
    return ss


class FoldingTest(unittest.TestCase):
    def test_a_run_of_identical_stacks_is_one_slice_per_frame(self):
        # stacks are LEAF FIRST: (leaf, mid, root)
        ss = sset(stacks=[(1000, (2, 1, 0)), (2000, (2, 1, 0)),
                          (3000, (2, 1, 0))])
        ev = [e for e in perfetto.to_trace_events(ss) if e["ph"] == "X"]
        self.assertEqual(len(ev), 3, "one slice per frame, not per sample")
        by = {e["name"]: e for e in ev}
        for name in ("root", "mid", "leaf"):
            self.assertEqual(by[name]["ts"], 1000)
            # last sample at 3000 plus one period of tail
            self.assertEqual(by[name]["dur"], 3000)

    def test_a_frame_that_leaves_the_stack_closes_its_slice(self):
        ss = sset(stacks=[(1000, (2, 1, 0)), (2000, (1, 0)),
                          (3000, (1, 0))])
        ev = {e["name"]: e for e in perfetto.to_trace_events(ss)
              if e["ph"] == "X"}
        self.assertEqual(ev["leaf"]["dur"], 1000)
        self.assertEqual(ev["mid"]["dur"], 3000)

    def test_a_gap_larger_than_the_threshold_starts_a_new_slice(self):
        # 1 ms period; the second run is 40 ms later, which the sampler did not
        # observe. One slice spanning the silence would be a claim about time
        # nobody measured.
        ss = sset(stacks=[(1000, (1, 0)), (2000, (1, 0)),
                          (42000, (1, 0)), (43000, (1, 0))])
        mids = [e for e in perfetto.to_trace_events(ss)
                if e["ph"] == "X" and e["name"] == "mid"]
        self.assertEqual(len(mids), 2)
        self.assertEqual(mids[0]["dur"], 2000)
        self.assertEqual(mids[1]["ts"], 42000)

    def test_sibling_frames_do_not_merge(self):
        ss = sset(stacks=[(1000, (1, 0)), (2000, (3, 0))])
        names = [e["name"] for e in perfetto.to_trace_events(ss)
                 if e["ph"] == "X"]
        self.assertEqual(sorted(names), ["mid", "other", "root"])

    def test_the_trace_carries_the_site_of_every_frame(self):
        ss = sset(stacks=[(1000, (2, 1, 0))])
        ev = {e["name"]: e for e in perfetto.to_trace_events(ss)
              if e["ph"] == "X"}
        self.assertEqual(ev["leaf"]["args"]["line"], 12)
        self.assertTrue(ev["leaf"]["args"]["site"].endswith("leaf.dart:12"))

    def test_threads_are_named_and_kept_apart(self):
        ss = sset(stacks=[(1000, (1, 0))])
        ss.samples.append(Sample(tid=7, timestamp=1000, isolate="iso2",
                                 stack=(1, 0)))
        ss.isolate_names["iso2"] = "worker"
        meta = [e for e in perfetto.to_trace_events(ss)
                if e["ph"] == "M" and e["name"] == "thread_name"]
        self.assertEqual(len(meta), 2)
        self.assertNotEqual(meta[0]["tid"], meta[1]["tid"])


class FoldedStackTest(unittest.TestCase):
    def test_counts_identical_stacks(self):
        ss = sset(stacks=[(1000, (2, 1, 0)), (2000, (2, 1, 0)),
                          (3000, (1, 0))])
        out = perfetto.to_folded(ss)
        self.assertIn("root;mid;leaf 2\n", out)
        self.assertIn("root;mid 1\n", out)

    def test_is_sorted_by_count_descending(self):
        ss = sset(stacks=[(1000, (1, 0)), (2000, (2, 1, 0)),
                          (3000, (1, 0)), (4000, (1, 0))])
        first = perfetto.to_folded(ss).splitlines()[0]
        self.assertTrue(first.startswith("root;mid 3"))


class TraceDocumentTest(unittest.TestCase):
    def test_it_says_what_the_slices_are(self):
        ss = sset(stacks=[(1000, (1, 0))])
        doc = perfetto.to_trace(ss)
        self.assertEqual(doc["displayTimeUnit"], "ms")
        self.assertIn("FOLDED SAMPLES", doc["otherData"]["note"])
        self.assertEqual(doc["otherData"]["samplePeriodUs"], "1000")

    def test_round_trips_through_gzip(self):
        import gzip
        import json
        import tempfile
        ss = sset(stacks=[(1000, (2, 1, 0))])
        with tempfile.TemporaryDirectory() as d:
            path = perfetto.write_trace(ss, os.path.join(d, "t.json"))
            self.assertTrue(path.endswith(".json.gz"))
            with gzip.open(path, "rt") as fh:
                back = json.load(fh)
        self.assertTrue(any(e["ph"] == "X" for e in back["traceEvents"]))


if __name__ == "__main__":
    unittest.main()
