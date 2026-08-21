"""Sample identity and the merge, pinned.

The bug these exist for was real and expensive: the first version keyed a
sample on `(isolate, tid, timestamp, stack)`, so a window fetched twice could
contribute the SAME sample twice whenever the second fetch symbolicated it
worse — a code object deoptimised between the two fetches comes back as
`<unknown Dart function>`. In one calibration run that admitted 2257 phantom
samples and moved a measured share by tens of points.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from samples import Profiler, _ScriptLines  # noqa: E402


class _NoVm:
    """A VmService that refuses every call — the merge needs none."""

    def call(self, method, params=None, timeout=None):
        raise AssertionError(f"the merge must not call {method}")


def fn(name, kind="Dart", url="file:///s.dart"):
    return {"kind": kind, "resolvedUrl": url, "function": {"name": name}}


def batch(functions, samples, period=1000):
    return {"samplePeriod": period, "maxStackDepth": 128, "pid": 3,
            "functions": functions, "samples": samples}


class MergeTest(unittest.TestCase):
    def setUp(self):
        self.p = Profiler(_NoVm())

    def test_indices_are_rekeyed_onto_a_global_table(self):
        # Two batches list the same two functions in OPPOSITE order. A merge
        # that trusted the per-batch indices would swap them.
        self.p._merge("iso", batch([fn("a"), fn("b")],
                                   [{"tid": 1, "timestamp": 1000, "stack": [0]}]))
        self.p._merge("iso", batch([fn("b"), fn("a")],
                                   [{"tid": 1, "timestamp": 2000, "stack": [0]}]))
        leaves = [self.p.set.frames[s.stack[0]].name for s in self.p.set.samples]
        self.assertEqual(leaves, ["a", "b"])

    def test_the_same_sample_twice_is_merged_away(self):
        b = batch([fn("a")], [{"tid": 1, "timestamp": 1000, "stack": [0]}])
        self.assertEqual(self.p._merge("iso", b), 1)
        self.assertEqual(self.p._merge("iso", b), 0)
        self.assertEqual(len(self.p.set.samples), 1)
        self.assertEqual(self.p.set.dropped_duplicates, 1)

    def test_a_degraded_refetch_does_not_become_a_second_sample(self):
        good = batch([fn("hotLoop")],
                     [{"tid": 1, "timestamp": 1000, "stack": [0]}])
        degraded = batch([fn("<unknown Dart function>", kind="Collected", url="")],
                         [{"tid": 1, "timestamp": 1000, "stack": [0]}])
        self.p._merge("iso", good)
        self.p._merge("iso", degraded)
        self.assertEqual(len(self.p.set.samples), 1)
        self.assertEqual(
            self.p.set.frames[self.p.set.samples[0].stack[0]].name, "hotLoop",
            "the first fetch wins: it was taken when the VM still knew the code")

    def test_the_same_timestamp_on_two_threads_is_two_samples(self):
        self.p._merge("iso", batch([fn("a")], [
            {"tid": 1, "timestamp": 1000, "stack": [0]},
            {"tid": 2, "timestamp": 1000, "stack": [0]}]))
        self.assertEqual(len(self.p.set.samples), 2)

    def test_isolates_are_kept_apart(self):
        b = batch([fn("a")], [{"tid": 1, "timestamp": 1000, "stack": [0]}])
        self.p._merge("isoA", b)
        self.p._merge("isoB", b)
        self.assertEqual(len(self.p.set.samples), 2)

    def test_out_of_range_indices_are_dropped_not_crashed(self):
        self.p._merge("iso", batch([fn("a")],
                                   [{"tid": 1, "timestamp": 1, "stack": [0, 7]}]))
        self.assertEqual(len(self.p.set.samples[0].stack), 1)

    def test_tags_and_truncation_survive_the_merge(self):
        self.p._merge("iso", batch([fn("a")], [
            {"tid": 1, "timestamp": 1, "stack": [0], "userTag": "measure",
             "vmTag": "Dart", "truncated": True}]))
        s = self.p.set.samples[0]
        self.assertEqual(s.user_tag, "measure")
        self.assertEqual(s.vm_tag, "Dart")
        self.assertTrue(s.truncated)


class ScriptLineTest(unittest.TestCase):
    def test_maps_a_token_position_to_its_line(self):
        # [line, tokenPos, column, tokenPos, column, ...]
        t = _ScriptLines([[10, 100, 1, 110, 5], [11, 200, 1], [42, 900, 3]])
        self.assertEqual(t.line_for(100), 10)
        self.assertEqual(t.line_for(115), 10)
        self.assertEqual(t.line_for(200), 11)
        self.assertEqual(t.line_for(950), 42)

    def test_before_the_first_entry_and_with_no_table_at_all(self):
        self.assertEqual(_ScriptLines([[10, 100, 1]]).line_for(5), 0)
        self.assertEqual(_ScriptLines([]).line_for(100), 0)
        self.assertEqual(_ScriptLines([[10, 100, 1]]).line_for(-1), 0)


if __name__ == "__main__":
    unittest.main()
