#!/usr/bin/env bash
# Emulator smoke test: install, launch, drive the login form offline (no real site), collect evidence.
# Fails on: install failure, a crash/process death, or a login error message that does not appear.
set -u
API=$1; PKG=com.alikarami.drooz; OUT=smoke-out; mkdir -p "$OUT"
APK=$(find artifact -name '*.apk' | head -1)
fail=0
say()  { echo "== $*"; }
dump() { adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull -q /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; dump "$1"; }
key()  { adb shell input keyevent "$@"; sleep 1.5; }
alive() { adb shell pidof $PKG >/dev/null || { say "PROCESS NOT RUNNING after $1"; fail=1; }; }
texts() { grep -oE 'text="[^"]+"' "$OUT/$1.xml" 2>/dev/null | sed 's/^text=//' | tr '\n' ' '; echo; }

say "device: sdk=$(adb shell getprop ro.build.version.sdk) release=$(adb shell getprop ro.build.version.release) abi=$(adb shell getprop ro.product.cpu.abilist) leanback=$(adb shell pm list features | grep -c 'android.software.leanback$') screen=$(adb shell wm size | tail -1) density=$(adb shell wm density | tail -1)"
# No soft keyboard: key events then go straight to the focused field, like a hardware keyboard.
for ime in $(adb shell ime list -s); do adb shell ime disable "$ime" >/dev/null; done
say "enabled IMEs after disabling: $(adb shell ime list -s | wc -l)"
adb install -r "$APK" 2>&1 | tail -1 | tee "$OUT/install.txt"
grep -q Success "$OUT/install.txt" || { say "INSTALL FAILED"; exit 1; }
adb shell dumpsys package $PKG | grep -E "versionName|minSdk" | head -2

run_case() { # name server user pass expected-text
  adb shell pm clear $PKG >/dev/null; adb logcat -c
  adb shell am start -W -n $PKG/.ui.MainActivity >/dev/null; sleep 10
  alive "launch ($1)"; shot "$1-0-launch"; say "$1 launch: $(texts "$1-0-launch")"
  key KEYCODE_DPAD_CENTER; adb shell input text "$2"; sleep 1; key KEYCODE_ENTER
  adb shell input text "$3"; sleep 1; key KEYCODE_ENTER
  adb shell input text "$4"; sleep 1; shot "$1-1-filled"; say "$1 filled: $(texts "$1-1-filled")"
  key KEYCODE_ENTER; sleep 8
  alive "submit ($1)"; shot "$1-2-result"; say "$1 result: $(texts "$1-2-result")"
  if grep -q "$5" "$OUT/$1-2-result.xml" 2>/dev/null; then say "$1: expected message shown"; else say "$1: EXPECTED MESSAGE MISSING ($5)"; fail=1; fi
  adb logcat -d > "$OUT/$1-logcat.txt"
}
run_case badaddr nodot smoke smoke "آدرس سایت معتبر نیست"             # client-side validation
run_case nohost drooz-smoke.invalid smoke smoke "اتصال به سایت برقرار نشد"  # DNS failure through OkHttp

adb logcat -d -b crash > "$OUT/crash.txt"
if grep -q "$PKG" "$OUT/crash.txt"; then say "CRASH:"; cat "$OUT/crash.txt"; fail=1; fi
grep -hE "FATAL EXCEPTION" "$OUT"/*-logcat.txt && fail=1
say "class-loading notes (informational): $(grep -hoE 'Failed resolution of: [^ ;]+' "$OUT"/*-logcat.txt | sort | uniq -c | tr '\n' ' ')"

# Trusted CA roots of this Android version (public data) for an offline TLS chain check.
adb pull /system/etc/security/cacerts "$OUT/cacerts" >/dev/null 2>&1 && say "cacerts: $(ls "$OUT/cacerts" | wc -l) roots"
say "result: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
