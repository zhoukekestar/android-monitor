#!/usr/bin/env python3
import argparse
import json
import socket
import struct
import sys
import time

from pathlib import Path


MAGIC = 0x414D4F4E
HEADER = struct.Struct(">IBBHIQI")
MAX_PAYLOAD_BYTES = 16 * 1024 * 1024
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
        if nal_start < nal_end:
            nal_types.append(data[nal_start] & 0x1F)
    return nal_types


def keyframe_has_startup_config(payload):
    nal_types = parse_nal_types(payload)
    try:
        idr_index = nal_types.index(NAL_TYPE_IDR)
    except ValueError:
        return False, nal_types
    prefix = nal_types[:idr_index]
    return NAL_TYPE_SPS in prefix and NAL_TYPE_PPS in prefix, nal_types


def recv_exact(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise EOFError("socket closed while reading")
        data.extend(chunk)
    return bytes(data)


def recv_line(sock):
    data = bytearray()
    while True:
        chunk = sock.recv(1)
        if not chunk:
            raise EOFError("socket closed before JSON config")
        if chunk == b"\n":
            return data.decode("utf-8")
        data.extend(chunk)


def connect_with_retry(host, port, timeout):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            sock = socket.create_connection((host, port), timeout=0.5)
            sock.settimeout(1.0)
            return sock
        except OSError as error:
            last_error = error
            time.sleep(0.1)
    raise TimeoutError(f"could not connect to {host}:{port}: {last_error}")


def send_json_line(sock, payload):
    sock.sendall(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")


def send_control_smoke(sock):
    messages = [
        {"type": "stats", "decoded_frames": 0, "dropped_frames": 0, "input_fps": 0.0, "bitrate_mbps": 0.0},
        {"type": "touch", "action": "down", "x": 0.25, "y": 0.35},
        {"type": "touch", "action": "move", "x": 0.40, "y": 0.45},
        {"type": "touch", "action": "up", "x": 0.40, "y": 0.45},
        {"type": "touch", "action": "cancel", "x": 0.40, "y": 0.45},
        {"type": "touch", "action": "scroll", "x": 0.50, "y": 0.50, "delta_x": 0.04, "delta_y": -0.08},
    ]
    for message in messages:
        send_json_line(sock, message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--expect-width", type=int, required=True)
    parser.add_argument("--expect-height", type=int, required=True)
    parser.add_argument("--expect-fps", type=int, required=True)
    parser.add_argument("--expect-bitrate-mbps", type=int, required=True)
    parser.add_argument("--timeout", type=float, default=8.0)
    args = parser.parse_args()

    deadline = time.monotonic() + args.timeout
    with connect_with_retry(args.host, args.port, args.timeout) as sock:
        hello = {
            "type": "client_hello",
            "manufacturer": "protocol-smoke",
            "model": "localhost",
            "api_level": 21,
            "screen_width": args.expect_width,
            "screen_height": args.expect_height,
            "supported_codecs": ["h264"],
        }
        send_json_line(sock, hello)

        config = json.loads(recv_line(sock))
        expected = {
            "type": "stream_config",
            "codec": "h264",
            "format": "annexb",
            "width": args.expect_width,
            "height": args.expect_height,
            "fps": args.expect_fps,
            "bitrate_mbps": args.expect_bitrate_mbps,
        }
        for key, value in expected.items():
            if config.get(key) != value:
                raise AssertionError(f"config {key}={config.get(key)!r}, expected {value!r}")

        send_control_smoke(sock)

        while time.monotonic() < deadline:
            header = recv_exact(sock, HEADER.size)
            magic, version, packet_type, flags, sequence, pts_ns, payload_length = HEADER.unpack(header)
            if magic != MAGIC:
                raise AssertionError(f"bad packet magic 0x{magic:08x}")
            if version != 1:
                raise AssertionError(f"unsupported packet version {version}")
            if payload_length <= 0 or payload_length > MAX_PAYLOAD_BYTES:
                raise AssertionError(f"invalid payload length {payload_length}")

            payload = recv_exact(sock, payload_length)
            if packet_type != 2:
                continue
            if flags & 1 == 0:
                continue

            has_config, nal_types = keyframe_has_startup_config(payload)
            if not has_config:
                raise AssertionError(f"keyframe sequence {sequence} lacks SPS/PPS before IDR; NALs={nal_types}")

            print(
                "[OK] Protocol smoke: "
                f"config={args.expect_width}x{args.expect_height}@{args.expect_fps}/{args.expect_bitrate_mbps}Mbps "
                f"keyframe_seq={sequence} pts_ns={pts_ns} payload={payload_length} bytes "
                "controls=stats,touch,scroll"
            )
            return 0

    print("[FAIL] No keyframe packet received before timeout.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"[FAIL] {Path(sys.argv[0]).name}: {error}", file=sys.stderr)
        raise SystemExit(1)
