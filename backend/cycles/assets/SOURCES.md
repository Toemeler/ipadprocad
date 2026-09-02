# Where the render assets came from

Anything in this directory ships inside the app, so every file needs a
licence that permits that. This is the record.

Add a row when you add a file. CC0 / public domain only, or your own work.

| file | source | licence |
|------|--------|---------|
| `hdri/studio.hdr` | [Poly Haven — `studio_kontrast_03`](https://polyhaven.com/a/studio_kontrast_03), 2K, downloaded as `studio_kontrast_03_2k.hdr` | CC0 |

## hdri/studio.hdr

A 2048x1024 equirectangular Radiance map of a white cyclorama studio: a
softbox on a stand as the key, two large white bounce panels, a dark alcove
behind them. Measured by `ci/check_hdri.py` at import:

    mean luminance 0.8312, peak 33.9  (peak is 41x the mean)
    above 1.0: 2.319% of the sphere
    brightest 1.0% of the sphere carries 27.0% of the light

Poly Haven, `studio_kontrast_03`, 2K Radiance. CC0 — public domain, no
attribution required and redistribution inside a binary permitted, which is
what shipping it in an .ipa is. Confirmed by the repository owner on
2026-09-02.

Renamed from `studio_kontrast_03_2k.hdr` on the way in. The name here is the
one `cycles_assets.dart` looks for and nothing else is picked up: a studio is
a lighting decision rather than a preference, and two of them are two
different products.
