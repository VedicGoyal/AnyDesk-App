// lib/history_store.dart
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

enum HistoryType { sent, received }

class HistoryEntry {
  final HistoryType type;
  final String name;
  final int size;
  final String pathOrLink; // save path (received) OR share link (sent)
  final String peer; // sender IP/host (received) OR "self" (sent)
  final DateTime ts;

  HistoryEntry({
    required this.type,
    required this.name,
    required this.size,
    required this.pathOrLink,
    required this.peer,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'name': name,
        'size': size,
        'pathOrLink': pathOrLink,
        'peer': peer,
        'ts': ts.toIso8601String(),
      };

  static HistoryEntry fromJson(Map<String, dynamic> m) {
    return HistoryEntry(
      type: (m['type'] == 'received') ? HistoryType.received : HistoryType.sent,
      name: m['name'] ?? 'file',
      size: (m['size'] is int)
          ? m['size'] as int
          : int.tryParse('${m['size']}') ?? 0,
      pathOrLink: m['pathOrLink'] ?? '',
      peer: m['peer'] ?? '',
      ts: DateTime.tryParse(m['ts'] ?? '') ?? DateTime.now(),
    );
  }
}

class HistoryStore {
  HistoryStore._();
  static final HistoryStore instance = HistoryStore._();

  static const _kKey = 'anydrop.history.v1';

  SharedPreferences? _sp;
  List<HistoryEntry> _cache = [];

  /// MUST be called before runApp() (on both real device and emulator)
  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    await _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    _sp ??= await SharedPreferences.getInstance();
    if (_cache.isNotEmpty) return;
    final raw = _sp!.getString(_kKey);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return;
    }
    final List decoded = jsonDecode(raw) as List;
    _cache = decoded
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<HistoryEntry>> all() async {
    await _ensureLoaded();
    // newest first
    final list = [..._cache]..sort((a, b) => b.ts.compareTo(a.ts));
    return list;
  }

  Future<void> _persist() async {
    _sp ??= await SharedPreferences.getInstance();
    final s = jsonEncode(_cache.map((e) => e.toJson()).toList());
    await _sp!.setString(_kKey, s);
  }

  /// Call on sender: record a session (one entry per file)
  Future<void> addSentSession({
    required List<File> files,
    required String shareLink,
  }) async {
    await _ensureLoaded();
    final now = DateTime.now();
    for (final f in files) {
      final name =
          f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'file';
      int size = 0;
      try {
        size = await f.length();
      } catch (_) {}
      _cache.add(HistoryEntry(
        type: HistoryType.sent,
        name: name,
        size: size,
        pathOrLink: shareLink,
        peer: 'self',
        ts: now,
      ));
    }
    await _persist();
  }

  /// Call on receiver: record a single received file
  Future<void> addReceivedFile({
    required String name,
    required int size,
    required String savedPath,
    required String fromHost, // ip:port or host
  }) async {
    await _ensureLoaded();
    _cache.add(HistoryEntry(
      type: HistoryType.received,
      name: name,
      size: size,
      pathOrLink: savedPath,
      peer: fromHost,
      ts: DateTime.now(),
    ));
    await _persist();
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _cache.clear();
    await _persist();
  }
}
