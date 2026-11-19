#!/bin/bash
set -euo pipefail

destination="/Applications/FlickerGuard.app"
work_dir=$(mktemp -d "/Applications/.FlickerGuard-install.XXXXXX")

cleanup() {
    if [[ -e "$work_dir/previous.app" || -L "$work_dir/previous.app" ]] && [[ ! -e "$destination" && ! -L "$destination" ]]; then
        if ! mv "$work_dir/previous.app" "$destination"; then
            printf 'Unable to restore the previous app. It is saved at %s/previous.app\n' "$work_dir" >&2
            return 1
        fi
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

is_running() {
    local result=0
    pgrep -u "$UID" -x FlickerGuard >/dev/null || result=$?
    if ((result > 1)); then
        printf 'Unable to check whether FlickerGuard is running.\n' >&2
        exit "$result"
    fi
    return "$result"
}

printf 'Downloading the latest published FlickerGuard release…\n'
curl --fail --location --show-error --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 300 \
    https://github.com/tcrouzet/FlickerGuard/releases/latest/download/FlickerGuard.app.zip \
    --output "$work_dir/app.zip"
ditto -x -k "$work_dir/app.zip" "$work_dir/unpacked"
app="$work_dir/unpacked/FlickerGuard.app"
[[ -d "$app" && ! -L "$app" && -x "$app/Contents/MacOS/FlickerGuard" ]] || {
    printf 'The download does not contain FlickerGuard.app.\n' >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == com.tcrouzet.FlickerGuard ]] || {
    printf 'Unexpected application identifier.\n' >&2
    exit 1
}
codesign --verify --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")

if is_running; then
    printf 'Quitting FlickerGuard…\n'
    pkill -TERM -u "$UID" -x FlickerGuard
    for ((attempt=0; attempt<50; attempt++)); do
        if ! is_running; then break; fi
        sleep 0.2
    done
fi
if is_running; then
    printf 'FlickerGuard is still running. Quit it from its menu and try again.\n' >&2
    exit 1
fi

printf 'Resetting FlickerGuard Accessibility authorization…\n'
tccutil reset Accessibility com.tcrouzet.FlickerGuard

if [[ -e "$destination" || -L "$destination" ]]; then
    mv "$destination" "$work_dir/previous.app"
fi
mv "$app" "$destination"
open "$destination"
printf 'FlickerGuard %s installed in %s and launched.\n' "$version" "$destination"
printf 'Allow FlickerGuard again in System Settings → Privacy & Security → Accessibility.\n'
