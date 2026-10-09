"""build123d job harness, executed inside the isolated on-device WASM worker."""
import base64
import contextlib
import json
import math
import sys
import tempfile
import traceback
from pathlib import Path

import build123d as bd

MAX_STEP_BYTES = 12 * 1024 * 1024
MAX_CHECKPOINTS = 32


def emit(event):
    # Original stdout is the event channel; generated print() never becomes JSON.
    sys.__stdout__.write(json.dumps(event, allow_nan=False) + "\n")
    sys.__stdout__.flush()


def shape_of(value):
    if isinstance(value, bd.BuildPart):
        value = value.part
    if not isinstance(value, bd.Shape):
        raise TypeError("result/publish must be a build123d Shape or BuildPart")
    return value


def inspect_shape(shape):
    solids = shape.solids()
    if not solids or not shape.is_valid:
        raise ValueError("geometry must contain valid, closed solids")
    volume = sum(s.volume for s in solids)
    if not math.isfinite(volume) or volume <= 0:
        raise ValueError("geometry has no positive finite volume")
    box = shape.bounding_box()
    return {"valid": True, "solids": len(solids), "volume_mm3": volume,
            "bounds_mm": {"min": list(box.min), "max": list(box.max)},
            "size_mm": list(box.size), "frame": "build123d: Z up, millimetres"}


def check_result(metrics, checks):
    if not isinstance(checks, dict):
        raise ValueError("checks must be an object")
    unknown = set(checks) - {"size_mm", "volume_mm3", "solids"}
    if unknown:
        raise ValueError(f"unsupported checks: {sorted(unknown)}")
    problems = []
    for key, expected in checks.items():
        if key == "size_mm":
            if (not isinstance(expected, list) or len(expected) != 3 or
                    any(isinstance(v, bool) or not isinstance(v, (int, float)) or
                        not math.isfinite(v) or v <= 0 for v in expected)):
                raise ValueError("size_mm must be three positive dimensions in Z-up coordinates")
            if any(abs(a - b) > max(0.05, abs(b) * 0.001)
                   for a, b in zip(metrics[key], expected)):
                problems.append(f"size_mm: measured {metrics[key]}, required {expected}")
        elif key == "solids":
            if isinstance(expected, bool) or not isinstance(expected, int) or expected < 1:
                raise ValueError("solids must be a positive integer")
            if metrics[key] != expected:
                problems.append(f"solids: measured {metrics[key]}, required {expected}")
        else:
            if (not isinstance(expected, list) or len(expected) != 2 or
                    any(isinstance(v, bool) or not isinstance(v, (int, float)) or
                        not math.isfinite(v) for v in expected) or
                    not 0 <= expected[0] <= expected[1]):
                raise ValueError("volume_mm3 must be a nonnegative [min, max] range")
            if not expected[0] <= metrics[key] <= expected[1]:
                problems.append(f"volume_mm3: measured {metrics[key]}, required {expected}")
    return problems


def run(job):
    code = job.get("code")
    if not isinstance(code, str) or not 0 < len(code.encode()) <= 100000:
        raise ValueError("code must be 1..100000 UTF-8 bytes")
    # Validate checks before executing a potentially expensive script.
    checks = job.get("checks", {})
    check_result({"size_mm": [1, 1, 1], "solids": 1, "volume_mm3": 1}, checks)
    checkpoints = 0
    with tempfile.TemporaryDirectory(prefix="build123d-") as tmp:
        root = Path(tmp)
        inputs = job.get("inputs", {})
        if not isinstance(inputs, dict) or len(inputs) > 16:
            raise ValueError("inputs must be at most 16 named STEP bodies")

        def import_existing(name):
            if name not in inputs:
                raise ValueError(f"unknown existing body {name!r}; available: {list(inputs)}")
            data = base64.b64decode(inputs[name], validate=True)
            if len(data) > MAX_STEP_BYTES:
                raise ValueError("input STEP exceeds limit")
            path = root / "input.step"
            path.write_bytes(data)
            # Native app is Y-up. Python code uses build123d's standard Z-up.
            return bd.import_step(path).rotate(bd.Axis.X, 90)

        def snapshot(value, label, final=False):
            nonlocal checkpoints
            if not final and checkpoints >= MAX_CHECKPOINTS:
                raise ValueError("at most 32 live checkpoints; publish major features only")
            shape = shape_of(value)
            metrics = inspect_shape(shape)
            path = root / "snapshot.step"
            app_shape = shape.rotate(bd.Axis.X, -90)
            # Transfer the placed B-Rep, rather than stale assembly children
            # retained by an imported XCAF Compound after a transform.
            from OCP.STEPControl import STEPControl_Writer, STEPControl_AsIs
            from OCP.IFSelect import IFSelect_RetDone
            writer = STEPControl_Writer()
            if writer.Transfer(app_shape.wrapped, STEPControl_AsIs) != IFSelect_RetDone:
                raise ValueError("STEP transfer failed")
            if writer.Write(str(path)) != IFSelect_RetDone:
                raise ValueError("STEP generation failed")
            data = path.read_bytes()
            if len(data) > MAX_STEP_BYTES:
                raise ValueError("generated STEP exceeds 12 MiB")
            checkpoints += 1
            event = {"type": "complete" if final else "preview", "label": str(label)[:120],
                     "step": base64.b64encode(data).decode(), "metrics": metrics,
                     "sequence": checkpoints}
            if final:
                event["problems"] = check_result(metrics, checks)
            emit(event)

        def publish(value, label="Building model"):
            snapshot(value, label)

        namespace = {"__name__": "__cad_model__", "publish": publish,
                     "import_existing": import_existing}
        # Keep generated stdout out of transport and avoid accumulating logs.
        with open('/dev/null', 'w') as sink, contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
            exec(compile(code, "model.py", "exec"), namespace)
            if "result" not in namespace:
                raise ValueError("assign the final build123d Shape to result")
            snapshot(namespace["result"], job.get("part", "Model"), final=True)


def main():
    try:
        job = json.loads(sys.stdin.buffer.read(16 * 1024 * 1024 + 1))
        run(job)
    except BaseException as error:
        emit({"type": "error", "error": f"{type(error).__name__}: {error}"[:2000],
              "traceback": traceback.format_exc()[-6000:]})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
