import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dash_bubble/dash_bubble.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/alert_service.dart';
import 'services/storage_service.dart';
import 'history_screen.dart';
import 'home_screen.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

  await initializeBackgroundService();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallShield-AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const AlertScreen(),
    );
  }
}

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final AlertService _alertService = AlertService();
  final StorageService _storageService = StorageService();

  // 🚨 UPDATE THIS WITH YOUR ACTIVE NGROK URL
  final String currentNgrokUrl = "https://concavely-inflationary-eddy.ngrok-free.dev/flutter-alerts";

  String _lastSavedExplanation = "";
  StreamSubscription? _alertSubscription;

  @override
  void initState() {
    super.initState();
    _alertService.connect(currentNgrokUrl);

    _alertSubscription = _alertService.alertStream.listen((payload) {
      if (payload['type'] == 'ALERT') {
        if (_lastSavedExplanation != payload['explanation']) {
          // 🚨 SILENT BACKGROUND SAVING
          // We still save the alert to memory so your History screen works!
          _storageService.saveAlert(payload);
          _lastSavedExplanation = payload['explanation'];

          // 🚨 DISABLED: _showThreatModal(payload);
          // We stopped main.dart from showing modals to prevent the spam glitch.
          // home_screen.dart will now handle 100% of the UI popups.
        }
      }
    });
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _alertService.disconnect();
    super.dispose();
  }

  // Floating Bubble Logic (unchanged)
  Future<void> _startFloatingBubble() async {
    final hasPermission = await DashBubble.instance.hasOverlayPermission();
    if (!hasPermission) {
      await DashBubble.instance.requestOverlayPermission();
      return;
    }

    await DashBubble.instance.startBubble(
      bubbleOptions: BubbleOptions(
        bubbleIcon: 'icon',
        bubbleSize: 60,
        enableClose: true,
        distanceToClose: 100,
      ),
      onTap: () {
        setState(() {
          _alertService.toggleMonitoring();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _alertService.isMonitoring ? "🛡️ AI Monitoring RESUMED" : "⏸️ AI Monitoring PAUSED",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: _alertService.isMonitoring ? const Color(0xFF6366F1) : Colors.grey,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFF6366F1)),
            const SizedBox(width: 10),
            Text('CallShield-AI', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bubble_chart, color: Colors.tealAccent),
            tooltip: "Launch Floating Bubble",
            onPressed: _startFloatingBubble,
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFF6366F1)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          )
        ],
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: _alertService.isConnected,
        builder: (context, isConnected, child) {
          return HomeScreen(
            isMonitoring: _alertService.isMonitoring,
            isConnected: isConnected,
            onToggle: () {
              setState(() {
                _alertService.toggleMonitoring();
              });
            },
          );
        },
      ),
    );
  }
}