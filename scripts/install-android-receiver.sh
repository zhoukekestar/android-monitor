#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

./gradlew runReceiverDebug
