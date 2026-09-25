import 'dart:io';

import 'package:callshield_app/message_shield/engine/message_shield_engine.dart';
import 'package:callshield_app/message_shield/models/analysis_result.dart';
import 'package:callshield_app/message_shield/models/message_input.dart';
import 'package:callshield_app/message_shield/models/scam_category.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_engine.dart';

/// End-to-end evaluation of the shipped artifacts against the held-out corpus
/// (`assets/message_shield/eval/held_out_corpus.json`).
///
/// The corpus is synthetic and authored for this repository (no third-party
/// data is redistributed), so the numbers below characterise *this
/// distribution* — they are not a claim about real-world accuracy. Thresholds
/// are regression guards set slightly below the measured values.
void main() {
  late MessageShieldEngine engine;
  late List<Map<String, dynamic>> corpus;

  setUpAll(() {
    engine = loadEngine();
    corpus = loadCorpus();
  });

  test('held-out corpus metrics (precision / recall / F1 / FPR)', () {
    int tp = 0, fp = 0, tn = 0, fn = 0;
    int legitSpamFlagged = 0;
    final Map<String, int> perClassTotal = <String, int>{};
    final Map<String, int> perClassCaught = <String, int>{};
    final List<String> misses = <String>[];
    final List<String> falsePositives = <String>[];

    for (final Map<String, dynamic> sample in corpus) {
      final String text = sample['text'] as String;
      final String label = sample['label'] as String;
      final AnalysisResult result = engine.analyze(MessageInput(text: text));
      final bool risky = result.band != RiskBand.safe || result.isSpam;
      final bool isLegit = label == 'legitimate';

      if (isLegit) {
        if (risky) {
          fp++;
          legitSpamFlagged += result.isSpam ? 1 : 0;
          if (falsePositives.length < 8) {
            falsePositives.add('${result.band.label} ${result.riskScore} :: $text');
          }
        } else {
          tn++;
        }
      } else {
        perClassTotal[label] = (perClassTotal[label] ?? 0) + 1;
        if (result.band == RiskBand.safe && !result.isSpam) {
          fn++;
          if (misses.length < 8) {
            misses.add('$label ${result.band.label} ${result.riskScore} :: $text');
          }
        } else {
          tp++;
          perClassCaught[label] = (perClassCaught[label] ?? 0) + 1;
        }
      }
    }

    final double precision = tp / (tp + fp);
    final double recall = tp / (tp + fn);
    final double f1 = 2 * precision * recall / (precision + recall);
    final double fpr = fp / (fp + tn);
    final double legitClean = tn / (tn + fp);

    final StringBuffer table = StringBuffer()
      ..writeln('--- Message Shield held-out evaluation (n=${corpus.length}) ---')
      ..writeln('TP=$tp FP=$fp TN=$tn FN=$fn')
      ..writeln('precision=${precision.toStringAsFixed(4)} '
          'recall=${recall.toStringAsFixed(4)} F1=${f1.toStringAsFixed(4)}')
      ..writeln('false-positive-rate on legitimate=${fpr.toStringAsFixed(4)} '
          '(legitimate left unflagged: ${(legitClean * 100).toStringAsFixed(1)}%)')
      ..writeln('legitimate messages routed to the spam bucket=$legitSpamFlagged');
    perClassTotal.forEach((String label, int total) {
      final int caught = perClassCaught[label] ?? 0;
      table.writeln('  $label: $caught/$total '
          '(${(100 * caught / total).toStringAsFixed(1)}%)');
    });
    if (misses.isNotEmpty) {
      table.writeln('sample misses:');
      misses.forEach(table.writeln);
    }
    if (falsePositives.isNotEmpty) {
      table.writeln('sample false positives:');
      falsePositives.forEach(table.writeln);
    }
    // ignore: avoid_print
    print(table.toString());
    expect(f1, greaterThanOrEqualTo(0.94), reason: 'F1 regression');
    expect(recall, greaterThanOrEqualTo(0.93), reason: 'recall regression');
    expect(precision, greaterThanOrEqualTo(0.94), reason: 'precision regression');
    expect(legitClean, greaterThanOrEqualTo(0.88),
        reason: 'too many legitimate messages flagged');
  });

  test('adversarially obfuscated slice holds up', () {
    final List<Map<String, dynamic>> adversarial = corpus
        .where((Map<String, dynamic> s) => s['adversarial'] == true)
        .toList();
    expect(adversarial.length, greaterThan(100),
        reason: 'adversarial slice should be a meaningful part of the corpus');
    int caught = 0;
    for (final Map<String, dynamic> sample in adversarial) {
      final AnalysisResult result =
          engine.analyze(MessageInput(text: sample['text'] as String));
      if (result.band != RiskBand.safe || result.isSpam) caught++;
    }
    final double rate = caught / adversarial.length;
    // ignore: avoid_print
    print('adversarial slice recall: ${(rate * 100).toStringAsFixed(1)}% '
        '($caught/${adversarial.length})');
    expect(rate, greaterThanOrEqualTo(0.9));
  });

  test('latency and memory stay inside the mobile budget', () {
    final List<String> texts = corpus
        .take(300)
        .map((Map<String, dynamic> s) => s['text'] as String)
        .toList();
    // Warm up the JIT so the measurement reflects the pipeline, not the VM.
    for (int i = 0; i < 80; i++) {
      engine.analyze(MessageInput(text: texts[i % texts.length]));
    }

    final List<int> micros = <int>[];
    for (final String text in texts) {
      final AnalysisResult result = engine.analyze(MessageInput(text: text));
      micros.add(result.processingMicros);
    }
    micros.sort();
    final double mean = micros.reduce((int a, int b) => a + b) / micros.length;
    final int p95 = micros[(micros.length * 95) ~/ 100];
    final int worst = micros.last;

    final int rssBefore = ProcessInfo.currentRss;
    for (final String text in texts) {
      engine.analyze(MessageInput(text: text));
    }
    final int rssAfter = ProcessInfo.currentRss;
    final int rssGrowthMb = (rssAfter - rssBefore) ~/ (1024 * 1024);

    // ignore: avoid_print
    print('pipeline latency over ${micros.length} messages: '
        'mean=${(mean / 1000).toStringAsFixed(2)}ms '
        'p95=${(p95 / 1000).toStringAsFixed(2)}ms '
        'worst=${(worst / 1000).toStringAsFixed(2)}ms; '
        'RSS growth after ${texts.length * 2} analyses: ${rssGrowthMb}MB');
    expect(mean, lessThan(pipelineBudget.inMicroseconds.toDouble() / 3));
    expect(p95, lessThan(pipelineBudget.inMicroseconds.toDouble()));
    // A runaway cache/leak would show up as hundreds of MB here.
    expect(rssGrowthMb, lessThan(64));
  });
}
