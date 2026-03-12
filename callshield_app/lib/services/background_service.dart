import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/io.dart';

// 🚨 UPDATE WITH YOUR NGROK URL
const String backendUrl = "wss://concavely-inflationary-eddy.ngrok-free.dev/flutter-alerts";

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Setup Notification Channels
  const AndroidNotificationChannel stickyChannel = AndroidNotificationChannel(
    'sticky_monitoring', // id
    'Active Monitoring', // title
    description: 'Shows that CallShield AI is actively protecting you.',
    importance: Importance.low, // Low importance so it doesn't buzz constantly
  );

  const AndroidNotificationChannel alertChannel = AndroidNotificationChannel(
    'scam_alerts', // id
    'Threat Alerts', // title
    description: 'High priority alerts when a scam is detected.',
    importance: Importance.max, // MAX importance for Heads-Up popups!
    playSound: true,
    enableVibration: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(stickyChannel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(alertChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // The background entry point
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'sticky_monitoring',
      initialNotificationTitle: 'CallShield-AI',
      initialNotificationContent: 'System Active & Monitoring',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false), // Skipping iOS for now
  );
}

// 🚨 THIS RUNS IN A COMPLETELY SEPARATE MEMORY SPACE (BACKGROUND ISOLATE)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // 1. Initialize the WebSocket directly inside the background service
  IOWebSocketChannel? channel;

  void connectWebSocket() async {
    try {
      final ws = await WebSocket.connect(
        backendUrl,
        headers: {"ngrok-skip-browser-warning": "69420"},
      );
      channel = IOWebSocketChannel(ws);
      debugPrint("✅ [Background] Connected to Node.js!");

      channel!.stream.listen((message) {
        final data = json.decode(message);

        // 2. TRIGGER NOTIFICATION IF SCAM DETECTED
        if (data['type'] == 'ALERT') {
          bool isCritical = data['threatLevel'] == 'CRITICAL';

          flutterLocalNotificationsPlugin.show(
            DateTime.now().millisecond, // Unique ID
            isCritical ? '🚨 CRITICAL SCAM DETECTED' : '⚠️ SUSPICIOUS CALL',
            data['explanation'],
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'scam_alerts',
                'Threat Alerts',
                importance: Importance.max,
                priority: Priority.max,
                icon: 'ic_bg_service_small', // We will add this icon later, default is app icon
                color: Color(0xFFEF4444),
                fullScreenIntent: true, // Pops up over other apps
              ),
            ),
          );

          // Send data back to the UI if the app happens to be open
          service.invoke('onThreatDetected', data);
        }
      }, onDone: () {
        debugPrint("❌ [Background] Disconnected. Reconnecting in 5s...");
        Future.delayed(const Duration(seconds: 5), connectWebSocket);
      });
    } catch (e) {
      debugPrint("❌ [Background] Connection failed: $e");
      Future.delayed(const Duration(seconds: 5), connectWebSocket);
    }
  }

  // Start the connection loop
  connectWebSocket();

  // Listen for commands from the UI (like Pause/Resume)
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}