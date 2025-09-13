import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  // ── Keys ────────────────────────────────────────────────────────────────────
  static const _kThemeKey = 'anydrop.theme.v1';
  static const _kDownloadDirKey = 'anydrop.downloadDir.v1';
  static const _kDisplayNameKey = 'anydrop.displayName.v1';
  static const _kAvatarIdKey = 'anydrop.avatarId.v1'; // legacy/simple
  static const _kOnboardSeenKey = 'anydrop.onboardSeen.v1';

  // NEW for maker:
  static const _kAvatarPngPathKey = 'anydrop.avatarPngPath.v1';
  static const _kAvatarConfigKey = 'anydrop.avatarConfig.v1';

  late SharedPreferences _sp;
  bool _loaded = false;

  // ── THEME ───────────────────────────────────────────────────────────────────
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  // ── DOWNLOAD DIRECTORY ──────────────────────────────────────────────────────
  final ValueNotifier<String?> downloadDirPath = ValueNotifier<String?>(null);

  // ── PROFILE ────────────────────────────────────────────────────────────────
  final ValueNotifier<String> displayName = ValueNotifier<String>('User');

  /// legacy/simple avatar index (still used as fallback)
  final ValueNotifier<int> avatarId = ValueNotifier<int>(0);

  /// path to rendered avatar PNG (preferred at runtime)
  final ValueNotifier<String?> avatarPngPath = ValueNotifier<String?>(null);

  /// opaque config text from the maker widget (JSON, etc.)
  final ValueNotifier<String?> avatarConfig = ValueNotifier<String?>(null);

  // ── ONBOARDING ──────────────────────────────────────────────────────────────
  bool get onboardSeen => _sp.getBool(_kOnboardSeenKey) ?? false;
  bool get firstRun => !onboardSeen;
  Future<void> markOnboarded() async => _sp.setBool(_kOnboardSeenKey, true);

  // ── INIT ────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_loaded) return;
    _sp = await SharedPreferences.getInstance();

    // theme
    switch (_sp.getString(_kThemeKey)) {
      case 'light':
        themeMode.value = ThemeMode.light;
        break;
      case 'dark':
        themeMode.value = ThemeMode.dark;
        break;
      default:
        themeMode.value = ThemeMode.system;
    }

    // download dir
    downloadDirPath.value = _sp.getString(_kDownloadDirKey);

    // profile
    displayName.value = _sp.getString(_kDisplayNameKey) ?? 'User';
    avatarId.value = _sp.getInt(_kAvatarIdKey) ?? 0;

    // maker
    avatarPngPath.value = _sp.getString(_kAvatarPngPathKey);
    avatarConfig.value = _sp.getString(_kAvatarConfigKey);

    _loaded = true;
  }

  Future<void> load() => init(); // back-compat

  // ── Theme / Downloads ───────────────────────────────────────────────────────
  Future<void> setThemeMode(ThemeMode m) async {
    themeMode.value = m;
    await _sp.setString(
        _kThemeKey,
        switch (m) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          _ => 'system',
        });
  }

  Future<void> setCustomDownloadDir(String? path) async {
    final cleaned = (path != null && path.isNotEmpty) ? path : null;
    downloadDirPath.value = cleaned;
    cleaned == null
        ? await _sp.remove(_kDownloadDirKey)
        : await _sp.setString(_kDownloadDirKey, cleaned);
  }

  bool get hasCustomDownloadDir =>
      downloadDirPath.value != null && downloadDirPath.value!.isNotEmpty;

  Future<Directory> resolveDownloadDir() async {
    if (hasCustomDownloadDir) return Directory(downloadDirPath.value!);
    if (Platform.isAndroid)
      return Directory('/storage/emulated/0/Download/AnyDrop');
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final d = await getDownloadsDirectory();
      if (d != null) return Directory(p.join(d.path, 'AnyDrop'));
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'AnyDrop'));
  }

  Future<String> platformDefaultLabel() async {
    if (Platform.isAndroid) return '/storage/emulated/0/Download/AnyDrop';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final d = await getDownloadsDirectory();
      return d != null ? p.join(d.path, 'AnyDrop') : 'Downloads/AnyDrop';
    }
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'AnyDrop');
  }

  // ── Profile mutators ────────────────────────────────────────────────────────
  Future<void> setDisplayName(String name) async {
    final v = name.trim().isEmpty ? 'User' : name.trim();
    displayName.value = v;
    await _sp.setString(_kDisplayNameKey, v);
  }

  /// legacy/simple
  Future<void> setAvatarId(int id) async {
    avatarId.value = id;
    await _sp.setInt(_kAvatarIdKey, id);
  }

  /// Preferred: save maker output (PNG path + config)
  Future<void> setAvatarMakerResult({
    required String pngPath,
    String? config,
  }) async {
    avatarPngPath.value = pngPath;
    avatarConfig.value = config;
    await _sp.setString(_kAvatarPngPathKey, pngPath);
    if (config == null) {
      await _sp.remove(_kAvatarConfigKey);
    } else {
      await _sp.setString(_kAvatarConfigKey, config);
    }
  }
}
