import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/analysis_result.dart';
import 'features.dart';

/// On-device message classifier.
///
/// Model: multinomial logistic regression (softmax) over a signed feature-hash
/// space of word unigrams/bigrams, character 4-grams and message flags, all
/// quantised to int8 (~80 KB). Inference is a sparse dot product: a few hundred
/// multiply-adds per message, pure CPU, no GPU, no native libraries, no network.
///
/// Weights are produced by `tool/message_shield/train_model.py` and shipped as
/// an asset. The model is ONE signal inside the risk engine — never the verdict
/// on its own (see risk_engine.dart).
class MlModel {
  MlModel({
    required this.version,
    required this.format,
    required this.featureVersion,
    required this.buckets,
    required this.classes,
    required this.scale,
    required this.weights,
    required this.bias,
    required this.trainingInfo,
    required this.metrics,
  });

  final int version;
  final String format;
  final String featureVersion;
  final int buckets;
  final List<String> classes;

  /// Quantisation scale: real weight = int8 value * scale.
  final double scale;

  /// int8 weights, row-major [classes][buckets].
  final Int8List weights;
  final Float32List bias;
  final Map<String, dynamic> trainingInfo;
  final Map<String, dynamic> metrics;

  int get parameterCount => classes.length * buckets;

  static MlModel fromJsonBytes(List<int> bytes) =>
      MlModel.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  factory MlModel.fromJson(Map<String, dynamic> json) {
    final Uint8List raw = base64Decode(json['weights_b64'] as String);
    final List<String> classes = (json['classes'] as List<dynamic>)
        .map((dynamic e) => e.toString())
        .toList(growable: false);
    final int buckets = (json['buckets'] as num).toInt();
    if (raw.length != classes.length * buckets) {
      throw FormatException(
        'model weights size ${raw.length} does not match '
        '${classes.length} classes x $buckets buckets',
      );
    }
    return MlModel(
      version: (json['version'] as num?)?.toInt() ?? 1,
      format: json['format'] as String? ?? 'hashed-linear-softmax-int8',
      featureVersion: json['feature_version'] as String? ?? 'unknown',
      buckets: buckets,
      classes: classes,
      scale: (json['quantization_scale'] as num).toDouble(),
      weights: Int8List.view(raw.buffer, raw.offsetInBytes, raw.length),
      bias: Float32List.fromList(
        (json['bias'] as List<dynamic>).map((dynamic e) => (e as num).toDouble()).toList(),
      ),
      trainingInfo: Map<String, dynamic>.from(
        (json['training'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
      ),
      metrics: Map<String, dynamic>.from(
        (json['metrics'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
      ),
    );
  }

  String get label => 'message_shield-ml-v$version';

  MlPrediction predictText(String text) => predict(Fx.vector(text, buckets));

  /// [features] is the sparse hashed vector produced by [Fx.vector].
  MlPrediction predict(Map<int, double> features) {
    final int nClasses = classes.length;
    final List<double> logits = List<double>.filled(nClasses, 0);
    for (int c = 0; c < nClasses; c++) {
      logits[c] = bias[c];
    }
    final int rowStride = buckets;
    for (final MapEntry<int, double> entry in features.entries) {
      final double value = entry.value;
      if (value == 0) continue;
      final int bucket = entry.key;
      for (int c = 0; c < nClasses; c++) {
        final int w = weights[c * rowStride + bucket];
        if (w != 0) logits[c] += value * w * scale;
      }
    }

    double maxLogit = logits[0];
    for (int c = 1; c < nClasses; c++) {
      if (logits[c] > maxLogit) maxLogit = logits[c];
    }
    double sum = 0;
    final List<double> probs = List<double>.filled(nClasses, 0);
    for (int c = 0; c < nClasses; c++) {
      final double e = math.exp(logits[c] - maxLogit);
      probs[c] = e;
      sum += e;
    }
    for (int c = 0; c < nClasses; c++) {
      probs[c] = sum == 0 ? 0 : probs[c] / sum;
    }

    int top = 0;
    for (int c = 1; c < nClasses; c++) {
      if (probs[c] > probs[top]) top = c;
    }
    return MlPrediction(classes: classes, probabilities: probs, topIndex: top);
  }
}

class MlPrediction {
  MlPrediction({
    required this.classes,
    required this.probabilities,
    required this.topIndex,
  });

  final List<String> classes;
  final List<double> probabilities;
  final int topIndex;

  String get topClass => classes[topIndex];

  double get topProbability => probabilities[topIndex];

  double probabilityOf(String label) {
    final int i = classes.indexOf(label);
    return i == -1 ? 0 : probabilities[i];
  }

  /// Probability mass on "not a legitimate message".
  double get nonLegitimateProbability {
    final int legit = classes.indexOf('legitimate');
    if (legit == -1) return topProbability;
    return (1 - probabilities[legit]).clamp(0.0, 1.0);
  }

  /// Sorted class scores for display.
  List<MlClassScore> get rankedScores {
    final List<int> order = List<int>.generate(classes.length, (int i) => i)
      ..sort((int a, int b) => probabilities[b].compareTo(probabilities[a]));
    return order
        .take(4)
        .map((int i) => MlClassScore(classes[i], probabilities[i]))
        .toList(growable: false);
  }

  @override
  String toString() =>
      'MlPrediction($topClass=${topProbability.toStringAsFixed(3)})';
}
