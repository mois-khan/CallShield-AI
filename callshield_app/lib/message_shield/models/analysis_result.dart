import '../utils/message_source.dart';
import 'message_input.dart';
import 'message_origin.dart';
import 'scam_category.dart';
import 'shield_signal.dart';

/// Textual finding about a URL inside the message. Message Shield never opens,
/// follows, or sandboxes a URL — only its text is inspected.
class UrlFinding {
  const UrlFinding({
    required this.url,
    required this.host,
    required this.suspicion,
    required this.reasons,
  });

  final String url;
  final String host;

  /// 0–100 textual suspicion of the link itself.
  final int suspicion;
  final List<String> reasons;

  bool get isSuspicious => suspicion >= 40;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'host': host,
        'suspicion': suspicion,
        'reasons': reasons,
      };

  static UrlFinding fromJson(Map<String, dynamic> json) => UrlFinding(
        url: json['url'] as String? ?? '',
        host: json['host'] as String? ?? '',
        suspicion: (json['suspicion'] as num?)?.toInt() ?? 0,
        reasons: (json['reasons'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(),
      );
}

/// One class probability produced by the on-device ML model.
class MlClassScore {
  const MlClassScore(this.label, this.probability);

  final String label;
  final double probability;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'probability': double.parse(probability.toStringAsFixed(4)),
      };

  static MlClassScore fromJson(Map<String, dynamic> json) => MlClassScore(
        json['label'] as String? ?? '',
        (json['probability'] as num?)?.toDouble() ?? 0,
      );
}

/// The complete, explainable verdict for one message.
class AnalysisResult {
  const AnalysisResult({
    required this.riskScore,
    required this.band,
    required this.headline,
    required this.categories,
    required this.signals,
    required this.urlFindings,
    required this.mlScores,
    required this.objectives,
    required this.recommendedActions,
    required this.explanation,
    required this.input,
    required this.processingMicros,
    required this.modelVersion,
    this.isSpam = false,
    this.fromCache = false,
    this.analyzedAt,
    this.id,
  });

  final int riskScore;
  final RiskBand band;

  /// Short headline for the result card, e.g. "SCAM DETECTED".
  final String headline;

  /// Ranked categories (most confident first).
  final List<ScamCategory> categories;
  final List<ShieldSignal> signals;
  final List<UrlFinding> urlFindings;
  final List<MlClassScore> mlScores;

  /// Plain-language "likely attacker objective".
  final List<String> objectives;

  /// Plain-language recommended actions.
  final List<String> recommendedActions;
  final String explanation;

  final MessageInput input;
  final int processingMicros;
  final String modelVersion;
  final bool isSpam;

  /// True when an identical message had already been analysed (no re-run).
  final bool fromCache;
  final DateTime? analyzedAt;

  /// Local history id.
  final String? id;

  ScamCategory get primaryCategory =>
      categories.isEmpty ? ScamCategory.suspicious : categories.first;

  List<ShieldSignal> get activeSignals =>
      signals.where((ShieldSignal s) => !s.isMitigation).toList(growable: false);

  List<ShieldSignal> get mitigations =>
      signals.where((ShieldSignal s) => s.isMitigation).toList(growable: false);

  bool get isThreat => band == RiskBand.scam;

  String get scoreLabel => '$riskScore/100';

  /// Display-ready description of where this message came from.
  MessageSourceDescriptor get source =>
      MessageSourceDescriptor.describe(input.channel, input.origin);

  AnalysisResult copyWith({
    String? id,
    bool? fromCache,
    DateTime? analyzedAt,
    int? riskScore,
    MessageInput? input,
  }) =>
      AnalysisResult(
        riskScore: riskScore ?? this.riskScore,
        band: band,
        headline: headline,
        categories: categories,
        signals: signals,
        urlFindings: urlFindings,
        mlScores: mlScores,
        objectives: objectives,
        recommendedActions: recommendedActions,
        explanation: explanation,
        input: input ?? this.input,
        processingMicros: processingMicros,
        modelVersion: modelVersion,
        isSpam: isSpam,
        fromCache: fromCache ?? this.fromCache,
        analyzedAt: analyzedAt ?? this.analyzedAt,
        id: id ?? this.id,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'riskScore': riskScore,
        'band': band.name,
        'headline': headline,
        'categories': categories.map((ScamCategory c) => c.id).toList(),
        'signals': signals.map((ShieldSignal s) => s.toJson()).toList(),
        'urlFindings': urlFindings.map((UrlFinding u) => u.toJson()).toList(),
        'mlScores': mlScores.map((MlClassScore m) => m.toJson()).toList(),
        'objectives': objectives,
        'recommendedActions': recommendedActions,
        'explanation': explanation,
        'isSpam': isSpam,
        'processingMicros': processingMicros,
        'modelVersion': modelVersion,
        'channel': input.channel.name,
        'sender': input.sender,
        'senderKind': input.senderKind.name,
        if (input.origin != null) 'origin': input.origin!.toJson(),
        if (input.ingestId != null) 'ingestId': input.ingestId,
        'textPreview': input.safeText.length > 500
            ? input.safeText.substring(0, 500)
            : input.safeText,
        if (analyzedAt != null) 'analyzedAt': analyzedAt!.toIso8601String(),
        if (id != null) 'id': id,
      };

  static AnalysisResult fromJson(Map<String, dynamic> json) {
    final RiskBand band = RiskBand.values.firstWhere(
      (RiskBand b) => b.name == json['band'],
      orElse: () => RiskBand.safe,
    );
    final List<String> categoryIds = (json['categories'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) => e.toString())
        .toList();
    return AnalysisResult(
      riskScore: (json['riskScore'] as num?)?.toInt() ?? 0,
      band: band,
      headline: json['headline'] as String? ?? '',
      categories: categoryIds.map(ScamCategory.byId).toList(),
      signals: (json['signals'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => ShieldSignal.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      urlFindings: (json['urlFindings'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => UrlFinding.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      mlScores: (json['mlScores'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => MlClassScore.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      objectives: (json['objectives'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
      recommendedActions: (json['recommendedActions'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
      explanation: json['explanation'] as String? ?? '',
      input: MessageInput(
        text: json['textPreview'] as String? ?? '',
        sender: json['sender'] as String?,
        channel: MessageChannel.values.firstWhere(
          (MessageChannel c) => c.name == json['channel'],
          orElse: () => MessageChannel.unknown,
        ),
        senderKind: SenderKind.values.firstWhere(
          (SenderKind k) => k.name == json['senderKind'],
          orElse: () => SenderKind.unknown,
        ),
        origin: MessageOrigin.fromJson(
          json['origin'] == null
              ? null
              : Map<String, dynamic>.from(json['origin'] as Map),
        ),
        ingestId: json['ingestId'] as String?,
      ),
      processingMicros: (json['processingMicros'] as num?)?.toInt() ?? 0,
      modelVersion: json['modelVersion'] as String? ?? 'unknown',
      isSpam: json['isSpam'] as bool? ?? false,
      analyzedAt: json['analyzedAt'] == null
          ? null
          : DateTime.tryParse(json['analyzedAt'] as String),
      id: json['id'] as String?,
    );
  }
}
