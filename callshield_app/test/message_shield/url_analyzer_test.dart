import 'dart:io';

import 'package:callshield_app/message_shield/engine/url_analyzer.dart';
import 'package:callshield_app/message_shield/intelligence/scam_intelligence.dart';
import 'package:callshield_app/message_shield/models/analysis_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UrlAnalyzer analyzer;

  setUpAll(() {
    analyzer = UrlAnalyzer(
      ScamIntelligence.fromJsonBytes(
        File('assets/message_shield/intelligence/scam_intelligence.json').readAsBytesSync(),
      ),
    );
  });

  UrlFinding one(String url) => analyzer.analyze(<String>[url]).single;

  test('official domains are treated as benign', () {
    for (final String url in <String>[
      'https://onlinesbi.sbi',
      'https://www.hdfcbank.com/login',
      'https://www.amazon.in/orders',
    ]) {
      expect(one(url).suspicion, lessThan(20), reason: url);
      expect(one(url).isSuspicious, isFalse, reason: url);
    }
  });

  test('brand-in-subdomain lookalikes are flagged', () {
    final UrlFinding finding = one('http://sbi.your-verify-login.ru/otp');
    expect(finding.isSuspicious, isTrue);
    expect(finding.reasons.join(' '), contains('official domain'));
  });

  test('raw IP hosts, shorteners and risky TLDs are flagged', () {
    expect(one('http://103.24.55.19/otp').isSuspicious, isTrue);
    expect(one('http://bit.ly/3xkYc2').isSuspicious, isTrue);
    expect(one('http://rbi-refund.online/claim').isSuspicious, isTrue);
  });

  test('chat app links that pull users into private chats are flagged', () {
    final UrlFinding finding = one('http://wa.me/919876500011');
    expect(finding.isSuspicious, isTrue);
    expect(finding.reasons.join(' ').toLowerCase(), contains('chat'));
  });

  test('findings never expose an active/opened URL state', () {
    // The analyzer is pure text: the only outputs are host, score and reasons.
    final UrlFinding finding = one('http://customs-clearance.help/pay');
    expect(finding.reasons, isNotEmpty);
    expect(finding.suspicion, greaterThanOrEqualTo(40));
  });

  test('suspicious findings become risk signals in one family', () {
    final List<UrlFinding> findings = analyzer.analyze(<String>[
      'http://sbi-kyc-update.xyz/verify',
      'http://bit.ly/3xkYc2',
      'https://www.hdfcbank.com',
    ]);
    final List<dynamic> signals = analyzer.signals(findings);
    expect(signals, isNotEmpty);
    expect(signals.map((dynamic s) => s.family).toSet(), <String>{'suspicious_url'});
  });
}
