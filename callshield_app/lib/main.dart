import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dash_bubble/dash_bubble.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/alert_service.dart';
import 'services/storage_service.dart';
import 'history_screen.dart';
import 'home_screen.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/background_service.dart';

import 'threat_dashboard.dart';
import 'demo_screen.dart';
// 🆕 MESSAGE SHIELD (additive only): second protection section.
import 'message_shield/background/message_shield_protection_entry.dart';
import 'message_shield/models/message_input.dart';
import 'message_shield/screens/message_shield_home_screen.dart';
import 'message_shield/screens/scan_message_screen.dart';
import 'message_shield/services/message_ingest_service.dart';
import 'message_shield/services/message_shield_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

  await initializeBackgroundService();

  // 🆕 MESSAGE SHIELD (additive only): the release AOT build removes Dart that
  // nothing references, which would drop the headless background entry point
  // Message Shield's foreground service starts. Taking its callback handle keeps
  // it in the snapshot (same mechanism flutter_local_notifications and
  // flutter_background_service use for their background entry points).
  PluginUtilities.getCallbackHandle(messageShieldProtectionMain);

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

class _AlertScreenState extends State<AlertScreen> with WidgetsBindingObserver {
  final AlertService _alertService = AlertService();
  final StorageService _storageService = StorageService();

  // 🚨 UPDATE THIS WITH YOUR ACTIVE NGROK URL
  final String currentNgrokUrl = "https://callshield-ai-backend.onrender.com/flutter-alerts";

  String _lastSavedExplanation = "";
  StreamSubscription? _alertSubscription;

  // ─── FLOATING POPUP state (single controlled path below) ───
  static const String _floatingPopupPrefKey = 'callshield_floating_popup_enabled';

  /// UI state: true while the floating popup is shown / meant to be shown.
  bool _floatingPopupOn = false;

  /// Debounce: one start/stop operation at a time (rapid presses are ignored).
  bool _floatingPopupBusy = false;

  /// True while the system overlay-permission screen is open, so that
  /// returning from settings re-checks the permission exactly once.
  bool _waitingForOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    _alertService.connect(currentNgrokUrl);

    // 🆕 MESSAGE SHIELD (additive only): if CallShield was opened by sharing or
    // selecting text from another app, open the scan screen ready to analyse it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSharedMessageIfAny());
    // 🆕 MESSAGE SHIELD (additive only): re-arm background SMS protection when
    // the user has it switched on (fresh install / app update / after Android
    // stopped the service). No-op when protection is off.
    MessageShieldService.ensureBackgroundProtection();

    // FLOATING POPUP ONLY: observe lifecycle so returning from the overlay
    // permission screen / backgrounding re-syncs the popup state safely.
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFloatingPopup());

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
    WidgetsBinding.instance.removeObserver(this);
    _alertSubscription?.cancel();
    _alertService.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // FLOATING POPUP ONLY: when the user comes back from the overlay
    // permission screen (or from background) re-check the real state once.
    // Backgrounding/locking needs no action: the popup is its own foreground
    // service and keeps running independently.
    if (state == AppLifecycleState.resumed) {
      _syncFloatingPopupAfterResume();
    }
  }

  // ═══ FLOATING POPUP — the ONE controlled path ═══
  // Every DashBubble call in the app lives in this section. START, STOP,
  // PERMISSION CHECK and STATE UPDATE each have exactly one method, so no
  // second code path can start/stop the bubble. Every call is wrapped in
  // try/catch: if the popup cannot work on a device, CallShield keeps
  // working normally and the control reflects the actual state.

  /// Single controlled PERMISSION CHECK. Never throws.
  Future<bool> _hasOverlayPermission() async {
    try {
      return await DashBubble.instance.hasOverlayPermission();
    } catch (e) {
      debugPrint('FloatingPopup: hasOverlayPermission failed: $e');
      return false;
    }
  }

  /// Single controlled PERMISSION REQUEST. Opens the system overlay settings
  /// screen at most once per press; the result is re-checked on return.
  Future<void> _requestOverlayPermission() async {
    try {
      await DashBubble.instance.requestOverlayPermission();
    } catch (e) {
      debugPrint('FloatingPopup: requestOverlayPermission failed: $e');
    }
  }

  /// Single controlled STATE READ (plugin's isRunning API). Never throws.
  Future<bool> _isBubbleRunning() async {
    try {
      return await DashBubble.instance.isRunning();
    } catch (e) {
      debugPrint('FloatingPopup: isRunning failed: $e');
      return false;
    }
  }

  /// Single controlled START. Never starts a second instance and never throws.
  Future<bool> _startBubble() async {
    try {
      if (await _isBubbleRunning()) return true; // dedupe: never a 2nd instance
      return await DashBubble.instance.startBubble(
        bubbleOptions: BubbleOptions(
          bubbleIcon: 'ic_bubble_shield', // dedicated shield drawable (res/drawable)
          bubbleSize: 60,
          enableClose: true,
          distanceToClose: 100,
        ),
        onTap: _onFloatingBubbleTapped, // unchanged: toggles Call Shield monitoring
      );
    } catch (e) {
      debugPrint('FloatingPopup: startBubble failed: $e');
      return false;
    }
  }

  /// Single controlled STOP. Never throws; returns the resulting running state.
  Future<bool> _stopBubble() async {
    try {
      if (await _isBubbleRunning()) {
        await DashBubble.instance.stopBubble();
      }
    } catch (e) {
      debugPrint('FloatingPopup: stopBubble failed: $e');
    }
    return _isBubbleRunning();
  }

  /// Persist the user's floating popup preference.
  Future<void> _setFloatingPopupPref(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_floatingPopupPrefKey, value);
    } catch (e) {
      debugPrint('FloatingPopup: saving preference failed: $e');
    }
  }

  /// Startup: restore the saved preference without ever blindly starting the
  /// bubble. Starts only when overlay permission is already granted; any
  /// failure leaves the app fully usable with the control showing OFF.
  Future<void> _initFloatingPopup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOn = prefs.getBool(_floatingPopupPrefKey) ?? false;
      if (!savedOn || !mounted) {
        if (mounted) setState(() => _floatingPopupOn = false);
        return;
      }
      if (!await _hasOverlayPermission()) {
        // Permission was revoked / never granted: never auto-request here.
        if (mounted) setState(() => _floatingPopupOn = false);
        return;
      }
      final running = await _startBubble(); // no-op when already running
      if (mounted) setState(() => _floatingPopupOn = running);
    } catch (e) {
      debugPrint('FloatingPopup: restore failed: $e');
      if (mounted) setState(() => _floatingPopupOn = false);
    }
  }

  /// App resumed: (1) if the user was granting overlay permission, re-check
  /// once and start only if it was actually granted; (2) otherwise re-sync
  /// the control with the real bubble state (covers permission revoked while
  /// the app existed, or the system stopping the service). Never re-opens the
  /// permission screen here and never force-starts the bubble repeatedly.
  Future<void> _syncFloatingPopupAfterResume() async {
    if (_floatingPopupBusy) return;
    final messenger = ScaffoldMessenger.of(context); // captured while context is valid
    try {
      if (_waitingForOverlayPermission) {
        _waitingForOverlayPermission = false;
        if (!mounted) return;
        if (await _hasOverlayPermission()) {
          await _onFloatingPopupControlPressed(turnOn: true);
        } else {
          setState(() => _floatingPopupOn = false);
          await _setFloatingPopupPref(false);
          messenger.showSnackBar(const SnackBar(
            content: Text('Overlay permission not granted — Floating Popup stays off'),
            duration: Duration(seconds: 3),
          ));
        }
        return;
      }
      final running = await _isBubbleRunning();
      if (!mounted || running == _floatingPopupOn) return;
      setState(() => _floatingPopupOn = running);
      if (!running) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_floatingPopupPrefKey) ?? false) {
          await _setFloatingPopupPref(false);
          messenger.showSnackBar(const SnackBar(
            content: Text('Floating Popup is off — overlay permission may have been revoked'),
            duration: Duration(seconds: 3),
          ));
        }
      }
    } catch (e) {
      debugPrint('FloatingPopup: resume sync failed: $e');
    }
  }

  /// The ONE entry point for the ON/OFF control. Debounced so rapid presses
  /// cannot race a start against a stop.
  Future<void> _onFloatingPopupControlPressed({bool? turnOn}) async {
    if (_floatingPopupBusy) return;
    _floatingPopupBusy = true;
    final bool enable = turnOn ?? !_floatingPopupOn;
    try {
      if (enable) {
        await _enableFloatingPopup();
      } else {
        await _disableFloatingPopup();
      }
    } finally {
      _floatingPopupBusy = false;
    }
  }

  Future<void> _enableFloatingPopup() async {
    final messenger = ScaffoldMessenger.of(context); // captured while context is valid
    // 1) Overlay permission must exist before any start attempt.
    if (!await _hasOverlayPermission()) {
      _waitingForOverlayPermission = true;
      await _requestOverlayPermission(); // opens system settings (no crash)
      if (!mounted) return;
      setState(() => _floatingPopupOn = false);
      await _setFloatingPopupPref(false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Overlay permission required to show the Floating Popup'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 3),
      ));
      return;
    }
    // 2) Single controlled START (dedupe + try/catch inside).
    final ok = await _startBubble();
    if (!mounted) return;
    setState(() => _floatingPopupOn = ok);
    await _setFloatingPopupPref(ok);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? '🟢 Floating Popup: ON'
          : '⚪ Floating Popup could not start on this device'),
      backgroundColor: ok ? const Color(0xFF6366F1) : Colors.redAccent,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _disableFloatingPopup() async {
    final messenger = ScaffoldMessenger.of(context); // captured while context is valid
    // Single controlled STOP (running-state check + try/catch inside).
    final stillRunning = await _stopBubble();
    if (!mounted) return;
    // Recover the UI to the ACTUAL state, whatever the stop call did.
    setState(() => _floatingPopupOn = stillRunning);
    await _setFloatingPopupPref(stillRunning);
    messenger.showSnackBar(SnackBar(
      content: Text(stillRunning
          ? '⚠️ Floating Popup could not be stopped'
          : '⚪ Floating Popup: OFF'),
      backgroundColor: stillRunning ? Colors.redAccent : Colors.grey,
      duration: const Duration(seconds: 2),
    ));
  }

  /// Unchanged bubble behaviour: tapping the floating popup toggles
  /// Call Shield monitoring exactly as before.
  void _onFloatingBubbleTapped() {
    if (!mounted) return;
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
  }

  // 🆕 MESSAGE SHIELD (additive only): cold-start share / PROCESS_TEXT intake.
  // It only navigates into Message Shield; Call Shield's own flow is untouched.
  Future<void> _openSharedMessageIfAny() async {
    try {
      final MessageInput? shared =
          await MessageIngestService().consumeSharedPayload();
      if (shared == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ScanMessageScreen(
            initialText: shared.text,
            initialSender: shared.sender,
            initialChannel: MessageChannel.share,
            initialOrigin: shared.origin,
          ),
        ),
      );
    } catch (_) {
      // Never let Message Shield intake disturb the Call Shield home screen.
    }
  }

  // The old one-way "_startFloatingBubble" was removed; the ON/OFF control
  // above is now the single path for everything bubble-related.

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
            icon: const Icon(Icons.play_circle_outline, color: Colors.tealAccent),
            tooltip: "Interactive Demo",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DemoScreen()),
              );
            },
          ),
          // FLOATING POPUP ON/OFF control (replaces the one-way
          // "Launch Floating Bubble"): shield icon + explicit ON/OFF state.
          Tooltip(
            message: 'Floating Popup: ${_floatingPopupOn ? "ON" : "OFF"}',
            child: Semantics(
              label: 'Floating Popup ${_floatingPopupOn ? "ON" : "OFF"}',
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _onFloatingPopupControlPressed(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        size: 22,
                        color: _floatingPopupOn ? Colors.greenAccent : Colors.white38,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _floatingPopupOn ? 'ON' : 'OFF',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _floatingPopupOn ? Colors.greenAccent : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard, color: Color(0xFF6366F1)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ThreatDashboard()),
              );
            },
          ),
          // 🆕 MESSAGE SHIELD (additive only): opens the new protection section.
          IconButton(
            icon: const Icon(Icons.sms_failed_rounded, color: Color(0xFF10B981)),
            tooltip: "Message Shield",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MessageShieldHomeScreen()),
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