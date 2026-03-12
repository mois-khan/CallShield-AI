import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final StorageService _storageService = StorageService();
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final alerts = await _storageService.getAlertHistory();
    setState(() {
      _alerts = alerts;
      _isLoading = false;
    });
  }

  void _exportEvidence(Map<String, dynamic> alert) {
    final String report = '''
🚨 CALLSHIELD-AI: CYBER THREAT REPORT 🚨

Date/Time: ${alert['timestamp'] ?? 'Unknown'}
Threat Level: ${alert['threatLevel']}
Scam Probability: ${alert['probability']}%

AI Analysis & Tactics Used:
${alert['explanation']}

Generated securely by CallShield-AI.
''';
    Share.share(report, subject: 'Cyber Fraud Evidence Report');
  }

  Future<void> _launchCyberPortal() async {
    final Uri url = Uri.parse('https://cybercrime.gov.in/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch cybercrime portal');
    }
  }

  Future<void> _callHelpline() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '1930');
    if (!await launchUrl(phoneUri)) {
      debugPrint('Could not launch dialer');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Matches the new Midnight theme
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Threat Dashboard',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.grey),
            onPressed: () async {
              await _storageService.clearHistory();
              _loadHistory();
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)))
          : _alerts.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined, size: 80, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              "No threats detected yet.\nYou are secure.",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: _alerts.length,
        itemBuilder: (context, index) {
          final alert = _alerts[index];
          final isCritical = alert['threatLevel'] == 'CRITICAL';
          final color = isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            // 🚨 THE MIDNIGHT GLASS UPGRADE
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: color.withOpacity(0.3), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Inner Content Padding
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(isCritical ? Icons.warning_rounded : Icons.privacy_tip, color: color, size: 24),
                                    const SizedBox(width: 10),
                                    Text(
                                      isCritical ? 'CRITICAL THREAT' : 'SUSPICIOUS',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${alert['probability']}% Match',
                                    style: GoogleFonts.plusJakartaSans(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              alert['explanation'] ?? 'No details provided.',
                              style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 15, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                      // Action Bar (Share, Call 1930, Portal)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          border: const Border(top: BorderSide(color: Colors.white12)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.share, size: 18, color: Color(0xFF6366F1)),
                              label: Text("Evidence", style: GoogleFonts.plusJakartaSans(color: const Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                              onPressed: () => _exportEvidence(alert),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.phone_in_talk, size: 18, color: Colors.greenAccent),
                              label: Text("1930", style: GoogleFonts.plusJakartaSans(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                              onPressed: _callHelpline,
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
        },
      ),
    );
  }
}