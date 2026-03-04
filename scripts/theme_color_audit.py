#!/usr/bin/env python3
"""Audit hardcoded colors and legacy color tokens in Dart files.

Usage:
  python scripts/theme_color_audit.py
  python scripts/theme_color_audit.py --path lib/screens/home
  python scripts/theme_color_audit.py --json
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Iterable


RULES: list[tuple[str, re.Pattern[str], str]] = [
    (
        "legacy-token",
        re.compile(r"\bAppColors\.(textPrimary|textSecondary|textTertiary|textHint|textDisabled)\b"),
        "Prefer adaptive tokens: primaryText/secondaryText/inactiveText/disabledText.",
    ),
    (
        "hardcoded-white-black",
        re.compile(r"\bColors\.(white|black|white10|white12|white24|white38|white54|white60|white70|white87)\b"),
        "Avoid direct white/black shades in UI text/background; use AppColors semantic tokens.",
    ),
    (
        "hardcoded-color-hex",
        re.compile(r"\bColor\(0x[0-9A-Fa-f]{8}\)"),
        "Move to AppColors token (or keep only for brand/asset-specific color with comment).",
    ),
    (
        "inline-alpha",
        re.compile(r"\.withValues\(alpha:\s*[0-9.]+\)"),
        "Prefer centralized alpha/token in AppColors or SettingsService.",
    ),
]

IGNORE_DIR_NAMES = {
    ".git",
    ".dart_tool",
    "build",
    "ios",
    "android",
    "linux",
    "macos",
    "windows",
}


def iter_dart_files(root: Path) -> Iterable[Path]:
    for path in root.rglob("*.dart"):
        if any(part in IGNORE_DIR_NAMES for part in path.parts):
            continue
        yield path


def audit_file(path: Path) -> list[dict]:
    results: list[dict] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return results

    for i, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        for kind, pattern, suggestion in RULES:
            if pattern.search(line):
                results.append(
                    {
                        "file": str(path),
                        "line": i,
                        "kind": kind,
                        "text": stripped[:220],
                        "suggestion": suggestion,
                    }
                )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit hardcoded/legacy color usage.")
    parser.add_argument(
        "--path",
        default="lib",
        help="Target folder or file to audit (default: lib).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable JSON output.",
    )
    args = parser.parse_args()

    target = Path(args.path)
    if not target.exists():
        raise SystemExit(f"Path not found: {target}")

    files = [target] if target.is_file() and target.suffix == ".dart" else list(iter_dart_files(target))
    findings: list[dict] = []
    for file in files:
        findings.extend(audit_file(file))

    findings.sort(key=lambda x: (x["file"], x["line"], x["kind"]))

    if args.json:
        print(json.dumps(findings, ensure_ascii=False, indent=2))
        return 0

    if not findings:
        print("No findings.")
        return 0

    by_kind: dict[str, int] = {}
    for f in findings:
        by_kind[f["kind"]] = by_kind.get(f["kind"], 0) + 1

    print("Theme Color Audit Findings")
    print("=" * 26)
    print(f"Total: {len(findings)}")
    for kind, count in sorted(by_kind.items()):
        print(f"- {kind}: {count}")
    print()

    for f in findings:
        print(f'{f["file"]}:{f["line"]} [{f["kind"]}]')
        print(f'  {f["text"]}')
        print(f'  -> {f["suggestion"]}')

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
