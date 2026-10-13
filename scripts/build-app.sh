#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
source "$project_dir/scripts/swift-env.sh"

signing_identity="${SIGNING_IDENTITY:--}"

/usr/bin/xcrun swift build --configuration release --arch arm64
binary_dir="$(/usr/bin/xcrun swift build --configuration release --arch arm64 --show-bin-path)"
app_path="$project_dir/build/Mouse Light Off.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
install -m 755 "$binary_dir/MouseLightOff" "$app_path/Contents/MacOS/MouseLightOff"
install -m 644 "$project_dir/Resources/MouseLightOff.icns" "$app_path/Contents/Resources/MouseLightOff.icns"
install -m 644 "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"

/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
signing_options=(--force --sign "$signing_identity" --identifier com.foxode.mouselightoff.app)
if [[ "$signing_identity" != "-" ]]; then
    # Direct distribution uses Hardened Runtime without App Sandbox or exceptions.
    signing_options+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${signing_options[@]}" "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf '\nBuilt: %s\n' "$app_path"
if [[ "$signing_identity" == "-" ]]; then
    printf '%s\n' 'Local ad hoc build. Copy to /Applications before granting permissions.'
else
    printf '%s\n' 'Signed release build. Notarize and staple before distribution.'
fi
