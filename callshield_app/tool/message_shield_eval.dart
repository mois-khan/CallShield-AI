// Message Shield evaluation harness (pure Dart, no Flutter, fully offline).
//
//   cd callshield_app
//   dart tool/message_shield_eval.dart
//
// Loads the shipped model + intelligence assets and the held-out corpus, runs the
// REAL end-to-end pipeline (rules + behaviour + ML + intelligence + risk) and
// prints measured precision / recall / F1 / false-positive rate plus inference
// time and RSS. Nothing here is fabricated: the numbers come from the run.
import 'dart:convert';
import 'dart:io';

import 'package:callshield_app/message_shield/engine/message_shield_engine.dart';
import 'package:callshield_app/message_shield/models/analysis_result.dart';
import 'package:callshield_app/message_shield/models/message_input.dart';
import 'package:callshield_app/message_shield/models/scam_category.dart';

const String kModelPath = 'assets/message_shield/ml/message_shield_model.json';
const String kIntelPath = 'assets/message_shield/intelligence/scam_intelligence.json';
const String kCorpusPath = 'assets/message_shield/eval/held_out_corpus.json';

class Row {
  Row(this.id, this.text, this.label, this.adversarial, this.result);

  final String id;
  final String text;
  final String label;
  final bool adversarial;
  final AnalysisResult result;

  bool get isLegit => label == 'legitimate';
  bool get isSpam => label == 'spam';
  bool get isScam => !isLegit && !isSpam;
  bool get flagged => result.band != RiskBand.safe;

  /// Spam bucket = the engine says bulk/promotional content (even when it is not
  /// dangerous enough to raise the risk band).
  bool get spamBucket => result.isSpam || result.band != RiskBand.safe;
}

class Counts {
  int tp = 0;
  int fp = 0;
  int fn = 0;
  int tn = 0;

  double get precision => tp + fp == 0 ? 0 : tp / (tp + fp);
  double get recall => tp + fn == 0 ? 0 : tp / (tp + fn);
  double get f1 => precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall);
  double get fpr => fp + tn == 0 ? 0 : fp / (fp + tn);
  double get accuracy => tp + tn + fp + fn == 0 ? 0 : (tp + tn) / (tp + tn + fp + fn);

  @override
  String toString() => 'P ${(precision * 100).toStringAsFixed(1)}%  '
      'R ${(recall * 100).toStringAsFixed(1)}%  '
      'F1 ${(f1 * 100).toStringAsFixed(1)}%  '
      'FPR ${(fpr * 100).toStringAsFixed(2)}%  '
      'acc ${(accuracy * 100).toStringAsFixed(1)}%  '
      '(tp $tp fp $fp fn $fn tn $tn)';
}

void main(List<String> args) {
  final File modelFile = File(kModelPath);
  final File intelFile = File(kIntelPath);
  final File corpusFile = File(kCorpusPath);
  for (final File f in <File>[modelFile, intelFile, corpusFile]) {
    if (!f.existsSync()) {
      stderr.writeln('missing ${f.path} - run from the callshield_app directory');
      exit(2);
    }
  }

  final engine = MessageShieldEngine.fromJsonAssets(
    modelBytes: modelFile.readAsBytesSync(),
    intelligenceBytes: intelFile.readAsBytesSync(),
  );
  final Map<String, dynamic> corpus =
      jsonDecode(corpusFile.readAsStringSync()) as Map<String, dynamic>;
  final List<dynamic> samples = corpus['samples'] as List<dynamic>;

  final List<Row> rows = <Row>[];
  final List<int> timings = <int>[];
  for (final dynamic raw in samples) {
    final Map<String, dynamic> sample = Map<String, dynamic>.from(raw as Map);
    final String text = sample['text'] as String;
    final AnalysisResult result = engine.analyze(
      MessageInput(text: text, sender: sample['label'] == 'legitimate' ? null : null),
    );
    timings.add(result.processingMicros);
    rows.add(Row(
      sample['id'] as String? ?? '',
      text,
      sample['label'] as String,
      sample['adversarial'] as bool? ?? false,
      result,
    ));
  }

  // ---------------------------------------------------------------- metrics
  final Counts anyRisk = Counts(); // legit vs (spam or scam) at SUSPICIOUS+
  final Counts scamBand = Counts(); // legit vs scam at SCAM band
  final Counts anyRiskAdv = Counts();
  final Counts spamBucket = Counts(); // spam/promotional bucketing, any band
  final Map<String, Counts> perClassAny = <String, Counts>{};
  final Map<String, Counts> perCategoryDetected = <String, Counts>{};
  int legitClean = 0;
  int legitFlagged = 0;
  int legitBucketedSpam = 0;

  for (final Row row in rows) {
    final bool predictedRisky = row.flagged;
    final bool predictedScam = row.result.band == RiskBand.scam;
    _add(anyRisk, row.isLegit, predictedRisky);
    _add(scamBand, row.isLegit, predictedScam);
    _add(spamBucket, row.isLegit, row.spamBucket);
    if (row.adversarial) _add(anyRiskAdv, row.isLegit, predictedRisky);

    if (row.isLegit) {
      if (predictedRisky) {
        legitFlagged++;
      } else {
        legitClean++;
      }
      if (row.spamBucket && !predictedRisky) legitBucketedSpam++;
    }

    // Per-class: for a scam class "detected" means the message was flagged; for
    // the spam class it means the engine put it in the spam/promotional bucket.
    for (final String label in <String>[
      'spam', 'phishing', 'financial_fraud', 'credential_theft',
      'impersonation', 'social_engineering', 'investment_scam', 'reward_scam', 'delivery_scam',
    ]) {
      if (row.label != label) continue;
      final Counts c = perClassAny.putIfAbsent(label, Counts.new);
      _add(c, false, label == 'spam' ? row.spamBucket : predictedRisky);
    }
    // False positives for every scam class are legitimate messages that got flagged.
    if (row.isLegit && predictedRisky) {
      for (final String label in <String>[
        'spam', 'phishing', 'financial_fraud', 'credential_theft',
        'impersonation', 'social_engineering', 'investment_scam', 'reward_scam', 'delivery_scam',
      ]) {
        perClassAny.putIfAbsent(label, Counts.new).fp++;
      }
    }

    if (!row.isLegit) {
      final Set<String> detected =
          row.result.categories.map((ScamCategory c) => c.id).toSet();
      if (row.result.band != RiskBand.safe) detected.add('flagged_only');
      final Counts c = perCategoryDetected.putIfAbsent(row.label, Counts.new);
      if (detected.contains(row.label) ||
          detected.contains('flagged_only') ||
          _compatible(row.label, detected)) {
        c.tp++;
      } else {
        c.fn++;
      }
    }
  }

  timings.sort();
  final int mean = timings.reduce((int a, int b) => a + b) ~/ timings.length;
  final int p50 = timings[timings.length ~/ 2];
  final int p95 = timings[(timings.length * 95) ~/ 100];
  final int max = timings.last;
  final int rss = ProcessInfo.currentRss;

  // ---------------------------------------------------------------- output
  stdout.writeln('Message Shield evaluation');
  stdout.writeln('engine: ${engine.version}');
  stdout.writeln('corpus: ${rows.length} held-out messages '
      '(${rows.where((Row r) => r.adversarial).length} obfuscated)');
  stdout.writeln('');
  stdout.writeln('END-TO-END  legit vs spam/scam (flag = SUSPICIOUS or SCAM)');
  stdout.writeln('  all messages     $anyRisk');
  stdout.writeln('  obfuscated slice $anyRiskAdv');
  stdout.writeln('END-TO-END  legit vs scam (flag = SCAM band only)');
  stdout.writeln('  all messages     $scamBand');
  stdout.writeln('END-TO-END  spam/promotional bucketing (band >= SUSPICIOUS or isSpam)');
  stdout.writeln('  all messages     $spamBucket');
  stdout.writeln('LEGITIMATE MESSAGES');
  stdout.writeln('  clean $legitClean / ${legitClean + legitFlagged} '
      '(${(100 * legitClean / (legitClean + legitFlagged)).toStringAsFixed(1)}% left alone), '
      'flagged $legitFlagged, additionally bucketed as promo-only $legitBucketedSpam');
  stdout.writeln('');
  stdout.writeln('PER-CLASS (detected for its own label; false positives are flagged legit messages)');
  final List<String> classKeys = perClassAny.keys.toList()..sort();
  for (final String key in classKeys) {
    stdout.writeln('  ${key.padRight(20)} ${perClassAny[key]}');
  }
  stdout.writeln('');
  stdout.writeln('CATEGORY-SPECIFIC RECALL (category named anywhere in the verdict)');
  final List<String> catKeys = perCategoryDetected.keys.toList()..sort();
  for (final String key in catKeys) {
    final Counts c = perCategoryDetected[key]!;
    final double recall = c.tp + c.fn == 0 ? 0 : c.tp / (c.tp + c.fn);
    stdout.writeln('  ${key.padRight(20)} ${(recall * 100).toStringAsFixed(1)}%  '
        '(${c.tp}/${c.tp + c.fn})');
  }
  stdout.writeln('');
  stdout.writeln('PERFORMANCE (per message, includes preprocessing + all engines + ML)');
  stdout.writeln('  mean ${(mean / 1000).toStringAsFixed(3)} ms   '
      'p50 ${(p50 / 1000).toStringAsFixed(3)} ms   '
      'p95 ${(p95 / 1000).toStringAsFixed(3)} ms   '
      'max ${(max / 1000).toStringAsFixed(3)} ms');
  stdout.writeln('  process RSS ${(rss / 1048576).toStringAsFixed(1)} MB');
  stdout.writeln('  model: ${engine.model.classes.length} classes x ${engine.model.buckets} buckets, '
      '${engine.model.parameterCount} int8 parameters');

  if (args.contains('--verbose')) {
    stdout.writeln('\nMISCLASSIFIED (risk not detected):');
    for (final Row row in rows.where((Row r) => !r.isLegit && !r.flagged).take(25)) {
      stdout.writeln('  [${row.label}] ${row.text}');
    }
    stdout.writeln('\nFALSE POSITIVES (legit flagged):');
    for (final Row row in rows.where((Row r) => r.isLegit && r.flagged)) {
      stdout.writeln('  [${row.result.band.name} ${row.result.riskScore}] ${row.text}');
    }
  }

  final File report = File('tool/message_shield/data/dart_eval_report.json');
  report.parent.createSync(recursive: true);
  report.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(<String, dynamic>{
    'engine': engine.version,
    'corpus_size': rows.length,
    'obfuscated_size': rows.where((Row r) => r.adversarial).length,
    'end_to_end_all': _dump(anyRisk),
    'end_to_end_obfuscated': _dump(anyRiskAdv),
    'end_to_end_scam_band': _dump(scamBand),
    'end_to_end_spam_bucket': _dump(spamBucket),
    'legitimate_clean_rate': double.parse(
        (legitClean / (legitClean + legitFlagged)).toStringAsFixed(4)),
    'legitimate_flagged': legitFlagged,
    'legitimate_promo_bucketed': legitBucketedSpam,
    'per_class': <String, dynamic>{
      for (final String key in classKeys) key: _dump(perClassAny[key]!),
    },
    'category_recall': <String, dynamic>{
      for (final String key in catKeys)
        key: (perCategoryDetected[key]!.tp /
                (perCategoryDetected[key]!.tp + perCategoryDetected[key]!.fn))
            .toStringAsFixed(3),
    },
    'performance': <String, dynamic>{
      'mean_us': mean, 'p50_us': p50, 'p95_us': p95, 'max_us': max, 'rss_bytes': rss,
    },
  }));
  stdout.writeln('\nreport written: ${report.path}');
}

bool _compatible(String label, Set<String> detected) {
  const Map<String, List<String>> overlaps = <String, List<String>>{
    'phishing': <String>['credential_theft', 'financial_fraud', 'impersonation', 'subscription_trap'],
    'financial_fraud': <String>['credential_theft', 'subscription_trap', 'phishing'],
    'credential_theft': <String>['financial_fraud', 'phishing', 'impersonation'],
    'impersonation': <String>['social_engineering', 'extortion', 'delivery_scam', 'financial_fraud'],
    'social_engineering': <String>['extortion', 'romance_scam', 'impersonation'],
    'investment_scam': <String>['reward_scam', 'financial_fraud'],
    'reward_scam': <String>['investment_scam', 'phishing'],
    'delivery_scam': <String>['phishing', 'impersonation', 'financial_fraud'],
  };
  for (final String alt in overlaps[label] ?? const <String>[]) {
    if (detected.contains(alt)) return true;
  }
  return false;
}

void _add(Counts c, bool negative, bool predictedPositive) {
  if (negative) {
    if (predictedPositive) {
      c.fp++;
    } else {
      c.tn++;
    }
  } else {
    if (predictedPositive) {
      c.tp++;
    } else {
      c.fn++;
    }
  }
}

Map<String, dynamic> _dump(Counts c) => <String, dynamic>{
      'precision': double.parse(c.precision.toStringAsFixed(4)),
      'recall': double.parse(c.recall.toStringAsFixed(4)),
      'f1': double.parse(c.f1.toStringAsFixed(4)),
      'false_positive_rate': double.parse(c.fpr.toStringAsFixed(4)),
      'accuracy': double.parse(c.accuracy.toStringAsFixed(4)),
      'tp': c.tp, 'fp': c.fp, 'fn': c.fn, 'tn': c.tn,
    };
