import 'dart:convert';

import '../utils/text_tables.dart';
import 'preprocessor.dart';

/// Feature extraction + hashing for the on-device ML model.
///
/// This is the Dart mirror of `tool/message_shield/features.py`; the shipped
/// weights were trained with that exact feature definition. Keep both sides in
/// sync and run `test/message_shield/ml_hashing_parity_test.dart` after any
/// change.
class Fx {
  const Fx._();

  /// Feature-space version shipped with the model (see text_tables.dart).
  static String get featureVersion => kMessageShieldFeatureVersion;

  /// FNV-1a 32-bit over the UTF-8 bytes of [value] (unsigned, wraps at 2^32).
  static int hash32(String value) {
    int h = kFnvOffset;
    for (final int byte in utf8.encode(value)) {
      h ^= byte & 0xff;
      h = (h * kFnvPrime) & 0xFFFFFFFF;
    }
    return h;
  }

  static int bucketOf(String feature, int buckets) => hash32(feature) % buckets;

  static int signOf(String feature) => ((hash32(feature) >> 31) & 1) == 1 ? -1 : 1;

  /// Deterministic, de-duplicated feature strings for one raw message.
  static List<String> featurize(String text) {
    final String clean = normalizeText(text);
    final String skeleton = skeletonize(text);
    final Set<String> feats = <String>{};

    _tokenFeatures(tokenize(clean), feats, 'u:', 'b:', 'c:');
    if (skeleton != clean) {
      _tokenFeatures(tokenize(skeleton), feats, 'su:', 'sb:', 'sc:');
    }

    final ProcessedMessage processed = preprocess(text);
    for (final String flag in processed.flags) {
      feats.add('f:$flag');
    }

    final List<String> sorted = feats.toList()..sort();
    return sorted;
  }

  /// Signed hashing trick: colliding features accumulate (identical in Python).
  static Map<int, double> vector(String text, int buckets) {
    final Map<int, double> vec = <int, double>{};
    for (final String feat in featurize(text)) {
      final int bucket = bucketOf(feat, buckets);
      final double sign = signOf(feat) == -1 ? -1.0 : 1.0;
      vec[bucket] = (vec[bucket] ?? 0) + sign;
    }
    return vec;
  }

  static void _tokenFeatures(
    List<String> tokens,
    Set<String> feats,
    String uni,
    String bi,
    String ch,
  ) {
    for (final String t in tokens) {
      feats.add('$uni$t');
    }
    for (int i = 0; i + 1 < tokens.length; i++) {
      feats.add('$bi${tokens[i]}_${tokens[i + 1]}');
    }

    int grams = 0;
    int qualifying = 0;
    for (final String t in tokens) {
      if (t.length < 5 || grams >= 240) continue;
      qualifying++;
      if (qualifying > 12) break;
      for (int i = 0; i + 4 <= t.length; i++) {
        feats.add('$ch${t.substring(i, i + 4)}');
        grams++;
        if (grams >= 240) break;
      }
    }
  }
}
