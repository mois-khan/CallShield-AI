import 'dart:io';

import 'package:callshield_app/message_shield/engine/risk_engine.dart';
import 'package:callshield_app/message_shield/intelligence/scam_intelligence.dart';
import 'package:callshield_app/message_shield/models/scam_category.dart';
import 'package:callshield_app/message_shield/models/shield_signal.dart';
import 'package:flutter_test/flutter_test.dart';

ShieldSignal signal(
  String id, {
  required String family,
  required int weight,
  ScamCategory? category,
  SignalSource source = SignalSource.rule,
}) =>
    ShieldSignal(
      id: id,
      family: family,
      category: category ?? ScamCategory.suspicious,
      weight: weight,
      label: id,
      source: source,
    );

void main() {
  late RiskEngine engine;

  setUpAll(() {
    engine = RiskEngine(
      intelligence: ScamIntelligence.fromJsonBytes(
        File('assets/message_shield/intelligence/scam_intelligence.json').readAsBytesSync(),
      ),
    );
  });

  test('a single weak signal stays in the SAFE band', () {
    final RiskAssessment assessment = engine.assess(<ShieldSignal>[
      signal('otp_mention', family: 'credential_mention', weight: 12),
      signal('urgency', family: 'urgency', weight: 16),
    ]);
    expect(assessment.band, RiskBand.safe);
    expect(assessment.score, lessThan(RiskEngineThresholds.suspicious));
  });

  test('duplicate evidence in the same family is not counted twice', () {
    final RiskAssessment one = engine.assess(<ShieldSignal>[
      signal('otp_share', family: 'credential_request:otp', weight: 62),
    ]);
    final RiskAssessment duplicated = engine.assess(<ShieldSignal>[
      signal('otp_share', family: 'credential_request:otp', weight: 62),
      signal('otp_share_behavior', family: 'credential_request:otp', weight: 62),
    ]);
    expect(duplicated.score - one.score, lessThan(15),
        reason: 'same-family evidence must collapse (got ${duplicated.score} vs ${one.score})');
  });

  test('different families combine through the combination bonus', () {
    final RiskAssessment credentialOnly = engine.assess(<ShieldSignal>[
      signal('otp_share', family: 'credential_request:otp', weight: 62),
    ]);
    final RiskAssessment combined = engine.assess(<ShieldSignal>[
      signal('otp_share', family: 'credential_request:otp', weight: 62),
      signal('authority', family: 'authority_context', weight: 14),
      signal('claim', family: 'impersonation_claim', weight: 22),
    ]);
    expect(combined.score, greaterThan(credentialOnly.score));
    expect(combined.combinationsApplied.map((SignalCombination c) => c.id),
        contains('credential_plus_authority'));
    expect(combined.band, RiskBand.scam);
  });

  test('mitigations lower the score but cannot hide a direct credential request', () {
    final RiskAssessment assessment = engine.assess(<ShieldSignal>[
      signal('otp_share', family: 'credential_request:otp', weight: 62),
      signal(
        'legit_helper',
        family: 'legit_context:otp_helper',
        weight: -30,
        category: ScamCategory.legitimate,
      ),
    ]);
    expect(assessment.mitigationPoints, 30);
    expect(assessment.score, greaterThanOrEqualTo(55),
        reason: 'the backstop must keep a real credential request risky');
  });

  test('ML alone cannot push a message into the scam band', () {
    final RiskAssessment assessment = engine.assess(
      <ShieldSignal>[],
      mlScamProbability: 0.99,
    );
    expect(assessment.band, RiskBand.safe,
        reason: 'ML without any other evidence is deliberately weak');
  });

  test('ML strengthens a message that already has evidence', () {
    final RiskAssessment without = engine.assess(<ShieldSignal>[
      signal('link', family: 'phishing_link', weight: 34),
    ]);
    final RiskAssessment with_ = engine.assess(
      <ShieldSignal>[signal('link', family: 'phishing_link', weight: 34)],
      mlScamProbability: 0.95,
    );
    expect(with_.score, greaterThan(without.score));
  });

  test('sender reputation derived from local history raises the score', () {
    final RiskAssessment clean = engine.assess(<ShieldSignal>[
      signal('urgency', family: 'urgency', weight: 16),
    ]);
    final RiskAssessment repeat = engine.assess(
      <ShieldSignal>[
        signal('urgency', family: 'urgency', weight: 16),
        signal('sender_history', family: 'sender_reputation', weight: 30, source: SignalSource.sender),
      ],
      senderRisk: 30,
    );
    expect(repeat.score, greaterThan(clean.score));
  });

  test('banding thresholds are stable', () {
    expect(RiskBand.fromScore(0), RiskBand.safe);
    expect(RiskBand.fromScore(29), RiskBand.safe);
    expect(RiskBand.fromScore(30), RiskBand.suspicious);
    expect(RiskBand.fromScore(59), RiskBand.suspicious);
    expect(RiskBand.fromScore(60), RiskBand.scam);
    expect(RiskBand.fromScore(100), RiskBand.scam);
  });

  test('the explanation always names what was detected', () {
    final RiskAssessment assessment = engine.assess(<ShieldSignal>[
      signal('otp_share', family: 'credential_request:otp', weight: 62, category: ScamCategory.credentialTheft),
      signal('urgency', family: 'urgency', weight: 16),
    ]);
    expect(assessment.explanation, contains('Detected:'));
    expect(assessment.explanation.toLowerCase(), contains('on-device'));
    expect(assessment.objectives, isNotEmpty);
    expect(assessment.actions, isNotEmpty);
  });
}
