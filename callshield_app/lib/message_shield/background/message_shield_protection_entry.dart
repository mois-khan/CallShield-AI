import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../database/message_shield_store.dart';
import '../services/message_shield_service.dart';

/// Method channel owned by Message Shield's own Android foreground service.
///
/// The Kotlin service (`MessageShieldProtectionService`) starts a headless
/// Flutter engine on this entry point, pushes each incoming SMS onto it and
/// waits for the on-device verdict. Nothing here touches Call Shield.
const String protectionChannelName = 'com.callshield.native/message_shield_bg';

/// Entry point for the headless engine inside the protection foreground service.
///
/// Runs independently of the visible Flutter UI:
///   * `analyzePayload`  - one SMS handed over directly by the SMS receiver
///   * `analyzePending`  - drain anything queued in the native inbox file
///                         (used after boot / service restart / app update)
///   * `snapshot`        - current counters, used for logs and diagnostics
@pragma('vm:entry-point')
Future<void> messageShieldProtectionMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugins (shared_preferences, path_provider, flutter_local_notifications)
  // must be available in this engine too.
  DartPluginRegistrant.ensureInitialized();

  const MethodChannel channel = MethodChannel(protectionChannelName);
  final MessageShieldService service = MessageShieldService();
  final MessageShieldStore store = service.store;
  await service.ensureInitialized();
  await store.refresh();
  debugPrint('🛡️ [MessageShieldService] background engine ready');

  /// Analyses everything the native receiver queued. Guarded so overlapping
  /// requests never run concurrently.
  Future<int> drainQueued({required bool appInForeground}) async {
    try {
      final List<dynamic> results = await service.drainIncoming(
        notify: true,
        appInForeground: appInForeground,
      );
      if (results.isNotEmpty) {
        debugPrint('🛡️ [MessageShieldService] analysed ${results.length} queued message(s)');
      }
      final MessageShieldStats stats = await store.stats();
      return stats.analyzed;
    } catch (e) {
      debugPrint('🛡️ [MessageShieldService] queued analysis failed: $e');
      // One bounded retry: the failed message stays in the inbox file, so a
      // later drain (or the next SMS) would still pick it up.
      Timer(const Duration(seconds: 20), () {
        drainQueued(appInForeground: appInForeground);
      });
      return -1;
    }
  }

  channel.setMethodCallHandler((MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments is Map
        ? Map<dynamic, dynamic>.from(call.arguments as Map)
        : <dynamic, dynamic>{};
    final bool appInForeground = args['appForeground'] as bool? ?? false;
    switch (call.method) {
      case 'analyzePayload':
        try {
          final dynamic result = await service.analyzeIncomingPayload(
            args,
            notify: true,
            appInForeground: appInForeground,
          );
          if (result != null) {
            debugPrint(
              '🛡️ [MessageShieldService] background verdict: '
              '${result.riskScore}/100 (${result.band.name})',
            );
          }
          return result?.riskScore;
        } catch (e) {
          debugPrint('🛡️ [MessageShieldService] payload analysis failed: $e');
          return -1;
        }
      case 'analyzePending':
        return drainQueued(appInForeground: appInForeground);
      case 'ping':
        return 'pong';
      default:
        return null;
    }
  });

  // Tell the service the Dart side can receive messages now (messages that
  // arrived while the engine was starting are delivered after this).
  try {
    await channel.invokeMethod<void>('dartReady');
  } catch (e) {
    debugPrint('🛡️ [MessageShieldService] dartReady handshake failed: $e');
  }
}
