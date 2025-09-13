// lib/pages/receive_discover_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:anydrop/net/peer_beacon.dart';
import 'package:anydrop/pages/receiver_page.dart';
import 'package:anydrop/pages/scan_qr_page.dart';

class ReceiveDiscoverPage extends StatefulWidget {
  const ReceiveDiscoverPage({super.key});

  @override
  State<ReceiveDiscoverPage> createState() => _ReceiveDiscoverPageState();
}

class _ReceiveDiscoverPageState extends State<ReceiveDiscoverPage> {
  final _scanner = PeerScanner();
  StreamSubscription<List<PeerInfo>>? _sub;

  List<PeerInfo> _peers = [];
  bool _timedOut = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _startScanner();
  }

  void _startScanner() {
    _timedOut = false;
    _peers = [];
    _timeoutTimer?.cancel();

    _scanner.start();
    _sub?.cancel();
    _sub = _scanner.stream.listen((list) {
      if (!mounted) return;
      setState(() {
        _peers = list;
      });
    });

    // After 8s, if nothing found, show hint card
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _peers.isEmpty) {
        setState(() => _timedOut = true);
      }
    });
    setState(() {}); // update UI immediately when restarting
  }

  Future<void> _refresh() async {
    await _scanner.stop();
    _startScanner();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _sub?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _pasteLink() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste manifest link'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: 'http://<ip>:<port>/<session>/manifest'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Open')),
        ],
      ),
    );
    if (!mounted || url == null || url.isEmpty) return;
    if (!url.contains('/manifest')) {
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

  @override
  Widget build(BuildContext context) {
    final hasPeers = _peers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          IconButton(
            tooltip: 'Scan QR',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanQrPage()),
              );
            },
          ),
          IconButton(
            tooltip: 'Paste link',
            icon: const Icon(Icons.link),
            onPressed: _pasteLink,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: hasPeers
                ? _PeerList(
                    key: const ValueKey('list'),
                    peers: _peers,
                    onTap: (p) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ReceiverPage(manifestUrl: p.manifestUrl),
                      ),
                    ),
                  )
                : _timedOut
                    ? _NoPeersHint(
                        key: const ValueKey('hint'),
                        onRetry: _refresh,
                      )
                    : _SearchingSection(
                        key: const ValueKey('search'),
                        onCancel: () => Navigator.pop(context),
                        onRetry: _refresh,
                      ),
          ),
        ),
      ),
    );
  }
}

class _SearchingSection extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  const _SearchingSection({
    super.key,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _PulsingCircle(),
        const SizedBox(height: 16),
        const Text('Searching for nearby senders…'),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ],
    );
  }
}

// replace the _PulsingCircle with this new widget
class _PulsingCircle extends StatefulWidget {
  const _PulsingCircle();

  @override
  State<_PulsingCircle> createState() => _PulsingCircleState();
}

class _PulsingCircleState extends State<_PulsingCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value; // 0..1
          return Stack(
            alignment: Alignment.center,
            children: [
              _ring(color, t),
              _ring(color, (t + 0.5) % 1.0), // second ripple, offset
              // central solid disk
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.2),
                ),
              ),
              Icon(
                Icons.search,
                size: 36,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(Color color, double t) {
    final size = 64.0 + (120.0 * t); // expands outward
    final opacity = (1 - t).clamp(0.0, 1.0); // fades as it grows
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.12 * opacity),
        border: Border.all(color: color.withOpacity(0.28 * opacity), width: 2),
      ),
    );
  }
}

class _NoPeersHint extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoPeersHint({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_tethering_off, size: 56),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'No peers found.\nMake sure the sender is sharing and both devices are on the same Wi-Fi or hotspot.',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

class _PeerList extends StatelessWidget {
  final List<PeerInfo> peers;
  final ValueChanged<PeerInfo> onTap;
  const _PeerList({super.key, required this.peers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: peers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = peers[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.wifi)),
          title: Text(p.name),
          subtitle:
              Text(p.manifestUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onTap(p),
        );
      },
    );
  }
}
