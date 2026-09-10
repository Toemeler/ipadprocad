# Fixtures for `verify_linux.sh`

`sample.ptp` — one part with one sketch and no features, in the packed
container `frontend/lib/doc_file.dart` writes: the magic, a little-endian
header length, the index, then `meta.json`.

It is a REAL document, not a hand-written stub. The part JSON inside it came
out of `part.json` in the bug bundle filed on 2026-09-09 (issue #42) — a
document the app itself wrote, on a device, from a session somebody had — and
was re-packed into the container so the app will open it. A stub would pass
`readDocHeader` and then exercise nothing.

`frontend/test/linux_verify_fixture_test.dart` pins that it stays openable, on
the host, so a container-format change is caught there rather than as "the
document was refused" forty minutes into a Linux verification run.
