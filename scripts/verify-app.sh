#!/usr/bin/env bash
# Verify a mounted or CI-installed app without launching it or changing state.
set -euo pipefail
test "$#" = 3
app_path="$1"
expected_version="$2"
expected_cpu="$3"
[[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
[[ "$expected_cpu" = arm64 || "$expected_cpu" = x86_64 ]] || exit 1
test -d "$app_path"
test ! -L "$app_path"
plist="$app_path/Contents/Info.plist"
test -f "$plist"
test ! -L "$plist"
test "$(plutil -extract CFBundleIdentifier raw -o - "$plist")" = com.usagemonitor.local
test "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" = "$expected_version"
test "$(plutil -extract CFBundleExecutable raw -o - "$plist")" = TiboTattle
# Native and Electron report different bundle minimums; the cask still limits
# installation to the qualified macOS 14+ support floor for both architectures.
electron=0
if [[ "$expected_version" != 0.1.18 ]]; then
  ruby -e 'exit((ARGV[0].split(".").map(&:to_i) <=> [0, 1, 20]) == -1 ? 1 : 0)' "$expected_version"
  electron=1
fi
minimum_macos="$(plutil -extract LSMinimumSystemVersion raw -o - "$plist")"
if [[ "$electron" = 1 ]]; then
  [[ "$minimum_macos" = 12.0 || "$minimum_macos" = 12.0.0 ]] || exit 1
else
  [[ "$minimum_macos" = 14.0 || "$minimum_macos" = 14.0.0 ]] || exit 1
fi
executables=(Contents/MacOS/TiboTattle)
if [[ "$electron" = 1 ]]; then
  executables+=(Contents/MacOS/TiboTattleNativeHandover)
  test -f "$app_path/Contents/Resources/app.asar"
  test ! -L "$app_path/Contents/Resources/app.asar"
  test -f "$app_path/Contents/Frameworks/Electron Framework.framework/Electron Framework"
else
  executables+=(Contents/Resources/runtime/bin/node)
fi
for relative in "${executables[@]}"; do
  executable="$app_path/$relative"
  test -f "$executable"
  test ! -L "$executable"
  test -x "$executable"
  test "$(lipo -archs "$executable")" = "$expected_cpu"
done
if [[ "$electron" = 1 ]]; then
  credential="$app_path/Contents/Resources/native/macos-keychain.node"
  test -f "$credential"
  test ! -L "$credential"
  test "$(lipo -archs "$credential")" = "$expected_cpu"
fi
# Dependencies may be universal, but every bundled Mach-O must contain the
# native slice. A signed opposite-architecture helper/addon is not usable.
binary_list="$(mktemp "${TMPDIR:-/tmp}/tibotattle-binaries.XXXXXX")"
trap 'rm -f "$binary_list"' EXIT
find "$app_path" -type f -print0 > "$binary_list"
while IFS= read -r -d '' binary; do
  binary_kind="$(file -b "$binary")"
  case "$binary_kind" in
    *Mach-O*)
      binary_archs="$(lipo -archs "$binary")"
      case " $binary_archs " in
        *" $expected_cpu "*) ;;
        *) exit 1;;
      esac;;
  esac
done < "$binary_list"
rm -f "$binary_list"
trap - EXIT
codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
