import 'scam_category.dart';

/// Where a piece of evidence came from. Shown in the UI so the user can see
/// which layer of the pipeline produced each finding.
enum SignalSource {
  rule('Rule engine'),
  behavior('Behaviour engine'),
  url('URL analysis'),
  intelligence('Scam intelligence'),
  ml('On-device ML'),
  sender('Sender reputation'),
  context('Message context');

  const SignalSource(this.label);

  final String label;
}

/// One explainable piece of evidence.
///
/// [family] is the correlation key: the risk engine collapses signals that
/// share a family so the same evidence cannot be counted twice (for example
/// "OTP request" from the rule engine and from the behaviour engine).
class ShieldSignal {
  const ShieldSignal({
    required this.id,
    required this.family,
    required this.category,
    required this.weight,
    required this.label,
    required this.source,
    this.detail,
    this.matchedText,
  });

  /// Stable evidence id (used for de-duplication and for tests).
  final String id;

  /// Overlap family used by the risk engine.
  final String family;

  final ScamCategory category;

  /// Contribution in risk points. Negative weights are *mitigations*
  /// (evidence that the message is probably legitimate).
  final int weight;

  final String label;
  final SignalSource source;
  final String? detail;

  /// The fragment of the message that triggered this signal, if any.
  final String? matchedText;

  bool get isMitigation => weight < 0;

  int get magnitude => weight < 0 ? -weight : weight;

  ShieldSignal copyWith({int? weight, String? label}) => ShieldSignal(
        id: id,
        family: family,
        category: category,
        weight: weight ?? this.weight,
        label: label ?? this.label,
        source: source,
        detail: detail,
        matchedText: matchedText,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'family': family,
        'category': category.id,
        'weight': weight,
        'label': label,
        'source': source.name,
        if (detail != null) 'detail': detail,
      };

  static ShieldSignal fromJson(Map<String, dynamic> json) => ShieldSignal(
        id: json['id'] as String? ?? 'unknown',
        family: json['family'] as String? ?? 'unknown',
        category: ScamCategory.byId(json['category'] as String? ?? 'suspicious'),
        weight: (json['weight'] as num?)?.toInt() ?? 0,
        label: json['label'] as String? ?? 'Signal',
        source: SignalSource.values.firstWhere(
          (SignalSource s) => s.name == json['source'],
          orElse: () => SignalSource.rule,
        ),
        detail: json['detail'] as String?,
      );
}
