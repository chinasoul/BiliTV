#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Build 2 APK variants: v7a/v8a with plugins enabled"
  echo
  echo "Usage:"
  echo "  bash scripts/build_apk_matrix.sh [extra flutter build apk args]"
  echo
  echo "Examples:"
  echo "  bash scripts/build_apk_matrix.sh"
  echo "  bash scripts/build_apk_matrix.sh --obfuscate --split-debug-info=build/symbols"
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/apk-matrix"
FLUTTER_OUTPUT_DIR="$ROOT_DIR/build/app/outputs/flutter-apk"
EXTRA_ARGS=("$@")

mkdir -p "$OUTPUT_DIR"

build_one() {
  local abi="$1"
  local target_platform="$2"
  local src_apk
  local dst_apk
  local output_name

  echo
  echo "==> Building $abi (plugins-on)"
  local cmd=(
    flutter build apk
    --release
    --split-per-abi
    --target-platform "$target_platform"
    --dart-define=ENABLE_PLUGINS=true
  )
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi
  "${cmd[@]}"

  src_apk="$FLUTTER_OUTPUT_DIR/app-$abi-release.apk"
  if [[ "$abi" == "armeabi-v7a" ]]; then
    output_name="v7a.apk"
  elif [[ "$abi" == "arm64-v8a" ]]; then
    output_name="v8a.apk"
  else
    output_name="${abi}.apk"
  fi
  dst_apk="$OUTPUT_DIR/$output_name"

  if [[ ! -f "$src_apk" ]]; then
    echo "ERROR: Expected APK not found: $src_apk" >&2
    exit 1
  fi

  cp "$src_apk" "$dst_apk"
  echo "Saved: $dst_apk"
}

build_one "armeabi-v7a" "android-arm"
build_one "arm64-v8a" "android-arm64"

echo
echo "Done. Output files:"
ls -lh "$OUTPUT_DIR"
