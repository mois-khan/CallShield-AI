import '../intelligence/scam_intelligence.dart';
import '../models/analysis_result.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';

/// Textual URL inspection.
///
/// PRIVACY / SAFETY CONTRACT: Message Shield never opens, resolves, fetches,
/// sandboxes or previews a URL. It only inspects the characters of the link
/// text already present in the message. There is no URL Shield and no sandbox.
class UrlAnalyzer {
  UrlAnalyzer(this.intelligence);

  final ScamIntelligence intelligence;

  static final RegExp _ipHost = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
  static final RegExp _brandLike = RegExp(
    r'(sbi|hdfc|icici|axis|kotak|pnb|paytm|phonepe|amazon|flipkart|netflix|jio|airtel|rbi|uidai|incometax|gst|gov|trai|customs|police|bank|kyc|refund|payment|wallet|upi)',
    caseSensitive: false,
  );
  static final RegExp _digits = RegExp(r'\d');
  static final RegExp _base64ish = RegExp(r'[A-Za-z0-9_\-]{28,}');

  List<UrlFinding> analyze(List<String> urls) {
    final List<UrlFinding> findings = <UrlFinding>[];
    for (final String url in urls.take(5)) {
      findings.add(_analyzeOne(url));
    }
    return findings;
  }

  UrlFinding _analyzeOne(String rawUrl) {
    final String url = rawUrl.trim();
    final Uri? uri = Uri.tryParse(url.contains('://') ? url : 'http://$url');
    final String host = (uri?.host ?? '').toLowerCase();
    final String path = (uri?.path ?? '').toLowerCase();
    final String query = (uri?.query ?? '').toLowerCase();
    final String full = url.toLowerCase();

    int suspicion = 0;
    final List<String> reasons = <String>[];

    if (host.isEmpty) {
      return UrlFinding(url: url, host: '', suspicion: 20, reasons: <String>['Unparseable link']);
    }

    if (intelligence.isKnownBenignDomain(host)) {
      return UrlFinding(
        url: url,
        host: host,
        suspicion: 2,
        reasons: <String>['Recognised official domain'],
      );
    }

    if (!full.startsWith('https://')) {
      suspicion += 10;
      reasons.add('No HTTPS');
    }
    if (_ipHost.hasMatch(host)) {
      suspicion += 28;
      reasons.add('Raw IP address instead of a domain');
    }
    if (host.contains('xn--')) {
      suspicion += 22;
      reasons.add('Punycode / lookalike characters in the domain');
    }
    final String tld = host.contains('.') ? host.split('.').last : '';
    if (intelligence.suspiciousTlds.contains(tld)) {
      suspicion += 18;
      reasons.add('Domain ends in .$tld, a commonly abused TLD');
    }
    final bool shortened = _isShortener(host);
    final bool chatShort = _isChatShortener(host);
    if (shortened) {
      suspicion += 20;
      reasons.add('Link shortener hides the real destination');
    }
    if (chatShort) {
      suspicion += 24;
      reasons.add('Invites you into a private chat (WhatsApp/Telegram)');
    }
    if (intelligence.freeHosts.any((String h) => host.contains(h))) {
      suspicion += 14;
      reasons.add('Hosted on free/throwaway hosting');
    }
    if (_wordCount(host, '-') >= 2) {
      suspicion += 8;
      reasons.add('Many hyphens in the domain');
    }
    if (host.split('.').length >= 4) {
      suspicion += 8;
      reasons.add('Deeply nested sub-domains');
    }
    if (_digits.allMatches(host).length >= 3) {
      suspicion += 10;
      reasons.add('Digits mixed into the domain name');
    }
    if (host.length > 30) {
      suspicion += 6;
      reasons.add('Unusually long domain');
    }
    if (full.contains('@')) {
      suspicion += 18;
      reasons.add('Credential-style "@" inside the link');
    }
    if (uri?.hasPort ?? false) {
      suspicion += 10;
      reasons.add('Non-standard port in the link');
    }

    // Brand abuse: brand name appears but not as the registrable domain.
    final List<String> labels = host.split('.');
    final String registrable = labels.length >= 2 ? '${labels[labels.length - 2]}.${labels.last}' : host;
    final String registrableSafe = _normalizeLookalike(registrable);
    final Match? brandMatch = _brandLike.firstMatch(host);
    if (brandMatch != null && !_looksLikeOfficial(registrableSafe, brandMatch.group(0)!)) {
      suspicion += 24;
      reasons.add('Uses the name "${brandMatch.group(0)}" but is not the official domain');
    }

    final int keywordHits = intelligence.urlPathKeywords
        .where((String k) => path.contains(k) || query.contains(k) || host.contains(k))
        .length;
    if (keywordHits >= 2) {
      suspicion += 14;
      reasons.add('Path contains credential/verification keywords');
    } else if (keywordHits == 1) {
      suspicion += 8;
      reasons.add('Path contains a bait keyword');
    }

    if (_base64ish.hasMatch(uri?.query ?? '')) {
      suspicion += 8;
      reasons.add('Long encoded parameter in the link');
    }

    // Very short paths on an otherwise unremarkable host: scam SMS links are
    // almost always bare short paths (bit.ly/3xkYc2, wa.me/9198…, /pay),
    // official deep links are not.
    final bool numericShortPath = RegExp(r'^/\d{6,}$').hasMatch(path);
    if (tld.isNotEmpty &&
        (path.length <= 1 ||
            path.startsWith('/pay') ||
            numericShortPath ||
            (shortened && path.length <= 12)) &&
        (suspicion >= 10 || host.length > 18 || numericShortPath)) {
      suspicion += 10;
      reasons.add('Link to a bare short path with no site context');
    }
    // URL-encoded tricks (redirects, escaped hosts) inside the path/query.
    final int specialChars =
        RegExp(r'[%:@=&?]').allMatches(path + query).length;
    if (specialChars >= 3) {
      suspicion += 6;
      reasons.add('Heavily encoded link text (possible redirect trick)');
    }

    if (reasons.isEmpty) {
      reasons.add('No obvious manipulation in the link text');
    }

    return UrlFinding(
      url: url,
      host: host,
      suspicion: suspicion.clamp(0, 100),
      reasons: reasons,
    );
  }

  bool _isShortener(String host) =>
      intelligence.urlShorteners.any((String s) => host == s || host.endsWith('.$s'));

  bool _isChatShortener(String host) =>
      intelligence.urlChatShorteners.any((String s) => host == s || host.endsWith('.$s'));

  bool _looksLikeOfficial(String registrable, String brand) {
    // "hdfcbank.com", "onlinesbi.sbi" etc. are treated as consistent brands.
    final String base = registrable.split('.').first;
    // Hyphenated compounds ("customs-clearance", "sbi-kyc-update") are the
    // classic lookalike pattern; official registrable domains never hyphenate.
    if (base.contains('-')) return false;
    return base.startsWith(brand) || base.endsWith(brand) || base.contains('${brand}bank') ||
        base.contains('${brand}pay') || base.contains('${brand}care');
  }

  String _normalizeLookalike(String host) {
    // 0->o, 1->l, 5->s, rn->m style lookalike folding for brand comparison.
    return host
        .replaceAll('0', 'o')
        .replaceAll('1', 'l')
        .replaceAll('5', 's')
        .replaceAll('rn', 'm');
  }

  int _wordCount(String value, String separator) =>
      separator.allMatches(value).length;

  /// Turns URL findings into risk signals (strongest one dominates the family).
  List<ShieldSignal> signals(List<UrlFinding> findings) {
    final List<ShieldSignal> signals = <ShieldSignal>[];
    final List<UrlFinding> suspicious = findings
        .where((UrlFinding f) => f.suspicion >= 40)
        .toList()
      ..sort((UrlFinding a, UrlFinding b) => b.suspicion.compareTo(a.suspicion));
    for (final UrlFinding finding in suspicious) {
      signals.add(
        ShieldSignal(
          id: 'suspicious_url:${finding.host}',
          family: 'suspicious_url',
          category: ScamCategory.phishing,
          weight: (finding.suspicion * 0.6).round().clamp(10, 56),
          label: 'Link looks suspicious (${finding.suspicion}/100)',
          source: SignalSource.url,
          detail: finding.reasons.take(3).join('; '),
          matchedText: finding.url.length > 60 ? '${finding.url.substring(0, 60)}…' : finding.url,
        ),
      );
    }
    return signals;
  }
}
