#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
app="$project_dir/dist/MouseBatteryBridge.app"
signing_identity=${CODE_SIGN_IDENTITY:--}

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$project_dir/Info.plist" "$app/Contents/Info.plist"

# --- App icon: 从 Assets.xcassets/AppIcon.appiconset 生成 AppIcon.icns ---
icon_src="$project_dir/Assets.xcassets/AppIcon.appiconset"
icon_tmp="$(mktemp -d)"
trap 'rm -rf "$icon_tmp"' EXIT
mkdir -p "$icon_tmp/AppIcon.iconset"

# 标准 macOS iconset 需要的尺寸: 16/32/128/256/512 (各含 1x 与 @2x)
# 优先直接拷贝 assetset 中已有的成品 PNG，缺失的尺寸从 1024 主图缩放生成
for size in 16 32 128 256 512; do
  double=$((size * 2))
  if [[ -f "$icon_src/$size.png" ]]; then
    cp "$icon_src/$size.png" "$icon_tmp/AppIcon.iconset/icon_${size}x${size}.png"
  else
    sips -z "$size" "$size" "$icon_src/1024.png" \
      --out "$icon_tmp/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  fi
  if [[ -f "$icon_src/$double.png" ]]; then
    cp "$icon_src/$double.png" "$icon_tmp/AppIcon.iconset/icon_${size}x${size}@2x.png"
  else
    sips -z "$double" "$double" "$icon_src/1024.png" \
      --out "$icon_tmp/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  fi
done

iconutil -c icns "$icon_tmp/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

setopt null_glob
swift_files=("$project_dir"/Sources/**/*.swift)
if (( ${#swift_files[@]} == 0 )); then
  echo "no Swift sources under Sources/" >&2
  exit 1
fi

swiftc "${swift_files[@]}" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework IOKit \
  -framework CoreFoundation \
  -framework MultipeerConnectivity \
  -framework ServiceManagement \
  -o "$app/Contents/MacOS/MouseBatteryBridge"

codesign --force --deep --sign "$signing_identity" "$app"
echo "$app"
