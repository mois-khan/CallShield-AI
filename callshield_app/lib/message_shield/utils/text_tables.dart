/// Character tables shared by the preprocessor and the ML feature extractor.
///
/// These MUST stay byte-for-byte equivalent to `tool/message_shield/features.py`
/// (the reference implementation used to train the shipped model). The parity
/// test `test/message_shield/ml_hashing_parity_test.dart` guards this.
library;

/// Zero width, bidi control, soft hyphen and variation selectors.
const String kZeroWidthChars =
    '\u200b\u200c\u200d\u200e\u200f\u202a\u202b\u202c\u202d\u202e\ufeff\u00ad\ufe0e\ufe0f';

/// Unicode space separators folded to a plain space.
const String kSpaceLikeChars =
    '\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000';

/// Confusable characters (Cyrillic / Greek / fullwidth) -> ASCII.
const Map<String, String> kHomoglyphMap = <String, String>{
  '\u0430': 'a', '\u0435': 'e', '\u043e': 'o', '\u0440': 'p', '\u0441': 'c',
  '\u0445': 'x', '\u0443': 'y', '\u043a': 'k', '\u043c': 'm', '\u0442': 't',
  '\u0432': 'b', '\u043d': 'h', '\u0456': 'i', '\u0455': 's', '\u0458': 'j',
  '\u04bb': 'h', '\u0501': 'd', '\u051b': 'q', '\u051d': 'w',
  '\u03b1': 'a', '\u03b2': 'b', '\u03b5': 'e', '\u03b7': 'n', '\u03b9': 'i',
  '\u03ba': 'k', '\u03bc': 'u', '\u03bd': 'v', '\u03bf': 'o', '\u03c1': 'p',
  '\u03c3': 'o', '\u03c4': 't', '\u03c5': 'u', '\u03c7': 'x',
  '\uff41': 'a', '\uff45': 'e', '\uff4f': 'o', '\uff50': 'p', '\uff43': 'c',
  '\uff44': 'd', '\uff46': 'f', '\uff47': 'g', '\uff48': 'h', '\uff49': 'i',
  '\uff4a': 'j', '\uff4b': 'k', '\uff4c': 'l', '\uff4d': 'm', '\uff4e': 'n',
};

/// Latin letters with diacritics -> base letter.
const Map<String, String> kDiacriticMap = <String, String>{
  '\u00e0': 'a', '\u00e1': 'a', '\u00e2': 'a', '\u00e3': 'a', '\u00e4': 'a', '\u00e5': 'a',
  '\u00e7': 'c', '\u00e8': 'e', '\u00e9': 'e', '\u00ea': 'e', '\u00eb': 'e',
  '\u00ec': 'i', '\u00ed': 'i', '\u00ee': 'i', '\u00ef': 'i',
  '\u00f1': 'n', '\u00f2': 'o', '\u00f3': 'o', '\u00f4': 'o', '\u00f5': 'o', '\u00f6': 'o',
  '\u00f9': 'u', '\u00fa': 'u', '\u00fb': 'u', '\u00fc': 'u', '\u00fd': 'y', '\u00ff': 'y',
  '\u015b': 's', '\u017a': 'z', '\u017c': 'z', '\u0107': 'c', '\u010d': 'c', '\u0161': 's',
};

/// Leetspeak fold used only for the skeleton view.
const Map<String, String> kLeetMap = <String, String>{
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b',
  '\$': 's', '@': 'a', '|': 'l', '+': 't', '\u00a7': 's',
};

/// FNV-1a 32-bit offset basis / prime (shared with the Python reference).
const int kFnvOffset = 0x811C9DC5;
const int kFnvPrime = 0x01000193;

/// Feature space version. Bump together with features.py when features change.
const String kMessageShieldFeatureVersion = 'fm-2';
