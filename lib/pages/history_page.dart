// lib/history_page.dart (or views/drawer/history_page.dart if you moved it)
import 'dart:io' show File; // ← needed for File(...)

import 'package:flutter/material.dart';
import 'package:anydrop/services/history_store.dart'; // <- your HistoryStore file path
import 'package:flutter/services.dart'; // for Clipboard
import 'package:open_filex/open_filex.dart'; // for opening files
import 'package:share_plus/share_plus.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late Future<List<HistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _future = _load();
  }

  Future<List<HistoryEntry>> _load() async {
    try {
      final list = await HistoryStore.instance.all();
      return list;
    } catch (e) {
      // We’ll rethrow so FutureBuilder can show an error UI
      throw Exception('Failed to load history: $e');
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _clear() async {
    await HistoryStore.instance.clear();
    if (!mounted) return;
    setState(() {
      _future = _load(); // refresh UI
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.download_done), text: 'Received'),
            Tab(icon: Icon(Icons.upload_file), text: 'Sent'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear history?'),
                  content: const Text(
                      'This will remove all sent & received entries.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true) {
                await _clear();
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _future = _load();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final all = snap.data ?? const [];
          final received = all
              .where((e) => e.type == HistoryType.received)
              .toList(growable: false);
          final sent = all
              .where((e) => e.type == HistoryType.sent)
              .toList(growable: false);

          Widget buildList(
              List<HistoryEntry> list, IconData icon, Color color) {
            if (list.isEmpty) {
              return const Center(child: Text('No entries yet'));
            }
            return RefreshIndicator(
              onRefresh: () async {
                setState(() => _future = _load());
                await _future;
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (ctx, i) {
                  final e = list[i];
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_humanBytes(e.size)} • ${e.peer}\n${e.pathOrLink}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      // quick, locale-respecting time
                      TimeOfDay.fromDateTime(e.ts).format(context),
                    ),
                    onTap: () async {
                      if (e.type == HistoryType.received) {
                        final f = File(e.pathOrLink);

                        // 1) Check if file exists
                        if (!await f.exists()) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('File not found:\n${e.pathOrLink}')),
                            );
                          }
                          return;
                        }

                        // 2) Try to open with default app
                        final result = await OpenFilex.open(e.pathOrLink);

                        // 3) If it worked, we’re done. Otherwise show a bottom sheet with fallback actions.
                        if (result.type != ResultType.done && context.mounted) {
                          String why;
                          switch (result.type) {
                            case ResultType.noAppToOpen:
                              why = 'No app installed to open this file type.';
                              break;
                            case ResultType.permissionDenied:
                              why = 'Permission denied while opening the file.';
                              break;
                            case ResultType.fileNotFound:
                              why = 'The file was not found on disk.';
                              break;
                            case ResultType.error:
                              why = 'Open failed: ${result.message}';
                              break;
                            default:
                              why = 'Could not open the file.';
                          }
                          // Show quick info
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(why)),
                          );

                          // Fallback actions
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.ios_share),
                                    title: const Text('Share file'),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      await Share.shareXFiles(
                                          [XFile(e.pathOrLink)]);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.content_copy),
                                    title: const Text('Copy path'),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      await Clipboard.setData(
                                          ClipboardData(text: e.pathOrLink));
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('Path copied')),
                                        );
                                      }
                                    },
                                  ),
                                  // Optional: quick delete from history (doesn’t delete file)
                                  // You can wire this to a proper remove() API later.
                                  // ListTile(
                                  //   leading: const Icon(Icons.delete_outline),
                                  //   title: const Text('Remove from history'),
                                  //   onTap: () async {
                                  //     Navigator.pop(ctx);
                                  //     // TODO: call your HistoryStore remove(e) when you add it
                                  //   },
                                  // ),
                                ],
                              ),
                            ),
                          );
                        }
                      } else {
                        // SENT: Copy share link
                        await Clipboard.setData(
                            ClipboardData(text: e.pathOrLink));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Link copied to clipboard')),
                          );
                        }
                      }
                    },
                  );
                },
              ),
            );
          }

          return TabBarView(
            controller: _tab,
            children: [
              buildList(received, Icons.download_done, Colors.green),
              buildList(sent, Icons.upload_file, Colors.blue),
            ],
          );
        },
      ),
    );
  }
}
