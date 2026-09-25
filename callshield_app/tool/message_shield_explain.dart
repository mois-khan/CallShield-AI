// Developer helper: run the real pipeline on one message and print every signal.
//
//   cd callshield_app
//   dart tool/message_shield_explain.dart "Dear customer, your KYC is expired..."
//   echo "some message" | dart tool/message_shield_explain.dart
import 'dart:io';

import 'package:callshield_app/message_shield/engine/message_shield_engine.dart';
import 'package:callshield_app/message_shield/models/analysis_result.dart';
import 'package:callshield_app/message_shield/models/message_input.dart';
import 'package:callshield_app/message_shield/models/shield_signal.dart';

void main(List<String> args) {
  final String text = args.isNotEmpty ? args.join(' ') : stdin.readLineSync() ?? '';
  if (text.trim().isEmpty) {
    stderr.writeln('usage: dart tool/message_shield_explain.dart "<message>"');
    exit(2);
  }

  final engine = MessageShieldEngine.fromJsonAssets(
    modelBytes: File('assets/message_shield/ml/message_shield_model.json').readAsBytesSync(),
    intelligenceBytes:
        File('assets/message_shield/intelligence/scam_intelligence.json').readAsBytesSync(),
  );

  final AnalysisResult result =
      engine.analyze(MessageInput(text: text, channel: MessageChannel.manual));

  stdout.writeln('text        : ${text.trim()}');
  stdout.writeln('risk        : ${result.riskScore}/100  ${result.band.label}  '
      '(${result.headline})');
  stdout.writeln('categories  : ${result.categories.map((dynamic c) => c.label).join(', ')}');
  stdout.writeln('spam        : ${result.isSpam}');
  stdout.writeln('explanation : ${result.explanation}');
  stdout.writeln('objective   : ${result.objectives.join(' | ')}');
  stdout.writeln('actions     :');
  for (final String a in result.recommendedActions) {
    stdout.writeln('              - $a');
  }
  stdout.writeln('ml          : ${result.mlScores.map((dynamic m) => '${m.label} ${(m.probability * 100).toStringAsFixed(1)}%').join(', ')}');
  stdout.writeln('signals     :');
  for (final ShieldSignal s in result.signals) {
    stdout.writeln('   ${s.weight.toString().padLeft(4)}  ${s.family.padRight(28)} '
        '${s.source.name.padRight(12)} ${s.label}'
        '${s.matchedText == null ? '' : '   <<${s.matchedText}>>'}');
  }
  if (result.urlFindings.isNotEmpty) {
    stdout.writeln('urls        :');
    for (final UrlFinding u in result.urlFindings) {
      stdout.writeln('   ${u.suspicion.toString().padLeft(3)}  ${u.host}  ${u.reasons.join('; ')}');
    }
  }
  stdout.writeln('timing      : ${(result.processingMicros / 1000).toStringAsFixed(3)} ms');
}
