import 'package:flutter/foundation.dart';

import '../database/message_shield_store.dart';
import '../services/message_shield_service.dart';

/// Optional hook for the background isolate Call Shield already runs.
///
/// Message Shield has its own Android foreground service
/// (`MessageShieldProtectionService` + `messageShieldProtectionMain`) which is
/// the primary, event-driven path: the SMS receiver hands each message straight
/// to it, so there is no polling anywhere.
///
/// This bridge stays as a *safety net* with a single additive call in
/// `services/background_service.dart`:
///
///   await MessageShieldBackgroundBridge.attach(service);
///
/// When that isolate happens to be alive it drains anything left in the native
/// inbox once, and then stays idle. It never touches call state, alerts, SOS,
/// Grandma Mode or reports, and it sends nothing over the network.
class MessageShieldBackgroundBridge {
  MessageShieldBackgroundBridge._();

  static bool _attached = false;

  static Future<void> attach(dynamic service) async {
    if (_attached) return;
    _attached = true;
    try {
      final MessageShieldStore store = MessageShieldStore();
      await store.refresh();
      final MessageShieldSettings settings = await store.settings();
      if (!settings.autoProtectionEnabled) {
        debugPrint('🛡️ [MessageShield] automatic protection off - bridge idle');
        return;
      }

      final MessageShieldService shield = MessageShieldService();
      await shield.ensureInitialized();

      // One-shot drain of the native inbox. Anything that arrives later is
      // pushed straight to Message Shield's own foreground service, and the UI
      // drains the rest on resume.
      final MessageShieldStats before = await store.stats();
      await shield.drainIncoming(notify: true, appInForeground: false);
      final MessageShieldStats after = await store.stats();
      if (after.analyzed > before.analyzed) {
        debugPrint(
          '🛡️ [MessageShield] analysed ${after.analyzed - before.analyzed} queued message(s)',
        );
        try {
          service.invoke('message_shield_update', <String, dynamic>{
            'analyzed': after.analyzed - before.analyzed,
          });
        } catch (_) {
          // The background service instance may not support invoke here.
        }
      }
    } catch (e) {
      debugPrint('🛡️ [MessageShield] bridge attach failed: $e');
      _attached = false;
    }
  }

  static void detach() {
    _attached = false;
  }
}
