import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../core/exceptions.dart';
import '../core/throttle.dart';
import '../core/vault_engine.dart';
import '../core/vault_manager.dart';

enum VaultStatus { loading, empty, locked, unlocked }

/// Single source of truth for the app. Screens listen to this.
class VaultController extends ChangeNotifier {
  static const Duration clipboardTtl = Duration(seconds: 15);
  static const String _biometricKey = 'vokul.master';

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  late final VaultEngine _engine = VaultEngine();
  late VaultManager _manager;
  late Throttle _throttle;

  VaultStatus status = VaultStatus.loading;
  String? notice;
  String query = '';
  Duration autoLockAfter = const Duration(minutes: 2);

  Timer? _clipboardTimer;
  String? _clipboardValue;

  VaultManager get manager => _manager;
  File get vaultFile => _manager.file;
  Throttle get throttle => _throttle;

  List<String> get services =>
      query.isEmpty ? _manager.listServices() : _manager.searchServices(query);

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}vokul');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}vault.vk');

    _manager = VaultManager(file: file, engine: _engine);
    _throttle = Throttle(Throttle.lockFileFor(file));

    status = await _manager.exists() ? VaultStatus.locked : VaultStatus.empty;
    notifyListeners();
  }

  // ---------------------------------------------------------------- unlocking

  Future<void> createVault(String masterPassword) async {
    await _manager.createNewVault(masterPassword);
    await _throttle.clear();
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// Throws [ThrottlingError] during a cooldown and [VaultError] on a bad
  /// password. Both are rendered inline on the unlock screen.
  Future<void> unlock(String masterPassword) async {
    final cooldown = await _throttle.cooldownRemaining();
    if (cooldown > Duration.zero) {
      throw ThrottlingError(
        'Too many failed attempts. Try again in ${cooldown.inSeconds}s.',
        cooldown,
      );
    }

    try {
      await _manager.loadAndDecrypt(masterPassword);
    } on VaultError {
      await _throttle.recordFailure();
      rethrow;
    }

    await _throttle.clear();
    notice = _manager.lastRecoveryNotice;
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  void lock() {
    _engine.lock();
    query = '';
    notice = null;
    clearClipboardNow();
    status = VaultStatus.locked;
    notifyListeners();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  // --------------------------------------------------------------- biometrics

  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> biometricsAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> biometricUnlockEnabled() async =>
      await _secureStorage.read(key: _biometricKey) != null;

  /// Stores the master password in the platform keystore/keychain. The vault
  /// file itself stays encrypted with Argon2id either way — this only shortcuts
  /// typing, and it is off unless the user turns it on.
  Future<void> enableBiometricUnlock(String masterPassword) async {
    final ok = await _localAuth.authenticate(
      localizedReason: 'Confirm it is you before saving the master password',
      options: const AuthenticationOptions(stickyAuth: true),
    );
    if (!ok) throw const VaultError('Biometric check was cancelled.');
    await _secureStorage.write(key: _biometricKey, value: masterPassword);
  }

  Future<void> disableBiometricUnlock() =>
      _secureStorage.delete(key: _biometricKey);

  Future<void> unlockWithBiometrics() async {
    final stored = await _secureStorage.read(key: _biometricKey);
    if (stored == null) {
      throw const VaultError('Biometric unlock is not set up.');
    }
    final ok = await _localAuth.authenticate(
      localizedReason: 'Unlock your vault',
      options: const AuthenticationOptions(stickyAuth: true),
    );
    if (!ok) throw const VaultError('Biometric check failed.');
    await unlock(stored);
  }

  // ------------------------------------------------------------------- record

  VaultRecord? record(String service) => _manager.getSecret(service);

  Future<void> saveService({
    required String service,
    String? originalService,
    String? password,
    String? totpSecret,
    bool removeTotp = false,
  }) async {
    if (originalService != null && originalService != service) {
      _manager.renameService(originalService, service);
    }
    _manager.setSecret(service, password: password, totpSecret: totpSecret);
    if (removeTotp) _manager.clearTotp(service);
    await _manager.save();
    notifyListeners();
  }

  Future<void> deleteService(String service) async {
    _manager.deleteSecret(service);
    await _manager.save();
    notifyListeners();
  }

  void search(String value) {
    query = value;
    notifyListeners();
  }

  // ---------------------------------------------------------------- clipboard

  /// Copies a secret and wipes it again after [clipboardTtl], the same way
  /// `vokul get` does on the desktop.
  Future<void> copySecret(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _clipboardValue = value;
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(clipboardTtl, clearClipboardNow);
  }

  Future<void> clearClipboardNow() async {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    final pending = _clipboardValue;
    _clipboardValue = null;
    if (pending == null) return;
    // Only clear if our value is still there, so we never wipe something the
    // user copied from another app in the meantime.
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == pending) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  // ------------------------------------------------------------ file transfer

  /// Hands the raw encrypted vault to the share sheet — it is useless without
  /// the master password, so this is safe to send to a desktop.
  Future<File> exportVaultFile() async => vaultFile;

  /// Replaces the local vault with one picked from storage, after backing the
  /// current one up.
  Future<void> importVaultFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final picked = result?.files.single;
    if (picked == null) return;

    final bytes = picked.bytes ??
        (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null) {
      throw const VaultStorageError('Could not read the selected file.');
    }

    await _manager.backupVault();
    await vaultFile.writeAsBytes(bytes, flush: true);
    await _throttle.clear();
    _engine.lock();
    status = VaultStatus.locked;
    notice = 'Imported a vault. Unlock it with its master password.';
    notifyListeners();
  }

  Future<void> destruct() async {
    await _manager.destruct();
    await _throttle.clear();
    await disableBiometricUnlock();
    await clearClipboardNow();
    status = VaultStatus.empty;
    notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    super.dispose();
  }
}

/// Single app-wide instance. Screens use `ListenableBuilder(listenable: vault)`.
final VaultController vault = VaultController();
