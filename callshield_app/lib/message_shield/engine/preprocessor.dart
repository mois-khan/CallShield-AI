import '../utils/text_tables.dart';

/// Preprocessor: turns one raw message into the canonical views used by every
/// later stage of the pipeline.
///
/// Layered contract:
///   * `clean`    – lowercase, confusables folded, whitespace collapsed
///   * `skeleton` – `clean` with leetspeak folded (obfuscation tolerant)
///   * `tokens`   – token stream with digit runs collapsed to `num`
///   * entities   – URLs, emails, UPI ids, phone numbers, digit runs
///
/// All of this runs on-device in microseconds. The text is treated purely as
/// data: nothing here executes, resolves or opens anything.
class ProcessedMessage {
  ProcessedMessage({
    required this.raw,
    required this.clean,
    required this.skeleton,
    required this.verbText,
    required this.tokens,
    required this.flags,
    required this.urls,
    required this.emails,
    required this.upiIds,
    required this.phones,
    required this.digitRuns,
    required this.letterCount,
    required this.upperCount,
    required this.exclamationCount,
    required this.questionCount,
  });

  final String raw;
  final String clean;
  final String skeleton;

  /// `clean` with payment-brand compounds neutralised ("google pay" -> "gpay"),
  /// so verb patterns do not read a brand name as a payment instruction.
  final String verbText;
  final List<String> tokens;
  final Set<String> flags;
  final List<String> urls;
  final List<String> emails;
  final List<String> upiIds;
  final List<String> phones;
  final List<String> digitRuns;
  final int letterCount;
  final int upperCount;
  final int exclamationCount;
  final int questionCount;

  bool get hasUrl => urls.isNotEmpty;
  bool get hasUpi => upiIds.isNotEmpty;
  bool get hasPhone => phones.isNotEmpty;
  bool get hasMoneyMention => flags.contains('has_money');
  bool get isCapsHeavy => flags.contains('caps_heavy');
  bool get isMixedScript => flags.contains('mixed_script');

  int get lengthChars => clean.length;

  int get wordCount => tokens.length;

  /// True when any of [patterns] matches the normalised text.
  bool matchesAny(Iterable<RegExp> patterns) =>
      patterns.any((RegExp p) => p.hasMatch(clean));

  /// True when any of [patterns] matches the leetspeak-folded text.
  bool matchesAnySkeleton(Iterable<RegExp> patterns) =>
      patterns.any((RegExp p) => p.hasMatch(skeleton) || p.hasMatch(clean));

  /// True when the instruction at [start]/[end] is negated, e.g.
  /// "do not share the OTP" or "OTP kisi ke saath share na karein".
  bool isNegatedInstruction(int start, int end) {
    final int from = (start - 30).clamp(0, clean.length);
    final int to = (end + 34).clamp(0, clean.length);
    final String before = clean.substring(from, start.clamp(0, clean.length));
    final String after = clean.substring(end.clamp(0, clean.length), to);
    return _negationBefore.hasMatch(before) || _negationAfter.hasMatch(after);
  }

  /// First match of [pattern] in the normalised text (used as evidence text).
  String? firstMatch(RegExp pattern) {
    final Match? m = pattern.firstMatch(clean);
    if (m == null) return null;
    final String value = m.group(0) ?? '';
    return value.length > 60 ? '${value.substring(0, 60)}…' : value;
  }
}

/// Builds a regex that tolerates obfuscation of short abbreviations:
/// `otp` also matches `o.t.p`, `o-t-p`, `o t p`, `0tp`, `O T P`.
RegExp spacedAbbrev(String letters, {bool wordBoundary = true}) {
  final String body = letters
      .split('')
      // Hyphen kept last inside the class so it stays a literal character.
      .map((String ch) => '${RegExp.escape(ch)}[\\s._*~`-]{0,3}')
      .join();
  return RegExp('${wordBoundary ? '\\b' : ''}$body${wordBoundary ? '\\b' : ''}');
}

final RegExp _wsRe = RegExp(r'\s+');

/// Brand compounds whose names contain a payment verb.
final RegExp _brandVerbs = RegExp(
  r'\b(google|g|amazon|apple|samsung|jio|airtel) ?pay\b',
  caseSensitive: false,
);

/// Replaces payment-brand compounds with a neutral token so that "Google Pay
/// wallet balance" is not mistaken for an instruction to pay.
String neutralizeBrandVerbs(String clean) =>
    clean.replaceAll(_brandVerbs, 'walletapp');

final RegExp _negationBefore = RegExp(
  r"(?:do not|don't|dont|never|not|no need to|without|avoid|mat|na|nahi)\s*(?:ever\s*)?$",
  caseSensitive: false,
);
final RegExp _negationAfter = RegExp(
  r'^[^.!?]{0,24}\b(?:na karein|na karo|na kijiye|mat karo|mat kijiye|share mat|na dena|never|not to share|with anyone|to anyone)\b',
  caseSensitive: false,
);
final RegExp _urlRe = RegExp(r'(?:https?://|www\.)[^\s]+', caseSensitive: false);
final RegExp _emailRe = RegExp(r'[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}');
final RegExp _upiRe = RegExp(
  r'\b[a-z0-9.\-_]{2,}@(?:okaxis|oksbi|okhdfcbank|okicici|ybl|paytm|apl|upi|ibl|axl|axisb)',
);
final RegExp _phoneRe = RegExp(r'(?:\+\d[\d\-\s]{7,}\d)|(?:\b[6-9]\d{9}\b)');
final RegExp _moneyRe = RegExp(r'(?:rs\.?|inr|₹|\$|usd|eur|pounds?)\s?[0-9]');
final RegExp _offerRe = RegExp(r'(?:[0-9]{1,3}\s?%\s?(?:off|discount|cashback|reward)|up\s?to\s?[0-9])');
final RegExp _digitRunRe = RegExp(r'[0-9]+');
final RegExp _tokenRe = RegExp(
  r'[a-z]+'
  r'|[0-9]+'
  r'|[\u0900-\u097f]+'
  r'|[\u0980-\u09ff]+'
  r'|[\u0a00-\u0a7f]+'
  r'|[\u0b80-\u0bff]+'
  r'|[\u0c00-\u0c7f]+'
  r'|[\u0600-\u06ff]+'
  r'|[\u0e00-\u0e7f]+',
);

final Map<int, String> _homoglyphsByCode = _byCode(kHomoglyphMap);
final Map<int, String> _diacriticsByCode = _byCode(kDiacriticMap);
final Map<int, String> _leetByCode = _byCode(kLeetMap);
final Set<int> _zeroWidth = kZeroWidthChars.runes.toSet();
final Set<int> _spaceLike = kSpaceLikeChars.runes.toSet();

Map<int, String> _byCode(Map<String, String> source) => <int, String>{
      for (final MapEntry<String, String> e in source.entries) e.key.runes.first: e.value,
    };

/// Drops invisible characters and folds exotic spaces (Unicode aware).
String stripInvisibles(String text) {
  final StringBuffer out = StringBuffer();
  for (final int cp in text.runes) {
    if (_zeroWidth.contains(cp)) continue;
    out.write(_spaceLike.contains(cp) ? ' ' : String.fromCharCode(cp));
  }
  return out.toString();
}

/// Lowercases and folds confusable / accented characters to ASCII.
String foldGlyphs(String text) {
  final StringBuffer out = StringBuffer();
  for (final int cp in text.runes) {
    final String low = cp == 0x0130 ? 'i' : String.fromCharCode(cp).toLowerCase();
    final String? folded = _homoglyphsByCode[cp] ?? _diacriticsByCode[cp];
    out.write(folded ?? low);
  }
  return out.toString();
}

/// Canonical normalised view.
String normalizeText(String text) {
  if (text.isEmpty) return '';
  return foldGlyphs(stripInvisibles(text)).replaceAll(_wsRe, ' ').trim();
}

/// Normalised view with leetspeak folded (used for obfuscation-tolerant rules).
String skeletonize(String text) {
  final String clean = normalizeText(text);
  final StringBuffer out = StringBuffer();
  for (final int cp in clean.runes) {
    out.write(_leetByCode[cp] ?? String.fromCharCode(cp));
  }
  return out.toString();
}

/// Tokens with digit runs collapsed to `num` (mirrors features.py tokenize()).
List<String> tokenize(String clean) {
  final List<String> out = <String>[];
  for (final RegExpMatch m in _tokenRe.allMatches(clean)) {
    final String token = m.group(0)!;
    final int first = token.codeUnitAt(0);
    out.add(first >= 0x30 && first <= 0x39 ? 'num' : token);
  }
  return out;
}

ProcessedMessage preprocess(String raw) {
  final String clean = normalizeText(raw);
  final String skeleton = skeletonize(raw);
  final List<String> tokens = tokenize(clean);

  // URLs keep their original casing: Message Shield must display and store
  // links exactly as they arrived (the URL analyzer lowercases internally).
  final String rawCollapsed = raw.replaceAll(_wsRe, ' ');
  final List<String> urls = _urlRe
      .allMatches(rawCollapsed)
      .map((RegExpMatch m) => m.group(0)!)
      .toList(growable: false);
  final List<String> emails = _emailRe
      .allMatches(clean)
      .map((RegExpMatch m) => m.group(0)!)
      .where((String e) => !_upiRe.hasMatch(e))
      .toList(growable: false);
  final List<String> upiIds = _upiRe
      .allMatches(clean)
      .map((RegExpMatch m) => m.group(0)!)
      .toList(growable: false);
  final List<String> phones = _phoneRe
      .allMatches(clean)
      .map((RegExpMatch m) => m.group(0)!.trim())
      .where((String p) => p.replaceAll(RegExp(r'[^0-9]'), '').length >= 8)
      .toList(growable: false);
  final List<String> digitRuns = _digitRunRe
      .allMatches(clean)
      .map((RegExpMatch m) => m.group(0)!)
      .where((String d) => d.length >= 3)
      .toList(growable: false);

  int letters = 0;
  int upper = 0;
  for (final int cp in raw.runes) {
    final String ch = String.fromCharCode(cp);
    if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
      letters++;
      if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) upper++;
    }
  }

  return ProcessedMessage(
    raw: raw,
    clean: clean,
    skeleton: skeleton,
    verbText: neutralizeBrandVerbs(clean),
    tokens: tokens,
    flags: messageFlags(raw: raw, clean: clean, digitRuns: digitRuns),
    urls: urls,
    emails: emails,
    upiIds: upiIds,
    phones: phones,
    digitRuns: digitRuns,
    letterCount: letters,
    upperCount: upper,
    exclamationCount: '!'.allMatches(clean).length,
    questionCount: '?'.allMatches(clean).length,
  );
}

/// Message level flags — must stay in sync with `message_flags()` in features.py.
Set<String> messageFlags({
  required String raw,
  required String clean,
  required List<String> digitRuns,
}) {
  final Set<String> flags = <String>{};
  if (clean.length >= 160) flags.add('long');
  if (_urlRe.hasMatch(clean)) flags.add('has_url');
  if (_shortenerHints.any(clean.contains)) flags.add('url_shortener');
  if (_phoneRe.hasMatch(clean)) flags.add('has_phone');
  if (_emailRe.hasMatch(clean)) flags.add('has_email');
  if (_upiRe.hasMatch(clean)) flags.add('has_upi');
  if (_moneyRe.hasMatch(clean)) flags.add('has_money');
  if (_offerRe.hasMatch(clean)) flags.add('has_offer_pct');

  bool hasDevanagari = false;
  bool hasOtherScript = false;
  bool hasAsciiAlpha = false;
  for (final int cp in clean.runes) {
    if (cp >= 0x0900 && cp <= 0x097f) {
      hasDevanagari = true;
    } else if ((cp >= 0x0980 && cp <= 0x0c7f) ||
        (cp >= 0x0600 && cp <= 0x06ff) ||
        (cp >= 0x0e00 && cp <= 0x0e7f)) {
      hasOtherScript = true;
    } else if (cp >= 0x61 && cp <= 0x7a) {
      hasAsciiAlpha = true;
    }
  }
  if (hasDevanagari) flags.add('script_devanagari');
  if (hasOtherScript) flags.add('script_other');
  if ((hasDevanagari || hasOtherScript) && hasAsciiAlpha) flags.add('mixed_script');

  int digitRunTokens = 0;
  for (final RegExpMatch m in _tokenRe.allMatches(clean)) {
    final int first = m.group(0)!.codeUnitAt(0);
    if (first >= 0x30 && first <= 0x39) digitRunTokens++;
  }
  if (digitRunTokens >= 2) flags.add('num_runs2');

  int letters = 0;
  int upper = 0;
  for (final int cp in raw.runes) {
    if (cp >= 0x41 && cp <= 0x5a) {
      letters++;
      upper++;
    } else if (cp >= 0x61 && cp <= 0x7a) {
      letters++;
    }
  }
  if (letters >= 6 && upper / (letters == 0 ? 1 : letters) > 0.4) {
    flags.add('caps_heavy');
  }
  if ('!'.allMatches(raw).length >= 2) flags.add('exclam2');
  if ('?'.allMatches(raw).length >= 2) flags.add('question2');
  return flags;
}

const List<String> _shortenerHints = <String>[
  'bit.ly', 'tinyurl', 'goo.gl', 't.co', 'ow.ly', 'is.gd', 'buff.ly',
  'cutt.ly', 'rb.gy', 'rebrand.ly', 'shorturl', 'tiny.cc', 'surl.li',
];
