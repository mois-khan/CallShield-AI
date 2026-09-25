/// Scam / spam taxonomy used by Message Shield.
///
/// Adding a category is a data change, not an engine change: append an entry to
/// [ScamCategory.all] (and optionally to the intelligence asset) and the rule,
/// behaviour, risk and UI layers pick it up automatically.
class ScamCategory {
  const ScamCategory({
    required this.id,
    required this.label,
    required this.group,
    this.isSpam = false,
    this.fallbackObjectives = const <String>[],
    this.fallbackActions = const <String>[],
  });

  final String id;
  final String label;
  final String group;

  /// Bulk/promotional spam is tracked separately from scams in the dashboard.
  final bool isSpam;

  /// Used when the intelligence asset has no richer mapping for [id].
  final List<String> fallbackObjectives;
  final List<String> fallbackActions;

  static const ScamCategory legitimate = ScamCategory(
    id: 'legitimate',
    label: 'Looks legitimate',
    group: 'legitimate',
  );

  static const ScamCategory financialFraud = ScamCategory(
    id: 'financial_fraud',
    label: 'Financial fraud',
    group: 'financial',
    fallbackObjectives: ['Move your money to the scammer'],
    fallbackActions: [
      'Do not transfer or approve any payment',
      'Do not share card details, UPI PIN or CVV',
      'Check the transaction only in your bank app',
    ],
  );

  static const ScamCategory credentialTheft = ScamCategory(
    id: 'credential_theft',
    label: 'Credential / OTP theft',
    group: 'credential',
    fallbackObjectives: ['Steal your authentication information'],
    fallbackActions: [
      'Do not share OTP, PIN, CVV or passwords with anyone',
      'Do not read the code out over a call',
      'Do not enter credentials on links from messages',
    ],
  );

  static const ScamCategory impersonation = ScamCategory(
    id: 'impersonation',
    label: 'Impersonation',
    group: 'impersonation',
    fallbackObjectives: ['Pressure you using a fake authority'],
    fallbackActions: [
      'Do not trust the claimed identity',
      'Verify with the official app, website or number',
      'No government agency demands instant payment by UPI',
    ],
  );

  static const ScamCategory socialEngineering = ScamCategory(
    id: 'social_engineering',
    label: 'Social engineering / coercion',
    group: 'social',
    fallbackObjectives: ['Panic you into acting without checking'],
    fallbackActions: [
      'Stop and talk to someone you trust before acting',
      'Do not send money based on a message alone',
      'Call the person back on their known number',
    ],
  );

  static const ScamCategory investmentScam = ScamCategory(
    id: 'investment_scam',
    label: 'Investment / job scam',
    group: 'opportunity',
    fallbackObjectives: ['Get you to invest or pay an upfront fee'],
    fallbackActions: [
      'Do not pay any registration, training or processing fee',
      'No genuine scheme guarantees fixed daily returns',
      'Check SEBI/RBI registration before investing',
    ],
  );

  static const ScamCategory rewardScam = ScamCategory(
    id: 'reward_scam',
    label: 'Lottery / reward scam',
    group: 'reward',
    fallbackObjectives: ['Make you pay a fee to "release" a prize'],
    fallbackActions: [
      'You cannot win a lottery you never entered',
      'Never pay a fee or tax to receive a prize',
      'Do not share bank details for a "cashback"',
    ],
  );

  static const ScamCategory deliveryScam = ScamCategory(
    id: 'delivery_scam',
    label: 'Courier / customs scam',
    group: 'delivery',
    fallbackObjectives: ['Collect a fake delivery or customs fee'],
    fallbackActions: [
      'Track the parcel only on the official courier app',
      'Customs never collects duty over chat or UPI links',
      'Do not pay a redelivery fee to an unknown account',
    ],
  );

  static const ScamCategory extortion = ScamCategory(
    id: 'extortion',
    label: 'Extortion / blackmail',
    group: 'coercion',
    fallbackObjectives: ['Blackmail you with threats or private content'],
    fallbackActions: [
      'Do not pay, paying rarely stops blackmail',
      'Keep screenshots as evidence',
      'Report to the cybercrime portal and local police',
    ],
  );

  static const ScamCategory romanceScam = ScamCategory(
    id: 'romance_scam',
    label: 'Romance / relationship scam',
    group: 'social',
    fallbackObjectives: ['Use an emotional bond to extract money'],
    fallbackActions: [
      'Be careful if money is requested before you ever meet',
      'Do not send gift cards, crypto or remittances',
      'Reverse image search the profile photo',
    ],
  );

  static const ScamCategory subscriptionTrap = ScamCategory(
    id: 'subscription_trap',
    label: 'Subscription / payment trap',
    group: 'financial',
    fallbackObjectives: ['Trap you into a recurring payment'],
    fallbackActions: [
      'Do not approve UPI collect requests you did not initiate',
      'Review mandates in your bank / UPI app',
      'Block the sender number',
    ],
  );

  static const ScamCategory phishing = ScamCategory(
    id: 'phishing',
    label: 'Phishing link',
    group: 'phishing',
    fallbackObjectives: ['Get you to open a credential-harvesting page'],
    fallbackActions: [
      'Do not tap the link',
      'Open the official app instead and check the alert there',
      'Block and report the sender',
    ],
  );

  static const ScamCategory suspicious = ScamCategory(
    id: 'suspicious',
    label: 'Suspicious message',
    group: 'unknown',
  );

  static const ScamCategory spam = ScamCategory(
    id: 'spam',
    label: 'Spam',
    group: 'spam',
    isSpam: true,
  );

  static const ScamCategory promotional = ScamCategory(
    id: 'promotional',
    label: 'Promotional (with opt-out)',
    group: 'legitimate',
  );

  static const List<ScamCategory> all = <ScamCategory>[
    legitimate,
    spam,
    promotional,
    phishing,
    financialFraud,
    credentialTheft,
    impersonation,
    socialEngineering,
    investmentScam,
    rewardScam,
    deliveryScam,
    extortion,
    romanceScam,
    subscriptionTrap,
    suspicious,
  ];

  static final Map<String, ScamCategory> _byId = <String, ScamCategory>{
    for (final ScamCategory c in all) c.id: c,
  };

  static ScamCategory byId(String id) => _byId[id] ?? suspicious;

  @override
  String toString() => 'ScamCategory($id)';
}

/// Final verdict banding shown to the user.
enum RiskBand {
  safe('SAFE', 'No strong scam pattern found'),
  suspicious('SUSPICIOUS', 'Some scam signals were found'),
  scam('SCAM', 'Multiple strong scam signals found');

  const RiskBand(this.label, this.description);

  final String label;
  final String description;

  static RiskBand fromScore(int score) {
    if (score >= RiskEngineThresholds.scam) return RiskBand.scam;
    if (score >= RiskEngineThresholds.suspicious) return RiskBand.suspicious;
    return RiskBand.safe;
  }
}

/// Score boundaries used by the risk engine (kept in one place for tuning).
class RiskEngineThresholds {
  const RiskEngineThresholds._();

  static const int suspicious = 30;
  static const int scam = 60;
}
