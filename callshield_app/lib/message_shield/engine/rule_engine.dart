import '../intelligence/scam_intelligence.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';
import 'preprocessor.dart';

/// Which textual view a rule pattern is evaluated against.
enum MatchView {
  /// Normalised text (lowercase, confusables folded).
  clean,

  /// Leetspeak-folded text (catches "0tp", "kyc@update").
  skeleton,

  /// Text with payment-brand compounds neutralised ("google pay" -> "walletapp").
  verb,

  /// Both clean and skeleton views (default for phrase rules).
  both,
}

/// One matcher inside a rule.
class RuleMatcher {
  const RuleMatcher(this.pattern, {this.view = MatchView.both});

  final RegExp pattern;
  final MatchView view;

  bool matches(ProcessedMessage msg) {
    switch (view) {
      case MatchView.clean:
        return pattern.hasMatch(msg.clean);
      case MatchView.skeleton:
        return pattern.hasMatch(msg.skeleton);
      case MatchView.verb:
        return pattern.hasMatch(msg.verbText);
      case MatchView.both:
        return pattern.hasMatch(msg.clean) || pattern.hasMatch(msg.skeleton);
    }
  }

  /// Index of the first match in the view, or null when there is no match.
  int? firstIndex(ProcessedMessage msg) {
    final RegExpMatch? m = pattern.firstMatch(view == MatchView.verb ? msg.verbText : msg.clean) ??
        (view == MatchView.both ? pattern.firstMatch(msg.skeleton) : null);
    return m?.start;
  }
}

/// A data-driven detection rule.
///
/// Rules describe *combinations*, not single keywords:
///  * [triggers] – any match fires the rule
///  * [requiresAny] – families that must also have fired, otherwise the rule is
///    reduced to [gatedFactor] of its weight (context-dependent evidence)
///  * [requiresContextPattern] – extra pattern that must also match (used to
///    demand e.g. a financial context word next to the trigger)
///  * [suppressIf] – patterns that cancel the rule entirely (legit helper text)
///
/// Adding a rule is a one-line data change; the engine never needs to change.
class DetectionRule {
  const DetectionRule({
    required this.id,
    required this.family,
    required this.category,
    required this.label,
    required this.weight,
    required this.triggers,
    this.requiresAny = const <String>{},
    this.requiresContext,
    this.suppressIf = const <RuleMatcher>[],
    this.gatedFactor = 0.3,
    this.source = SignalSource.rule,
    this.detail,
    this.requirePositiveInstruction = false,
  });

  final String id;

  /// Overlap family for the risk engine (same family == same evidence).
  final String family;
  final ScamCategory category;
  final String label;
  final int weight;
  final List<RuleMatcher> triggers;

  /// Family ids (or family prefixes) that make this rule "confirmed".
  final Set<String> requiresAny;

  /// An additional pattern that must match for the rule to be confirmed.
  final RuleMatcher? requiresContext;

  final List<RuleMatcher> suppressIf;
  final double gatedFactor;
  final SignalSource source;
  final String? detail;

  /// When true the rule only fires for a *non-negated* instruction, so
  /// "do not share the OTP" or "OTP share na karein" never counts as a request.
  final bool requirePositiveInstruction;

  bool isSuppressed(ProcessedMessage msg) =>
      suppressIf.any((RuleMatcher m) => m.matches(msg));
}

/// Runs the rule catalog over one processed message.
class RuleEngine {
  RuleEngine({required this.rules});

  final List<DetectionRule> rules;

  /// Evaluates all rules, returns every signal that fired.
  ///
  /// Two passes are used so [DetectionRule.requiresAny] can reference families
  /// produced by other rules regardless of catalog order.
  List<ShieldSignal> evaluate(ProcessedMessage msg) {
    final List<_Candidate> fired = <_Candidate>[];

    for (final DetectionRule rule in rules) {
      if (rule.isSuppressed(msg)) continue;
      final RuleMatcher? match = _firstMatch(rule, msg);
      if (match == null) continue;
      if (rule.requirePositiveInstruction && _isNegated(rule, msg)) continue;
      fired.add(_Candidate(rule, msg));
    }

    final Set<String> firedFamilies = <String>{
      for (final _Candidate c in fired) c.rule.family,
    };

    final List<ShieldSignal> signals = <ShieldSignal>[];
    for (final _Candidate c in fired) {
      final DetectionRule rule = c.rule;
      bool confirmed = true;
      if (rule.requiresAny.isNotEmpty) {
        confirmed = rule.requiresAny.any(
          (String f) => firedFamilies.any((String fired) => fired == f || fired.startsWith('$f:')),
        );
      }
      if (confirmed && rule.requiresContext != null) {
        confirmed = rule.requiresContext!.matches(msg);
      }
      final int weight = confirmed
          ? rule.weight
          : (rule.weight * rule.gatedFactor).round().clamp(1, rule.weight);

      signals.add(
        ShieldSignal(
          id: rule.id,
          family: rule.family,
          category: rule.category,
          weight: weight,
          label: confirmed ? rule.label : '${rule.label} (weak context)',
          source: rule.source,
          detail: rule.detail,
          matchedText: _evidence(rule, msg),
        ),
      );
    }
    return signals;
  }

  RuleMatcher? _firstMatch(DetectionRule rule, ProcessedMessage msg) {
    for (final RuleMatcher matcher in rule.triggers) {
      if (matcher.matches(msg)) return matcher;
    }
    return null;
  }

  /// True when every trigger match of [rule] sits inside a negation.
  bool _isNegated(DetectionRule rule, ProcessedMessage msg) {
    bool sawMatch = false;
    for (final RuleMatcher matcher in rule.triggers) {
      for (final String text in <String>[msg.clean, msg.skeleton]) {
        for (final RegExpMatch m in matcher.pattern.allMatches(text)) {
          sawMatch = true;
          if (!msg.isNegatedInstruction(m.start, m.end)) return false;
        }
      }
    }
    return sawMatch;
  }

  String? _evidence(DetectionRule rule, ProcessedMessage msg) {
    for (final RuleMatcher matcher in rule.triggers) {
      final Match? m = matcher.pattern.firstMatch(msg.clean) ??
          matcher.pattern.firstMatch(msg.skeleton);
      final String? value = m?.group(0);
      if (value != null && value.isNotEmpty) {
        return value.length > 60 ? '${value.substring(0, 60)}…' : value;
      }
    }
    return null;
  }
}

class _Candidate {
  _Candidate(this.rule, this.msg);

  final DetectionRule rule;
  final ProcessedMessage msg;
}

/// Helper used by rule definitions and by [ScamIntelligence] lookups.
ScamCategory categoryById(String id) => ScamCategory.byId(id);
