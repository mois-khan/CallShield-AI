import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dash_bubble/dash_bubble.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/alert_service.dart';
import 'services/storage_service.dart';
import 'history_screen.dart';
import 'home_screen.dart'; // 🚨 Connecting our new UI!

import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 🚨 NEW
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required before doing native stuff

  // Ask for notification permissions on Android 13+
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

  // Start the indestructible background brain
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
  StreamSubscription? _alertSubscription; // 🚨 New: Background Listener

  @override
  void initState() {
    super.initState();
    _alertService.connect(currentNgrokUrl);

    // 🚨 NEW: Instead of a StreamBuilder building the whole screen,
    // we listen in the background and pop up a sleek modal when an alert hits!
    _alertSubscription = _alertService.alertStream.listen((payload) {
      if (payload['type'] == 'ALERT') {
        if (_lastSavedExplanation != payload['explanation']) {
          _storageService.saveAlert(payload);
          _lastSavedExplanation = payload['explanation'];

          // Trigger the premium alert modal
          _showThreatModal(payload);
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

  // 🚨 THE PREMIUM ALERT MODAL (Glassmorphism Bottom Sheet)
  void _showThreatModal(Map<String, dynamic> payload) {
    bool isCritical = payload['threatLevel'] == 'CRITICAL';
    Color warningColor = isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.85),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              border: Border(top: BorderSide(color: warningColor.withOpacity(0.5), width: 2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 20),
                Icon(Icons.warning_rounded, color: warningColor, size: 60),
                const SizedBox(height: 16),
                Text(
                  isCritical ? 'CRITICAL THREAT DETECTED' : 'SUSPICIOUS ACTIVITY',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: warningColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Scam Probability:", style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
                          Text("${payload['probability']}%", style: GoogleFonts.plusJakartaSans(color: warningColor, fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: Colors.white24),
                      ),
                      Text(
                        '${payload['explanation']}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 15, color: Colors.white, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: warningColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text("DISMISS ALARM", style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
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
      // 🚨 NEW: The body is now your beautiful Home Screen!
      body: ValueListenableBuilder<bool>(
        valueListenable: _alertService.isConnected,
        builder: (context, isConnected, child) {
          return HomeScreen(
            isMonitoring: _alertService.isMonitoring,
            isConnected: isConnected, // Pass the live state to the UI
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