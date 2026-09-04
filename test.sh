#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
out="$project_dir/dist/CompxCodecTests"
mkdir -p "$project_dir/dist"
swiftc \
  "$project_dir/Sources/Battery/BatteryReading.swift" \
  "$project_dir/Sources/Devices/Compx/CompxCodec.swift" \
  "$project_dir/Tests/CompxCodecTests.swift" \
  "$project_dir/Tests/main.swift" \
  -target arm64-apple-macos13.0 \
  -o "$out"
"$out"
