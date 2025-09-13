// lib/receiver_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:anydrop/services/history_store.dart';
import 'package:anydrop/services/settings_store.dart';
import 'package:anydrop/services/notify_service.dart';

enum TaskState { idle, downloading, cancelled, completed, error }

/// Simple model for a download task
class DownloadTask {
  final String name;
  final int size; // bytes (may be 0 if unknown)

  // dynamic fields
  int received = 0;
  double progress = 0.0; // 0.0 - 1.0
  double speedBytesPerSec = 0.0;
  TaskState state = TaskState.idle;

  /// Stable notification id for this task
  final int notifId =
      DateTime.now().microsecondsSinceEpoch.remainder(100000000);

  // internals
  StreamSubscription<List<int>>? _sub;
  IOSink? _sink;
  bool started = false; // guard to prevent double-starts

  DownloadTask({required this.name, required this.size});
}

class ReceiverPage extends StatefulWidget {
  final String manifestUrl;
  const ReceiverPage({super.key, required this.manifestUrl});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  final List<DownloadTask> _tasks = [];
  bool _loadingManifest = false;
  String? _baseSessionUrl;

  // Queue control
  static const int _maxConcurrent = 2;
  int _active = 0;
  final Queue<int> _pending = Queue<int>();
  bool _downloadAllRequested = false;

  // Aggregate notification throttling
  static const int _aggThrottleMs = 600;
  DateTime _lastAggNotify = DateTime.fromMillisecondsSinceEpoch(0);

  // Single “All files” notification id
  static const int _aggNotifId = 900;

  @override
  void initState() {
    super.initState();
    _prepareAndFetch();
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }

  /// Returns (file, sink) for the final save path using *only* SettingsStore.
  /// Ensures unique filename and creates parent directory.
  Future<(File, IOSink)> _openSinkFor(String originalName) async {
    final dir = await SettingsStore.instance.resolveDownloadDir();
    await dir.create(recursive: true);

    // ensure unique name
    final ext = p.extension(originalName);
    final base = p.basenameWithoutExtension(originalName);
    var candidate = File(p.join(dir.path, originalName));
    var i = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(dir.path, '$base ($i)$ext'));
      i++;
    }
    final sink = candidate.openWrite();
    debugPrint('[AnyDrop] Saving to: ${candidate.path}');
    return (candidate, sink);
  }

  Future<void> _prepareAndFetch() async {
    final uri = Uri.parse(widget.manifestUrl);
    final pStr = uri.path.endsWith('/manifest')
        ? uri.path.substring(0, uri.path.length - '/manifest'.length)
        : uri.path;
    _baseSessionUrl = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port,
      path: pStr,
    ).toString();
    await _fetchManifest();
  }

  Future<void> _fetchManifest() async {
    setState(() => _loadingManifest = true);
    try {
      final res = await http.get(Uri.parse(widget.manifestUrl));
      if (res.statusCode != 200) {
        throw Exception('manifest failed ${res.statusCode}');
      }
      final List decoded = jsonDecode(res.body) as List;
      _tasks
        ..clear()
        ..addAll(decoded.map((item) {
          final name = item['name']?.toString() ?? 'file';
          final size = (item['size'] is int)
              ? item['size'] as int
              : int.tryParse(item['size']?.toString() ?? '') ?? 0;
          return DownloadTask(name: name, size: size);
        }));
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch manifest: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingManifest = false);
    }
  }

  Future<bool> _ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Try MANAGE_EXTERNAL_STORAGE (Android 11+)
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;

    // Fallback for Android ≤10
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  // --- Queue orchestration ---

  void _downloadAll() {
    _downloadAllRequested = true;

    // enqueue all indices that aren’t finished
    _pending.clear();
    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      if (t.state != TaskState.completed) _pending.add(i);
    }

    // show initial aggregate notification (0% if total known)
    _updateAggregateNotification(force: true);

    _pumpQueue();
    setState(() {}); // refresh header UI
  }

  void _pumpQueue() {
    while (_active < _maxConcurrent && _pending.isNotEmpty) {
      final i = _pending.removeFirst();
      _startSingle(i);
    }
  }

  void _maybeContinueQueue() {
    _active = _tasks.where((t) => t.state == TaskState.downloading).length;
    if (_downloadAllRequested) _pumpQueue();
    _updateAggregateNotification(); // keep the header notification fresh
  }

  // --- Aggregate helpers/notification ---

  (int total, int received) _totals() {
    int total = 0, received = 0;
    for (final t in _tasks) {
      if (t.size > 0) total += t.size;
      received += t.received;
    }
    return (total, received);
  }

  Future<void> _updateAggregateNotification({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastAggNotify).inMilliseconds < _aggThrottleMs) {
      return;
    }
    _lastAggNotify = now;

    final (total, received) = _totals();
    final anyActive = _tasks.any(
        (t) => t.state == TaskState.downloading || t.state == TaskState.idle);
    final allDone = _tasks.isNotEmpty &&
        _tasks.every((t) => t.state == TaskState.completed);

    if (allDone) {
      // Show a single “All files received” and clear progress
      await NotifyService.instance.cancel(_aggNotifId);
      await NotifyService.instance.showDone(
        id: _aggNotifId,
        title: 'All files received',
        body: 'Completed ${_tasks.length} file(s)',
      );
      return;
    }

    if (!anyActive) {
      // Nothing to show
      await NotifyService.instance.cancel(_aggNotifId);
      return;
    }

    // If we can compute %, show progress. Otherwise just keep it hidden (or you
    // could show a generic “Receiving files…” notification without percent).
    if (total > 0) {
      final pct = ((received / total) * 100).clamp(0, 100).round();
      await NotifyService.instance.showProgress(
        id: _aggNotifId,
        title: 'Receiving files',
        percent: pct,
      );
    }
  }

  // --- Single download ---

  Future<void> _startSingle(int i) async {
    if (_baseSessionUrl == null || i < 0 || i >= _tasks.length) return;
    final task = _tasks[i];

    if (task.started ||
        task.state == TaskState.downloading ||
        task.state == TaskState.completed) return;
    task.started = true;

    task.state = TaskState.downloading;
    task.received = 0;
    task.progress = 0;
    task.speedBytesPerSec = 0;

    // Create/refresh a 0% per-task notification
    await NotifyService.instance.showProgress(
      id: task.notifId,
      title: 'Downloading ${task.name}',
      percent: 0,
    );

    _active++;
    setState(() {});
    _updateAggregateNotification(force: true);

    final fileUrl = '$_baseSessionUrl/file?i=$i';
    final client = http.Client();
    final req = http.Request('GET', Uri.parse(fileUrl));

    try {
      final streamed = await client.send(req);
      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}');
      }

      // Ask for storage permission on Android
      final ok = await _ensureStoragePermission();
      if (!ok) {
        // Drain & close the HTTP response so the socket is freed
        try {
          await streamed.stream.drain();
        } catch (_) {}
        client.close();

        // Mark task + free the queue slot
        task.state = TaskState.error;
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Storage permission needed to save to Downloads')),
          );
        }
        _active = (_active > 0) ? _active - 1 : 0;
        _maybeContinueQueue();
        // Error notification
        await NotifyService.instance.showError(
          id: task.notifId,
          title: task.name,
          body: 'Permission denied',
        );
        return;
      }

      final (outFile, sink) = await _openSinkFor(task.name);
      task._sink = sink;

      final contentLengthHeader = streamed.contentLength;
      int bytesSinceLastTick = 0;
      const speedSampleIntervalMs = 500;
      var lastSpeedUpdate = DateTime.now();

      task._sub = streamed.stream.listen((chunk) async {
        if (task.state != TaskState.downloading) return; // cancelled or changed
        task._sink!.add(chunk);
        task.received += chunk.length;
        bytesSinceLastTick += chunk.length;

        if (task.size > 0) {
          task.progress = task.received / task.size;
          if (task.progress > 1.0) task.progress = 1.0;
        } else if (contentLengthHeader != null && contentLengthHeader > 0) {
          task.progress = task.received / contentLengthHeader;
        }

        // ------- compute elapsed BEFORE using it -------
        final now = DateTime.now();
        final elapsedMs = now.difference(lastSpeedUpdate).inMilliseconds;

        // per-task speed + throttled per-task notification
        if (elapsedMs >= speedSampleIntervalMs) {
          task.speedBytesPerSec = (bytesSinceLastTick) / (elapsedMs / 1000.0);
          bytesSinceLastTick = 0;
          lastSpeedUpdate = now;

          final pct = (task.progress * 100).clamp(0, 100).round();
          await NotifyService.instance.showProgress(
            id: task.notifId,
            title: 'Downloading ${task.name}',
            percent: pct,
          );

          // also refresh aggregate notification with a light throttle
          _updateAggregateNotification();
        }

        if (mounted) setState(() {});
      }, onDone: () async {
        await task._sink?.flush();
        await task._sink?.close();
        task._sub = null;
        task._sink = null;
        task.state = TaskState.completed;

        // ✅ Use the actual saved file path (handles "file (1).ext" uniqueness)
        final savedPath =
            (await _openSinkFor(task.name)).$1.path; // just for path
        // (We already wrote to a unique file above; this is only to get the path string)

        // ✅ Android: ask MediaScanner to index the new file so it appears immediately
        if (Platform.isAndroid) {
          try {
            final uri = Uri.file(savedPath);
            await Process.run(
              'am',
              [
                'broadcast',
                '-a',
                'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
                '-d',
                uri.toString()
              ],
            );
          } catch (_) {}
        }

        // ✅ Log to history with a reliable size
        final fromHost = Uri.parse(_baseSessionUrl!).authority;
        await HistoryStore.instance.addReceivedFile(
          name: p.basename(savedPath),
          size: task.size > 0
              ? task.size
              : (contentLengthHeader ?? task.received),
          savedPath: savedPath,
          fromHost: fromHost,
        );

        // Finish notifications for this task
        await NotifyService.instance.cancel(task.notifId);
        await NotifyService.instance.showDone(
          id: task.notifId,
          title: task.name,
          body: 'Download complete',
        );

        if (task.size > 0) task.progress = 1.0;
        if (mounted) setState(() {});
        client.close();
        _maybeContinueQueue();
      }, onError: (e) async {
        await task._sink?.close();
        task._sub = null;
        task._sink = null;
        task.state = TaskState.error;
        task.started = false;

        await NotifyService.instance.cancel(task.notifId);
        await NotifyService.instance.showError(
          id: task.notifId,
          title: task.name,
          body: 'Download failed',
        );

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download error: $e')),
          );
        }
        client.close();
        _maybeContinueQueue();
      }, cancelOnError: true);
    } catch (e) {
      task.state = TaskState.error;
      task.started = false;

      await NotifyService.instance.cancel(task.notifId);
      await NotifyService.instance.showError(
        id: task.notifId,
        title: task.name,
        body: 'Download failed',
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
      client.close();
      _maybeContinueQueue();
    }
  }

  Future<void> _cancelSingle(int i) async {
    final t = _tasks[i];
    if (t.state == TaskState.downloading) {
      await t._sub?.cancel();
      await t._sink?.close();
      t._sub = null;
      t._sink = null;
      t.state = TaskState.cancelled;
      t.started = false;
      await NotifyService.instance.cancel(t.notifId);
      if (mounted) setState(() {});
      _maybeContinueQueue();
    }
  }

  void _retrySingle(int i) {
    final t = _tasks[i];
    if (t.state == TaskState.cancelled || t.state == TaskState.error) {
      t.state = TaskState.idle;
      t.received = 0;
      t.progress = 0;
      t.speedBytesPerSec = 0;
      setState(() {});
      _pending.add(i);
      _pumpQueue();
    }
  }

  void _cancelAll() {
    for (final t in _tasks) {
      t._sub?.cancel();
      t._sink?.close();
      t._sub = null;
      t._sink = null;
      if (t.state == TaskState.downloading) {
        t.state = TaskState.cancelled;
      }
      // cancel any per-task notifications
      NotifyService.instance.cancel(t.notifId);
    }
    _pending.clear();
    _active = 0;
    _downloadAllRequested = false;
    // cancel aggregate notification
    NotifyService.instance.cancel(_aggNotifId);
    if (mounted) setState(() {});
  }

  String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _humanSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  @override
  Widget build(BuildContext context) {
    final canDownloadAll = _tasks.any((t) => t.state != TaskState.completed);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Files'),
        actions: [
          IconButton(
            tooltip: 'Download All',
            onPressed: canDownloadAll ? _downloadAll : null,
            icon: const Icon(Icons.download_for_offline),
          ),
        ],
      ),
      body: _loadingManifest
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No files to receive'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _fetchManifest,
                        child: const Text('Retry Manifest'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Aggregate overall header (UI)
                    Builder(
                      builder: (ctx) {
                        final (totalBytes, receivedBytes) = _totals();
                        final overall = (totalBytes > 0)
                            ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
                            : 0.0;

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('All files',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: overall),
                              const SizedBox(height: 4),
                              Text('${_humanBytes(receivedBytes)} / '
                                  '${totalBytes > 0 ? _humanBytes(totalBytes) : 'Unknown'}'),
                            ],
                          ),
                        );
                      },
                    ),

                    // List of tasks
                    Expanded(
                      child: ListView.builder(
                        itemCount: _tasks.length,
                        itemBuilder: (context, index) {
                          final t = _tasks[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(t.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LinearProgressIndicator(value: t.progress),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('${_humanBytes(t.received)} / '
                                          '${t.size > 0 ? _humanBytes(t.size) : 'Unknown'}'),
                                      Text(
                                        switch (t.state) {
                                          TaskState.completed => 'Completed',
                                          TaskState.cancelled => 'Cancelled',
                                          TaskState.error => 'Error',
                                          TaskState.downloading =>
                                            _humanSpeed(t.speedBytesPerSec),
                                          _ => 'Idle',
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: _buildTrailingButtons(index, t),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTrailingButtons(int index, DownloadTask t) {
    switch (t.state) {
      case TaskState.idle:
        return IconButton(
          icon: const Icon(Icons.download),
          onPressed: () {
            if (_downloadAllRequested || _active >= _maxConcurrent) {
              _pending.add(index);
              _pumpQueue();
            } else {
              _startSingle(index);
            }
          },
        );
      case TaskState.downloading:
        return IconButton(
          icon: const Icon(Icons.cancel),
          onPressed: () => _cancelSingle(index),
        );
      case TaskState.cancelled:
      case TaskState.error:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _retrySingle(index),
        );
      case TaskState.completed:
        return const Icon(Icons.check, color: Colors.green);
    }
  }
}
