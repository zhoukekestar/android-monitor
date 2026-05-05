#!/usr/bin/env python3
import sys
from collections import Counter
from pathlib import Path


VCL_NAL_TYPES = set(range(1, 6))
NAL_TYPE_IDR = 5
NAL_TYPE_SPS = 7
NAL_TYPE_PPS = 8


def find_start_codes(data):
    offset = 0
    limit = len(data)
    while offset + 2 < limit:
        if data[offset:offset + 3] == b"\x00\x00\x01":
            yield offset, 3
            offset += 3
            continue
        if offset + 3 < limit and data[offset:offset + 4] == b"\x00\x00\x00\x01":
            yield offset, 4
            offset += 4
            continue
        offset += 1


def parse_nal_types(data):
    starts = list(find_start_codes(data))
    nal_types = []
    for index, (start, start_code_size) in enumerate(starts):
        nal_start = start + start_code_size
        nal_end = starts[index + 1][0] if index + 1 < len(starts) else len(data)
        if nal_start >= nal_end:
            continue
        nal_types.append(data[nal_start] & 0x1F)
    return nal_types


def verify_keyframe_config(nal_types):
    if not nal_types:
        return "No Annex-B NAL units found."

    counts = Counter(nal_types)
    missing = []
    if counts[NAL_TYPE_SPS] == 0:
        missing.append("SPS")
    if counts[NAL_TYPE_PPS] == 0:
        missing.append("PPS")
    if counts[NAL_TYPE_IDR] == 0:
        missing.append("IDR")
    if missing:
        return "Missing required NAL type(s): " + ", ".join(missing) + "."

    prefix_has_sps = False
    prefix_has_pps = False
    previous_vcl_was_idr = False
    previous_idr_had_config = False
    idr_count = 0

    for index, nal_type in enumerate(nal_types):
        if nal_type == NAL_TYPE_SPS:
            prefix_has_sps = True
        elif nal_type == NAL_TYPE_PPS:
            prefix_has_pps = True

        if nal_type == NAL_TYPE_IDR:
            idr_count += 1
            has_config = prefix_has_sps and prefix_has_pps
            if not has_config and not (previous_vcl_was_idr and previous_idr_had_config):
                return f"IDR NAL #{idr_count} at NAL index {index} is not preceded by SPS and PPS."
            previous_vcl_was_idr = True
            previous_idr_had_config = has_config or previous_idr_had_config
            prefix_has_sps = False
            prefix_has_pps = False
        elif nal_type in VCL_NAL_TYPES:
            previous_vcl_was_idr = False
            previous_idr_had_config = False
            prefix_has_sps = False
            prefix_has_pps = False

    return None


def main():
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <annex-b.h264>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    data = path.read_bytes()
    nal_types = parse_nal_types(data)
    error = verify_keyframe_config(nal_types)
    if error:
        print(f"[FAIL] {path}: {error}", file=sys.stderr)
        return 1

    counts = Counter(nal_types)
    print(
        "[OK] Annex-B H.264 startup config: "
        f"SPS={counts[NAL_TYPE_SPS]} PPS={counts[NAL_TYPE_PPS]} IDR={counts[NAL_TYPE_IDR]} NALs={len(nal_types)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
