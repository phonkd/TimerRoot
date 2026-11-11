#!/usr/bin/env bash

# Start the installed Shizuku server when a stale external starter does not
# pass the native-library path required by a newer Shizuku server.
set -euo pipefail

ADB="${ADB:-adb}"

if ! command -v "$ADB" >/dev/null 2>&1; then
    printf 'error: adb not found; set ADB to its absolute path\n' >&2
    exit 1
fi

if ! "$ADB" get-state >/dev/null 2>&1; then
    printf 'error: no authorized Android device is available over adb\n' >&2
    exit 1
fi

if "$ADB" shell 'pidof shizuku_server >/dev/null 2>&1'; then
    printf 'Shizuku is already running.\n'
    exit 0
fi

# Variables in this block are deliberately expanded by the Android shell.
# shellcheck disable=SC2016
"$ADB" shell '
    apk=$(pm path moe.shizuku.privileged.api | sed -n "s/^package://p" | head -n 1)
    abi=$(getprop ro.product.cpu.abi)
    case "$abi" in
        arm64-v8a) lib_abi=arm64 ;;
        armeabi-v7a|armeabi) lib_abi=arm ;;
        x86_64) lib_abi=x86_64 ;;
        x86) lib_abi=x86 ;;
        *) lib_abi=unsupported ;;
    esac
    lib=${apk%/*}/lib/$lib_abi

    if [ -z "$apk" ] || [ ! -f "$lib/librish.so" ]; then
        printf "error: cannot locate Shizuku and its %s native library\n" "$abi" >&2
        exit 1
    fi

    setsid env CLASSPATH="$apk" LD_LIBRARY_PATH="$lib" \
        /system/bin/app_process \
        -Djava.class.path="$apk" \
        -Dshizuku.library.path="$lib" \
        /system/bin \
        --nice-name=shizuku_server \
        rikka.shizuku.server.ShizukuService \
        >/data/local/tmp/shizuku-manual.log 2>&1 </dev/null &
'

sleep 2

if ! "$ADB" shell 'pidof shizuku_server >/dev/null 2>&1'; then
    printf 'error: Shizuku did not start; device log follows:\n' >&2
    "$ADB" shell 'cat /data/local/tmp/shizuku-manual.log 2>/dev/null' >&2
    exit 1
fi

printf 'Shizuku is running. Open TimerRoot and allow Shizuku access if prompted.\n'
