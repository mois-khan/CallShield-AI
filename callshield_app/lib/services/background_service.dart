import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

// 🚨 UPDATE WITH YOUR NGROK URL
const String backendUrl = "wss://concavely-inflationary-eddy.ngrok-free.dev/flutter-alerts";
bool hasSentSOSThisSession = false;

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

  // 🧠 THE NETWORK STATE
  IOWebSocketChannel? channel;
  Timer? pingTimer;
  int missedPongs = 0;
  int reconnectDelay = 2; // Starts at 2 seconds, doubles on failure

  // 🔄 THE STATE SYNC FUNCTION
  Future<void> syncSOSState() async {
    final prefs = await SharedPreferences.getInstance();
    // Force a reload from disk to bypass Isolate caching issues
    await prefs.reload();

    final String? userName = prefs.getString('userName');
    final String? sosNumber = prefs.getString('sosNumber');

    if (userName != null && userName.isNotEmpty && sosNumber != null && sosNumber.isNotEmpty) {
      final handshake = jsonEncode({
        "action": "register_sos",
        "userName": userName,
        "contacts": [sosNumber]
      });
      channel?.sink.add(handshake);
      debugPrint("📡 [SYNC] Pushed SOS contacts to Server: $userName");
    } else {
      debugPrint("⚠️ [SYNC] Memory is empty. No SOS contacts sent.");
    }
  }

  // 🔌 THE CONNECTION ENGINE
  void connectWebSocket() async {
    try {
      debugPrint("🔄 [Network] Attempting to connect...");
      final ws = await WebSocket.connect(
        backendUrl,
        headers: {"ngrok-skip-browser-warning": "69420"},
      );
      channel = IOWebSocketChannel(ws);

      // ✅ CONNECTION SUCCESS: Reset backoff and sync state!
      debugPrint("✅ [Network] Connected to Node.js Server!");
      reconnectDelay = 2;
      missedPongs = 0;

      // 🚨 NEW: Tell the UI we connected!
      service.invoke('server_status', {'isConnected': true});

      // Sync the latest saved contacts from the hard drive immediately
      await syncSOSState();

      // 🏓 THE WATCHDOG HEARTBEAT
      pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        missedPongs++;
        if (missedPongs >= 3) {
          // 👻 Phantom Connection Detected! Server hasn't answered in 15 seconds.
          debugPrint("💀 [Network] Phantom Connection detected. Killing socket.");
          timer.cancel();
          channel?.sink.close(); // Forcefully trigger the onDone block
        } else {
          // Send the ping!
          channel?.sink.add(jsonEncode({"action": "ping"}));
        }
      });

      // 🎧 THE LISTENER
      channel!.stream.listen((message) async {

        debugPrint("📥 [Network Incoming] $message");

        final data = json.decode(message);

        // Catch the Pong and reset the strike counter!
        if (data['action'] == 'pong') {
          missedPongs = 0;
          return;
        }

        // ==========================================
        // 🚨 2. TRIGGER NOTIFICATION & SMS LOGIC
        // ==========================================
        if (data['type'] == 'ALERT') {
          debugPrint("🔔 [ALERT] Threat payload received! Processing...");
          bool isCritical = data['threatLevel'] == 'CRITICAL';

          // ⏱️ Calculate Latency
          String latencyText = "";
          if (data['dispatch_time'] != null) {
            final int serverTime = data['dispatch_time'];
            final int phoneTime = DateTime.now().millisecondsSinceEpoch;
            final int deliveryLatency = phoneTime - serverTime;
            latencyText = "\n\n[⚡ E2E Delivery: ${deliveryLatency}ms]";
          }

          // 🛡️ Attempt to show Notification (Safely!)
          try {
            debugPrint("🔔 [ALERT] Attempting to show OS notification...");
            await flutterLocalNotificationsPlugin.show(
              id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
              title: isCritical ? '🚨 CRITICAL SCAM DETECTED' : '⚠️ SUSPICIOUS CALL',
              body: "${data['explanation']}$latencyText",
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  'scam_alerts',
                  'Threat Alerts',
                  importance: Importance.max,
                  priority: Priority.max,
                  icon: 'ic_bg_service_small', // Ensure this icon exists!
                  color: const Color(0xFFEF4444),
                  fullScreenIntent: true,
                  styleInformation: BigTextStyleInformation(
                    "${data['explanation']}$latencyText",
                    htmlFormatBigText: true,
                  ),
                ),
              ),
            );
            debugPrint("✅ [ALERT] OS Notification displayed!");
          } catch (e) {
            debugPrint("❌ [ALERT] Failed to show OS notification: $e");
          }

          // Update the UI
          service.invoke('onThreatDetected', data);

          // ==========================================
          // 🚨 3. THE NATIVE ANDROID SMS TRIGGER
          // ==========================================
          if (isCritical) {
            if (!hasSentSOSThisSession) {
              hasSentSOSThisSession = true;

              final prefs = await SharedPreferences.getInstance();
              final String? userName = prefs.getString('userName');
              final String? sosNumber = prefs.getString('sosNumber');

              if (sosNumber != null && sosNumber.isNotEmpty) {
                final String probability = data['probability']?.toString() ?? '99';
                final String tactics = (data['tactics'] as List?)?.join(', ') ?? 'Unknown';

                String msgBody = "🚨 CallShield SOS 🚨\n${userName ?? 'A user'} is on a flagged scam call (Threat Level: $probability%).\n\nTactics detected: $tactics.\n\nPlease call them immediately to interrupt the scam.";

                debugPrint("📱 [NATIVE] Threat Critical! Firing native SMS to $sosNumber...");

                try {
                  final Telephony telephony = Telephony.instance;

                  // 🚨 FIRE AND FORGET:
                  // By removing the 'statusListener', we bypass the Android 14 Receiver crash!
                  telephony.sendSms(
                    to: sosNumber,
                    message: msgBody,
                  );

                  debugPrint("✅ [NATIVE] SMS command successfully handed to Android OS!");
                } catch (e) {
                  debugPrint("❌ [NATIVE] SMS Plugin Error: $e");
                }
              } else {
                debugPrint("⚠️ [NATIVE] Critical Threat, but no SOS number saved in memory!");
              }
            } else {
              debugPrint("🛡️ [NATIVE] Anti-Spam Lock Active: SMS already sent this session.");
            }
          }
        }

      }, onDone: () {
        service.invoke('server_status', {'isConnected': false});
        // 📉 GRACEFUL OR UNGRACEFUL DISCONNECT
        pingTimer?.cancel();
        debugPrint("❌ [Network] Socket Closed. Backoff: Reconnecting in ${reconnectDelay}s...");
        Future.delayed(Duration(seconds: reconnectDelay), connectWebSocket);
        // Exponential Backoff: Double the wait time, cap it at 30 seconds
        reconnectDelay = (reconnectDelay * 2).clamp(2, 30);
      });

    } catch (e) {
      service.invoke('server_status', {'isConnected': false});
      // 💥 CONNECTION REFUSED / NO INTERNET
      pingTimer?.cancel();
      debugPrint("❌ [Network] Connection Failed: $e");
      debugPrint("⏳ [Network] Backoff: Retrying in ${reconnectDelay}s...");
      Future.delayed(Duration(seconds: reconnectDelay), connectWebSocket);
      reconnectDelay = (reconnectDelay * 2).clamp(2, 30);
    }
  }

  // Start the engine
  connectWebSocket();

  // Listen for commands from the UI (like Pause/Resume)
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // 🚨 NEW: Listen for SOS updates from the UI!
  service.on('force_sos_sync').listen((event) async {
    debugPrint("🔄 [Isolate Bridge] UI requested immediate SOS sync!");
    await syncSOSState();
  });
}