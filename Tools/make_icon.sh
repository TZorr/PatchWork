#!/bin/bash
#
# make_icon.sh
# PatchWork — Tools
#
# Redraws PatchWork/Assets.xcassets/AppIcon.appiconset from
# Tools/MakeIcon.swift, and icon.png beside it.
#
# Not a build phase. The icon changes about once in the life of an app, and
# ENABLE_USER_SCRIPT_SANDBOXING is on — a script phase writing into the source
# tree would need an exemption to express something that almost never changes.
#
# Usage: ./Tools/make_icon.sh
#

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/make-icon"
swiftc -O Tools/MakeIcon.swift -o "$OUT"

echo "==> Drawing"
"$OUT" "$PWD"
