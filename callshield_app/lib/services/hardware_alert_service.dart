import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';

class HardwareAlertService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 1. Initialize the Notification Channel
  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(settings: initializationSettings);

    // 🚨 ADDED THIS: Ask Android 13+ for permission to show notifications
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
  // 2. The Main Trigger Function
  Future<void> triggerSensoryAlert(String threatLevel, int probability, String reason) async {
    bool isCritical = threatLevel == 'CRITICAL';

    // --- A. VIBRATION ---
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      if (isCritical) {
        // Aggressive SOS Pattern: wait, buzz, wait, buzz, wait, buzz
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500], intensities: [0, 255, 0, 255, 0, 255]);
      } else {
        // Suspicious Pattern: Two quick taps
        Vibration.vibrate(pattern: [0, 150, 100, 150]);
      }
    }

    // --- B. AUDIO BEEP ---
    // Note: To use this, you'll need to drop a 'beep.mp3' in your assets folder later.
    // For now, we wrap it in a try-catch so it doesn't crash if the file is missing.
    try {
      // await _audioPlayer.play(AssetSource('beep.mp3'));
    } catch (e) {
      print("Audio file not found yet, skipping beep.");
    }

    // --- C. HEADS-UP NOTIFICATION ---
    // This forces the notification to drop down from the top of the screen
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'callshield_security_alerts', // Channel ID
      'Security Alerts',            // Channel Name
      channelDescription: 'High priority fraud detection alerts',
      importance: Importance.max,   // MAX ensures it drops down over other apps
      priority: Priority.high,
      enableVibration: false,       // We are handling custom vibration manually above
      colorized: true,
      color: isCritical ? Color(0xFFD32F2F) : Color(0xFFF57C00), // Red or Orange
    );

    NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: 8888,
      title: 'Title',
      body: 'Body',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'scam_alerts',
          'Threat Alerts',
          importance: Importance.max,
          priority: Priority.max,
          // icon: 'ic_bg_service_small', // Ensure this matches your Android drawables
          color: Color(0xFFEF4444), // Red color
        ),
      ),
    );
  }
}