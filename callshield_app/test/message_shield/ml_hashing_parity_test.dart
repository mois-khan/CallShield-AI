import 'dart:convert';
import 'dart:io';

import 'package:callshield_app/message_shield/engine/features.dart';
import 'package:callshield_app/message_shield/engine/ml_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the contract between `tool/message_shield/features.py` (which trained
/// the shipped weights) and `lib/message_shield/engine/features.dart` (which
/// runs on device). Regenerate the fixture with:
///   python tool/message_shield/export_parity_vectors.py
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    fixture = jsonDecode(
      File('test/message_shield/parity_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('fixture uses the shipped feature-space version', () {
    expect(fixture['feature_version'], Fx.featureVersion);
  });

  test('FNV-1a hashing matches the Python reference', () {
    for (final dynamic raw in fixture['hashes'] as List<dynamic>) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw as Map);
      final String feature = row['feature'] as String;
      expect(Fx.hash32(feature), row['hash'], reason: 'hash of $feature');
      expect(Fx.bucketOf(feature, fixture['buckets'] as int), row['bucket'],
          reason: 'bucket of $feature');
      expect(Fx.signOf(feature), row['sign'], reason: 'sign of $feature');
    }
  });

  test('extracted feature sets match the Python reference exactly', () {
    for (final dynamic raw in fixture['messages'] as List<dynamic>) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw as Map);
      final List<String> expected =
          (row['features'] as List<dynamic>).map((dynamic e) => e.toString()).toList();
      expect(Fx.featurize(row['text'] as String), expected,
          reason: 'features for: ${row['text']}');
    }
  });

  test('signed hashed vectors match the Python reference', () {
    for (final dynamic raw in fixture['messages'] as List<dynamic>) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw as Map);
      final Map<String, dynamic> expected = Map<String, dynamic>.from(row['vector'] as Map);
      final Map<int, double> actual = Fx.vector(row['text'] as String, fixture['buckets'] as int);
      final Map<String, double> actualString = <String, double>{
        for (final MapEntry<int, double> e in actual.entries) '${e.key}': e.value,
      };
      expect(actualString, expected, reason: 'vector for: ${row['text']}');
    }
  });

  group('shipped model', () {
    late MlModel model;

    setUpAll(() {
      model = MlModel.fromJsonBytes(
        File('assets/message_shield/ml/message_shield_model.json').readAsBytesSync(),
      );
    });

    test('loads with matching dimensions and honest metadata', () {
      expect(model.classes.length, 10);
      expect(model.weights.length, model.classes.length * model.buckets);
      expect(model.classes, contains('legitimate'));
      expect(model.classes, contains('credential_theft'));
      expect(model.metrics['held_out_test_quantised_int8'], isNotNull);
    });

    test('separates a clear scam from a clear legitimate message', () {
      final MlPrediction scam = model.predictText(
        'Your KYC is expired, update now at http://sbi-kyc-update.xyz/verify or your '
        'account will be blocked within 24 hours.',
      );
      final MlPrediction legit = model.predictText(
        '482913 is your OTP for SBI net banking login. Do not share this code with '
        'anyone, including bank staff.',
      );
      expect(scam.nonLegitimateProbability, greaterThan(0.8));
      expect(legit.topClass, 'legitimate');
    });

    test('is robust to leet/obfuscated wording', () {
      final MlPrediction prediction = model.predictText(
        'sh4re the 0TP with 0ur officer immediatly for K.Y.C verif1cation',
      );
      expect(prediction.nonLegitimateProbability, greaterThan(0.7));
    });

    test('returns normalised probabilities', () {
      final MlPrediction prediction = model.predictText('hello there, are we meeting at 7?');
      final double sum = prediction.probabilities.reduce((double a, double b) => a + b);
      expect(sum, closeTo(1.0, 1e-6));
    });
  });
}
