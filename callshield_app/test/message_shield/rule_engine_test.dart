import 'package:callshield_app/message_shield/engine/preprocessor.dart';
import 'package:callshield_app/message_shield/engine/rule_engine.dart';
import 'package:callshield_app/message_shield/engine/rules/rule_catalog.dart';
import 'package:callshield_app/message_shield/models/shield_signal.dart';
import 'package:flutter_test/flutter_test.dart';

List<ShieldSignal> fire(String text) =>
    RuleEngine(rules: RuleCatalog.rules).evaluate(preprocess(text));

ShieldSignal? find(List<ShieldSignal> signals, String id) {
  for (final ShieldSignal s in signals) {
    if (s.id == id) return s;
  }
  return null;
}

void main() {
  group('combination logic', () {
    test('a bare OTP mention is a weak signal, not a verdict', () {
      final List<ShieldSignal> signals = fire('Your OTP is 482913');
      final ShieldSignal? mention = find(signals, 'otp_mention');
      expect(mention, isNotNull, reason: 'the mention rule should fire');
      expect(mention!.weight, lessThan(15),
          reason: 'OTP alone must not score like a scam (got ${mention.weight})');
      expect(find(signals, 'otp_share_request'), isNull);
    });

    test('OTP + request to share is a strong signal', () {
      final List<ShieldSignal> signals = fire('Please share the OTP you just received with our officer');
      final ShieldSignal? request = find(signals, 'otp_share_request');
      expect(request, isNotNull);
      expect(request!.weight, greaterThanOrEqualTo(60));
    });

    test('urgency alone stays low', () {
      final List<ShieldSignal> signals = fire('Meeting is urgent, please confirm now');
      final ShieldSignal? urgency = find(signals, 'urgency');
      expect(urgency, isNotNull);
      expect(urgency!.weight, lessThanOrEqualTo(16));
    });

    test('payment request is gated on a money context', () {
      final List<ShieldSignal> withContext = fire('Please transfer Rs.4,999 to my account today');
      final List<ShieldSignal> withoutContext = fire('Please transfer the file to my account');
      expect(find(withContext, 'payment_request')!.weight,
          greaterThan(find(withoutContext, 'payment_request')?.weight ?? 0));
    });
  });

  group('suppression', () {
    test('legitimate helper text suppresses the OTP-request rule', () {
      final List<ShieldSignal> signals = fire(
        '482913 is your OTP. Do not share this OTP with anyone, including bank staff.',
      );
      expect(find(signals, 'otp_share_request'), isNull);
      expect(find(signals, 'legit_otp_helper_text')?.weight, lessThan(0));
    });

    test('a negated instruction never counts as a request', () {
      final List<ShieldSignal> signals =
          fire('OTP kisi ke saath share na karein, bank kabhi OTP nahi maangta');
      expect(find(signals, 'otp_share_request'), isNull);
      expect(find(signals, 'pin_password_request'), isNull);
    });

    test('official-domain links are treated as legitimate context', () {
      final List<ShieldSignal> signals =
          fire('View your statement: https://www.hdfcbank.com/login');
      expect(find(signals, 'legit_brand_official_domain')?.weight, lessThan(0));
    });
  });

  group('obfuscation tolerance', () {
    test('detects leet-spelled OTP requests', () {
      final List<ShieldSignal> signals = fire('pls sh4re the 0TP with our officer now');
      expect(find(signals, 'otp_share_request'), isNotNull);
    });

    test('detects spaced abbreviations', () {
      final List<ShieldSignal> signals = fire('kindly share the O T P to complete K Y C');
      expect(find(signals, 'otp_share_request'), isNotNull);
    });

    test('detects obfuscated CVV requests', () {
      final List<ShieldSignal> signals = fire('we need your c.v.v and card exp1r3 date to unblock');
      expect(find(signals, 'pin_password_request'), isNotNull);
    });
  });

  group('family design', () {
    test('the catalog has no duplicate rule ids and no empty triggers', () {
      final Set<String> ids = <String>{};
      for (final DetectionRule rule in RuleCatalog.rules) {
        expect(ids.add(rule.id), isTrue, reason: 'duplicate rule id ${rule.id}');
        expect(rule.triggers, isNotEmpty, reason: '${rule.id} has no triggers');
        expect(rule.family, isNotEmpty);
      }
    });
  });
}
