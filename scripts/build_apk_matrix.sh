#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Build 4 APK variants: v7a/v8a x plugins on/off"
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
  local plugin_enabled="$3"
  local plugin_tag
  local src_apk
  local dst_apk

  if [[ "$plugin_enabled" == "true" ]]; then
    plugin_tag="plugins-on"
  else
    plugin_tag="plugins-off"
  fi

  echo
  echo "==> Building $abi ($plugin_tag)"
  local cmd=(
    flutter build apk
    --release
    --split-per-abi
    --target-platform "$target_platform"
    --dart-define=ENABLE_PLUGINS="$plugin_enabled"
  )
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    cmd+=("${EXTRA_ARGS[@]}")
  fi
  "${cmd[@]}"

  src_apk="$FLUTTER_OUTPUT_DIR/app-$abi-release.apk"
  dst_apk="$OUTPUT_DIR/bili_tv_${abi}_${plugin_tag}.apk"

  if [[ ! -f "$src_apk" ]]; then
    echo "ERROR: Expected APK not found: $src_apk" >&2
    exit 1
  fi

  cp "$src_apk" "$dst_apk"
  echo "Saved: $dst_apk"
}

build_one "armeabi-v7a" "android-arm" "true"
build_one "armeabi-v7a" "android-arm" "false"
build_one "arm64-v8a" "android-arm64" "true"
build_one "arm64-v8a" "android-arm64" "false"

echo
echo "Done. Output files:"
ls -lh "$OUTPUT_DIR"
