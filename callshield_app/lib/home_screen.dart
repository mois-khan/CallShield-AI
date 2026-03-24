import 'dart:ui';
import 'dart:convert'; // Added for jsonDecode
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_sender_background/sms_sender.dart';

class HomeScreen extends StatefulWidget {
  final bool isMonitoring;
  final bool isConnected;
  final VoidCallback onToggle;

  const HomeScreen({
    super.key,
    required this.isMonitoring,
    required this.isConnected,
    required this.onToggle,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// 🚨 FIXED: Removed the extra curly brace and added WidgetsBindingObserver
class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late bool _liveConnectionStatus;

  @override
  void initState() {
    super.initState();

    _liveConnectionStatus = widget.isConnected;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 🚨 1. Register the observer to listen for Wake-Ups
    WidgetsBinding.instance.addObserver(this);

    // 🚨 2. Check for alerts immediately on fresh app boot
    _checkForPendingAlerts();

    // 🚨 3. Listen for connection drops/reconnects
    FlutterBackgroundService().on('server_status').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _liveConnectionStatus = event['isConnected'] as bool;
        });
      }
    });

    // 🚨 4. Keep listening for alerts if the app is ALREADY open
    FlutterBackgroundService().on('onThreatDetected').listen((event) {
      if (event != null && mounted) {
        _showScamAlert(event);
      }
    });
  }

  @override
  void dispose() {
    // 🚨 Unregister the observer
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  // ==========================================
  // 🚨 THE ANSWERING MACHINE LOGIC 🚨
  // ==========================================

  // THIS FIRES EVERY TIME THE APP COMES TO THE FOREGROUND
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 App Resumed! Checking for missed alerts...");
      _checkForPendingAlerts();
    }
  }

  // THE MEMORY CHECKER
  Future<void> _checkForPendingAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force refresh memory
    final String? alertJson = prefs.getString('pending_alert');

    if (alertJson != null) {
      debugPrint("🚨 Found a missed alert in memory! Triggering UI...");

      // 1. Delete it so it doesn't pop up again next time
      await prefs.remove('pending_alert');

      // 2. Parse it and show your beautiful red banner
      if (mounted) {
        final data = jsonDecode(alertJson);
        _showScamAlert(data);
      }
    }
  }

  // 🚨 YOUR SCAM BANNER UI
  void _showScamAlert(dynamic data) {
    // NOTE: This is a placeholder!
    // Replace this with the code you use to draw that red screenshot you showed me!
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  "CRITICAL THREAT DETECTED",
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Scam Probability: ${data['probability']}%",
                  style: GoogleFonts.plusJakartaSans(color: Colors.redAccent, fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  data['explanation'] ?? "Suspicious activity detected.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(color: Colors.grey[400]),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => Navigator.pop(context),
                    child: Text("DISMISS ALARM", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        }
    );
  }
  // ==========================================


  // 🚨 THE SOS SETUP DIALOG
  void _showSOSDialog() async {
    final prefs = await SharedPreferences.getInstance();
    TextEditingController nameController = TextEditingController(text: prefs.getString('userName') ?? '');
    TextEditingController phoneController = TextEditingController(text: prefs.getString('sosNumber') ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.emergency, color: Color(0xFFEF4444)),
              const SizedBox(width: 8),
              Text("SOS Contacts", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "If a critical scam is detected, CallShield will instantly SMS this contact.",
                style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Your Name",
                  labelStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade800)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Emergency Phone (e.g. +91...)",
                  labelStyle: const TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade800)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF6366F1))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: GoogleFonts.plusJakartaSans(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () async {
                // Request SMS Permission from the user
                var status = await Permission.sms.status;
                if (!status.isGranted) {
                  status = await Permission.sms.request();
                }

                if (status.isGranted) {
                  // Save to physical device memory!
                  await prefs.setString('userName', nameController.text);
                  await prefs.setString('sosNumber', phoneController.text);

                  // Tell the background service to push this to Node.js INSTANTLY
                  FlutterBackgroundService().invoke('force_sos_sync');

                  if (mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("SOS Contact Saved & Armed!"), backgroundColor: Colors.green),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("SMS Permission is required for SOS!"), backgroundColor: Colors.red),
                  );
                }
              },
              child: Text("Save", style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isSystemActive = widget.isMonitoring && _liveConnectionStatus;

    String statusText = "System Paused";
    Color statusColor = Colors.grey;
    if (!_liveConnectionStatus) {
      statusText = "Server Disconnected";
      statusColor = const Color(0xFFEF4444);
    } else if (isSystemActive) {
      statusText = "Monitoring Active";
      statusColor = const Color(0xFF6366F1);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Security Overview",
                          style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 16),
                        ),
                        Text(
                          _liveConnectionStatus ? "You are protected." : "Action Required.",
                          style: GoogleFonts.plusJakartaSans(
                            color: _liveConnectionStatus ? Colors.white : const Color(0xFFEF4444),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.emergency),
                        color: const Color(0xFFEF4444),
                        tooltip: "SOS Settings",
                        onPressed: _showSOSDialog,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 50),

                // THE HERO SHIELD (Pulsing Radar)
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: isSystemActive ? _pulseAnimation.value : 1.0,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSystemActive
                                ? const Color(0xFF6366F1).withOpacity(0.15)
                                : Colors.grey.withOpacity(0.05),
                            boxShadow: isSystemActive ? [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withOpacity(0.3),
                                blurRadius: 40,
                                spreadRadius: 10,
                              )
                            ] : [],
                          ),
                          child: Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSystemActive
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF1E293B),
                              ),
                              child: Icon(
                                isSystemActive ? Icons.security : Icons.shield_outlined,
                                size: 50,
                                color: !_liveConnectionStatus
                                    ? const Color(0xFFEF4444)
                                    : (isSystemActive ? Colors.white : Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 30),
                Center(
                  child: Text(
                    statusText,
                    style: GoogleFonts.plusJakartaSans(
                      color: statusColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 50),

                // THE COMMAND CENTER
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "AI Call Scanner",
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                !_liveConnectionStatus
                                    ? "Waiting for connection..."
                                    : (widget.isMonitoring ? "Analyzing in real-time" : "Sleeping"),
                                style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 14),
                              ),
                            ],
                          ),
                          Switch.adaptive(
                            value: widget.isMonitoring,
                            onChanged: _liveConnectionStatus
                                ? (val) => widget.onToggle()
                                : null,
                            activeColor: const Color(0xFF6366F1),
                            inactiveTrackColor: const Color(0xFF1E293B),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                Text(
                  "Latest Scam Tactics",
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 140,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildThreatCard(
                        "The FedEx/Customs Scam",
                        "Automated calls claiming a package contains illegal goods. Do not press 1.",
                        Icons.local_shipping_outlined,
                      ),
                      _buildThreatCard(
                        "TRAI Disconnection",
                        "Scammers impersonating telecom officials threatening to block your number.",
                        Icons.cell_tower,
                      ),
                      _buildThreatCard(
                        "WhatsApp Screen Share",
                        "Never share your screen while on a video call. They can read your OTPs.",
                        Icons.mobile_screen_share,
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThreatCard(String title, String desc, IconData icon) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 13, height: 1.4),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}