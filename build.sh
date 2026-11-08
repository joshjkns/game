#!/usr/bin/env bash
# Exports the Linux x86_64 build to build/linux/UNWOUND.x86_64.
# Needs Godot 4.7 and its export templates. Set GODOT if it isn't on PATH:
#   GODOT=/path/to/godot ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot not found. Install it or run: GODOT=/path/to/godot ./build.sh" >&2
	exit 1
fi

mkdir -p build/linux
"$GODOT" --headless --import
"$GODOT" --headless --export-release "Linux" build/linux/UNWOUND.x86_64
chmod +x build/linux/UNWOUND.x86_64
echo "Built build/linux/UNWOUND.x86_64"
