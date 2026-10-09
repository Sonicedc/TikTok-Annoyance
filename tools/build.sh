#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d /private/tmp/tiktokblocker-build.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
cp "$project_dir/Makefile" "$project_dir/control" "$project_dir/TikTokBlocker.plist" "$project_dir/Tweak.xm" "$project_dir/Preferences.m" "$project_dir/Preferences.h" "$project_dir/SettingsUI.xm" "$build_dir/"
export CLANG_MODULE_CACHE_PATH="$build_dir/modules"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
make -C "$build_dir" package
mkdir -p "$project_dir/packages"
cp "$build_dir"/packages/*.deb "$project_dir/packages/"
