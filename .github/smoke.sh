#!/usr/bin/env bash
# Emulator smoke test: install, launch, drive the login form offline (no real site), collect evidence.
# Fails only on install failure, a crash or the process dying; screenshots/UI dumps are reviewed by hand.
set -u
API=$1; PKG=com.alikarami.drooz; OUT=smoke-out; mkdir -p "$OUT"
APK=$(find artifact -name '*.apk' | head -1)
fail=0
say()  { echo "== $*"; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull -q /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1; }
key()  { adb shell input keyevent "$@"; sleep 1.5; }
alive() { adb shell pidof $PKG >/dev/null || { say "PROCESS NOT RUNNING after $1"; fail=1; }; }
texts() { grep -oE 'text="[^"]+"' "$OUT/$1.xml" 2>/dev/null | sed 's/^text=//' | tr '\n' ' '; echo; }

say "device: sdk=$(adb shell getprop ro.build.version.sdk) release=$(adb shell getprop ro.build.version.release) abi=$(adb shell getprop ro.product.cpu.abilist) leanback=$(adb shell pm list features | grep -c 'android.software.leanback$')"
say "apk: $APK"
adb install -r "$APK" 2>&1 | tail -1 | tee "$OUT/install.txt"
grep -q Success "$OUT/install.txt" || { say "INSTALL FAILED"; exit 1; }
adb shell dumpsys package $PKG | grep -E "versionName|minSdk" | head -2

run_case() { # name server user pass
  adb shell pm clear $PKG >/dev/null; adb logcat -c
  adb shell am start -W -n $PKG/.ui.MainActivity >/dev/null; sleep 10
  alive "launch ($1)"; shot "$1-0-launch"; say "$1 launch texts: $(texts "$1-0-launch")"
  key KEYCODE_DPAD_CENTER; adb shell input text "$2"; sleep 1; key KEYCODE_ENTER
  adb shell input text "$3"; sleep 1; key KEYCODE_ENTER
  adb shell input text "$4"; sleep 1; shot "$1-1-filled"; key KEYCODE_ENTER
  sleep 8; alive "submit ($1)"; shot "$1-2-result"; say "$1 result texts: $(texts "$1-2-result")"
  adb logcat -d > "$OUT/$1-logcat.txt"
}
run_case badaddr nodot smoke smoke          # client-side validation: expect «آدرس سایت معتبر نیست»
run_case nohost drooz-smoke.invalid smoke smoke   # DNS failure through OkHttp: expect «اتصال به سایت برقرار نشد»

adb logcat -d -b crash > "$OUT/crash.txt"
if [ -s "$OUT/crash.txt" ] && grep -q "$PKG" "$OUT/crash.txt"; then say "CRASH:"; cat "$OUT/crash.txt"; fail=1; fi
grep -hE "FATAL EXCEPTION|NoSuchMethodError|NoClassDefFoundError|VerifyError" "$OUT"/*-logcat.txt && fail=1

# Trusted CA roots of this Android version (public data) for an offline TLS chain check.
adb pull /system/etc/security/cacerts "$OUT/cacerts" >/dev/null 2>&1 && say "cacerts: $(ls "$OUT/cacerts" | wc -l) roots"
say "result: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
