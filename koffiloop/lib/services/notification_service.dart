import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _userId;
  bool _initialized = false;

  Future<void> init(String userId) async {
    if (_initialized) return;
    _userId = userId;

    tz.initializeTimeZones();

    await _configureLocalNotifications();
    await _requestPermissions();
    await _setupTokenHandling();
    await _setupMessageHandlers();

    _initialized = true;
  }

  Future<void> _configureLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );
  }

  Future<void> _requestPermissions() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );
  }

  Future<void> _setupTokenHandling() async {
    String? token = await _fcm.getToken();
    if (token != null && _userId != null) {
      await _saveTokenToFirestore(token);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (_userId != null) {
        await _saveTokenToFirestore(newToken);
      }
    });
  }

  Future<void> _saveTokenToFirestore(String token) async {
    if (_userId == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .update({
      'fcmToken': token,
      'tokenUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _setupMessageHandlers() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationPayload(message.data);
    });

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationPayload(initialMessage.data);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'koffiloop_channel',
      'KoffiLoop Notifications',
      channelDescription: 'Order updates, messages, and promotions',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'KoffiLoop',
      message.notification?.body ?? '',
      platformDetails,
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      _handleNotificationPayload(data);
    }
  }

  void _handleNotificationPayload(Map<String, dynamic> data) {
    final type = data['type'];
    final targetId = data['targetId'];

    debugPrint('Notification tapped: type=$type, targetId=$targetId');
  }

  Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'koffiloop_channel',
          'KoffiLoop Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> schedule({
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    await _localNotifications.zonedSchedule(
      DateTime.now().millisecond,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'koffiloop_channel',
          'KoffiLoop Notifications',
          importance: Importance.max,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
  }

  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
  }

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  Future<void> deleteToken() async {
    if (_userId != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({'fcmToken': FieldValue.delete()});
    }
    await _fcm.deleteToken();
  }

  Future<void> sendOrderUpdate({
    required String orderId,
    required String customerId,
    required String status,
  }) async {
    if (_userId == null) return;

    final statusLabels = {
      'preparing': 'Your order is being prepared ☕',
      'ready': 'Your order is ready for pickup! 🎉',
      'completed': 'Order completed. Thank you! ✨',
      'cancelled': 'Order cancelled. Sorry! 😔',
    };

    final body = statusLabels[status] ?? 'Order status updated';

    await showLocal(
      title: 'Order Update #$orderId',
      body: body,
      payload: jsonEncode({
        'type': 'order',
        'targetId': orderId,
        'status': status,
      }),
    );

    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': customerId,
      'orderId': orderId,
      'type': 'order_update',
      'title': 'Order Update',
      'body': body,
      'status': status,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> dispose() async {
      await deleteToken();
      _initialized = false;
      _userId = null;
    }

    Future<void> notifyNewOrder({
    required String orderId,
    required String sellerId,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'sellerId': sellerId,
      'orderId': orderId,
      'type': 'new_order',
      'title': 'New Order',
      'body': 'You have a new order (#$orderId).',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}