#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app="$project_dir/dist/MouseBatteryBridge.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_dir/Info.plist")
dmg="$project_dir/dist/MouseBatteryBridge-$version.dmg"

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
