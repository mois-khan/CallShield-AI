import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';

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


      // 🚨 NEW: THE SOS HANDSHAKE
      // Fetch the saved contacts and silently register them with the server
      final prefs = await SharedPreferences.getInstance();
      final String? userName = prefs.getString('userName');
      final String? sosNumber = prefs.getString('sosNumber');

      if (userName != null && userName.isNotEmpty && sosNumber != null && sosNumber.isNotEmpty) {
        final handshake = jsonEncode({
          "action": "register_sos",
          "userName": userName,
          "contacts": [sosNumber] // Sending as a list in case we add multiple later
        });
        channel!.sink.add(handshake);
        debugPrint("📡 [SOS] Registered emergency contacts for $userName with server!");
      }


      channel!.stream.listen((message) {
        final data = json.decode(message);

        // 2. TRIGGER NOTIFICATION IF SCAM DETECTED
        if (data['type'] == 'ALERT') {
          bool isCritical = data['threatLevel'] == 'CRITICAL';

          // ⏱️ Step A: Calculate Latency first!
          String latencyText = "";
          if (data['dispatch_time'] != null) {
            final int serverTime = data['dispatch_time'];
            final int phoneTime = DateTime.now().millisecondsSinceEpoch;
            final int deliveryLatency = phoneTime - serverTime;
            latencyText = "\n\n[⚡ E2E Delivery: ${deliveryLatency}ms]";
          }

          // Step B: Tell the OS to show the notification WITH the latency printed on it
          // Step B: Tell the OS to show the notification
          flutterLocalNotificationsPlugin.show(
            id: DateTime.now().millisecond,
            title: isCritical ? '🚨 CRITICAL SCAM DETECTED' : '⚠️ SUSPICIOUS CALL',
            body: "${data['explanation']}$latencyText",
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                'scam_alerts',
                'Threat Alerts',
                importance: Importance.max,
                priority: Priority.max,
                icon: 'ic_bg_service_small',
                color: const Color(0xFFEF4444),
                fullScreenIntent: true,
                // 🚨 THE FIX: Forces Android to show the full multi-line text!
                styleInformation: BigTextStyleInformation(
                  "${data['explanation']}$latencyText",
                  htmlFormatBigText: true,
                ),
              ),
            ),
          );

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