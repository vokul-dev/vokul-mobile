#!/usr/bin/env bash
#
# Generates the android/ and ios/ folders with `flutter create`, then applies
# every platform change Vokul needs:
#
#   Android  - USE_BIOMETRIC permission
#            - FlutterFragmentActivity (required by local_auth)
#            - FLAG_SECURE (no screenshots, blank app-switcher preview)
#            - minSdk 23 (required by flutter_secure_storage + biometrics)
#            - allowBackup=false (the vault must not ride along in cloud backup)
#   iOS      - NSFaceIDUsageDescription
#            - iOS 13 deployment target
#
# Re-running it is safe: every patch checks whether it has already been applied.
#
# Usage:   ./setup.sh [org]
# Example: ./setup.sh com.yourname

set -euo pipefail

ORG="${1:-com.example}"
MIN_SDK=23
IOS_TARGET="13.0"

cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH. Install it from https://docs.flutter.dev/get-started/install and run this again."
  exit 1
fi

echo "==> Generating platform folders (org: $ORG)"
# flutter create ALWAYS rewrites lib/main.dart and test/widget_test.dart to its
# stock counter-app template, even in an existing project - it only leaves
# other files alone. Snapshot the real ones first and restore them after, so
# the app you actually built survives.
SNAPSHOT="$(mktemp -d)"
cp -r lib "$SNAPSHOT/lib"
[ -d test ] && cp -r test "$SNAPSHOT/test"
cp pubspec.yaml "$SNAPSHOT/pubspec.yaml"

flutter create --org "$ORG" --project-name vokul_mobile --platforms=android,ios .

echo "==> Restoring app source (flutter create overwrites lib/main.dart and test/widget_test.dart)"
rm -rf lib test
cp -r "$SNAPSHOT/lib" lib
[ -d "$SNAPSHOT/test" ] && cp -r "$SNAPSHOT/test" test
cp "$SNAPSHOT/pubspec.yaml" pubspec.yaml
rm -rf "$SNAPSHOT"
# flutter create also seeds test/widget_test.dart pointing at the counter app;
# it must not survive the restore above if it somehow reappears.
rm -f test/widget_test.dart

echo "==> Fetching packages"
flutter pub get

# --------------------------------------------------------------------- Android

MANIFEST="android/app/src/main/AndroidManifest.xml"

echo "==> Patching $MANIFEST"
python3 - "$MANIFEST" <<'PY'
import re, sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

if "USE_BIOMETRIC" not in src:
    src = re.sub(
        r"(<manifest[^>]*>\n)",
        r'\1    <uses-permission android:name="android.permission.USE_BIOMETRIC" />\n',
        src,
        count=1,
    )

# A password vault has no business in Google's automatic cloud backup.
if "android:allowBackup" not in src:
    src = re.sub(
        r"(<application\b)",
        r'\1\n        android:allowBackup="false"',
        src,
        count=1,
    )

open(path, "w", encoding="utf-8").write(src)
print("    manifest ok")
PY

echo "==> Rewriting MainActivity"
MAIN_ACTIVITY="$(find android/app/src/main -name 'MainActivity.kt' -o -name 'MainActivity.java' | head -n 1)"
if [ -z "$MAIN_ACTIVITY" ]; then
  echo "    MainActivity not found - skipping"
else
  PACKAGE="$(grep -m1 '^package' "$MAIN_ACTIVITY" | sed 's/package //; s/;//' | tr -d '\r')"
  KOTLIN_PATH="$(dirname "$MAIN_ACTIVITY")/MainActivity.kt"
  rm -f "$MAIN_ACTIVITY"
  cat > "$KOTLIN_PATH" <<EOF
package $PACKAGE

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * FlutterFragmentActivity, not FlutterActivity: local_auth shows the biometric
 * prompt as a fragment and silently fails without it.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Keeps passwords out of screenshots, screen recordings, and the
        // thumbnail Android renders in the app switcher.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
EOF
  echo "    $KOTLIN_PATH ($PACKAGE)"
fi

echo "==> Setting minSdk to $MIN_SDK"
for GRADLE in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$GRADLE" ] || continue
  python3 - "$GRADLE" "$MIN_SDK" <<'PY'
import re, sys

path, min_sdk = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()

# Handles both `minSdk = flutter.minSdkVersion` (kts) and
# `minSdkVersion flutter.minSdkVersion` (groovy), plus literal numbers.
patterns = [
    (r"minSdk\s*=\s*[^\n]+", f"minSdk = {min_sdk}"),
    (r"minSdkVersion\s+[^\n]+", f"minSdkVersion {min_sdk}"),
]
for pattern, replacement in patterns:
    if re.search(pattern, src):
        src = re.sub(pattern, replacement, src, count=1)
        break
else:
    print(f"    could not find a minSdk line in {path} - set it to {min_sdk} by hand")

open(path, "w", encoding="utf-8").write(src)
print(f"    {path}")
PY
done

# ------------------------------------------------------------------------- iOS

PLIST="ios/Runner/Info.plist"
if [ -f "$PLIST" ]; then
  echo "==> Patching $PLIST"
  python3 - "$PLIST" <<'PY'
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

if "NSFaceIDUsageDescription" not in src:
    entry = (
        "\t<key>NSFaceIDUsageDescription</key>\n"
        "\t<string>Unlock your vault without typing the master password.</string>\n"
    )
    marker = "</dict>\n</plist>"
    src = src.replace(marker, entry + marker, 1)
    open(path, "w", encoding="utf-8").write(src)
    print("    Face ID usage description added")
else:
    print("    already present")
PY
fi

PODFILE="ios/Podfile"
if [ -f "$PODFILE" ]; then
  echo "==> Setting iOS deployment target to $IOS_TARGET"
  python3 - "$PODFILE" "$IOS_TARGET" <<'PY'
import re, sys

path, target = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
src = re.sub(r"^#?\s*platform :ios.*$", f"platform :ios, '{target}'", src, count=1, flags=re.M)
open(path, "w", encoding="utf-8").write(src)
print(f"    {path}")
PY
fi

echo
echo "Done. Next:"
echo "  flutter test      # includes the CLI vault-compatibility checks"
echo "  flutter run"
