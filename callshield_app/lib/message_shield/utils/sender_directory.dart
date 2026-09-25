/// Local directory of commonly seen transactional SMS sender ids.
///
/// Android gives Message Shield the raw sender id (for example `VM-SBIINB`).
/// That is technically correct but hard to read, so this table maps *known*
/// sender-id tokens to the organisation they belong to. It is a display
/// convenience only:
///
///  * it never changes the risk analysis,
///  * it never invents a source for an unknown sender,
///  * the raw sender id is always shown next to the friendly name in the UI.
///
/// A sender id matching this table is NOT a proof that the message is genuine -
/// anyone can spoof an alphanumeric sender id, which is exactly why the raw id
/// stays visible.
class SenderDirectory {
  SenderDirectory._();

  /// `normalised sender token -> organisation`
  static const Map<String, String> organisations = <String, String>{
    // Banks
    'SBIINB': 'State Bank of India',
    'SBIPSG': 'State Bank of India',
    'ATMSBI': 'State Bank of India',
    'HDFCBK': 'HDFC Bank',
    'HDFCBN': 'HDFC Bank',
    'ICICIB': 'ICICI Bank',
    'ICICIN': 'ICICI Bank',
    'AXISBK': 'Axis Bank',
    'KOTAKB': 'Kotak Mahindra Bank',
    'PNBBNK': 'Punjab National Bank',
    'BOBBNK': 'Bank of Baroda',
    'IDFCFB': 'IDFC FIRST Bank',
    'YESBNK': 'YES Bank',
    'INDBNK': 'IndusInd Bank',
    'CANBNK': 'Canara Bank',
    'UNIONB': 'Union Bank of India',
    'CENTBK': 'Central Bank of India',
    'IOBANK': 'Indian Overseas Bank',
    'FEDERL': 'Federal Bank',
    'AUBANK': 'AU Small Finance Bank',
    // Payments and wallets
    'PAYTM': 'Paytm',
    'PYTMBK': 'Paytm Payments Bank',
    'PHONEPE': 'PhonePe',
    'GPAY': 'Google Pay',
    'AMON': 'Amazon Pay',
    // Cards, brokers, insurers
    'ZERODH': 'Zerodha',
    'GROWW': 'Groww',
    'UPSTOX': 'Upstox',
    'ANGELB': 'Angel One',
    'NSDL': 'NSDL',
    'CDSL': 'CDSL',
    'LICIND': 'Life Insurance Corporation of India',
    'HDFCLI': 'HDFC Life',
    'ICICIP': 'ICICI Prudential',
    'MAXLIF': 'Max Life Insurance',
    'SBILIF': 'SBI Life Insurance',
    // Government / utilities
    'UIDAI': 'UIDAI (Aadhaar)',
    'DGTLKR': 'DigiLocker',
    'INCOMETAX': 'Income Tax Department',
    'GSTN': 'GST Network',
    'EPFO': 'EPFO',
    'IRCTC': 'IRCTC',
    'RAILWY': 'Indian Railways',
    'PASSPT': 'Passport Seva',
    'VAHAN': 'VAHAN (Transport Department)',
    'BESCOM': 'BESCOM',
    'MSEB': 'Maharashtra State Electricity Board',
    'BSES': 'BSES Rajdhani Power',
    'KSEBL': 'Kerala State Electricity Board',
    // Telecom
    'JIO': 'Reliance Jio',
    'JIOINF': 'Reliance Jio',
    'AIRTEL': 'Airtel',
    'AIRTELX': 'Airtel',
    'VODAFN': 'Vi (Vodafone Idea)',
    'BSNL': 'BSNL',
    // Commerce, delivery, mobility, OTT
    'AMZNIN': 'Amazon India',
    'AMAZON': 'Amazon',
    'FLIPKT': 'Flipkart',
    'MYNTRA': 'Myntra',
    'AJIO': 'AJIO',
    'MEESHO': 'Meesho',
    'SWIGGY': 'Swiggy',
    'ZOMATO': 'Zomato',
    'BIGBSK': 'BigBasket',
    'BLINKT': 'Blinkit',
    'ZEPTO': 'Zepto',
    'DOMINO': 'Domino\'s Pizza',
    'DELHIV': 'Delhivery',
    'DTDC': 'DTDC',
    'BLUDRT': 'Blue Dart',
    'FEDEX': 'FedEx',
    'EKART': 'Ekart',
    'XPRESSB': 'XpressBees',
    'INDIGO': 'IndiGo',
    'AIRIND': 'Air India',
    'IRCTCF': 'IRCTC',
    'OLACAB': 'Ola',
    'UBERIN': 'Uber',
    'NETFLX': 'Netflix',
    'SPOTIF': 'Spotify',
    'HOTSTR': 'Hotstar',
    'GOOGLE': 'Google',
    'MSFT': 'Microsoft',
    'APPLE': 'Apple',
    'META': 'Meta',
    'WHTAPP': 'WhatsApp',
    'TELEGM': 'Telegram',
    'INSTAG': 'Instagram',
    'FACEBK': 'Facebook',
    'TWITTR': 'X (Twitter)',
    'LINKDN': 'LinkedIn',
  };

  /// Organisation for a sender id, or null when we simply do not know it.
  static String? organisationFor(String? sender) {
    final String token = normalise(sender);
    if (token.isEmpty) return null;

    final String? exact = organisations[token];
    if (exact != null) return exact;

    // Carriers/inboxes sometimes add or keep a two-letter operator prefix
    // ("VMSBIINB", "AXHDFCBK"): try again without it.
    if (token.length > 2) {
      final String? stripped = organisations[token.substring(2)];
      if (stripped != null) return stripped;
    }

    // Ids are occasionally suffixed ("SBIINB-S", "SBIINB.T").
    for (final MapEntry<String, String> entry in organisations.entries) {
      if (token.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  /// Uppercase, alphanumeric-only form used for lookups.
  static String normalise(String? sender) {
    if (sender == null) return '';
    return sender.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// True when the sender looks like a phone number rather than a sender id.
  static bool looksLikeNumber(String? sender) {
    if (sender == null) return false;
    final String s = sender.replaceAll(RegExp(r'[\s\-()]'), '');
    return RegExp(r'^\+?\d{6,15}$').hasMatch(s);
  }
}
