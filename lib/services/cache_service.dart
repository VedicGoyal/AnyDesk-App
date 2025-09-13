import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CacheService {
  CacheService._();
  static final instance = CacheService._();

  /// Clears temporary caches your app controls (safe & sandboxed).
  Future<void> clear() async {
    // 1) OS temp cache (Flutter cache dir)
    final tmp = await getTemporaryDirectory();
    await _deleteDir(tmp);

    // 2) App support cache (if any)
    try {
      final support = await getApplicationSupportDirectory();
      await _deleteDir(support);
    } catch (_) {
      // Not all platforms have support dir — ignore
    }

    // NOTE: We intentionally do NOT touch downloads/history folders.
    // Those are user data, not cache.
  }

  Future<void> _deleteDir(Directory dir) async {
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Some files may be in use; ignore and move on.
      }
    }
    // Re-create so app still has a place to write
    try {
      await dir.create(recursive: true);
    } catch (_) {}
  }
}
