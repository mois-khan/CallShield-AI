import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_sender_background/sms_sender.dart';
import 'live_radar_screen.dart';
import 'package:flutter/services.dart';

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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late bool _liveConnectionStatus;

  bool isGrandmaModeEnabled = false;

  bool _isModalOpen = false; // 🚨 The Anti-Spam Lock
  static const platform = MethodChannel('com.callshield.native/telecom'); // 🚨 The Kotlin Bridge

  @override
  void initState() {
    super.initState();

    _liveConnectionStatus = widget.isConnected;
    _loadGrandmaModeState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addObserver(this);
    _checkForPendingAlerts();

    FlutterBackgroundService().on('server_status').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _liveConnectionStatus = event['isConnected'] as bool;
        });
      }
    });

    FlutterBackgroundService().on('onThreatDetected').listen((event) {
      if (event != null && mounted) {
        _showScamAlert(event);
      }
    });

    // 🚨 Listen for Grandma Mode trigger from the background
    FlutterBackgroundService().on('trigger_grandma_mode').listen((event) async {
      if (mounted) {
        debugPrint("💥 [UI Bridge] Executing Native Kotlin Hangup!");
        try {
          await platform.invokeMethod('endCall');

          // 🚨 If the normal red warning banner is open, dismiss it!
          if (_isModalOpen) {
            Navigator.of(context).pop();
            _isModalOpen = false;
          }

          // 🚨 Launch the beautiful Post-Call Receipt
          if (event != null) {
            _showThreatNeutralizedReceipt(event);
          }
        } catch (e) {
          debugPrint("❌ [UI Bridge] Native Hangup Failed: $e");
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadGrandmaModeState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isGrandmaModeEnabled = prefs.getBool('grandma_mode') ?? false;
    });
  }

  Future<void> _toggleGrandmaMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('grandma_mode', value);
    setState(() {
      isGrandmaModeEnabled = value;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? '🛡️ Grandma Mode: ACTIVE (Auto-Hangup Armed)' : 'Grandma Mode: OFF',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
          ),
          backgroundColor: value ? const Color(0xFFEF4444) : Colors.grey[800],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 App Resumed! Checking for missed alerts...");
      _checkForPendingAlerts();
    }
  }

  Future<void> _checkForPendingAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String? alertJson = prefs.getString('pending_alert');

    if (alertJson != null) {
      await prefs.remove('pending_alert');
      if (mounted) {
        final data = jsonDecode(alertJson);
        _showScamAlert(data);
      }
    }
  }

  // 🚨 THE FIXED SCAM BANNER UI
  void _showScamAlert(dynamic data) {
    if (_isModalOpen) return;

    _isModalOpen = true;

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
    ).whenComplete(() {
      _isModalOpen = false;
    });
  }

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
                var status = await Permission.sms.status;
                if (!status.isGranted) {
                  status = await Permission.sms.request();
                }

                if (status.isGranted) {
                  await prefs.setString('userName', nameController.text);
                  await prefs.setString('sosNumber', phoneController.text);

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
                                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                !_liveConnectionStatus ? "Waiting for connection..." : (widget.isMonitoring ? "Analyzing in real-time" : "Sleeping"),
                                style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 14),
                              ),
                              const SizedBox(height: 12),

                              if (_liveConnectionStatus)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF6366F1),
                                      side: const BorderSide(color: Color(0xFF6366F1)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                  ),
                                  icon: const Icon(Icons.radar, size: 18),
                                  label: Text("Open Live Radar", style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveRadarScreen()));
                                  },
                                )
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
                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isGrandmaModeEnabled ? const Color(0xFFEF4444).withOpacity(0.5) : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: SwitchListTile(
                    title: Text(
                      'Grandma Mode',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      'Auto-hangup calls if critical threat > 95%',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isGrandmaModeEnabled ? const Color(0xFFEF4444).withOpacity(0.2) : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.phone_disabled_rounded,
                        color: isGrandmaModeEnabled ? const Color(0xFFEF4444) : Colors.white54,
                      ),
                    ),
                    value: isGrandmaModeEnabled,
                    activeColor: const Color(0xFFEF4444),
                    onChanged: _toggleGrandmaMode,
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

  // ==========================================
  // 🚨 PHASE 3: THE POST-CALL RECEIPT (DOPAMINE HIT)
  // ==========================================
  void _showThreatNeutralizedReceipt(dynamic data) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false, // Force the user to interact with the receipt
      barrierColor: Colors.black87, // Darken the background heavily
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {

        // Extract tactics safely
        List<dynamic> rawTactics = data['tactics'] ?? [];
        String tacticsString = rawTactics.isNotEmpty
            ? rawTactics.join(', ')
            : 'Coercion & Impersonation';

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF10B981), width: 2), // Emerald Green Border
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 10,
                    )
                  ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // THE SHIELD ICON
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gpp_good_rounded, color: Color(0xFF10B981), size: 80),
                  ),
                  const SizedBox(height: 24),

                  // TITLE
                  Text(
                    "THREAT NEUTRALIZED",
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF10B981),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Call forcefully terminated to protect your assets.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // FORENSIC DATA BOX
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        _buildReceiptRow(Icons.radar, "Threat Level", "${data['probability']}% (Critical)"),
                        const Divider(color: Colors.white10, height: 24),
                        _buildReceiptRow(Icons.psychology, "Attacker Tactics", tacticsString),
                        const Divider(color: Colors.white10, height: 24),
                        _buildReceiptRow(Icons.shield_rounded, "Data Protected", "Financial Routing, OTPs, Voice Footprint"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // THE DISMISS BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text("SECURE & RETURN", style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Helper widget for the receipt rows
  Widget _buildReceiptRow(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey[500], size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.grey[500], fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        )
      ],
    );
  }
}