import 'dart:math' as math;

import '../intelligence/scam_intelligence.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';

/// A combination that only becomes dangerous when several evidence families
/// appear together (this is where "OTP + request + financial context" beats a
/// plain keyword match).
class SignalCombination {
  const SignalCombination({
    required this.id,
    required this.label,
    required this.families,
    required this.bonus,
    this.minimum = 2,
  });

  final String id;
  final String label;
  final List<String> families;
  final int bonus;

  /// How many of [families] must be present.
  final int minimum;
}

/// Explainable risk assessment produced by the correlation stage.
class RiskAssessment {
  const RiskAssessment({
    required this.score,
    required this.band,
    required this.headline,
    required this.categories,
    required this.familyScores,
    required this.combinationsApplied,
    required this.explanation,
    required this.objectives,
    required this.actions,
    required this.mitigationPoints,
    required this.isSpam,
  });

  final int score;
  final RiskBand band;
  final String headline;
  final List<ScamCategory> categories;

  /// family -> correlated contribution (0–100) used for the noisy-OR.
  final Map<String, int> familyScores;
  final List<SignalCombination> combinationsApplied;
  final String explanation;
  final List<String> objectives;
  final List<String> actions;
  final int mitigationPoints;
  final bool isSpam;
}

/// Correlates every signal into one explainable 0–100 score.
///
/// Overlap handling: signals sharing a [ShieldSignal.family] are collapsed
/// (strongest one counts fully, extra ones only add a small increment), so the
/// same evidence produced by the rule engine, the behaviour engine and the LLM
/// feature cannot be counted three times.
class RiskEngine {
  RiskEngine({required this.intelligence});

  final ScamIntelligence intelligence;

  /// Corroboration bonus — only applied when *different* families agree.
  static const List<SignalCombination> combinations = <SignalCombination>[
    SignalCombination(
      id: 'credential_plus_authority',
      label: 'Credential request combined with an impersonated authority',
      families: <String>['credential_request', 'impersonation_claim', 'authority_context'],
      bonus: 14,
    ),
    SignalCombination(
      id: 'credential_plus_urgency',
      label: 'Credential request under time pressure',
      families: <String>['credential_request', 'urgency', 'malicious_threat'],
      bonus: 12,
    ),
    SignalCombination(
      id: 'payment_plus_authority',
      label: 'Payment demand combined with an authority threat',
      families: <String>['payment_request', 'impersonation_claim', 'authority_context', 'malicious_threat'],
      bonus: 14,
    ),
    SignalCombination(
      id: 'payment_plus_urgency',
      label: 'Payment demand pushed with urgency',
      families: <String>['payment_request', 'urgency', 'keep_on_call'],
      bonus: 10,
    ),
    SignalCombination(
      id: 'secrecy_plus_payment',
      label: 'Payment demand plus a secrecy instruction',
      families: <String>['secrecy_demand', 'payment_request', 'credential_request'],
      bonus: 16,
    ),
    SignalCombination(
      id: 'remote_access_plus_credential',
      label: 'Remote access request plus credentials',
      families: <String>['remote_access', 'credential_request', 'payment_request'],
      bonus: 16,
    ),
    SignalCombination(
      id: 'suspicious_link_plus_request',
      label: 'Suspicious link plus a request for details',
      families: <String>['suspicious_url', 'phishing_link', 'credential_request', 'payment_request'],
      bonus: 12,
    ),
    SignalCombination(
      id: 'reward_plus_fee',
      label: 'Prize framing plus an upfront fee',
      families: <String>['reward_lure', 'payment_request', 'money_context'],
      bonus: 14,
    ),
    SignalCombination(
      id: 'delivery_plus_fee',
      label: 'Parcel framing plus a fee',
      families: <String>['delivery_story', 'payment_request', 'phishing_link'],
      bonus: 12,
    ),
    SignalCombination(
      id: 'opportunity_plus_fee',
      label: 'Guaranteed returns plus an upfront payment',
      families: <String>['opportunity_context', 'payment_request', 'money_context'],
      bonus: 14,
    ),
    SignalCombination(
      id: 'extortion_plus_crypto',
      label: 'Blackmail paired with a crypto demand',
      families: <String>['extortion_threat', 'crypto_context', 'secrecy_demand'],
      bonus: 18,
    ),
    SignalCombination(
      id: 'ml_plus_rule',
      label: 'On-device ML agrees with the rule evidence',
      families: <String>['ml_class', 'credential_request', 'payment_request', 'phishing_link'],
      bonus: 8,
    ),
  ];

  RiskAssessment assess(
    List<ShieldSignal> signals, {
    int senderRisk = 0,
    double? mlScamProbability,
    bool mlTopIsLegitimate = false,
    bool mlSpam = false,
  }) {
    final List<ShieldSignal> positives = signals.where((ShieldSignal s) => !s.isMitigation).toList();
    final List<ShieldSignal> mitigations = signals.where((ShieldSignal s) => s.isMitigation).toList();

    // ---- 1. collapse families (no double counting) ------------------------
    final Map<String, List<ShieldSignal>> byFamily = <String, List<ShieldSignal>>{};
    for (final ShieldSignal s in positives) {
      byFamily.putIfAbsent(s.family, () => <ShieldSignal>[]).add(s);
    }

    final Map<String, int> familyScores = <String, int>{};
    byFamily.forEach((String family, List<ShieldSignal> group) {
      group.sort((ShieldSignal a, ShieldSignal b) => b.magnitude.compareTo(a.magnitude));
      final int strongest = group.first.magnitude;
      int extra = 0;
      for (int i = 1; i < group.length; i++) {
        extra += group[i].magnitude;
      }
      // Extra evidence inside the same family adds a small, capped increment.
      familyScores[family] = (strongest + (extra * 0.15).round()).clamp(0, 100);
    });

    // ---- 2. sender reputation (local history, never uploaded) -------------
    if (senderRisk > 0) {
      familyScores['sender_reputation'] = senderRisk.clamp(0, 100);
    }

    // ---- 3. on-device ML contribution (one signal among many) -------------
    int mlFamilyScore = 0;
    if (mlScamProbability != null) {
      final int evidenceFamilies = familyScores.length;
      double contribution = mlScamProbability * 34;
      if (evidenceFamilies == 0) {
        // ML alone is deliberately weak: no lexical or behavioural evidence.
        contribution *= 0.35;
      } else if (evidenceFamilies == 1) {
        contribution *= 0.7;
      }
      mlFamilyScore = contribution.round().clamp(0, 40);
      if (mlFamilyScore > 0) familyScores['ml_class'] = mlFamilyScore;
    }

    // ---- 4. noisy-OR over families (probabilistic, not additive) ----------
    double remaining = 1.0;
    final List<MapEntry<String, int>> ranked = familyScores.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    for (final MapEntry<String, int> entry in ranked) {
      final double p = (entry.value.clamp(0, 100)) / 100.0;
      remaining *= (1 - p);
    }
    double score = (1 - remaining) * 100;

    // ---- 5. corroboration bonuses ---------------------------------------
    final List<SignalCombination> applied = <SignalCombination>[];
    int bonus = 0;
    for (final SignalCombination combo in combinations) {
      final int hits = combo.families.where(_familyPresent(familyScores)).length;
      if (hits >= combo.minimum) {
        applied.add(combo);
        bonus += combo.bonus;
      }
    }
    score += math.min(bonus, 30);

    // ---- 6. mitigations (legitimate context) ----------------------------
    final Map<String, int> mitigationFamilies = <String, int>{};
    for (final ShieldSignal s in mitigations) {
      mitigationFamilies[s.family] =
          math.max(mitigationFamilies[s.family] ?? 0, s.magnitude);
    }
    int mitigationPoints = 0;
    mitigationFamilies.forEach((String _, int value) => mitigationPoints += value);
    mitigationPoints = math.min(mitigationPoints, 45);
    score -= mitigationPoints;

    // Backstop: a message that explicitly asks for credentials/money cannot be
    // marked safe only because it also contains a generic "do not share" line.
    final int coreRisk = <String>['credential_request', 'payment_request', 'remote_access', 'extortion_threat']
        .map((String prefix) => _strongestMatching(familyScores, prefix))
        .fold(0, math.max);
    if (coreRisk >= 55) {
      score = math.max(score, math.min(88, coreRisk.toDouble()));
    }

    score = score.clamp(0, 100);
    int finalScore = score.round();

    // ---- 7. ML says legitimate: soften weak evidence only ----------------
    if (mlTopIsLegitimate && mlFamilyScore == 0 && finalScore < 40) {
      finalScore = math.max(0, finalScore - 8);
    }

    final RiskBand band = RiskBand.fromScore(finalScore);
    final List<ScamCategory> categories = _rankCategories(positives);
    // The ML model sees bulk-promotional wording the rule catalog may miss;
    // a confident spam verdict without any dangerous family stays in the
    // spam bucket instead of being called "safe".
    final bool noScamCategory = categories.isEmpty ||
        categories.every((ScamCategory c) => c == ScamCategory.suspicious || c.isSpam);
    final bool isSpam =
        _isSpam(categories, finalScore) || (mlSpam && finalScore < 30 && noScamCategory);

    final String headline = _headline(band, categories, isSpam);
    final List<String> objectives = _objectives(signals, categories, band);
    final List<String> actions = _actions(signals, categories, band);

    return RiskAssessment(
      score: finalScore,
      band: band,
      headline: headline,
      categories: categories,
      familyScores: familyScores,
      combinationsApplied: applied,
      explanation: _explain(finalScore, band, signals, applied, mitigationPoints, isSpam),
      objectives: objectives,
      actions: actions,
      mitigationPoints: mitigationPoints,
      isSpam: isSpam,
    );
  }

  /// Family matching also accepts prefixed sub-families (`credential_request:otp`).
  bool Function(String) _familyPresent(Map<String, int> families) => (String wanted) =>
        families.keys.any((String f) => f == wanted || f.startsWith('$wanted:'));

  int _strongestMatching(Map<String, int> families, String prefix) {
    int best = 0;
    families.forEach((String family, int value) {
      if (family == prefix || family.startsWith('$prefix:')) best = math.max(best, value);
    });
    return best;
  }

  List<ScamCategory> _rankCategories(List<ShieldSignal> positives) {
    final Map<String, int> byCategory = <String, int>{};
    for (final ShieldSignal s in positives) {
      if (s.category == ScamCategory.legitimate) continue;
      final int current = byCategory[s.category.id] ?? 0;
      byCategory[s.category.id] = math.max(current, s.magnitude);
    }
    final List<MapEntry<String, int>> ranked = byCategory.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    final List<ScamCategory> out = <ScamCategory>[];
    for (final MapEntry<String, int> entry in ranked) {
      if (entry.value < 12) continue;
      final ScamCategory c = ScamCategory.byId(entry.key);
      if (c == ScamCategory.suspicious) continue;
      out.add(c);
      if (out.length >= 3) break;
    }
    if (out.isEmpty) out.add(ScamCategory.suspicious);
    return out;
  }

  bool _isSpam(List<ScamCategory> categories, int score) {
    if (categories.isEmpty) return false;
    final ScamCategory top = categories.first;
    if (top.isSpam || top == ScamCategory.promotional) return true;
    if (score >= RiskEngineThresholds.scam) return false;
    // Pure promotional content that is not dangerous still counts as spam.
    final Map<String, int> spamIds = <String, int>{
      ScamCategory.spam.id: 1,
      ScamCategory.promotional.id: 1,
    };
    return spamIds.containsKey(top.id);
  }

  String _headline(RiskBand band, List<ScamCategory> categories, bool isSpam) {
    if (band == RiskBand.safe) {
      return isSpam ? 'SPAM, NOT A SCAM' : 'LOOKS SAFE';
    }
    if (band == RiskBand.suspicious) {
      return isSpam ? 'SPAM / LOW RISK' : 'SUSPICIOUS MESSAGE';
    }
    if (isSpam) return 'SPAM WITH SCAM PATTERNS';
    return 'SCAM DETECTED';
  }

  List<String> _objectives(List<ShieldSignal> signals, List<ScamCategory> categories, RiskBand band) {
    if (band == RiskBand.safe) return const <String>[];
    final List<String> out = <String>[];
    final List<ShieldSignal> ordered = signals.where((ShieldSignal s) => !s.isMitigation).toList()
      ..sort((ShieldSignal a, ShieldSignal b) => b.magnitude.compareTo(a.magnitude));
    for (final ShieldSignal s in ordered) {
      if (s.source == SignalSource.behavior && s.detail != null && s.magnitude >= 30) {
        if (!out.contains(s.detail)) out.add(s.detail!);
      }
    }
    for (final ScamCategory c in categories) {
      for (final String o in intelligence.objectivesFor(c.id).followedBy(c.fallbackObjectives)) {
        if (!out.contains(o)) out.add(o);
      }
      if (out.length >= 3) break;
    }
    return out.take(3).toList(growable: false);
  }

  List<String> _actions(List<ShieldSignal> signals, List<ScamCategory> categories, RiskBand band) {
    if (band == RiskBand.safe) {
      return const <String>['No action needed based on this message'];
    }
    final List<String> out = <String>[];
    for (final ScamCategory c in categories) {
      for (final String a in intelligence.actionsFor(c.id).followedBy(c.fallbackActions)) {
        if (!out.contains(a)) out.add(a);
      }
    }
    if (band == RiskBand.scam) {
      const List<String> universal = <String>[
        'Do not reply to this message',
        'Block and report the sender',
      ];
      for (final String u in universal) {
        if (!out.contains(u)) out.add(u);
      }
    }
    return out.take(5).toList(growable: false);
  }

  String _explain(
    int score,
    RiskBand band,
    List<ShieldSignal> signals,
    List<SignalCombination> applied,
    int mitigationPoints,
    bool isSpam,
  ) {
    final List<ShieldSignal> positives = signals.where((ShieldSignal s) => !s.isMitigation).toList()
      ..sort((ShieldSignal a, ShieldSignal b) => b.magnitude.compareTo(a.magnitude));
    final String top = positives.take(4).map((ShieldSignal s) => s.label).join(', ');
    final StringBuffer buffer = StringBuffer();
    if (band == RiskBand.safe) {
      buffer.write('Risk $score/100. No dangerous combination was found.');
      if (positives.isNotEmpty) {
        buffer.write(' Weak signals only: ${positives.take(2).map((ShieldSignal s) => s.label).join(', ')}.');
      }
    } else {
      buffer.write('Risk $score/100. Detected: ${top.isEmpty ? 'suspicious wording' : top}.');
    }
    if (applied.isNotEmpty) {
      buffer.write(' Combination: ${applied.first.label}.');
    }
    if (mitigationPoints > 0) {
      buffer.write(' Legitimate context reduced the score by $mitigationPoints points.');
    }
    if (isSpam && band != RiskBand.scam) {
      buffer.write(' This looks like bulk advertising rather than fraud.');
    }
    buffer.write(' Scored fully on-device.');
    return buffer.toString();
  }
}
