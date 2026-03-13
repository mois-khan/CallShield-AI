import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  final bool isMonitoring;
  final bool isConnected; // 🚨 NEW: Added connection state
  final VoidCallback onToggle;



  const HomeScreen({
    super.key,
    required this.isMonitoring,
    required this.isConnected, // 🚨 NEW
    required this.onToggle,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // 🚨 THE SOS SETUP DIALOG
  void _showSOSDialog() async {
    final prefs = await SharedPreferences.getInstance();
    TextEditingController nameController = TextEditingController(text: prefs.getString('userName') ?? '');
    TextEditingController phoneController = TextEditingController(text: prefs.getString('sosNumber') ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2A), // Dark theme matching your app
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
                // Save to physical device memory!
                await prefs.setString('userName', nameController.text);
                await prefs.setString('sosNumber', phoneController.text);
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("SOS Contact Saved!"), backgroundColor: Colors.green),
                );
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
    // 🚨 NEW LOGIC: It only glows if the user wants it ON *AND* the server is connected
    bool isSystemActive = widget.isMonitoring && widget.isConnected;

    // 🚨 NEW LOGIC: Dynamic Status Text
    String statusText = "System Paused";
    Color statusColor = Colors.grey;
    if (!widget.isConnected) {
      statusText = "Server Disconnected";
      statusColor = const Color(0xFFEF4444); // Red warning
    } else if (isSystemActive) {
      statusText = "Monitoring Active";
      statusColor = const Color(0xFF6366F1); // Indigo active
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

                // 1. THE HEADER
                // 1. THE HEADER
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
                          widget.isConnected ? "You are protected." : "Action Required.",
                          style: GoogleFonts.plusJakartaSans(
                            color: widget.isConnected ? Colors.white : const Color(0xFFEF4444),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    // 🚨 THE NEW SOS BUTTON
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
                        onPressed: _showSOSDialog, // Opens our new setup dialog!
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 50),

                // 2. THE HERO SHIELD (Pulsing Radar)
                Center(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        // Only pulse if actively connected and monitoring
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
                                // Red icon if disconnected, white if active, grey if paused
                                color: !widget.isConnected
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

                // 3. THE COMMAND CENTER (Midnight Glassmorphism)
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
                                !widget.isConnected
                                    ? "Waiting for connection..."
                                    : (widget.isMonitoring ? "Analyzing in real-time" : "Sleeping"),
                                style: GoogleFonts.plusJakartaSans(color: Colors.grey[400], fontSize: 14),
                              ),
                            ],
                          ),
                          Switch.adaptive(
                            value: widget.isMonitoring,
                            // 🚨 Disable switch if there is no server connection!
                            onChanged: widget.isConnected
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

                // 4. THREAT INTELLIGENCE FEED (Unchanged)
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