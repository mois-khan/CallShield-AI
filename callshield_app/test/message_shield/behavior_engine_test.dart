import 'package:callshield_app/message_shield/engine/behavior_engine.dart';
import 'package:callshield_app/message_shield/engine/preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> intentsOf(String text) =>
    BehaviorEngine().detect(preprocess(text)).map((BehaviorFinding f) => f.intent.id).toSet();

void main() {
  test('detects the OTP objective', () {
    expect(intentsOf('Share the OTP you just received to complete verification'),
        contains('share_otp'));
  });

  test('detects credential objectives', () {
    expect(intentsOf('Provide your net banking password and PIN to reactivate'),
        contains('share_pin_password'));
  });

  test('detects money and upfront-fee objectives', () {
    expect(intentsOf('Transfer Rs.4,999 to refund.help@ybl for the refund'),
        contains('send_money'));
    expect(intentsOf('Pay the processing fee of Rs.999 to release your loan'),
        contains('pay_fee'));
  });

  test('detects remote-access instruction', () {
    expect(intentsOf('Install AnyDesk so I can guide you and share your screen'),
        contains('share_screen_or_install'));
  });

  test('detects crypto demand', () {
    expect(intentsOf('Send the amount as USDT to this wallet address today'),
        contains('transfer_crypto'));
  });

  test('detects secrecy and staying-on-call instructions', () {
    final Set<String> intents = intentsOf(
      'Do not tell anyone in the family. Stay on the call until the transfer completes.',
    );
    expect(intents, contains('keep_secret'));
    expect(intents, contains('stay_on_call'));
  });

  test('detects approve-a-collect-request', () {
    expect(intentsOf('Approve the request in your UPI app twice to receive the refund'),
        contains('approve_payment_request'));
  });

  test('detects link and callback objectives', () {
    expect(
      intentsOf('Click this link http://bit.ly/3xkYc2 and verify your account'),
      contains('click_link'),
    );
    expect(
      intentsOf('Call our customer care on 9876500011 for help with your account'),
      contains('call_back'),
    );
  });

  group('precision guards', () {
    test('a negated share instruction produces no share intent', () {
      expect(
        intentsOf('Do not share the OTP with anyone, not even bank staff'),
        isNot(contains('share_otp')),
      );
    });

    test('an official helpline is not treated as a callback demand', () {
      expect(
        intentsOf('If this was not you, call our official helpline 1800123456'),
        isNot(contains('call_back')),
      );
    });

    test('a payment brand is not read as a payment instruction', () {
      expect(
        intentsOf('Your Google Pay wallet balance is Rs.2,499 as of today'),
        isNot(contains('send_money')),
      );
    });

    test('a personal message produces no behavioural intents at all', () {
      expect(intentsOf('Hey, are we still meeting at 7? Let me know.'), isEmpty);
    });
  });
}
