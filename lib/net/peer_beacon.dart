// lib/net/peer_beacon.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// UDP port for AnyDrop peer discovery (same on sender/receiver)
const int kAnyDropDiscoveryPort = 53334;

/// Info we broadcast/collect.
class PeerInfo {
  final String name; // Sender display name
  final String ip; // Sender IPv4
  final int port; // HTTP port of the sharing server
  final String sessionPath; // e.g. /s/ab12cd
  DateTime lastSeen; // used for UI staleness

  PeerInfo({
    required this.name,
    required this.ip,
    required this.port,
    required this.sessionPath,
    required this.lastSeen,
  });

  String get manifestUrl => 'http://$ip:$port$sessionPath/manifest';

  factory PeerInfo.fromJson(Map<String, dynamic> m, String fallbackIp) {
    final ip = (m['ip'] as String?)?.trim();
    return PeerInfo(
      name: (m['name'] as String? ?? 'Sender').trim(),
      ip: (ip == null || ip.isEmpty) ? fallbackIp : ip,
      port: (m['port'] as num?)?.toInt() ?? 0,
      sessionPath: (m['sessionPath'] as String? ?? '').trim(),
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'port': port,
        'sessionPath': sessionPath,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

  @override
  int get hashCode => Object.hash(ip, port, sessionPath);

  @override
  bool operator ==(Object other) =>
      other is PeerInfo &&
      ip == other.ip &&
      port == other.port &&
      sessionPath == other.sessionPath;
}

/// Sender side: broadcast a small JSON packet on the LAN every 1s.
class PeerAnnouncer {
  final InternetAddress localIp; // your IPv4 (e.g. 192.168.1.23)
  final String name;
  final int port;
  final String sessionPath;

  RawDatagramSocket? _sock;
  Timer? _timer;

  PeerAnnouncer({
    required this.localIp,
    required this.name,
    required this.port,
    required this.sessionPath,
  });

  // Compute subnet broadcast as x.y.z.255 from a /24 assumption.
  InternetAddress _subnetBroadcast(InternetAddress ip) {
    final parts = ip.address.split('.');
    if (parts.length == 4) {
      return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return InternetAddress('255.255.255.255');
  }

  Future<void> start() async {
    // Bind to any IPv4; enable broadcast.
    // DO NOT set reusePort on Android (not supported).
    _sock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    _sock!.broadcastEnabled = true;

    final payload = utf8.encode(jsonEncode({
      'name': name,
      'ip': localIp.address,
      'port': port,
      'sessionPath': sessionPath,
    }));

    final bcastSubnet = _subnetBroadcast(localIp);
    final bcastGlobal = InternetAddress('255.255.255.255');

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        _sock?.send(payload, bcastSubnet, kAnyDropDiscoveryPort);
        _sock?.send(payload, bcastGlobal, kAnyDropDiscoveryPort);
      } catch (_) {
        // ignore broadcast errors
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _sock?.close();
    _sock = null;
  }
}

/// Receiver side: listen for Beacons and surface fresh peers.
/// Emits updates on [stream] whenever the peer list changes.
class PeerScanner {
  RawDatagramSocket? _sock;
  final _controller = StreamController<List<PeerInfo>>.broadcast();
  final Map<int, PeerInfo> _peers = {}; // hashCode -> PeerInfo
  Timer? _gcTimer;

  Stream<List<PeerInfo>> get stream => _controller.stream;

  Future<void> start() async {
    // Listen on all IPv4 interfaces. No reusePort here.
    _sock = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kAnyDropDiscoveryPort,
      reuseAddress: true,
    );
    _sock!.broadcastEnabled = true;

    _sock!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _sock!.receive();
      if (dg == null) return;
      try {
        final text = utf8.decode(dg.data);
        final m = jsonDecode(text) as Map<String, dynamic>;
        final info = PeerInfo.fromJson(m, dg.address.address);
        final key = info.hashCode;
        final existing = _peers[key];
        if (existing == null) {
          _peers[key] = info;
          _controller.add(_snapshot());
        } else {
          existing.lastSeen = DateTime.now();
        }
      } catch (_) {
        // ignore malformed packets
      }
    });

    // GC stale entries (no update for 5s)
    _gcTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      final removed = <int>[];
      _peers.forEach((k, v) {
        if (now.difference(v.lastSeen).inSeconds > 5) removed.add(k);
      });
      if (removed.isNotEmpty) {
        for (final k in removed) {
          _peers.remove(k);
        }
        _controller.add(_snapshot());
      }
    });
  }

  List<PeerInfo> _snapshot() {
    final list = _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> stop() async {
    _gcTimer?.cancel();
    _gcTimer = null;
    _sock?.close();
    _sock = null;
    // keep stream open (page may re-use)
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
