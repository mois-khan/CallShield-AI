import '../../models/scam_category.dart';
import '../preprocessor.dart';
import '../rule_engine.dart';

/// Message Shield rule catalog (data only — the engine is generic).
///
/// Design notes
/// ------------
/// * Rules detect *combinations*. "OTP" alone is [otpMention] with a tiny
///   weight; the OTP signal only becomes strong when an action ("share the
///   OTP") or a credential demand appears ([otpShareRequest]).
/// * `requiresAny` gates a rule on evidence families fired by other rules, and
///   `requiresContext` demands a nearby context word.
/// * `suppressIf` cancels a rule when legitimate helper text is present
///   ("Do not share this OTP with anyone, including bank staff").
/// * Families are the overlap keys consumed by the risk engine, so the same
///   evidence cannot be counted twice.
class RuleCatalog {
  const RuleCatalog._();

  // Regex helpers ----------------------------------------------------------
  static RegExp _r(String pattern) => RegExp(pattern, caseSensitive: false);

  /// CVV written plainly or obfuscated: cvv, c.v.v, c v v, c-v-v.
  static const String _cvv = r'c[\s._*-]{0,2}v[\s._*-]{0,2}v';

  /// Tolerates obfuscated abbreviations: otp, 0tp, o.t.p, o t p.
  /// OTP written plainly or obfuscated: otp, 0tp, o.t.p, o t p, 0.t.p.
  static const String _otpAbbr = r'0?[o0][\s._*-]{0,3}t[\s._*-]{0,3}p';

  static RegExp _abbrev(String letters) => spacedAbbrev(letters);

  static final RegExp _urgency = _r(
    r'\b(urgent|urgently|immediately|immediate|right now|asap|within \d+ (minutes|hours)|last warning|final warning|before it (expires|is too late)|time is running out|act now|without delay|jaldi|turant|abhi)\b',
  );
  static final RegExp _threat = _r(
    r'\b(arrest|arrested|legal action|police case|fir|warrant|non[- ]bailable|court notice|penalty|fine|jail|imprison|lawsuit|prosecut|deport|seize|detained|cyber cell|crime branch)\b',
  );
  static final RegExp _secrecy = _r(
    r"\b(do not (tell|inform|disclose|share (this )?with)|don'?t (tell|inform)|keep (this )?(a )?secret|keep (it )?confidential|tell (no ?one|nobody)|without telling|confidential investigation|kisi ko na batao|kisi ko mat batao)\b",
  );
  static final RegExp _prizeContext = _r(
    r'\b(won|winner|lottery|lucky draw|prize|jackpot|cashback|reward|gift|voucher|scratch card|giveaway)\b',
  );
  static final RegExp _authorityClaim = _r(
    r'\b(i am|this is|we are|calling from|officer from|department of|head office|nodal officer|senior officer|inspector|constable)\b',
  );
  static final RegExp _installVerb = _r(
    r'\b(install|download|open the app|download the app|apk)\b',
  );
  static final RegExp _remoteTools = _r(
    r'\b(anydesk|teamviewer|quick ?support|rustdesk|airdroid|screen ?(share|sharing)|mirror your screen|join a video (call|meeting) for verification)\b',
  );
  static final RegExp _cryptoVerb = _r(
    r'\b(usdt|btc|bitcoin|ethereum|trc20|erc20|crypto|wallet address|binance|tron|seed phrase)\b',
  );
  static final RegExp _benignOrder = _r(
    r'\b(delivered|out for delivery|shipped|has been picked|order confirmed|invoice|statement|receipt|ticket|resolved|credited|debited|salary)\b',
  );
  static final RegExp _legitHelper = _r(
    r'(do not share (this )?(otp|code|pin)|never share|never asks?|not share it with anyone|share na karein|kisi ke saath share|bank (staff|never)|no action is required|do not disclose)',
  );

  // Trigger helpers --------------------------------------------------------
  static List<RuleMatcher> _any(List<RegExp> patterns, {MatchView view = MatchView.both}) =>
      patterns.map((RegExp p) => RuleMatcher(p, view: view)).toList(growable: false);

  static final List<DetectionRule> rules = <DetectionRule>[
    // ======================================================================
    // Credential / OTP theft
    // ======================================================================
    DetectionRule(
      id: 'otp_mention',
      family: 'credential_mention',
      category: ScamCategory.credentialTheft,
      label: 'OTP mentioned',
      weight: 12,
      triggers: _any(<RegExp>[_abbrev('otp'), _r(r'\bone[- ]time password\b')]),
      requiresAny: <String>{'credential_request', 'financial_context', 'impersonation', 'urgency_threat'},
      detail: 'Mentioning an OTP is normal in real bank messages, so this stays weak unless other evidence appears.',
    ),
    DetectionRule(
      id: 'otp_share_request',
      family: 'credential_request:otp',
      category: ScamCategory.credentialTheft,
      label: 'OTP / code is being requested',
      weight: 62,
      triggers: <RuleMatcher>[
        RuleMatcher(_r(
          '\\b(share|send|tell|provide|read|forward|confirm|reply with|bata|bhej|dont tell anyone|give me)\\b[^.!?]{0,40}($_otpAbbr|code|verification code|security code|one[- ]time password)',
        )),
        RuleMatcher(_r(
          '\\b($_otpAbbr|verification code|security code|code)\\b[^.!?]{0,40}\\b(share|send|tell|provide|read|forward|confirm|reply|bata|bhej|with me|to me|to our officer|with our officer)\\b',
        )),
        RuleMatcher(_r('\\b(the code|$_otpAbbr) (we|i) (just )?(sent|shared)[^.!?]{0,30}\\b(give|share|tell|read|reply)')),
      ],
      suppressIf: _any(<RegExp>[_legitHelper]),
      requirePositiveInstruction: true,
      detail: 'Requesting an OTP/code over a message is one of the strongest scam signals.',
    ),
    DetectionRule(
      id: 'pin_password_request',
      family: 'credential_request:pin',
      category: ScamCategory.credentialTheft,
      label: 'PIN / password / CVV requested',
      weight: 60,
      triggers: <RuleMatcher>[
        RuleMatcher(_r(
          '\\b(share|send|tell|provide|read|enter|confirm|type|reply with)\\b[^.!?]{0,40}\\b(pin|mpin|upi pin|atm pin|$_cvv|password|passcode|user id|username|login|net ?banking password)\\b',
        )),
        RuleMatcher(_r(
          '\\b($_cvv|pin|mpin|password|passcode)\\b[^.!?]{0,30}\\b(share|send|tell|provide|read|enter|verify|confirm)\\b',
        )),
        RuleMatcher(_r(
          '\\b(16 digit|card number|card expir|expiry|expire date|exp1r3)\\b[^.!?]{0,40}\\b($_cvv|expiry|expire|otp|confirm|unblock)\\b',
        )),
        RuleMatcher(_r('\\b($_cvv|card expir[ey]|expiry date)\\b[^.!?]{0,40}\\b(unblock|verify|confirm|refund|share|provide|send)\\b')),
      ],
      suppressIf: _any(<RegExp>[_legitHelper]),
      requirePositiveInstruction: true,
    ),
    DetectionRule(
      id: 'verification_code_context',
      family: 'credential_context',
      category: ScamCategory.credentialTheft,
      label: 'Verification-code framing',
      weight: 26,
      triggers: _any(<RegExp>[
        _r(r'\b(verify|verification|confirm your identity|security verification|kyc verification|re[- ]?verification)\b'),
      ]),
      requiresAny: <String>{'credential_request', 'impersonation', 'phishing_link'},
    ),
    DetectionRule(
      id: 'sim_activation',
      family: 'credential_context',
      category: ScamCategory.credentialTheft,
      label: 'SIM activation / porting trick',
      weight: 30,
      triggers: _any(<RegExp>[
        _r(r'\b(new sim|sim activation|activate (your|the) sim|sim will be (blocked|deactivated)|e-?sim|port (your )?number)\b'),
      ]),
      requiresAny: <String>{'credential_request', 'impersonation'},
    ),

    // ======================================================================
    // Financial fraud
    // ======================================================================
    DetectionRule(
      id: 'payment_request',
      family: 'payment_request',
      category: ScamCategory.financialFraud,
      label: 'Payment / transfer is being requested',
      weight: 52,
      triggers: <RuleMatcher>[
        // Verb view so brand names ("Google Pay") never look like an instruction.
        RuleMatcher(
          _r(r'\b(transfer|send|pay|deposit|remit|bhej|jama)\b[^.!?]{0,40}\b(rs\.?|inr|₹|\$)?\s?\d[\d,\.]*'),
          view: MatchView.verb,
        ),
        RuleMatcher(
          _r(r'\b(transfer|send|pay|deposit)\b[^.!?]{0,50}\b(upi|account|wallet|this number|upi id|@ybl|@paytm|@ok\w+)\b'),
          view: MatchView.verb,
        ),
        RuleMatcher(
          _r(r'\b(pay|transfer|send|deposit)\b[^.!?]{0,30}\b(fee|charge|penalty|duty|deposit|amount|money)\b'),
          view: MatchView.verb,
        ),
      ],
      requiresAny: <String>{'money_context', 'impersonation'},
      requirePositiveInstruction: true,
    ),
    DetectionRule(
      id: 'upi_collect_request',
      family: 'payment_request',
      category: ScamCategory.financialFraud,
      label: 'Approve a UPI collect request',
      weight: 58,
      triggers: _any(<RegExp>[
        _r(r'\bapprove (the|this)?\s?(payment|collect|upi)?\s?request\b'),
        _r(r'\baccept (the|this) (payment|collect)? ?request\b'),
        _r(r'\bapprove (it|twice|the request) in your upi app\b'),
        _r(r'\benter (your )?upi pin to (receive|accept)\b'),
        _r(r'\bapprove the request in your upi\b'),
      ]),
      detail: 'A UPI collect request moves money OUT of the account, never in.',
    ),
    DetectionRule(
      id: 'reverse_transfer_trick',
      family: 'payment_request',
      category: ScamCategory.financialFraud,
      label: 'Fake wrong-transfer reversal',
      weight: 50,
      triggers: _any(<RegExp>[
        _r(r'\b(wrong|extra|excess) (transaction|amount|money|transfer)s?\b'),
        _r(r'\bcredited (to your account )?by mistake\b'),
        _r(r'\breverse the (transaction|transfer|debit)\b'),
        _r(r'\btransfer (it|the amount|the money) back\b'),
      ]),
      requiresAny: <String>{'payment_request', 'money_context'},
    ),
    DetectionRule(
      id: 'money_context',
      family: 'money_context',
      category: ScamCategory.financialFraud,
      label: 'Money / account context',
      weight: 18,
      triggers: _any(<RegExp>[
        _r(r'\b(rs\.?|inr|₹|\$)\s?\d[\d,\.]*\b'),
        _r(r'\b(bank account|account number|ifsc|upi id|beneficiary|wallet|balance|debit|credit)\b'),
      ]),
    ),
    DetectionRule(
      id: 'processing_fee',
      family: 'payment_request:fee',
      category: ScamCategory.financialFraud,
      label: 'Upfront fee demanded',
      weight: 44,
      triggers: _any(<RegExp>[
        _r(r'\b(processing|registration|activation|convenience|clearance|handling|redelivery|release|training|security) (fee|charge|charges|deposit|amount)\b'),
        _r(r'\bpay (rs\.? ?\d[\d,\.]*|[\d,\.]+ ?(rs|rupees))\b[^.!?]{0,30}\b(to (release|receive|claim|activate|unblock|complete))\b'),
        _r(r'\b(small|nominal|token) (fee|charge|amount)\b'),
      ]),
      requiresAny: <String>{'money_context', 'payment_request', 'prize_context', 'opportunity_context'},
    ),
    DetectionRule(
      id: 'refund_lure',
      family: 'refund_lure',
      category: ScamCategory.financialFraud,
      label: 'Pending refund lure',
      weight: 40,
      triggers: _any(<RegExp>[
        _r(r'\b(pending|failed|stuck|unclaimed|process(ing)?) (refund|reimbursement|cashback)\b'),
        _r(r'\brefund (of|amount) (rs\.?|inr|₹)'),
        _r(r'\bclaim (your )?refund\b'),
        _r(r'\brefund will be (credited|processed)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'credential_request', 'phishing_link', 'money_context'},
    ),
    DetectionRule(
      id: 'card_compromise',
      family: 'credential_request:card',
      category: ScamCategory.financialFraud,
      label: 'Card compromise story',
      weight: 46,
      triggers: _any(<RegExp>[
        _r(r'\b(card|account) (is |has been )?(compromised|blocked|suspended|locked|frozen|misused)\b'),
        _r(r'\bsuspicious activity (on|in) your (account|card)\b'),
      ]),
      requiresAny: <String>{'credential_request', 'impersonation', 'impersonation_claim', 'payment_request'},
    ),
    DetectionRule(
      id: 'loan_fee',
      family: 'payment_request:loan',
      category: ScamCategory.financialFraud,
      label: 'Loan fee before disbursal',
      weight: 40,
      triggers: _any(<RegExp>[
        _r(r'\b(loan|credit line) (is )?approved\b'),
        _r(r'\binstant (loan|approval)\b'),
        _r(r'\bno (cibil|documents|income proof)\b'),
        _r(r'\bdisburs(e|al|ement) (fee|charge|amount)\b'),
      ]),
      requiresAny: <String>{'money_context', 'payment_request', 'opportunity_context'},
    ),

    // ======================================================================
    // Impersonation
    // ======================================================================
    DetectionRule(
      id: 'authority_claim',
      family: 'impersonation_claim',
      category: ScamCategory.impersonation,
      label: 'Claims to be an authority',
      weight: 22,
      triggers: _any(<RegExp>[_authorityClaim, _r(r'\b(officer|inspector|constable|advocate|lawyer|notary)\b')]),
      requiresAny: <String>{'authority_context', 'malicious_threat', 'payment_request', 'credential_request'},
      detail: 'Claiming to be an authority is only meaningful together with a demand.',
    ),
    DetectionRule(
      id: 'authority_context',
      family: 'authority_context',
      category: ScamCategory.impersonation,
      label: 'Authority context word',
      weight: 14,
      triggers: _any(<RegExp>[
        _r(r'\b(income tax|it department|gst|rbi|reserve bank|uidai|aadhaar|trai|cyber ?crime|crime branch|cbi|enforcement directorate|passport office|municipal|nodal officer|customs|police|court|tribunal)\b'),
      ]),
    ),
    DetectionRule(
      id: 'legal_threat',
      family: 'malicious_threat',
      category: ScamCategory.impersonation,
      label: 'Arrest / legal threat',
      weight: 46,
      triggers: _any(<RegExp>[_threat]),
      requiresAny: <String>{'authority_context', 'impersonation_claim', 'payment_request', 'secrecy_demand'},
    ),
    DetectionRule(
      id: 'illegal_activity_accusation',
      family: 'malicious_threat',
      category: ScamCategory.impersonation,
      label: 'Accuses you of illegal activity',
      weight: 40,
      triggers: _any(<RegExp>[
        _r(r'\b(money laundering|illegal (items|activity|goods|transactions?)|narcotics|drugs case|terror(ism)? funding|hawala|black money)\b'),
      ]),
      requiresAny: <String>{'authority_context', 'impersonation_claim', 'payment_request'},
    ),
    DetectionRule(
      id: 'govt_penalty',
      family: 'malicious_threat',
      category: ScamCategory.impersonation,
      label: 'Government penalty demand',
      weight: 40,
      triggers: _any(<RegExp>[
        _r(r'\bpay (the )?(penalty|fine|settlement)\b'),
        _r(r'\bpenalty of (rs\.?|inr|₹)'),
        _r(r'\bsettle the (case|amount|fine)\b'),
      ]),
      requiresAny: <String>{'authority_context', 'payment_request'},
    ),
    DetectionRule(
      id: 'bank_impersonation',
      family: 'impersonation_claim',
      category: ScamCategory.impersonation,
      label: 'Bank staff / security framing',
      weight: 34,
      triggers: _any(<RegExp>[
        _r(r'\b(fraud|compliance|security|verification|risk) (department|team|officer|cell)\b'),
        _r(r'\b(from|representing) (the )?(bank|head office|customer care|nodal)\b'),
        _r(r'\b(bank|card) (officer|executive|representative|agent)\b'),
      ]),
      requiresAny: <String>{'credential_request', 'payment_request', 'money_context', 'impersonation_claim'},
    ),
    DetectionRule(
      id: 'courier_customs_story',
      family: 'delivery_story',
      category: ScamCategory.deliveryScam,
      label: 'Courier / customs story',
      weight: 30,
      triggers: _any(<RegExp>[
        _r(r'\b(parcel|package|shipment|consignment|courier|delivery)\b[^.!?]{0,40}\b(held|customs|illegal|stuck|clearance|duty|seized|returned)\b'),
        _r(r'\bcustoms\b[^.!?]{0,40}\b(fee|duty|clearance|penalty|release)\b'),
        _r(r'\b(parcel|package|shipment)\b[^.!?]{0,40}\b(could not be delivered|failed|incomplete address|reschedule|redelivery)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'malicious_threat', 'phishing_link', 'delivery_scam'},
    ),
    DetectionRule(
      id: 'telecom_threat',
      family: 'malicious_threat',
      category: ScamCategory.impersonation,
      label: 'Telecom disconnection threat',
      weight: 32,
      triggers: _any(<RegExp>[
        _r(r'\b(number|sim|connection) will be (disconnected|deactivated|blocked)\b'),
        _r(r'\billegal (activity|usage) (on|from) your number\b'),
        _r(r'\btrai\b'),
      ]),
      requiresAny: <String>{'payment_request', 'credential_request', 'impersonation_claim', 'authority_context'},
    ),
    DetectionRule(
      id: 'utility_disconnection',
      family: 'malicious_threat',
      category: ScamCategory.impersonation,
      label: 'Utility disconnection threat',
      weight: 28,
      triggers: _any(<RegExp>[
        _r(r'\b(electricity|power|gas|water) (bill|connection|supply)\b[^.!?]{0,40}\b(disconnect|cut|pending|due)\b'),
        _r(r'\bservice will be disconnected\b'),
      ]),
      requiresAny: <String>{'payment_request', 'phishing_link'},
    ),

    // ======================================================================
    // Social engineering / coercion
    // ======================================================================
    DetectionRule(
      id: 'urgency',
      family: 'urgency',
      category: ScamCategory.socialEngineering,
      label: 'Artificial urgency',
      weight: 16,
      triggers: _any(<RegExp>[_urgency]),
      detail: 'Urgency alone is common in real messages, so it stays a weak signal.',
    ),
    DetectionRule(
      id: 'secrecy_demand',
      family: 'secrecy_demand',
      category: ScamCategory.socialEngineering,
      label: 'Asks you to keep it secret',
      weight: 42,
      triggers: _any(<RegExp>[_secrecy]),
      detail: 'A genuine organisation never asks you to hide a transaction from family or police.',
    ),
    DetectionRule(
      id: 'emergency_family',
      family: 'emergency_story',
      category: ScamCategory.socialEngineering,
      label: 'Emergency / family-in-trouble story',
      weight: 34,
      triggers: _any(<RegExp>[
        _r(r'\b(accident|hospital|icu|operation|admitted|in trouble|police custody|detained|kidnap)\b'),
        _r(r'\b(this is my new number|my phone (broke|is broken)|lost my phone)\b'),
        _r(r'\b(mummy|papa|mom|dad|beta)\b[^.!?]{0,30}\b(money|urgent|help|transfer)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'secrecy_demand', 'urgency', 'extortion_threat'},
    ),
    DetectionRule(
      id: 'extortion_threat',
      family: 'extortion_threat',
      category: ScamCategory.extortion,
      label: 'Blackmail / sextortion threat',
      weight: 52,
      triggers: _any(<RegExp>[
        _r(r'\b(private|intimate|morph(ed)?) (photos|videos|pictures|images|chats)\b'),
        _r(r'\b(i will (send|share|upload|leak|publish)|will be (sent|uploaded|published))[^.!?]{0,40}\b(your (contacts|friends|family|photos|chats|videos)|online|social media)\b'),
        _r(r'\bpay (me )?or i will\b'),
        _r(r'\b(harm|hurt|kill) (you|your (family|wife|children))\b'),
        _r(r'\bwe have recorded (your|the)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'crypto_context', 'urgency', 'secrecy_demand'},
    ),
    DetectionRule(
      id: 'crypto_context',
      family: 'crypto_context',
      category: ScamCategory.financialFraud,
      label: 'Crypto wallet demand',
      weight: 34,
      triggers: _any(<RegExp>[_cryptoVerb]),
      requiresAny: <String>{'payment_request', 'extortion_threat', 'opportunity_context'},
    ),
    DetectionRule(
      id: 'remote_access_request',
      family: 'remote_access',
      category: ScamCategory.socialEngineering,
      label: 'Remote access / screen-share request',
      weight: 56,
      triggers: _any(<RegExp>[_remoteTools, _installVerb]),
      requiresAny: <String>{'credential_request', 'impersonation_claim', 'authority_context', 'payment_request', 'remote_access'},
      detail: 'Remote-control apps give the scammer full access to your phone, including OTPs.',
    ),
    DetectionRule(
      id: 'keep_on_call',
      family: 'keep_on_call',
      category: ScamCategory.socialEngineering,
      label: 'Told to stay on the call',
      weight: 26,
      triggers: _any(<RegExp>[
        _r(r'\b(stay|stay on|do not (disconnect|cut|hang up)|keep the (call|video call) (on|connected)|do not leave the call)\b'),
        _r(r'\bdo not tell anyone (during|on) the call\b'),
      ]),
      requiresAny: <String>{'impostor_act', 'authority_context', 'payment_request', 'secrecy_demand'},
    ),
    DetectionRule(
      id: 'impostor_act',
      family: 'impostor_act',
      category: ScamCategory.impersonation,
      label: 'Fake identity being asserted',
      weight: 20,
      triggers: _any(<RegExp>[
        _r(r'\bthis is (my |our )?new number\b'),
        _r(r'\bi am (your|from|the) \w+ (from|of|department|bank|police|office)\b'),
        _r(r'\b(i am|this is) (the )?(police|inspector|officer|cbi|cyber ?crime|customs)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'credential_request', 'urgency', 'secrecy_demand'},
    ),
    DetectionRule(
      id: 'romance_framing',
      family: 'romance_framing',
      category: ScamCategory.romanceScam,
      label: 'Romance / gift framing',
      weight: 24,
      triggers: _any(<RegExp>[
        _r(r'\b(i love you|my dear|my love|miss you so much)\b'),
        _r(r'\b(gift|present|parcel) (for you )?from (abroad|uk|usa|dubai)\b'),
        _r(r'\b(pay the (customs|clearance) (fee|charge))[^.!?]{0,30}\b(gift|present)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'money_context', 'crypto_context'},
    ),
    DetectionRule(
      id: 'subscription_trap',
      family: 'payment_request:subscription',
      category: ScamCategory.subscriptionTrap,
      label: 'Subscription / mandate trap',
      weight: 30,
      triggers: _any(<RegExp>[
        _r(r'\b(auto ?debit|mandate|recurring payment|subscription (renewal|expired|activated))\b'),
        _r(r'\b(cancel|stop) (your )?(subscription|membership)\b[^.!?]{0,40}\b(pay|fee|charge)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'phishing_link', 'money_context'},
    ),

    // ======================================================================
    // Investment / opportunity
    // ======================================================================
    DetectionRule(
      id: 'guaranteed_returns',
      family: 'opportunity_context',
      category: ScamCategory.investmentScam,
      label: 'Guaranteed-return claim',
      weight: 46,
      triggers: _any(<RegExp>[
        _r(r'\b(guaranteed|assured|fixed|sure) (profit|return|returns|income|gain|result)\b'),
        _r(r'\b\d{2,3}\s?(percent|%)\s?(profit|return|returns|daily|monthly|per|in)\b'),
        _r(r'\bdouble your (money|capital|investment)\b'),
        _r(r'\bno risk (investment|trading|profit)\b'),
        _r(r'\b(daily|weekly|monthly) (profit|returns?|payout|income)\b'),
      ]),
      detail: 'No regulated instrument guarantees fixed returns — this claim is itself the scam.',
    ),
    DetectionRule(
      id: 'trading_group_invite',
      family: 'opportunity_context',
      category: ScamCategory.investmentScam,
      label: 'Trading / VIP group invite',
      weight: 34,
      triggers: _any(<RegExp>[
        _r(r'\b(vip|premium|paid) (group|channel|membership|batch)\b'),
        _r(r'\b(trading|stock|intraday|option|futures) (group|tips|signals|batch|calls)\b'),
        _r(r'\bjoin (our|the) (telegram|whatsapp|trading) (group|channel)\b'),
        _r(r'\bsebi registered expert\b'),
      ]),
      requiresAny: <String>{'opportunity_context', 'payment_request', 'chat_channel_funnel'},
    ),
    DetectionRule(
      id: 'job_offer_fee',
      family: 'opportunity_context',
      category: ScamCategory.investmentScam,
      label: 'Job / task offer with upfront payment',
      weight: 40,
      triggers: _any(<RegExp>[
        _r(r'\b(part ?time|work from home|data entry|typing|copy paste|mobile task|simple task) (job|work|tasks?)\b'),
        _r(r'\b(daily payout|earn \d|earn rs\.? ?\d|earn up to)\b'),
        _r(r'\b(registration|training|kit|security) (fee|deposit|charge)\b[^.!?]{0,40}\b(job|task|work|join|start)\b'),
        _r(r'\b(selected|shortlisted) for (a )?(part ?time|work from home|typing|data entry) (job|role)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'chat_channel_funnel', 'money_context', 'opportunity_context'},
    ),
    DetectionRule(
      id: 'chat_channel_funnel',
      family: 'chat_channel_funnel',
      category: ScamCategory.suspicious,
      label: 'Pushed to a private chat/channel',
      weight: 22,
      triggers: _any(<RegExp>[
        _r(r'\b(t\.me|wa\.me|chat\.whatsapp\.com|telegram\.me|discord\.gg)\b'),
        _r(r'\b(whatsapp|telegram) (me|us|this number|for details)\b'),
        _r(r'\b(dm|message) (me|us) (on|at)\b'),
      ]),
      requiresAny: <String>{'opportunity_context', 'payment_request', 'phishing_link', 'credential_request'},
    ),

    // ======================================================================
    // Rewards
    // ======================================================================
    DetectionRule(
      id: 'prize_claim',
      family: 'reward_lure',
      category: ScamCategory.rewardScam,
      label: 'Prize / lottery win claim',
      weight: 44,
      triggers: _any(<RegExp>[
        _r(r'\b(you|ur|your (number|mobile|sim))\b[^.!?]{0,25}\b(won|win|selected as (the )?(lucky )?winner)\b'),
        _r(r'\b(lottery|lucky draw|jackpot|kbc)\b'),
        _r(r'\byou are (the )?(lucky )?(winner|selected)\b'),
        _r(r'\b(prize|reward) (money|of rs|coupon)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'credential_request', 'money_context', 'phishing_link'},
    ),
    DetectionRule(
      id: 'cashback_lure',
      family: 'reward_lure',
      category: ScamCategory.rewardScam,
      label: 'Cashback / gift claim lure',
      weight: 30,
      triggers: _any(<RegExp>[
        _r(r'\b(cashback|reward points|gift voucher|scratch card|spin and win) (of|worth|claim|is waiting)\b'),
        _r(r'\bclaim your (cashback|reward|gift|voucher|prize)\b'),
      ]),
      requiresAny: <String>{'payment_request', 'phishing_link', 'money_context', 'credential_request'},
    ),
    DetectionRule(
      id: 'prize_tax_fee',
      family: 'reward_lure',
      category: ScamCategory.rewardScam,
      label: 'Fee demanded to release a prize',
      weight: 38,
      triggers: _any(<RegExp>[_prizeContext]),
      requiresContext: RuleMatcher(_r(r'\b(fee|charge|tax|duty|deposit|processing|clearance|verification charge)\b')),
      detail: 'A real prize never requires an upfront payment.',
    ),

    // ======================================================================
    // Phishing / links
    // ======================================================================
    DetectionRule(
      id: 'bare_action_link',
      family: 'phishing_link',
      category: ScamCategory.phishing,
      label: 'Message pushes a link to act',
      weight: 30,
      triggers: _any(<RegExp>[
        _r(r'\b(click|open|visit|tap|login|log in|verify|update|re-?verify|claim|unlock|reactivate|complete|confirm)\b[^.!?]{0,40}(https?://|www\.|bit\.ly|tinyurl|\.xyz|\.top|\.click|\.online|\.info|\.ru\b)'),
        _r(r'(https?://|www\.)[^\s]+[^.!?]{0,20}\b(to (verify|claim|update|unlock|complete|avoid|prevent))\b'),
        _r(r'\b(link|link below|this link|given link)\b[^.!?]{0,30}\b(open|click|verify|update)\b'),
      ]),
    ),
    DetectionRule(
      id: 'link_with_deadline',
      family: 'phishing_link',
      category: ScamCategory.phishing,
      label: 'Link plus deadline',
      weight: 34,
      triggers: _any(<RegExp>[_r(r'(https?://|www\.)')]),
      requiresContext: RuleMatcher(_r(r'\b(within \d+ (minutes|hours)|today|expires|last chance|before midnight|immediately|24 hours|12 hours)\b')),
    ),
    DetectionRule(
      id: 'link_plus_credentials',
      family: 'phishing_link',
      category: ScamCategory.phishing,
      label: 'Link plus credential request',
      weight: 40,
      triggers: _any(<RegExp>[_r(r'(https?://|www\.)')]),
      requiresContext: RuleMatcher(
        _r(r'\b(otp|pin|cvv|password|net ?banking|login|kyc|card number|upi|aadhaar)\b'),
      ),
    ),
    DetectionRule(
      id: 'suspicious_host_keywords',
      family: 'suspicious_url',
      category: ScamCategory.phishing,
      label: 'Link host looks like a fake brand page',
      weight: 30,
      triggers: _any(<RegExp>[
        _r(r'(https?://|www\.)[a-z0-9\-]*(kyc|verify|otp|login|secure|update|account|refund|claim|reward|cashback|prize|unlock|support|customs|delivery|pay)[a-z0-9\-]*\.[a-z]{2,}'),
      ]),
    ),

    // ======================================================================
    // Bulk spam
    // ======================================================================
    DetectionRule(
      id: 'bulk_promo',
      family: 'bulk_promo',
      category: ScamCategory.spam,
      label: 'Bulk promotional wording',
      weight: 26,
      triggers: _any(<RegExp>[
        _r(r'\b(flat|upto|up to|huge|mega|grand) ?\d{1,3}% ?(off|discount|cashback)\b'),
        _r(r'\b(limited (period|time) offer|offer ends (today|tonight)|hurry|order now|buy now|shop now)\b'),
        _r(r'\b(free gift|free voucher|combo offer|buy 1 get 1|bogo|get (one|a) free)\b'),
        _r(r'\b(increase your followers|weight loss|guaranteed result in \d+ days|adult (chat|dating)|loan without documents|instant approval|zero documents)\b'),
        _r(r'\b(forward this (message|to)|reply yes to (claim|get|receive))\b'),
        _r(r'\b(hot offer|special offer|exclusive offer|sabse sasta|limited stock|few left)\b'),
        _r(r'\bearn (daily payouts?|\d+ ?(per day|daily))\b'),
      ]),
      // Newsletter/transactional senders add real opt-outs, order notices and
      // "no action required" lines; bulk scam bursts never do.
      suppressIf: _any(<RegExp>[
        _legitHelper,
        _benignOrder,
        _r(r'\b(to unsubscribe|unsubscribe|opt ?out)\b'),
      ]),
    ),
    DetectionRule(
      id: 'spam_pressure',
      family: 'bulk_promo',
      category: ScamCategory.spam,
      label: 'Spam call-to-action',
      weight: 14,
      triggers: _any(<RegExp>[
        _r(r'\b(whatsapp|call|contact|dial) (us|me|now|today|this number|\+?\d{8,})\b'),
        _r(r'\b(dm us|text us|message us|reply (now|today|yes|start|stop))\b'),
      ]),
      requiresAny: <String>{'bulk_promo'},
    ),

    // ======================================================================
    // Suspicious-but-unclear (keeps recall on unknown wording)
    // ======================================================================
    DetectionRule(
      id: 'hinglish_urgency',
      family: 'urgency',
      category: ScamCategory.suspicious,
      label: 'Hinglish urgency / threat phrasing',
      weight: 22,
      triggers: _any(<RegExp>[
        _r(r'\b(account band|ac band|a\/?c band|number band|turant|jaldi (karo|bhejo)|abhi bhejo|warna)\b'),
        _r(r'(वरना|तुरंत|खाता बंद|ब्लॉक हो जाएगा)'),
        _r(r'\b(paise|paisa|rupaye|pesa) (bhejo|transfer karo|jama karo)\b'),
      ]),
    ),
    DetectionRule(
      id: 'mixed_language_scam_vocab',
      family: 'credential_request',
      category: ScamCategory.credentialTheft,
      label: 'Mixed-language credential request',
      weight: 34,
      triggers: _any(<RegExp>[
        _r(r'\b(otp|code|cvv|pin)\b[^.!?]{0,40}\b(bata|bhej|share karo|de dijiye|batao|bata dijiye)\b'),
        _r(r'(ओटीपी|पिन|सीवीवी)[^.!?]{0,30}(शेयर|बताइए|बताएं|भेजें)'),
        // Latin "OTP" + Devanagari share verb + threat context
        // ("OTP … शेयर करें वरना खाता बंद") - the threat tail keeps real
        // "do not share" warnings from matching.
        _r(r'\b(otp|code|cvv|pin)\b[^.!?]{0,40}(शेयर|भेजें|बताइए|बताएं|बता)[^.!?]{0,40}(वरना|बंद|ब्लॉक|जाएगा|तुरंत)'),
        _r(r'(\u0993\u099f\u09bf\u09aa\u09bf)[^.!?]{0,25}(\u09a6\u09bf\u09a8|\u09ac\u09b2\u09c1\u09a8)'),
      ]),
      suppressIf: _any(<RegExp>[_legitHelper]),
    ),

    // ======================================================================
    // Legitimate context (mitigations, negative weights)
    // ======================================================================
    DetectionRule(
      id: 'legit_otp_helper_text',
      family: 'legit_context:otp_helper',
      category: ScamCategory.legitimate,
      label: 'Standard "do not share this OTP" notice',
      weight: -30,
      triggers: _any(<RegExp>[_legitHelper]),
      detail: 'Real banks add this warning; its presence argues against a credential-theft scam.',
    ),
    DetectionRule(
      id: 'legit_no_action_required',
      family: 'legit_context:no_action',
      category: ScamCategory.legitimate,
      label: 'Explicitly says no action is required',
      weight: -22,
      triggers: _any(<RegExp>[
        _r(r'\bno action (is )?(required|needed)\b'),
        _r(r'\b(already (updated|verified|done)|successfully (completed|updated|delivered))\b'),
      ]),
    ),
    DetectionRule(
      id: 'legit_transaction_notice',
      family: 'legit_context:transaction_notice',
      category: ScamCategory.legitimate,
      label: 'Plain transaction / delivery notification',
      weight: -18,
      triggers: _any(<RegExp>[_benignOrder]),
      requiresAny: <String>{'legit_context', 'legit_marker'},
      suppressIf: _any(<RegExp>[
        _r(r'\b(share|send|transfer|pay|approve|click|install)\b'),
      ]),
    ),
    DetectionRule(
      id: 'legit_optout_marker',
      family: 'legit_context:optout',
      category: ScamCategory.promotional,
      label: 'Has a real opt-out / official-app pointer',
      weight: -16,
      triggers: _any(<RegExp>[
        _r(r'\b(reply stop|to unsubscribe|unsubscribe|opt ?out)\b'),
        _r(r'\b(official app|official website|official helpline|official customer care)\b'),
      ]),
    ),
    DetectionRule(
      id: 'legit_brand_official_domain',
      family: 'legit_context:official_domain',
      category: ScamCategory.legitimate,
      label: 'Links only to an official domain',
      weight: -20,
      triggers: _any(<RegExp>[
        _r(r'(https?://)?(www\.)?(onlinesbi\.sbi|sbi\.co\.in|hdfcbank\.com|icicibank\.com|axisbank\.com|jio\.com|airtel\.in|amazon\.in|flipkart\.com|netflix\.com|gov\.in|nic\.in)'),
      ]),
      suppressIf: _any(<RegExp>[
        _r(r'(https?://|www\.)[a-z0-9\-]*(\.xyz|\.top|\.click|\.online|\.info|\.ru\b|bit\.ly|tinyurl)'),
      ]),
    ),
  ];
}
