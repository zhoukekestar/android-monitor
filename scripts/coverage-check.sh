#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

echo "==> Android core coverage"
./gradlew \
    :android-receiver:testDebugUnitTest \
    :android-receiver:jacocoDebugUnitTestReport \
    :android-receiver:jacocoDebugCoverageVerification

python3 - AndroidReceiver/app/build/reports/jacoco/jacocoDebugUnitTestReport/jacocoDebugUnitTestReport.xml <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
root = ET.parse(path).getroot()
for counter in root.findall("counter"):
    if counter.attrib["type"] == "LINE":
        missed = int(counter.attrib["missed"])
        covered = int(counter.attrib["covered"])
        total = missed + covered
        if total == 0:
            print("[FAIL] No Android line coverage rows found.", file=sys.stderr)
            raise SystemExit(2)
        ratio = covered / total
        print(f"Android core total: {covered}/{total} {ratio:.2%}")
        if ratio < 0.95:
            print("[FAIL] Android core line coverage is below 95%.", file=sys.stderr)
            raise SystemExit(1)
        break
else:
    print("[FAIL] No Android LINE counter found in JaCoCo XML.", file=sys.stderr)
    raise SystemExit(2)
PY

echo "==> Swift menu core coverage"
swift test --package-path MacHost --enable-code-coverage

CODECOV_PATH="$(swift test --package-path MacHost --show-codecov-path)"
python3 - "$CODECOV_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

covered = 0
total = 0
for file_summary in data["data"][0]["files"]:
    filename = file_summary["filename"]
    if "/MacHostMenuCore/" not in filename:
        continue
    lines = file_summary["summary"]["lines"]
    covered += int(lines["covered"])
    total += int(lines["count"])
    print(f"{filename}: {lines['covered']}/{lines['count']} {lines['percent']:.2f}%")

if total == 0:
    print("[FAIL] No Swift MacHostMenuCore coverage rows found.", file=sys.stderr)
    raise SystemExit(2)

ratio = covered / total
print(f"Swift MacHostMenuCore total: {covered}/{total} {ratio:.2%}")
if ratio < 0.95:
    print("[FAIL] Swift MacHostMenuCore line coverage is below 95%.", file=sys.stderr)
    raise SystemExit(1)
PY

echo "==> Shell ADB device helper tests"
scripts/test-adb-device-helper.sh

echo "==> Shell replace receiver helper tests"
scripts/test-replace-receiver-helper.sh

echo "==> Shell signature audit helper tests"
scripts/test-audit-receiver-signature.sh

echo "==> Android Studio run configuration tests"
python3 scripts/test-android-studio-run-configs.py

echo "[OK] Coverage gates passed."
