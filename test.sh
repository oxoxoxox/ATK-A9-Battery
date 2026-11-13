#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
out="$project_dir/dist/CompxCodecTests"
mkdir -p "$project_dir/dist"
swiftc \
  "$project_dir/Sources/Battery/"*.swift \
  "$project_dir/Sources/HID/"*.swift \
  "$project_dir/Sources/Devices/"**/*.swift \
  "$project_dir/Sources/Log/MBLog.swift" \
  "$project_dir/Sources/UI/StatusModel.swift" \
  "$project_dir/Sources/Settings/AppSettings.swift" \
  "$project_dir/Sources/UI/MenuBarButton.swift" \
  "$project_dir/Tests/CompxCodecTests.swift" \
  "$project_dir/Tests/StatusModelTests.swift" \
  "$project_dir/Tests/SettingsTests.swift" \
  "$project_dir/Tests/MenuBarButtonTests.swift" \
  "$project_dir/Tests/main.swift" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework IOKit \
  -framework SwiftUI \
  -o "$out"
"$out"
