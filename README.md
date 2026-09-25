# Vokul Mobile

A Flutter port of [Vokul](https://github.com/DevX-Dragon/vokul), the local-first
CLI password manager. Same vault, same crypto, same rules — just with thumbs
instead of a terminal.

The `vault.vk` file is **byte-compatible** with the Python CLI. Copy it from
your laptop to your phone and it opens with the same master password, and back
again after editing.

## Getting it running

```bash
bash setup.sh com.yourname     # your reverse-domain org
flutter test                   # includes the vault-compatibility checks
flutter run
```

`setup.sh` runs `flutter create` to generate `android/` and `ios/`, then applies
every platform change this app needs:

| | |
| --- | --- |
| Android | `USE_BIOMETRIC` permission |
| | `FlutterFragmentActivity` — `local_auth`'s prompt is a fragment and fails silently without it |
| | `FLAG_SECURE` — no screenshots, no vault thumbnail in the app switcher |
| | `minSdk 23`, required by `flutter_secure_storage` and biometrics |
| | `allowBackup="false"` — the vault should not ride along in cloud backup |
| iOS | `NSFaceIDUsageDescription` |
| | deployment target 13.0 |

Running it twice is safe; each patch checks whether it already applied.
`setup.sh` also snapshots `lib/`, `test/` and `pubspec.yaml` before calling
`flutter create` and restores them afterward — `flutter create` unconditionally
overwrites `lib/main.dart` and `test/widget_test.dart` with its own counter-app
template even in an existing project, so without that guard your first
`flutter run` would build the stock demo instead of Vokul. On Windows, run the
script under Git Bash or WSL, or apply "Platform setup" below by hand.

The platform folders are generated rather than committed because `flutter
create` produces them for your Flutter version, Xcode project format and
package name — a checked-in `.xcodeproj` or gradle wrapper goes stale fast.
`flutter create` only fills in what is missing, so `lib/`, `test/` and
`pubspec.yaml` are untouched.

Tests live in `test/compatibility_test.dart`: a real `vault.vk` written by the
Python CLI, asserted to decrypt here. If a change ever breaks interoperability,
that test fails before anyone's vault does.

## What carried over from the CLI

| CLI | App |
| --- | --- |
| `vokul init` | First-run screen |
| `vokul add` / `edit` | Add service, edit service |
| `vokul get` | Tap a service; copy clears the clipboard after 15s |
| `vokul list` / `search` | Vault list with live search |
| `vokul totp` | Live code with a 30-second countdown ring |
| `vokul history` | Expandable history, three passwords deep |
| `vokul generate` | Generator screen and in-form sheet |
| `vokul delete` | Delete from the service screen |
| `vokul destruct` | Settings › Destroy this vault (type DESTROY) |
| Persistent lockout | Same `.vault.vk.lock` file, shown as a countdown |
| Automatic backups | Same `backups/vault.vk.bak_*`, pruned to the last 10 |
| Self-healing vault | Same backup recovery, with a banner explaining it |

Added for the phone: biometric unlock, auto-lock when backgrounded, and
import/export of the vault file.

## Layout

```
lib/
  core/            no Flutter imports — pure Dart, matches vokul/core/*.py
    argon2_params.dart   Argon2id cost parameters (keep in sync with params.py)
    vault_engine.dart    Argon2id + AES-256-GCM  (crypto.py)
    vault_manager.dart   file format, backups, recovery  (vault.py)
    throttle.dart        brute-force lockout  (__main__.py)
    totp.dart            RFC 6238, pyotp defaults
    password_generator.dart
  state/
    vault_controller.dart  single ChangeNotifier the screens listen to
  ui/                      screens and theme
```

### File format

Unchanged from the CLI:

```json
{ "salt": "<base64, 16 bytes>",
  "nonce": "<base64, 12 bytes>",
  "ciphertext": "<base64, AES-256-GCM ciphertext followed by the 16-byte tag>" }
```

Plaintext inside is `{"service": {"pass": [current, ...history], "totp": secret|null}}`.
The older bare-list shape still loads, same as the CLI's loader.

Key derivation is Argon2id, t=3, m=64 MiB, p=4, 32-byte output. Those numbers
live in one file; changing any of them makes vaults unreadable by the CLI.

## Making unlock faster

Argon2id at 64 MiB is deliberately expensive, and `package:cryptography`
implements it in pure Dart. On a mid-range Android phone expect roughly one to
three seconds per unlock. It runs on a background isolate, so the UI stays
responsive, and the app shows why it is waiting.

If that is too slow for you, `_deriveKeyWorker` in `lib/core/vault_engine.dart`
is the only place to change. Any standard Argon2id implementation — for example
`package:hashlib`, or a native binding over FFI — interoperates, as long as the
parameters stay identical.

## Platform setup (what `setup.sh` does, if you prefer to do it by hand)

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

`local_auth` needs the host activity to be a `FlutterFragmentActivity`, so edit
`MainActivity.kt`:

```kotlin
import io.flutter.embedding.android.FlutterFragmentActivity
class MainActivity : FlutterFragmentActivity()
```

Blocking screenshots and hiding the app-switcher preview is worth adding in
`MainActivity.onCreate`:

```kotlin
window.setFlags(
    WindowManager.LayoutParams.FLAG_SECURE,
    WindowManager.LayoutParams.FLAG_SECURE,
)
```

`flutter_secure_storage` needs `minSdkVersion 18` or higher in
`android/app/build.gradle`.

**iOS** (`ios/Runner/Info.plist`):

```xml
<key>NSFaceIDUsageDescription</key>
<string>Unlock your vault without typing the master password.</string>
```

## Security notes, stated plainly

- The master password is never written to disk by the app itself. Turning on
  biometric unlock is the exception: it stores the password in the Android
  Keystore / iOS Keychain, gated behind a biometric check. It is off by default.
- Dart strings are immutable and garbage-collected, so plaintext passwords can
  linger in memory until collected. The derived key is a `Uint8List` and gets
  zeroed on lock. A determined attacker with a rooted device and a memory
  dumper is outside what this design defends against.
- Clipboard contents are readable by other apps while they sit there. Copies
  clear after 15 seconds, and only if the value is still the one this app put
  there.
- The lockout is a deterrent against someone tapping at your phone, not against
  an attacker with the vault file. That is what Argon2id is for.

## License

MIT, matching the upstream project.
