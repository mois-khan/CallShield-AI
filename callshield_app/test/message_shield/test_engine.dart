import 'dart:convert';
import 'dart:io';

import 'package:callshield_app/message_shield/engine/message_shield_engine.dart';
import 'package:callshield_app/message_shield/models/analysis_result.dart';
import 'package:callshield_app/message_shield/models/message_input.dart';
import 'package:callshield_app/message_shield/models/scam_category.dart';

/// Loads the SHIPPED model + intelligence assets through dart:io so the tests
/// exercise exactly what the app runs on device (no mocks, no fixtures).
MessageShieldEngine loadEngine() => MessageShieldEngine.fromJsonAssets(
      modelBytes: File('assets/message_shield/ml/message_shield_model.json').readAsBytesSync(),
      intelligenceBytes:
          File('assets/message_shield/intelligence/scam_intelligence.json').readAsBytesSync(),
    );

AnalysisResult analyzeText(MessageShieldEngine engine, String text, {String? sender}) =>
    engine.analyze(MessageInput(text: text, sender: sender));

List<Map<String, dynamic>> loadCorpus() {
  final Map<String, dynamic> json = jsonDecode(
    File('assets/message_shield/eval/held_out_corpus.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return (json['samples'] as List<dynamic>)
      .map((dynamic e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

bool isRisky(AnalysisResult result) => result.band != RiskBand.safe;

/// Per-message budget for the whole pipeline on a modern phone core. The
/// measured mean is ~4 ms; this is a generous regression guard, not a target.
const Duration pipelineBudget = Duration(milliseconds: 60);
