/// Where a message came from.
///
/// Every field here is filled in *only* when Android actually handed the value
/// to the app (SMS broadcast extras, the launching intent, the referring app).
/// When Android does not expose something, the field stays `null` and the UI
/// says so instead of guessing. Nothing in this class is inferred from the
/// message text and nothing is read from other applications.
class MessageOrigin {
  const MessageOrigin({
    this.appPackage,
    this.appLabel,
    this.shareAction,
    this.simSlot,
    this.carrier,
    this.subscriptionId,
    this.originatingAddress,
    this.senderAlias,
    this.deliveredAt,
  });

  /// Package name of the app that shared/selected the text into CallShield.
  /// Usually null for the system share sheet: Android only reports the source
  /// app when a referrer is set (see the report / UI wording).
  final String? appPackage;

  /// Human-readable name of [appPackage] when Android could resolve it.
  final String? appLabel;

  /// Raw intent action, e.g. `android.intent.action.SEND`.
  final String? shareAction;

  /// 0-based SIM slot index, when the device exposes it.
  final int? simSlot;

  /// Carrier / operator name of the receiving subscription, when available.
  final String? carrier;

  /// Android subscription id of the SIM that received the SMS.
  final int? subscriptionId;

  /// SMS originating address as reported by Android (falls back to the display
  /// sender id when the carrier only sent the alphanumeric id).
  final String? originatingAddress;

  /// The alphanumeric sender id / address Android reported for this SMS
  /// (for example `VM-SBIINB`). Never invented.
  final String? senderAlias;

  /// When Android delivered the message to the app (SMS service-centre
  /// timestamp when the broadcast carried one).
  final DateTime? deliveredAt;

  bool get isEmpty =>
      appPackage == null &&
      appLabel == null &&
      shareAction == null &&
      simSlot == null &&
      carrier == null &&
      subscriptionId == null &&
      originatingAddress == null &&
      senderAlias == null &&
      deliveredAt == null;

  bool get hasAppSource => (appPackage ?? '').trim().isNotEmpty;

  /// Friendly app name: the label Android resolved, else a locally known name
  /// for the package, else the raw package name (never a made-up brand).
  String? get appDisplayName {
    final String? label = appLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final String? pkg = appPackage?.trim();
    if (pkg == null || pkg.isEmpty) return null;
    return knownApps[pkg] ?? pkg;
  }

  /// SIM slot as humans count (1-based) when Android gave us an index.
  int? get simSlotNumber => simSlot == null ? null : simSlot! + 1;

  MessageOrigin copyWith({
    String? appPackage,
    String? appLabel,
    String? shareAction,
    int? simSlot,
    String? carrier,
    int? subscriptionId,
    String? originatingAddress,
    String? senderAlias,
    DateTime? deliveredAt,
  }) =>
      MessageOrigin(
        appPackage: appPackage ?? this.appPackage,
        appLabel: appLabel ?? this.appLabel,
        shareAction: shareAction ?? this.shareAction,
        simSlot: simSlot ?? this.simSlot,
        carrier: carrier ?? this.carrier,
        subscriptionId: subscriptionId ?? this.subscriptionId,
        originatingAddress: originatingAddress ?? this.originatingAddress,
        senderAlias: senderAlias ?? this.senderAlias,
        deliveredAt: deliveredAt ?? this.deliveredAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (appPackage != null) 'appPackage': appPackage,
        if (appLabel != null) 'appLabel': appLabel,
        if (shareAction != null) 'shareAction': shareAction,
        if (simSlot != null) 'simSlot': simSlot,
        if (carrier != null) 'carrier': carrier,
        if (subscriptionId != null) 'subscriptionId': subscriptionId,
        if (originatingAddress != null) 'originatingAddress': originatingAddress,
        if (senderAlias != null) 'senderAlias': senderAlias,
        if (deliveredAt != null) 'deliveredAt': deliveredAt!.toIso8601String(),
      };

  static MessageOrigin? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final MessageOrigin origin = MessageOrigin(
      appPackage: _string(json['appPackage']),
      appLabel: _string(json['appLabel']),
      shareAction: _string(json['shareAction']),
      simSlot: (json['simSlot'] as num?)?.toInt(),
      carrier: _string(json['carrier']),
      subscriptionId: (json['subscriptionId'] as num?)?.toInt(),
      originatingAddress: _string(json['originatingAddress']),
      senderAlias: _string(json['senderAlias']),
      deliveredAt: json['deliveredAt'] == null
          ? null
          : DateTime.tryParse(json['deliveredAt'] as String),
    );
    return origin.isEmpty ? null : origin;
  }

  static String? _string(Object? value) {
    final String? s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Locally known package → app name table. This is a *display* convenience for
  /// packages Android actually reported to us; it never fabricates a source.
  static const Map<String, String> knownApps = <String, String>{
    'com.whatsapp': 'WhatsApp',
    'com.whatsapp.w4b': 'WhatsApp Business',
    'org.telegram.messenger': 'Telegram',
    'org.thunderdog.challegram': 'Telegram X',
    'com.google.android.apps.messaging': 'Google Messages',
    'com.android.mms': 'Messages',
    'com.samsung.android.messaging': 'Samsung Messages',
    'com.google.android.gm': 'Gmail',
    'com.microsoft.office.outlook': 'Outlook',
    'com.yahoo.mobile.client.android.mail': 'Yahoo Mail',
    'com.android.chrome': 'Chrome',
    'com.brave.browser': 'Brave',
    'org.mozilla.firefox': 'Firefox',
    'com.opera.browser': 'Opera',
    'com.instagram.android': 'Instagram',
    'com.facebook.katana': 'Facebook',
    'com.facebook.orca': 'Messenger',
    'org.thoughtcrime.securesms': 'Signal',
    'com.slack': 'Slack',
    'com.discord': 'Discord',
    'com.linkedin.android': 'LinkedIn',
    'com.twitter.android': 'X',
    'com.truecaller': 'Truecaller',
    'com.google.android.googlequicksearchbox': 'Google',
    'com.microsoft.teams': 'Microsoft Teams',
    'com.viber.voip': 'Viber',
    'com.tencent.mm': 'WeChat',
    'com.google.android.apps.docs': 'Google Drive',
    'com.android.shell': 'Android shell (adb)',
  };
}
