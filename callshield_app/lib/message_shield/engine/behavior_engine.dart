import '../models/scam_category.dart';
import '../models/shield_signal.dart';
import 'preprocessor.dart';

/// What the sender is trying to get the user to do.
class BehaviorIntent {
  const BehaviorIntent({
    required this.id,
    required this.label,
    required this.objective,
    required this.actions,
    required this.category,
    required this.weight,
    required this.patterns,
    this.requiresPatterns = const <RegExp>[],
    this.suppressPattern,
    this.ignoreNegated = true,
  });

  final String id;
  final String label;

  /// Plain-language "likely attacker objective".
  final String objective;

  /// Recommended actions for the user.
  final List<String> actions;
  final ScamCategory category;
  final int weight;
  final List<RegExp> patterns;

  /// At least one of these must also match (keeps precision high).
  final List<RegExp> requiresPatterns;

  /// Matches that cancel this probe (e.g. "call our official helpline").
  final RegExp? suppressPattern;

  /// When true a negated instruction ("do not share the OTP") is ignored.
  final bool ignoreNegated;
}

/// A detected behaviour with its evidence.
class BehaviorFinding {
  const BehaviorFinding({
    required this.intent,
    required this.confidence,
    this.evidence,
  });

  final BehaviorIntent intent;
  final double confidence;
  final String? evidence;

  ShieldSignal toSignal() => ShieldSignal(
        id: 'intent_${intent.id}',
        family: 'intent:${intent.id}',
        category: intent.category,
        weight: (intent.weight * confidence).round().clamp(1, 100),
        label: intent.label,
        source: SignalSource.behavior,
        detail: intent.objective,
        matchedText: evidence,
      );
}

/// Behaviour engine: the "what does the sender want me to do" stage.
///
/// This is deliberately the strongest part of the pipeline: a message that asks
/// for an OTP, money, crypto, credentials, a remote-access app or secrecy is
/// dangerous regardless of how it is worded.
class BehaviorEngine {
  BehaviorEngine({List<BehaviorIntent>? intents}) : intents = intents ?? BehaviorCatalog.intents;

  final List<BehaviorIntent> intents;

  List<BehaviorFinding> detect(ProcessedMessage msg) {
    final List<BehaviorFinding> findings = <BehaviorFinding>[];
    for (final BehaviorIntent intent in intents) {
      if (intent.suppressPattern != null &&
          (intent.suppressPattern!.hasMatch(msg.clean) ||
              intent.suppressPattern!.hasMatch(msg.verbText))) {
        continue;
      }
      final RegExp? hit = _firstHit(intent.patterns, msg, intent.ignoreNegated);
      if (hit == null) continue;
      if (intent.requiresPatterns.isNotEmpty &&
          _firstHit(intent.requiresPatterns, msg, false) == null) {
        continue;
      }
      findings.add(
        BehaviorFinding(
          intent: intent,
          confidence: _confidence(intent, msg),
          evidence: _evidence(msg, hit),
        ),
      );
    }
    findings.sort((BehaviorFinding a, BehaviorFinding b) => b.intent.weight.compareTo(a.intent.weight));
    return findings;
  }

  List<ShieldSignal> signals(ProcessedMessage msg) =>
      detect(msg).map((BehaviorFinding f) => f.toSignal()).toList(growable: false);

  /// Finds the first non-negated hit across the clean, skeleton and
  /// verb-neutralised views.
  RegExp? _firstHit(List<RegExp> patterns, ProcessedMessage msg, bool ignoreNegated) {
    for (final RegExp p in patterns) {
      for (final String text in <String>[msg.clean, msg.verbText, msg.skeleton]) {
        for (final RegExpMatch m in p.allMatches(text)) {
          if (ignoreNegated && msg.isNegatedInstruction(m.start, m.end)) continue;
          return p;
        }
      }
    }
    return null;
  }

  double _confidence(BehaviorIntent intent, ProcessedMessage msg) {
    double confidence = 0.85;
    if (intent.patterns.length > 1) {
      int hits = 0;
      for (final RegExp p in intent.patterns) {
        if (p.hasMatch(msg.clean) || p.hasMatch(msg.skeleton) || p.hasMatch(msg.verbText)) hits++;
      }
      if (hits > 1) confidence += 0.1;
    }
    if (intent.requiresPatterns.isNotEmpty) confidence += 0.05;
    return confidence.clamp(0.5, 1.0);
  }

  String? _evidence(ProcessedMessage msg, RegExp pattern) {
    final Match? m = pattern.firstMatch(msg.clean) ?? pattern.firstMatch(msg.skeleton);
    final String? value = m?.group(0);
    if (value == null || value.isEmpty) return null;
    return value.length > 60 ? '${value.substring(0, 60)}…' : value;
  }
}

/// Behaviour probe catalog (data only).
class BehaviorCatalog {
  const BehaviorCatalog._();

  static RegExp _r(String p) => RegExp(p, caseSensitive: false);

  /// CVV written plainly or obfuscated: cvv, c.v.v, c v v.
  static const String _cvv = r'c[\s._*-]{0,2}v[\s._*-]{0,2}v';

  static final RegExp _moneyWord = _r(r'\b(rs\.?|inr|₹|\$|money|amount|cash|funds|paise|paisa|rupaye)\b');
  static final RegExp _paymentVerb = _r(r'\b(pay|paid|transfer|send|deposit|remit|bhej|jama|approve|accept|credit)\b');
  static final RegExp _bankContext = _r(
    r'\b(account|bank|upi|wallet|card|transaction|beneficiary|ifsc|balance|loan|refund|emi|policy)\b',
  );

  /// OTP written plainly or obfuscated: otp, 0tp, o.t.p, O T P, o t p.
  static const String _otpAbbr = r'0?[o0][\s._*-]{0,3}t[\s._*-]{0,3}p';

  static final List<BehaviorIntent> intents = <BehaviorIntent>[
    BehaviorIntent(
      id: 'share_otp',
      label: 'Wants your OTP / verification code',
      objective: 'Steal authentication information (OTP) to access your account',
      actions: <String>[
        'Do not reply and do not share the OTP',
        'Nobody legitimate - not even bank staff - needs your OTP',
        'If you already shared it, change your passwords and call your bank',
      ],
      category: ScamCategory.credentialTheft,
      weight: 78,
      patterns: <RegExp>[
        _r('\\b(share|send|tell|provide|read|forward|confirm|reply with|bata|bhej)\\b[^.!?]{0,40}\\b($_otpAbbr|one[- ]time password|verification code|security code|code)\\b'),
        _r('\\b($_otpAbbr|verification code|security code)\\b[^.!?]{0,40}\\b(share|send|tell|provide|read|forward|bata|bhej|to me|with me|with our officer)\\b'),
      ],
    ),
    BehaviorIntent(
      id: 'share_pin_password',
      label: 'Wants your PIN / password / CVV',
      objective: 'Steal your banking credentials',
      actions: <String>[
        'Never share PIN, CVV, passwords or MPIN with anyone',
        'Change the PIN/password if you already shared it',
      ],
      category: ScamCategory.credentialTheft,
      weight: 76,
      patterns: <RegExp>[
        _r('\\b(share|send|tell|provide|read|enter|confirm|type|reply with)\\b[^.!?]{0,40}\\b(pin|mpin|upi pin|atm pin|$_cvv|password|passcode|net ?banking password)\\b'),
        _r('\\b($_cvv|pin|mpin|password|passcode)\\b[^.!?]{0,30}\\b(share|send|tell|provide|read|unblock)\\b'),
      ],
    ),
    BehaviorIntent(
      id: 'reveal_bank_details',
      label: 'Wants your card / account details',
      objective: 'Harvest card and account details',
      actions: <String>[
        'Do not share card number, expiry, CVV or account details',
        'Verify through your bank app instead',
      ],
      category: ScamCategory.financialFraud,
      weight: 68,
      patterns: <RegExp>[
        _r(r'\b(share|provide|send|confirm|enter|tell)\b[^.!?]{0,40}\b(card number|16 digit|account number|ifsc|expiry|aadhaar|pan|date of birth)\b'),
        _r(r'\b(16 digit|card number|account number|aadhaar number)\b[^.!?]{0,30}\b(share|provide|confirm|send|verify)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'send_money',
      label: 'Wants you to send money',
      objective: 'Move your money to the scammer',
      actions: <String>[
        'Do not transfer any money',
        'No genuine refund, prize or penalty is paid by sending money first',
      ],
      category: ScamCategory.financialFraud,
      weight: 70,
      patterns: <RegExp>[
        _r(r'\b(pay|transfer|send|deposit|remit|bhej|jama)\b[^.!?]{0,40}\b(rs\.?|inr|₹|\$)\s?\d'),
        _r(r'\b(pay|transfer|send|deposit)\b[^.!?]{0,40}\b(upi|account|wallet|this number|@ybl|@paytm|@ok\w+)\b'),
        _r(r'\b(transfer|send) (the )?(money|amount|funds) (to|back to|immediately)\b'),
      ],
      requiresPatterns: <RegExp>[_moneyWord, _bankContext, _r(r'\b(upi|wallet)\b')],
      // "Google Pay wallet balance is Rs.x" names a brand and an amount but is
      // a balance notification, not a payment instruction.
      suppressPattern:
          _r(r'\b(google ?pay|gpay|phone ?pe|phonepe|amazon pay|paytm|payment app|wallet balance)\b'),
    ),
    BehaviorIntent(
      id: 'approve_payment_request',
      label: 'Wants you to approve a collect request',
      objective: 'Trick you into authorising a debit from your account',
      actions: <String>[
        'Never approve a UPI collect request you did not create',
        'Approving sends money out, it never receives money',
      ],
      category: ScamCategory.financialFraud,
      weight: 76,
      patterns: <RegExp>[
        _r(r'\bapprove (the|this)?\s?(payment|collect|upi)?\s?request\b'),
        _r(r'\baccept (the|this) (payment|collect)? ?request\b'),
        _r(r'\benter (your )?upi pin to (receive|accept|complete)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'pay_fee',
      label: 'Wants an upfront fee',
      objective: 'Collect a fake fee, duty or processing charge',
      actions: <String>[
        'Never pay a fee to release a prize, refund, parcel or loan',
        'Customs and banks never collect charges over chat or UPI',
      ],
      category: ScamCategory.financialFraud,
      weight: 62,
      patterns: <RegExp>[
        _r(r'\b(processing|registration|activation|clearance|handling|redelivery|release|training|verification|convenience) (fee|charge|charges|deposit)\b'),
        _r(r'\bpay (rs\.? ?\d|[\d,]+ ?(rs|rupees))\b[^.!?]{0,30}\b(release|receive|claim|activate|unblock|complete|avoid)\b'),
        _r(r'\b(small|nominal|token) (fee|amount|charge)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'click_link',
      label: 'Wants you to open a link',
      objective: 'Get you onto a fake page that steals credentials or money',
      actions: <String>[
        'Do not tap the link',
        'Open the official app or type the official website yourself',
      ],
      category: ScamCategory.phishing,
      weight: 52,
      patterns: <RegExp>[
        _r(r'\b(click|open|visit|tap|log ?in|login|verify|update|re-?verify|claim|unlock|reactivate|complete) [^.!?]{0,40}(https?://|www\.|bit\.ly|tinyurl|\.xyz|\.top|\.click|\.info|\.ru\b)'),
        _r(r'\b(link|this link|given link|link below)\b[^.!?]{0,30}\b(open|click|verify|update|complete)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'share_screen_or_install',
      label: 'Wants a remote-access app or screen share',
      objective: 'See your screen to read OTPs and operate your banking app',
      actions: <String>[
        'Never install AnyDesk/TeamViewer/QuickSupport at someone else\'s request',
        'Never share your screen while banking',
      ],
      category: ScamCategory.socialEngineering,
      weight: 84,
      patterns: <RegExp>[
        _r(r'\b(anydesk|teamviewer|quick ?support|rustdesk|airdroid|screen ?(share|sharing)|mirror your screen)\b'),
        _r(r'\b(install|download)\b[^.!?]{0,30}\b(app|application|apk|software)\b[^.!?]{0,30}\b(verification|support|help|refund|kyc|bank)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'transfer_crypto',
      label: 'Wants crypto sent',
      objective: 'Receive funds that cannot be reversed or traced',
      actions: <String>[
        'Do not send crypto - transfers are irreversible',
        'Treat any crypto wallet demand as a scam',
      ],
      category: ScamCategory.financialFraud,
      weight: 74,
      patterns: <RegExp>[
        _r(r'\b(send|transfer|deposit|pay)\b[^.!?]{0,40}\b(usdt|btc|bitcoin|ethereum|crypto|tron|trc20|wallet address)\b'),
        _r(r'\b(wallet address|seed phrase|binance id)\b'),
      ],
      requiresPatterns: <RegExp>[_paymentVerb, _r(r'\b(crypto|usdt|btc|bitcoin|wallet)\b')],
    ),
    BehaviorIntent(
      id: 'share_personal_info',
      label: 'Wants personal documents / KYC data',
      objective: 'Collect identity documents for fraud or loan abuse',
      actions: <String>[
        'Do not send Aadhaar, PAN, selfies or document photos over chat',
        'Verify the request through the official app or branch',
      ],
      category: ScamCategory.phishing,
      weight: 56,
      patterns: <RegExp>[
        _r(r'\b(send|share|upload|provide|whatsapp)\b[^.!?]{0,40}\b(aadhaar|aadhar|pan card|passport|selfie|photo of|document)\b'),
        _r(r'\b(aadhaar|pan|passport) (number|card|copy|photo)\b[^.!?]{0,30}\b(share|send|upload)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'call_back',
      label: 'Wants you to call a number',
      objective: 'Move you onto a call where pressure tactics work',
      actions: <String>[
        'Call the number printed on your card or the official website instead',
        'Do not call numbers that arrive inside messages',
      ],
      category: ScamCategory.socialEngineering,
      weight: 44,
      patterns: <RegExp>[
        // \\s? before the number: "call our customer care on 98765…" must hit
        // while "call our official helpline 1800…" stays suppressed below.
        _r(r'\b(call|dial|contact|reach) (this|the|us at|me at|now)?[^.!?]{0,20}\s?(\+?\d[\d\s-]{7,}|number)\b'),
        _r(r'\bwhatsapp (me|us|this number) on \b'),
      ],
      requiresPatterns: <RegExp>[_bankContext, _moneyWord, _r(r'\b(care|support|officer|department|team)\b')],
      suppressPattern: _r(r'\b(official (helpline|number|app|website)|toll ?free|1800 ?\d{3,})\b'),
    ),
    BehaviorIntent(
      id: 'act_immediately',
      label: 'Pushes you to act immediately',
      objective: 'Stop you from verifying the message',
      actions: <String>[
        'Slow down - urgency is the scammer\'s main tool',
        'Verify through official channels before doing anything',
      ],
      category: ScamCategory.socialEngineering,
      weight: 34,
      patterns: <RegExp>[
        _r(r'\b(immediately|urgent|urgently|right now|within \d+ (minutes|hours)|last warning|final warning|before it expires|act now|jaldi|turant)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'keep_secret',
      label: 'Asks you to keep it secret',
      objective: 'Isolate you so nobody can warn you',
      actions: <String>[
        'Tell a family member or friend right now',
        'Genuine institutions never ask for secrecy',
      ],
      category: ScamCategory.socialEngineering,
      weight: 70,
      patterns: <RegExp>[
        _r(r"\b(do not (tell|inform|disclose)|don'?t (tell|inform)|keep (this )?(a )?secret|keep (it )?confidential|tell (no ?one|nobody)|without telling|kisi ko na batao)\b"),
      ],
    ),
    BehaviorIntent(
      id: 'stay_on_call',
      label: 'Tells you to stay on the call',
      objective: 'Keep you under control while money moves',
      actions: <String>[
        'You are always allowed to hang up',
        'Hang up and call the organisation back on its official number',
      ],
      category: ScamCategory.socialEngineering,
      weight: 50,
      patterns: <RegExp>[
        _r(r'\b(stay on (the )?(call|line)|do not (disconnect|cut|hang up)|keep the (call|video call) (on|connected)|do not leave the call)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'provide_bank_details_for_credit',
      label: 'Wants bank details to "credit" money',
      objective: 'Harvest account details for fraudulent credits or mandates',
      actions: <String>[
        'Money can be sent with just your UPI id - account and IFSC are never needed',
        'Do not share account numbers or IFSC for receiving money',
      ],
      category: ScamCategory.financialFraud,
      weight: 58,
      patterns: <RegExp>[
        _r(r'\b(bank details|account number|ifsc|beneficiary)\b[^.!?]{0,40}\b(to (receive|credit|claim)|for (credit|payment|refund))\b'),
        _r(r'\b(share|send|provide|give)\b[^.!?]{0,30}\b(bank details|account number|ifsc code)\b'),
      ],
    ),
    BehaviorIntent(
      id: 'verify_identity',
      label: 'Wants you to "verify your identity"',
      objective: 'Push you into a verification flow controlled by the scammer',
      actions: <String>[
        'Check the account in the official app instead of "verifying"',
        'Real verification never happens over a chat message',
      ],
      category: ScamCategory.phishing,
      weight: 48,
      patterns: <RegExp>[
        _r(r'\b(verify|confirm|update) (your )?(identity|details|account|kyc|information)\b'),
        _r(r'\b(re-?verify|re-?kyc|re-?activate) (your )?(account|card|sim|number)\b'),
      ],
      requiresPatterns: <RegExp>[_r(r'\b(link|click|visit|here|url|http)\b'), _bankContext, _r(r'\b(otp|code|pin|cvv)\b')],
    ),
  ];
}
