import 'package:callshield_app/message_shield/engine/preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalisation', () {
    test('folds case, zero-width characters and exotic spaces', () {
      final ProcessedMessage msg = preprocess('Your\u200b   OTP\u00a0IS 482913');
      expect(msg.clean, 'your otp is 482913');
    });

    test('folds Cyrillic homoglyphs (а/е/о) back to ASCII', () {
      final ProcessedMessage msg = preprocess('KYC update f\u043er y\u043eur acc\u043eunt');
      expect(msg.clean, contains('for your account'));
    });

    test('builds a leet-folded skeleton view', () {
      final ProcessedMessage msg = preprocess('Sh4re the 0TP n0w');
      expect(msg.clean, 'sh4re the 0tp n0w');
      expect(msg.skeleton, 'share the otp now');
    });

    test('tokenises digit runs as a single num token', () {
      final ProcessedMessage msg = preprocess('Rs 12,500 credited on 24/09/2026');
      expect(msg.tokens.contains('num'), isTrue);
      expect(msg.tokens.contains('credited'), isTrue);
    });

    test('neutralises payment-brand compounds so they are not read as a verb', () {
      final ProcessedMessage msg = preprocess('Your Google Pay wallet balance is Rs.2,499');
      expect(msg.verbText.contains('walletapp'), isTrue);
      expect(msg.verbText.contains('pay wallet'), isFalse);
    });
  });

  group('entity extraction', () {
    test('extracts urls, upi ids, phones and amounts', () {
      final ProcessedMessage msg = preprocess(
        'Pay Rs.4,999 to refund.help@ybl or call +91 98765 00011, link http://bit.ly/3xkYc2',
      );
      expect(msg.urls, contains('http://bit.ly/3xkYc2'));
      expect(msg.upiIds, contains('refund.help@ybl'));
      expect(msg.phones, isNotEmpty);
      expect(msg.hasMoneyMention, isTrue);
      expect(msg.flags, contains('url_shortener'));
    });

    test('detects mixed-script messages', () {
      final ProcessedMessage msg =
          preprocess('आपका OTP शेयर करें warna account band ho jayega');
      expect(msg.isMixedScript, isTrue);
      expect(msg.flags, contains('script_devanagari'));
    });
  });

  group('negation guard', () {
    test('recognises "do not share" style negations', () {
      final ProcessedMessage msg =
          preprocess('482913 is your OTP. Do not share this OTP with anyone.');
      final RegExpMatch match =
          RegExp('share').firstMatch(msg.clean)!;
      expect(msg.isNegatedInstruction(match.start, match.end), isTrue);
    });

    test('recognises Hindi negations written after the verb', () {
      final ProcessedMessage msg = preprocess('OTP kisi ke saath share na karein');
      final RegExpMatch match = RegExp('otp').firstMatch(msg.clean)!;
      expect(msg.isNegatedInstruction(match.start, match.end), isTrue);
    });

    test('does not treat a genuine request as negated', () {
      final ProcessedMessage msg = preprocess('Please share the OTP with me now');
      final RegExpMatch match = RegExp('share').firstMatch(msg.clean)!;
      expect(msg.isNegatedInstruction(match.start, match.end), isFalse);
    });
  });

  group('obfuscated abbreviation matcher', () {
    test('matches otp spelled with separators or leet', () {
      expect(spacedAbbrev('otp').hasMatch('send the o.t.p now'), isTrue);
      expect(spacedAbbrev('otp').hasMatch('send the o t p now'), isTrue);
      expect(spacedAbbrev('otp').hasMatch('cannot pay the bill'), isFalse);
    });
  });
}
