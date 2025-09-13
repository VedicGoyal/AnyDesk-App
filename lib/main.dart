// lib/main.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_apps/device_apps.dart';

import 'package:anydrop/backend/server.dart';
import 'package:anydrop/pages/receiver_page.dart';
import 'package:anydrop/pages/scan_qr_page.dart';
import 'package:anydrop/services/history_store.dart';
import 'package:anydrop/widgets/app_drawer.dart';
import 'package:anydrop/services/settings_store.dart';
import 'package:anydrop/pages/onboarding_page.dart';
import 'package:anydrop/pages/apps_chooser_page.dart';
import 'package:anydrop/net/peer_beacon.dart';
import 'package:anydrop/pages/receive_discover_page.dart';
import 'package:anydrop/services/notify_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HistoryStore.instance.init();
  await SettingsStore.instance.init();
  await NotifyService.instance.init(); // <-- ADD
  await NotifyService.instance.ensurePermission(); // <-- Android 13+ prompt
  runApp(const AnyDropApp());
}

class AnyDropApp extends StatelessWidget {
  const AnyDropApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'AnyDrop',
        themeMode: mode,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark,
        ),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = SettingsStore.instance;
      if (s.firstRun && mounted) {
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingPage()),
        );
        if (ok == true) {
          await s.markOnboarded();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => const HomePage();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AnyDropServer? _server;
  bool _isSharing = false;
  String? _shareLink;
  PeerAnnouncer? _announcer;

  // Sender-side progress
  int _sentBytes = 0;
  int _totalBytes = 0;
  bool _totalKnown = true;
  double get _progress => _totalBytes > 0 ? _sentBytes / _totalBytes : 0.0;

  // Used to rebuild the QR dialog live
  VoidCallback? _dialogRebuilder;

  @override
  void dispose() {
    _stopSharing();
    _announcer?.stop(); // defensive
    super.dispose();
  }

  // Prefer LAN/hotspot IPv4 addresses; skip oddballs (192.0.*, 169.254.*, emulator alias)
  Future<String?> _localIpAddress() async {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    bool isWifiLike(String n) {
      final s = n.toLowerCase();
      return s.contains('wlan') ||
          s.contains('wifi') ||
          s.contains('ap') ||
          s.contains('eth');
    }

    bool isTunnel(String n) {
      final s = n.toLowerCase();
      return s.contains('tun') ||
          s.contains('ppp') ||
          s.contains('rmnet') ||
          s.contains('ccmni') ||
          s.contains('pdp') ||
          s.contains('vpn');
    }

    bool is192_168(InternetAddress a) => a.address.startsWith('192.168.');
    bool is172_priv(InternetAddress a) {
      final p = a.address.split('.');
      if (p.length != 4) return false;
      final b0 = int.tryParse(p[0]) ?? 0;
      final b1 = int.tryParse(p[1]) ?? 0;
      return b0 == 172 && b1 >= 16 && b1 <= 31;
    }

    bool is10_priv(InternetAddress a) => a.address.startsWith('10.');
    bool isBad(InternetAddress a) =>
        a.address.startsWith('169.254.') ||
        a.address.startsWith('192.0.') ||
        a.address == '10.0.2.15';

    final wifi192 = <InternetAddress>[];
    final wifi172 = <InternetAddress>[];
    final wifi10 = <InternetAddress>[];
    final other192 = <InternetAddress>[];
    final other172 = <InternetAddress>[];
    final other10 = <InternetAddress>[];
    final fallback = <InternetAddress>[];

    for (final iface in ifaces) {
      if (isTunnel(iface.name)) continue;
      for (final a in iface.addresses) {
        if (a.isLoopback || a.type != InternetAddressType.IPv4) continue;
        if (isBad(a)) continue;

        final w = isWifiLike(iface.name);
        if (is192_168(a)) {
          (w ? wifi192 : other192).add(a);
          continue;
        }
        if (is172_priv(a)) {
          (w ? wifi172 : other172).add(a);
          continue;
        }
        if (is10_priv(a)) {
          (w ? wifi10 : other10).add(a);
          continue;
        }
        fallback.add(a);
      }
    }

    final ordered = [
      ...wifi192,
      ...wifi172,
      ...other192,
      ...other172,
      ...wifi10,
      ...other10,
      ...fallback
    ];
    return ordered.isNotEmpty ? ordered.first.address : null;
  }

  // ------------------ SEND: shared helpers ------------------

  Future<bool> _ensureReadStorage() async {
    if (!Platform.isAndroid) return true;
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<void> _startSharingWithFiles(List<File> files) async {
    if (files.isEmpty) return;

    _sentBytes = 0;
    _totalBytes = 0;
    _totalKnown = true;
    for (final f in files) {
      try {
        final len = await f.length();
        if (len > 0) {
          _totalBytes += len;
        } else {
          _totalKnown = false;
        }
      } catch (_) {
        _totalKnown = false;
      }
    }

    final server = AnyDropServer();

    server.onBytesSent = (bytes) {
      _sentBytes += bytes;
      if (mounted) setState(() {});
      _dialogRebuilder?.call();
    };

    final port = await server.start(files);
    final ip = await _localIpAddress();

    if (ip == null) {
      await server.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No network available')),
      );
      return;
    }

    // Start LAN announcer with new constructor (localIp:)
    _announcer?.stop(); // safety
    _announcer = PeerAnnouncer(
      localIp: InternetAddress(ip), // ← CHANGED
      name: SettingsStore.instance.displayName.value,
      port: port,
      sessionPath: server.sessionPath,
    );
    await _announcer!.start();

    final link = "http://$ip:$port${server.sessionPath}/manifest";

    await HistoryStore.instance.addSentSession(
      files: files,
      shareLink: link,
    );

    if (!mounted) return;
    setState(() {
      _server = server;
      _isSharing = true;
      _shareLink = link;
    });

    _showShareDialog(link);
  }

  // ------------------ SEND: pickers ------------------

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // allow bytes fallback if path is missing
    );
    if (result == null || result.files.isEmpty) return;

    final files = <File>[];

    for (final pf in result.files) {
      if (pf.path != null) {
        files.add(File(pf.path!));
      } else if (pf.bytes != null) {
        final tmp = await getTemporaryDirectory();
        final out = File(p.join(tmp.path, pf.name));
        await out.writeAsBytes(pf.bytes!, flush: true);
        files.add(out);
      }
    }

    await _startSharingWithFiles(files);
  }

  Future<void> _pickFolder() async {
    if (Platform.isAndroid && !await _ensureReadStorage()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission required')),
      );
      return;
    }

    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose a folder to share',
    );
    if (dirPath == null) return;

    final root = Directory(dirPath);
    if (!await root.exists()) return;

    final files = <File>[];
    await for (final ent in root.list(recursive: true, followLinks: false)) {
      if (ent is File) {
        final name = p.basename(ent.path);
        if (!name.startsWith('.')) files.add(ent); // skip hidden
      }
    }

    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files found in this folder')),
      );
      return;
    }

    await _startSharingWithFiles(files);
  }

  Future<void> _pickApps() async {
    final apps = await DeviceApps.getInstalledApplications(
      includeAppIcons: true,
      includeSystemApps: false,
      onlyAppsWithLaunchIntent: true,
    );

    if (!mounted) return;

    final selected = await Navigator.push<List<Application>>(
      context,
      MaterialPageRoute(builder: (_) => AppsChooserPage(apps: apps)),
    );

    if (!mounted || selected == null || selected.isEmpty) return;

    final files = <File>[];
    for (final a in selected) {
      final path = a.apkFilePath; // non-null String in device_apps
      if (path.isNotEmpty) {
        files.add(File(path));
      }
    }

    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not locate APK files')),
      );
      return;
    }

    if (Platform.isAndroid && !await _ensureReadStorage()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission required')),
      );
      return;
    }

    await _startSharingWithFiles(files);
  }

  // ------------------ RECEIVE ------------------

  Future<void> _openReceiveSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Receive Files',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.paste),
                        label: const Text('Paste link'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _promptAndOpenManifest();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ScanQrPage()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _promptAndOpenManifest() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste manifest link'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://<sender-ip>:<port>/<session>/manifest',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Open')),
        ],
      ),
    );

    if (!mounted || url == null || url.isEmpty) return;

    if (!url.contains('/manifest')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is not a manifest link')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReceiverPage(manifestUrl: url)),
    );
  }

  // ------------------ Server lifecycle & dialogs ------------------

  Future<void> _stopSharing() async {
    // Stop HTTP server
    try {
      await _server?.stop();
    } catch (_) {}
    _server = null;

    // Stop rebuilding the share dialog
    _dialogRebuilder = null;

    // Stop UDP announcer (do this outside setState)
    try {
      await _announcer?.stop();
    } catch (_) {}
    _announcer = null;

    if (!mounted) return;
    setState(() {
      _isSharing = false;
      _shareLink = null;
      _sentBytes = 0;
      _totalBytes = 0;
      _totalKnown = true;
    });
  }

  void _showShareDialog(String link) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            _dialogRebuilder = () {
              if (Navigator.of(ctx).mounted) {
                setLocalState(() {});
              }
            };

            return AlertDialog(
              title: const Text("Share this link"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(link),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: QrImageView(
                      data: link,
                      errorStateBuilder: (c, e) =>
                          const Text("Could not generate QR"),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_totalKnown && _totalBytes > 0) ...[
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 8),
                    Text(
                      '${(_progress * 100).toStringAsFixed(1)}%  '
                      '(${_humanBytes(_sentBytes)} / ${_humanBytes(_totalBytes)})',
                    ),
                  ] else ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text('Sent ${_humanBytes(_sentBytes)}'),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text("Close"),
                ),
                TextButton(
                  onPressed: () async {
                    await _stopSharing();
                    if (context.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text("Stop Sharing"),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _dialogRebuilder = null;
    });
  }

  // ------------------ helpers ------------------

  String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // ------------------ UI ------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AnyDrop")),
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const _HelpDialog(),
          );
        },
        label: const Text('Help'),
        icon: const Icon(Icons.help_outline),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.upload),
              label: const Text("Send Files"),
              onPressed: _isSharing ? null : _openSendSheet,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text("Receive Files"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReceiveDiscoverPage()),
                );
              },
            ),
            const SizedBox(height: 16),
            if (_isSharing)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sharing session',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_shareLink != null) ...[
                        const SizedBox(height: 6),
                        SelectableText(_shareLink!),
                      ],
                      const SizedBox(height: 8),
                      if (_totalKnown && _totalBytes > 0) ...[
                        LinearProgressIndicator(value: _progress),
                        const SizedBox(height: 4),
                        Text(
                          '${(_progress * 100).toStringAsFixed(1)}%  '
                          '(${_humanBytes(_sentBytes)} / ${_humanBytes(_totalBytes)})',
                        ),
                      ] else ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 4),
                        Text('Sent ${_humanBytes(_sentBytes)}'),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSendSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Send from',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.folder),
                      label: const Text('Folder'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pickFolder();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.insert_drive_file),
                      label: const Text('Files'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pickFiles();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.android),
                label: const Text('Apps (APK)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickApps();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Help', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              '1. Before sharing, make sure both devices are on the same Wi-Fi, or one device has a mobile hotspot turned on.\n\n'
              '2. On the receiver, tap “Receive Files” and either scan the QR shown on the sender or paste the manifest link.',
              style: textStyle,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
