#!/usr/bin/env python3
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def parse_args():
    parser = argparse.ArgumentParser(
        description="Decode an H.264 stream and verify frames are visible and changing."
    )
    parser.add_argument("input", type=Path)
    parser.add_argument("--min-frames", type=int, default=4)
    parser.add_argument("--min-mean-luma", type=float, default=20.0)
    parser.add_argument("--min-diff", type=float, default=0.10)
    parser.add_argument("--fps", type=float, default=1.0)
    parser.add_argument("--keep-frames", type=Path)
    return parser.parse_args()


def run_ffmpeg(input_path: Path, output_dir: Path, fps: float):
    pattern = output_dir / "frame-%03d.png"
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(input_path),
        "-vf",
        f"fps={fps},scale=160:-1",
        str(pattern),
    ]
    subprocess.run(command, check=True)


def mean_luma(image: Image.Image) -> float:
    return ImageStat.Stat(image.convert("L")).mean[0]


def mean_abs_diff(a: Image.Image, b: Image.Image) -> float:
    diff = ImageChops.difference(a.convert("L"), b.convert("L"))
    return ImageStat.Stat(diff).mean[0]


def main():
    args = parse_args()
    if not args.input.exists() or args.input.stat().st_size == 0:
        print(f"[FAIL] H.264 input is missing or empty: {args.input}", file=sys.stderr)
        return 2
    if shutil.which("ffmpeg") is None:
        print("[FAIL] ffmpeg was not found on PATH", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="android-monitor-freshness-") as temp_name:
        temp_dir = Path(temp_name)
        run_ffmpeg(args.input, temp_dir, args.fps)
        frames = sorted(temp_dir.glob("frame-*.png"))
        if args.keep_frames:
            args.keep_frames.mkdir(parents=True, exist_ok=True)
            for frame in frames:
                shutil.copy2(frame, args.keep_frames / frame.name)

        if len(frames) < args.min_frames:
            print(
                f"[FAIL] Only decoded {len(frames)} sampled frame(s), expected at least {args.min_frames}.",
                file=sys.stderr,
            )
            return 1

        images = [Image.open(frame).convert("RGB") for frame in frames]
        lumas = [mean_luma(image) for image in images]
        max_luma = max(lumas)
        diffs = [
            mean_abs_diff(images[index], images[index + 1])
            for index in range(len(images) - 1)
        ]
        max_diff = max(diffs) if diffs else 0.0

        print(
            "[INFO] H.264 freshness: "
            f"frames={len(frames)} max_luma={max_luma:.2f} max_adjacent_diff={max_diff:.3f}"
        )

        if max_luma < args.min_mean_luma:
            print(
                f"[FAIL] Frames look too dark: max luma {max_luma:.2f} < {args.min_mean_luma:.2f}.",
                file=sys.stderr,
            )
            return 1

        if max_diff < args.min_diff:
            print(
                f"[FAIL] Sampled frames did not change enough: {max_diff:.3f} < {args.min_diff:.3f}.",
                file=sys.stderr,
            )
            return 1

    print("[OK] H.264 frames are visible and changing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
