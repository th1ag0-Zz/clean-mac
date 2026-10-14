#!/bin/bash
set -euo pipefail

app_path=${1:-}
output_path=${2:-build/Clean-Mac.dmg}
volume_name="Clean Mac"

if [[ -z "$app_path" || ! -d "$app_path" || "$app_path" != *.app ]]; then
  echo "Uso: $0 '/caminho/Clean Mac.app' [arquivo.dmg]" >&2
  exit 2
fi

app_path=$(cd "$(dirname "$app_path")" && pwd)/$(basename "$app_path")
mkdir -p "$(dirname "$output_path")"
output_path=$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")

work_dir=$(mktemp -d /private/tmp/clean-mac-dmg.XXXXXX)
stage_dir="$work_dir/stage"
mount_dir="$work_dir/mount"
writable_image="$work_dir/writable.dmg"
mounted=0

cleanup() {
  if [[ "$mounted" == 1 ]]; then
    hdiutil detach "$mount_dir" -quiet || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$stage_dir" "$mount_dir"
ditto "$app_path" "$stage_dir/$(basename "$app_path")"
ln -s /Applications "$stage_dir/Applications"

hdiutil create -volname "$volume_name" -srcfolder "$stage_dir" \
  -format UDRW -ov "$writable_image" -quiet
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$mount_dir" \
  "$writable_image" -quiet
mounted=1

osascript - "$mount_dir" "$(basename "$app_path")" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  set appName to item 2 of argv
  set volumeFolder to (POSIX file mountPath) as alias
  tell application "Finder"
    open volumeFolder
    set installerWindow to container window of volumeFolder
    set current view of installerWindow to icon view
    set toolbar visible of installerWindow to false
    set statusbar visible of installerWindow to false
    set bounds of installerWindow to {160, 160, 760, 500}
    set viewOptions to icon view options of installerWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 14
    set position of item appName of volumeFolder to {160, 165}
    set position of item "Applications" of volumeFolder to {440, 165}
    update volumeFolder without registering applications
    delay 1
    close installerWindow
  end tell
end run
APPLESCRIPT

# Finder grava a apresentação da janela em .DS_Store no volume montado.
sync
hdiutil detach "$mount_dir" -quiet
mounted=0
hdiutil convert "$writable_image" -format UDZO -o "$output_path" -ov -quiet
hdiutil verify "$output_path" -quiet
echo "DMG criado: $output_path"
