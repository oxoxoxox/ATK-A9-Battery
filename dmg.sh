#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app="$project_dir/dist/MouseBatteryBridge.app"
dmg="$project_dir/dist/MouseBatteryBridge.dmg"

"$project_dir/build.sh"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

hdiutil create \
  -volname "MouseBatteryBridge" \
  -srcfolder "$staging" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$dmg" >/dev/null
echo "$dmg"
