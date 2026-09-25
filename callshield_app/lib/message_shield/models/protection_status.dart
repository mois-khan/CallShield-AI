/// Coarse health of Message Shield's background protection.
///
/// Derived only from real Android state (permissions, whether the foreground
/// service is alive, whether the app is exempt from battery optimisation).
enum ProtectionHealth {
  /// The user turned automatic protection off.
  off,

  /// Everything Android needs is in place.
  active,

  /// Working, but Android may delay or stop background work.
  restricted,

  /// A permission is missing, so automatic screening cannot run.
  permissionRequired,
}

/// Snapshot of the native background-protection state.
class ProtectionStatus {
  const ProtectionStatus({
    this.sdkInt = 0,
    this.autoProtectionEnabled = false,
    this.smsPermissionGranted = false,
    this.notificationPermissionGranted = false,
    this.batteryOptimizationIgnored = false,
    this.serviceRunning = false,
    this.bootRecoveryRegistered = false,
    this.receiverRegistered = false,
    this.carrierLabel,
  });

  /// Android API level of the device (0 when unknown).
  final int sdkInt;

  /// User setting, mirrored into native preferences for the SMS receiver.
  final bool autoProtectionEnabled;

  /// RECEIVE_SMS granted.
  final bool smsPermissionGranted;

  /// POST_NOTIFICATIONS granted (always true below Android 13).
  final bool notificationPermissionGranted;

  /// `PowerManager.isIgnoringBatteryOptimizations(packageName)`.
  final bool batteryOptimizationIgnored;

  /// The Message Shield foreground service is currently alive.
  final bool serviceRunning;

  /// The boot/recovery receiver is declared in the manifest.
  final bool bootRecoveryRegistered;

  /// The SMS broadcast receiver is declared in the manifest.
  final bool receiverRegistered;

  /// Carrier name of the default SMS subscription, when Android exposes it.
  final String? carrierLabel;

  bool get batteryOptimized => !batteryOptimizationIgnored;

  /// Android 13+ only: below that, notification permission is implicit.
  bool get notificationPermissionRequired => sdkInt >= 33;

  ProtectionHealth get health {
    if (!autoProtectionEnabled) return ProtectionHealth.off;
    if (!smsPermissionGranted) return ProtectionHealth.permissionRequired;
    if (!serviceRunning) return ProtectionHealth.restricted;
    if (notificationPermissionRequired && !notificationPermissionGranted) {
      return ProtectionHealth.restricted;
    }
    if (batteryOptimized) return ProtectionHealth.restricted;
    return ProtectionHealth.active;
  }

  String get emoji {
    switch (health) {
      case ProtectionHealth.active:
        return '🟢';
      case ProtectionHealth.restricted:
        return '🟡';
      case ProtectionHealth.permissionRequired:
        return '🔴';
      case ProtectionHealth.off:
        return '⚪';
    }
  }

  String get headline {
    switch (health) {
      case ProtectionHealth.active:
        return 'Active';
      case ProtectionHealth.restricted:
        return 'Restricted by Android';
      case ProtectionHealth.permissionRequired:
        return 'Permission required';
      case ProtectionHealth.off:
        return 'Automatic protection is off';
    }
  }

  /// One-line explanation of the current state (never overstates protection).
  String get explanation {
    switch (health) {
      case ProtectionHealth.active:
        return 'Message Shield is listening for new SMS in the background and '
            'analysing them on this device.';
      case ProtectionHealth.restricted:
        if (!serviceRunning) {
          return 'The background service is not running right now. It restarts '
              'automatically when Android allows it (app opened, SMS received, '
              'or device rebooted).';
        }
        if (notificationPermissionRequired && !notificationPermissionGranted) {
          return 'Notifications are blocked, so alerts and the ongoing '
              'protection notice are hidden. Analysis still happens on device.';
        }
        return 'Android is allowed to delay background work for this app. '
            'Exempting it makes background screening more reliable.';
      case ProtectionHealth.permissionRequired:
        return 'The SMS permission is not granted, so incoming messages cannot '
            'be screened automatically. Manual scanning still works.';
      case ProtectionHealth.off:
        return 'Turn on Automatic protection to screen incoming SMS in the '
            'background. Manual scanning is always available.';
    }
  }

  factory ProtectionStatus.fromJson(Map<dynamic, dynamic> json) => ProtectionStatus(
        sdkInt: (json['sdkInt'] as num?)?.toInt() ?? 0,
        autoProtectionEnabled: json['autoProtectionEnabled'] as bool? ?? false,
        smsPermissionGranted: json['smsPermissionGranted'] as bool? ?? false,
        notificationPermissionGranted:
            json['notificationPermissionGranted'] as bool? ?? true,
        batteryOptimizationIgnored:
            json['batteryOptimizationIgnored'] as bool? ?? false,
        serviceRunning: json['serviceRunning'] as bool? ?? false,
        bootRecoveryRegistered: json['bootRecoveryRegistered'] as bool? ?? false,
        receiverRegistered: json['receiverRegistered'] as bool? ?? false,
        carrierLabel: json['carrierLabel']?.toString(),
      );
}
