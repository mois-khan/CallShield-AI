import 'package:flutter/material.dart';
import 'services/alert_service.dart';

void main() {
  runApp(const CallShieldApp());
}

class CallShieldApp extends StatelessWidget {
  const CallShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CallShield-AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
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
  final String currentNgrokUrl = "https://concavely-inflationary-eddy.ngrok-free.dev";

  // 🚨 NEW: State variable to track if the alert is minimized
  bool _isMinimized = false;

  @override
  void initState() {
    super.initState();
    _alertService.connect(currentNgrokUrl);
  }

  @override
  void dispose() {
    _alertService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CallShield-AI', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.grey[200],
        elevation: 0,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _alertService.alertStream,
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final payload = snapshot.data!;

          if (payload['type'] == 'SYSTEM') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield, color: Colors.green, size: 80),
                  const SizedBox(height: 20),
                  Text(payload['message'] ?? 'Monitoring Active',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            );
          }

          if (payload['type'] == 'ALERT') {
            bool isCritical = payload['threatLevel'] == 'CRITICAL';
            Color warningColor = isCritical ? Colors.red.shade700 : Colors.orange.shade700;

            // 🔽 MINIMIZED STATE UI 🔽
            if (_isMinimized) {
              return Column(
                children: [
                  // The Minimized Banner
                  Container(
                    width: double.infinity,
                    color: warningColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isCritical ? 'CRITICAL THREAT (Tap to expand)' : 'SUSPICIOUS (Tap to expand)',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_full, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _isMinimized = false; // Maximize it!
                            });
                          },
                        )
                      ],
                    ),
                  ),
                  // The rest of your app can go down here while minimized!
                  const Expanded(
                    child: Center(
                      child: Text("App is minimized. Call is still being monitored.",
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                ],
              );
            }

            // 🔼 FULL SCREEN (MAXIMIZED) UI 🔼
            return Container(
              width: double.infinity,
              color: warningColor,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Collapse Button at the top right
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.close_fullscreen, color: Colors.white, size: 30),
                      onPressed: () {
                        setState(() {
                          _isMinimized = true; // Minimize it!
                        });
                      },
                    ),
                  ),
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 100),
                  const SizedBox(height: 20),
                  Text(
                    isCritical ? 'CRITICAL THREAT DETECTED' : 'SUSPICIOUS CALLER',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        Text('Scam Probability: ${payload['probability']}%',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const Divider(),
                        Text('Reason: ${payload['explanation']}',
                            style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}