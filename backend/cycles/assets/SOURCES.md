# Where the render assets came from

Anything in this directory ships inside the app, so every file needs a
licence that permits that. This is the record.

Add a row when you add a file. CC0 / public domain only, or your own work.

| file | source | licence |
|------|--------|---------|
| `hdri/studio.hdr` | supplied by the repository owner, 2026-09-02, as `studio_kontrast_03_2k.hdr` | **to confirm — see below** |

## hdri/studio.hdr

A 2048x1024 equirectangular Radiance map of a white cyclorama studio: a
softbox on a stand as the key, two large white bounce panels, a dark alcove
behind them. Measured by `ci/check_hdri.py` at import:

    mean luminance 0.8312, peak 33.9  (peak is 41x the mean)
    above 1.0: 2.319% of the sphere
    brightest 1.0% of the sphere carries 27.0% of the light

**The licence row is not filled in and it needs to be.** The file arrived
without provenance. Its name follows the `<slug>_<resolution>.hdr` convention
that Poly Haven uses for downloads, and everything Poly Haven publishes is
CC0, but a naming convention is not a licence and nobody should treat this
line as one. Whoever added the file knows where it came from; that goes here
before a release.

Nothing technical depends on this. The renderer neither reads nor cares about
this file, and an unlicensed asset renders exactly as well as a licensed one
— which is the whole problem, and the reason the record is kept by hand.
