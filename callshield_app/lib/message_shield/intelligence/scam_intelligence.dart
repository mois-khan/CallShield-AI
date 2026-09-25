import 'dart:convert';

/// One known scam technique / campaign fingerprint.
class ScamFingerprint {
  ScamFingerprint({
    required this.id,
    required this.categoryId,
    required this.weight,
    required this.label,
    required this.phrases,
  }) : patterns = phrases
            .map((String p) => RegExp(RegExp.escape(p), caseSensitive: false))
            .toList(growable: false);

  final String id;
  final String categoryId;
  final int weight;
  final String label;
  final List<String> phrases;
  final List<RegExp> patterns;
}

class SenderPattern {
  SenderPattern({
    required this.id,
    required this.label,
    required this.weight,
    required String regex,
  }) : pattern = RegExp(regex, caseSensitive: false);

  final String id;
  final String label;
  final int weight;
  final RegExp pattern;
}

/// Locally loaded scam intelligence (no network, no cloud calls).
///
/// Everything is data driven: new fingerprints, brands, URL tables or category
/// objectives can be added to the JSON asset without touching engine code.
class ScamIntelligence {
  ScamIntelligence({
    required this.version,
    required this.categoryObjectives,
    required this.categoryActions,
    required this.authorities,
    required this.fingerprints,
    required this.legitContextPatterns,
    required this.legitMarkerPatterns,
    required this.senderPatterns,
    required this.urlShorteners,
    required this.urlChatShorteners,
    required this.suspiciousTlds,
    required this.freeHosts,
    required this.urlPathKeywords,
    required this.benignDomains,
    required this.upiHandleSuffixes,
  });

  final String version;

  /// categoryId -> plain language objectives
  final Map<String, List<String>> categoryObjectives;
  final Map<String, List<String>> categoryActions;

  /// authority kind (bank, government, police, telecom, courier, wallet, brands, support)
  final Map<String, List<String>> authorities;

  final List<ScamFingerprint> fingerprints;

  /// Phrases that indicate a *legitimate* message ("do not share this OTP").
  final List<RegExp> legitContextPatterns;
  final List<RegExp> legitMarkerPatterns;
  final List<SenderPattern> senderPatterns;

  final Set<String> urlShorteners;
  final Set<String> urlChatShorteners;
  final Set<String> suspiciousTlds;
  final Set<String> freeHosts;
  final Set<String> urlPathKeywords;
  final Set<String> benignDomains;
  final Set<String> upiHandleSuffixes;

  /// Authority kinds mentioned in [text] (used for impersonation detection).
  Set<String> authorityKindsIn(String text) {
    final Set<String> kinds = <String>{};
    for (final MapEntry<String, List<String>> entry in authorities.entries) {
      for (final String value in entry.value) {
        if (value.trim().isEmpty) continue;
        if (text.contains(value.trim())) {
          kinds.add(entry.key);
          break;
        }
      }
    }
    return kinds;
  }

  /// Sender ids that belong to a known-good service (local allowlist only).
  bool isKnownBenignDomain(String host) {
    final String h = host.toLowerCase();
    for (final String domain in benignDomains) {
      if (h == domain || h.endsWith('.$domain')) return true;
    }
    return false;
  }

  List<String> objectivesFor(String categoryId) => categoryObjectives[categoryId] ?? const <String>[];

  List<String> actionsFor(String categoryId) => categoryActions[categoryId] ?? const <String>[];

  bool matchesLegitContext(String clean) =>
      legitContextPatterns.any((RegExp p) => p.hasMatch(clean));

  bool matchesLegitMarker(String clean) =>
      legitMarkerPatterns.any((RegExp p) => p.hasMatch(clean));

  /// Fingerprint hits for a normalised message.
  List<ScamFingerprint> hits(String clean) {
    final List<ScamFingerprint> out = <ScamFingerprint>[];
    for (final ScamFingerprint fp in fingerprints) {
      for (final RegExp pattern in fp.patterns) {
        if (pattern.hasMatch(clean)) {
          out.add(fp);
          break;
        }
      }
    }
    return out;
  }

  /// Bumped whenever the shipped asset changes.
  String get label => 'scam-intel-v$version';

  static ScamIntelligence fromJsonBytes(List<int> bytes) =>
      ScamIntelligence.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

  factory ScamIntelligence.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) =>
        (value as List<dynamic>? ?? <dynamic>[]).map((dynamic e) => e.toString()).toList();

    final Map<String, dynamic> categories =
        Map<String, dynamic>.from(json['categories'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{});
    final Map<String, List<String>> objectives = <String, List<String>>{};
    final Map<String, List<String>> actions = <String, List<String>>{};
    categories.forEach((String key, dynamic value) {
      final Map<String, dynamic> entry = Map<String, dynamic>.from(value as Map);
      objectives[key] = strings(entry['objectives']);
      actions[key] = strings(entry['actions']);
    });

    final Map<String, dynamic> rawAuthorities =
        Map<String, dynamic>.from(json['authorities'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{});
    final Map<String, List<String>> authorities = <String, List<String>>{};
    rawAuthorities.forEach((String key, dynamic value) {
      authorities[key] = strings(value).map((String s) => s.toLowerCase()).toList();
    });

    final List<ScamFingerprint> fingerprints = (json['fingerprints'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic e) {
      final Map<String, dynamic> fp = Map<String, dynamic>.from(e as Map);
      return ScamFingerprint(
        id: fp['id'] as String? ?? 'fp_unknown',
        categoryId: fp['category'] as String? ?? 'suspicious',
        weight: (fp['weight'] as num?)?.toInt() ?? 10,
        label: fp['label'] as String? ?? 'Known scam pattern',
        phrases: strings(fp['phrases']),
      );
    }).toList(growable: false);

    final Map<String, dynamic> url =
        Map<String, dynamic>.from(json['url'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{});

    List<RegExp> compile(List<String> phrases) => phrases
        .where((String p) => p.trim().isNotEmpty)
        .map((String p) => RegExp(RegExp.escape(p), caseSensitive: false))
        .toList(growable: false);

    return ScamIntelligence(
      version: json['version'] as String? ?? '1.0.0',
      categoryObjectives: objectives,
      categoryActions: actions,
      authorities: authorities,
      fingerprints: fingerprints,
      legitContextPatterns: compile(strings(json['legit_context_phrases'])),
      legitMarkerPatterns: compile(strings(json['legit_marker_phrases'])),
      senderPatterns: (json['scam_sender_patterns'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) {
        final Map<String, dynamic> s = Map<String, dynamic>.from(e as Map);
        return SenderPattern(
          id: s['id'] as String? ?? 'sender_unknown',
          label: s['label'] as String? ?? 'Sender signal',
          weight: (s['weight'] as num?)?.toInt() ?? 4,
          regex: s['regex'] as String? ?? r'^$',
        );
      }).toList(growable: false),
      urlShorteners: strings(url['shorteners']).map((String s) => s.toLowerCase()).toSet(),
      urlChatShorteners: strings(url['chat_shorteners']).map((String s) => s.toLowerCase()).toSet(),
      suspiciousTlds: strings(url['suspicious_tlds']).map((String s) => s.toLowerCase()).toSet(),
      freeHosts: strings(url['free_hosts']).map((String s) => s.toLowerCase()).toSet(),
      urlPathKeywords: strings(url['path_keywords']).map((String s) => s.toLowerCase()).toSet(),
      benignDomains: strings(url['benign_domains']).map((String s) => s.toLowerCase()).toSet(),
      upiHandleSuffixes: strings(json['upi_handle_suffixes']).map((String s) => s.toLowerCase()).toSet(),
    );
  }
}
