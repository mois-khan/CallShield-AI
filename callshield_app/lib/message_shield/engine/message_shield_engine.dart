import '../intelligence/scam_intelligence.dart';
import '../models/analysis_result.dart';
import '../models/message_input.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';
import 'behavior_engine.dart';
import 'features.dart';
import 'ml_engine.dart';
import 'preprocessor.dart';
import 'risk_engine.dart';
import 'rule_engine.dart';
import 'rules/rule_catalog.dart';
import 'url_analyzer.dart';

/// Local history the store keeps about a sender (never leaves the device).
class SenderHistory {
  const SenderHistory({this.seenCount = 0, this.scamCount = 0});

  final int seenCount;
  final int scamCount;
}

/// Message Shield pipeline:
///
///   preprocess -> rule engine -> behaviour engine -> on-device ML ->
///   scam intelligence -> URL text analysis -> risk correlation -> verdict
///
/// The engine is pure Dart with no plugins, no I/O and no network, so it can run
/// in a background isolate and be tested directly.
class MessageShieldEngine {
  MessageShieldEngine({
    required this.model,
    required this.intelligence,
    RuleEngine? ruleEngine,
    BehaviorEngine? behaviorEngine,
    UrlAnalyzer? urlAnalyzer,
    RiskEngine? riskEngine,
  })  : ruleEngine = ruleEngine ?? RuleEngine(rules: RuleCatalog.rules),
        behaviorEngine = behaviorEngine ?? BehaviorEngine(),
        urlAnalyzer = urlAnalyzer ?? UrlAnalyzer(intelligence),
        riskEngine = riskEngine ?? RiskEngine(intelligence: intelligence);

  factory MessageShieldEngine.fromJsonAssets({
    required List<int> modelBytes,
    required List<int> intelligenceBytes,
  }) =>
      MessageShieldEngine(
        model: MlModel.fromJsonBytes(modelBytes),
        intelligence: ScamIntelligence.fromJsonBytes(intelligenceBytes),
      );

  final MlModel model;
  final ScamIntelligence intelligence;
  final RuleEngine ruleEngine;
  final BehaviorEngine behaviorEngine;
  final UrlAnalyzer urlAnalyzer;
  final RiskEngine riskEngine;

  String get version => '${model.label}+${intelligence.label}';

  /// Cheap deterministic fingerprint of a message used for the analysis cache
  /// (identical text is never analysed twice).
  static int fingerprint(String text) => Fx.hash32(normalizeText(text));

  AnalysisResult analyze(MessageInput input, {SenderHistory? senderHistory}) {
    final Stopwatch stopwatch = Stopwatch()..start();
    final ProcessedMessage msg = preprocess(input.safeText);

    final List<ShieldSignal> signals = <ShieldSignal>[];
    signals.addAll(ruleEngine.evaluate(msg));
    signals.addAll(behaviorEngine.signals(msg));
    signals.addAll(_intelligenceSignals(msg));
    signals.addAll(_senderSignals(input, senderHistory));

    final List<UrlFinding> urlFindings = urlAnalyzer.analyze(msg.urls);
    signals.addAll(urlAnalyzer.signals(urlFindings));

    final MlPrediction prediction = model.predictText(input.safeText);

    final RiskAssessment assessment = riskEngine.assess(
      signals,
      senderRisk: _senderRiskPoints(input, senderHistory),
      mlScamProbability: prediction.nonLegitimateProbability,
      mlTopIsLegitimate: prediction.topClass == 'legitimate',
      mlSpam: prediction.topClass == 'spam' && prediction.topProbability >= 0.85,
    );

    stopwatch.stop();
    return AnalysisResult(
      riskScore: assessment.score,
      band: assessment.band,
      headline: assessment.headline,
      categories: assessment.categories,
      signals: _sortedSignals(signals),
      urlFindings: urlFindings,
      mlScores: prediction.rankedScores,
      objectives: assessment.objectives,
      recommendedActions: assessment.actions,
      explanation: assessment.explanation,
      input: input,
      processingMicros: stopwatch.elapsedMicroseconds,
      modelVersion: version,
      isSpam: assessment.isSpam,
      analyzedAt: DateTime.now(),
    );
  }

  List<ShieldSignal> _sortedSignals(List<ShieldSignal> signals) {
    final List<ShieldSignal> copy = List<ShieldSignal>.of(signals);
    copy.sort((ShieldSignal a, ShieldSignal b) => b.magnitude.compareTo(a.magnitude));
    return copy;
  }

  /// Scam intelligence fingerprints (local campaign database).
  List<ShieldSignal> _intelligenceSignals(ProcessedMessage msg) {
    final List<ShieldSignal> out = <ShieldSignal>[];
    for (final ScamFingerprint fp in intelligence.hits(msg.clean)) {
      out.add(
        ShieldSignal(
          id: 'intel_${fp.id}',
          family: 'fingerprint:${fp.categoryId}',
          category: ScamCategory.byId(fp.categoryId),
          weight: fp.weight,
          label: fp.label,
          source: SignalSource.intelligence,
          detail: 'Matches a known scam pattern in the local intelligence database.',
        ),
      );
    }
    return out;
  }

  /// Sender-side signals: sender id shape, trust list and local history.
  List<ShieldSignal> _senderSignals(MessageInput input, SenderHistory? history) {
    final List<ShieldSignal> out = <ShieldSignal>[];
    final String? sender = input.sender;

    if (input.isTrustedSender) {
      out.add(
        const ShieldSignal(
          id: 'sender_trusted',
          family: 'legit_context:trusted_sender',
          category: ScamCategory.legitimate,
          weight: -25,
          label: 'Sender is marked as trusted',
          source: SignalSource.sender,
          detail: 'You marked this sender as trusted on this device.',
        ),
      );
    }

    if (sender != null && sender.trim().isNotEmpty) {
      for (final SenderPattern pattern in intelligence.senderPatterns) {
        if (!pattern.pattern.hasMatch(sender.trim().toLowerCase())) continue;
        out.add(
          ShieldSignal(
            id: 'sender_${pattern.id}',
            family: 'sender_shape',
            category: ScamCategory.suspicious,
            weight: pattern.weight,
            label: pattern.label,
            source: SignalSource.sender,
            detail: 'Sender id: ${sender.trim()}',
          ),
        );
      }
    }

    final int historyRisk = _senderRiskPoints(input, history);
    if (historyRisk > 0) {
      out.add(
        ShieldSignal(
          id: 'sender_history',
          family: 'sender_reputation',
          category: ScamCategory.suspicious,
          weight: historyRisk,
          label: 'This sender has previous risky messages',
          source: SignalSource.sender,
          detail: '${history!.scamCount} of ${history.seenCount} saved messages from this sender looked risky.',
        ),
      );
    }
    return out;
  }

  /// 0–40 points derived only from on-device history plus sender shape.
  int _senderRiskPoints(MessageInput input, SenderHistory? history) {
    if (history == null || history.seenCount == 0) return 0;
    if (input.isTrustedSender) return 0;
    final double ratio = history.scamCount / history.seenCount;
    double points = ratio * 34;
    if (history.seenCount < 2) points *= 0.5;
    return points.round().clamp(0, 40);
  }
}
