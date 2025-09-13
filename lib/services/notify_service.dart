import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotifyService {
  NotifyService._();
  static final NotifyService instance = NotifyService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Android: ensure the channel exists
    const channel = AndroidNotificationChannel(
      'downloads',
      'Downloads',
      description: 'Download progress and completion',
      importance: Importance.high,
      showBadge: false,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _inited = true;
  }

  Future<void> ensurePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      // we won’t block if denied; just skip showing
    }
    // iOS: will prompt on first notification automatically if needed
  }

  /// 0..100. Ongoing progress notification.
  Future<void> showProgress({
    required int id,
    required String title,
    required int percent, // 0..100
  }) async {
    final android = AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Download progress and completion',
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: percent.clamp(0, 100),
      ongoing: percent < 100,
      priority: Priority.high,
      importance: Importance.high,
    );

    final ios = const DarwinNotificationDetails();

    await _plugin.show(
      id,
      title,
      '$percent%',
      NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> showDone({
    required int id,
    required String title,
    String? body,
  }) async {
    final android = const AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Download progress and completion',
      priority: Priority.high,
      importance: Importance.high,
    );
    final ios = const DarwinNotificationDetails();

    await _plugin.show(
      id,
      title,
      body ?? 'Download complete',
      NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> showError({
    required int id,
    required String title,
    String? body,
  }) async {
    final android = const AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Download progress and completion',
      priority: Priority.high,
      importance: Importance.high,
    );
    final ios = const DarwinNotificationDetails();

    await _plugin.show(
      id,
      title,
      body ?? 'Download failed',
      NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> cancel(int id) => _plugin.cancel(id);
  Future<void> cancelAll() => _plugin.cancelAll();
}
