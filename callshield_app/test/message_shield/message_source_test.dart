import 'package:callshield_app/message_shield/database/message_shield_store.dart';
import 'package:callshield_app/message_shield/engine/message_shield_engine.dart';
import 'package:callshield_app/message_shield/models/analysis_result.dart';
import 'package:callshield_app/message_shield/models/message_input.dart';
import 'package:callshield_app/message_shield/models/message_origin.dart';
import 'package:callshield_app/message_shield/models/scam_category.dart';
import 'package:callshield_app/message_shield/services/message_shield_service.dart';
import 'package:callshield_app/message_shield/utils/message_source.dart';
import 'package:callshield_app/message_shield/utils/sender_directory.dart';
import 'package:callshield_app/message_shield/utils/time_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The shipped model + intelligence assets, exactly what the device runs.
  late MessageShieldEngine testEngine;
  setUpAll(() => testEngine = loadEngine());

  group('MessageOrigin', () {
    test('round-trips through JSON and drops empty origins', () {
      final MessageOrigin origin = MessageOrigin(
        appPackage: 'com.whatsapp',
        appLabel: 'WhatsApp',
        shareAction: 'android.intent.action.SEND',
        simSlot: 1,
        carrier: 'Jio',
        subscriptionId: 2,
        originatingAddress: '+919876543210',
        senderAlias: 'VM-SBIINB',
        deliveredAt: DateTime(2026, 9, 24, 15, 14),
      );
      final MessageOrigin? restored =
          MessageOrigin.fromJson(origin.toJson());
      expect(restored, isNotNull);
      expect(restored!.appPackage, 'com.whatsapp');
      expect(restored.appDisplayName, 'WhatsApp');
      expect(restored.simSlot, 1);
      expect(restored.simSlotNumber, 2);
      expect(restored.carrier, 'Jio');
      expect(restored.subscriptionId, 2);
      expect(restored.originatingAddress, '+919876543210');
      expect(restored.deliveredAt, DateTime(2026, 9, 24, 15, 14));

      expect(MessageOrigin.fromJson(<String, dynamic>{}), isNull);
      expect(const MessageOrigin().isEmpty, isTrue);
    });

    test('falls back to a local name table for a known package only', () {
      const MessageOrigin known = MessageOrigin(appPackage: 'org.telegram.messenger');
      expect(known.appDisplayName, 'Telegram');
      const MessageOrigin unknown = MessageOrigin(appPackage: 'com.example.unknown');
      expect(unknown.appDisplayName, 'com.example.unknown');
      expect(const MessageOrigin().appDisplayName, isNull);
    });
  });

  group('MessageSourceDescriptor', () {
    test('SMS is reported as SMS', () {
      final MessageSourceDescriptor source =
          MessageSourceDescriptor.describe(MessageChannel.smsInbox, null);
      expect(source.kind, MessageSourceKind.sms);
      expect(source.label, 'SMS');
      expect(source.isAutomatic, isTrue);
    });

    test('share reports the app only when Android provided it', () {
      final MessageSourceDescriptor withApp = MessageSourceDescriptor.describe(
        MessageChannel.share,
        const MessageOrigin(appPackage: 'com.whatsapp'),
      );
      expect(withApp.kind, MessageSourceKind.sharedApp);
      expect(withApp.label, 'WhatsApp');
      expect(withApp.sublabel, contains('com.whatsapp'));

      final MessageSourceDescriptor withoutApp =
          MessageSourceDescriptor.describe(MessageChannel.share, null);
      expect(withoutApp.kind, MessageSourceKind.sharedUnreported);
      expect(withoutApp.label, 'Shared to CallShield');
      expect(withoutApp.sublabel.toLowerCase(), contains('not provided by android'));
      expect(withoutApp.hasReportedApp, isFalse);
    });

    test('manual and clipboard are user-supplied sources', () {
      expect(
        MessageSourceDescriptor.describe(MessageChannel.manual, null).label,
        'Pasted manually',
      );
      expect(
        MessageSourceDescriptor.describe(MessageChannel.clipboard, null).kind,
        MessageSourceKind.clipboard,
      );
      expect(
        MessageSourceDescriptor.describe(MessageChannel.unknown, null).label,
        contains('Unknown'),
      );
    });
  });

  group('SenderDirectory', () {
    test('resolves real transactional sender ids', () {
      expect(SenderDirectory.organisationFor('VM-SBIINB'), 'State Bank of India');
      expect(SenderDirectory.organisationFor('HDFCBK'), 'HDFC Bank');
      expect(SenderDirectory.organisationFor('SBIINB-S'), 'State Bank of India');
      expect(SenderDirectory.organisationFor('AXHDFCBK'), 'HDFC Bank');
    });

    test('never invents an organisation', () {
      expect(SenderDirectory.organisationFor('+919876543210'), isNull);
      expect(SenderDirectory.organisationFor('QWERTY99'), isNull);
      expect(SenderDirectory.organisationFor(null), isNull);
    });

    test('detects phone-number senders', () {
      expect(SenderDirectory.looksLikeNumber('+919876543210'), isTrue);
      expect(SenderDirectory.looksLikeNumber('9876543210'), isTrue);
      expect(SenderDirectory.looksLikeNumber('VM-SBIINB'), isFalse);
      expect(SenderDirectory.looksLikeNumber(null), isFalse);
    });
  });

  group('timestamp formatting', () {
    test('formats an absolute local timestamp', () {
      expect(formatShieldDateTime(DateTime(2026, 9, 24, 15, 14)),
          '24 Sep 2026, 3:14 PM');
      expect(formatShieldDateTime(DateTime(2026, 1, 5, 0, 7)), '5 Jan 2026, 12:07 AM');
      expect(formatShieldDateTime(null), '');
    });
  });

  group('AnalysisResult persistence of the source', () {
    test('origin and ingest id survive a store round-trip', () {
      final MessageInput input = MessageInput(
        text: 'Your KYC is expiring. Update now at http://sbi-kyc.xyz',
        sender: 'VM-SBIINB',
        channel: MessageChannel.smsInbox,
        origin: MessageOrigin(
          originatingAddress: '+919876543210',
          senderAlias: 'VM-SBIINB',
          simSlot: 1,
          carrier: 'Jio',
          subscriptionId: 2,
          deliveredAt: DateTime(2026, 9, 24, 15, 14),
        ),
        ingestId: 'ingest-1',
      );
      final AnalysisResult result =
          testEngine.analyze(input, senderHistory: const SenderHistory());
      final AnalysisResult restored =
          AnalysisResult.fromJson(result.copyWith(id: 'ms-1').toJson());

      expect(restored.input.channel, MessageChannel.smsInbox);
      expect(restored.input.sender, 'VM-SBIINB');
      expect(restored.input.ingestId, 'ingest-1');
      expect(restored.input.origin, isNotNull);
      expect(restored.input.origin!.simSlotNumber, 2);
      expect(restored.input.origin!.carrier, 'Jio');
      expect(restored.input.origin!.originatingAddress, '+919876543210');
      expect(restored.input.origin!.deliveredAt, DateTime(2026, 9, 24, 15, 14));
      expect(restored.source.kind, MessageSourceKind.sms);
      expect(restored.id, 'ms-1');
    });
  });

  group('native payload mapping', () {
    test('maps every field Android provided', () {
      final MessageInput? input = MessageShieldService.incomingPayloadToInput(<String, dynamic>{
        'id': 'abc-1',
        'sender': 'VM-SBIINB',
        'address': '+919876543210',
        'body': 'Dear customer, your KYC is expired. Update immediately.',
        'ts': '2026-09-24T15:14:00.000',
        'delivered': '2026-09-24T15:13:58.000',
        'subId': 2,
        'slot': 1,
        'carrier': 'Jio',
      });
      expect(input, isNotNull);
      expect(input!.channel, MessageChannel.smsInbox);
      expect(input.ingestId, 'abc-1');
      expect(input.origin!.carrier, 'Jio');
      expect(input.origin!.simSlot, 1);
      expect(input.origin!.deliveredAt, DateTime(2026, 9, 24, 15, 13, 58));
      expect(input.senderKind, SenderKind.alphanumericId);
    });

    test('ignores an empty body and tolerates missing metadata', () {
      expect(
        MessageShieldService.incomingPayloadToInput(<String, dynamic>{'body': '  '}),
        isNull,
      );
      final MessageInput? bare = MessageShieldService.incomingPayloadToInput(
        <String, dynamic>{'body': 'hello', 'sender': 'VM-HDFCBK'},
      );
      expect(bare, isNotNull);
      expect(bare!.ingestId, isNull);
      // The sender id Android reported is kept as-is...
      expect(bare.origin?.senderAlias, 'VM-HDFCBK');
      // ...but nothing was invented for what Android did not provide.
      expect(bare.origin?.carrier, isNull);
      expect(bare.origin?.simSlot, isNull);
      expect(bare.origin?.originatingAddress, isNull);

      final MessageInput? anonymous = MessageShieldService.incomingPayloadToInput(
        <String, dynamic>{'body': 'hello'},
      );
      expect(anonymous?.origin, isNull);
    });
  });

  group('notification text', () {
    test('never contains the message text', () {
      const String body =
          'Your account will be blocked. Share the OTP 482913 immediately.';
      final AnalysisResult result = testEngine.analyze(
        const MessageInput(text: body, sender: 'VM-SBIINB'),
        senderHistory: const SenderHistory(),
      );
      final String title = MessageShieldService.notificationTitle(result);
      final String notification = MessageShieldService.notificationBody(result);
      expect(notification.toLowerCase(), isNot(contains('otp 482913')));
      expect(notification, isNot(contains(body)));
      expect(title, isNot(contains(body)));
      expect(notification, contains('${result.riskScore}/100'));
      expect(notification, contains('Source: Pasted manually'));
    });

    test('a scam verdict is flagged as a possible scam', () {
      final AnalysisResult result = testEngine.analyze(
        const MessageInput(
          text: 'Dear customer your KYC is expired, update immediately at '
              'http://sbi-kyc-update.xyz/verify or your account will be blocked in 24 hours',
          sender: 'VM-SBIINB',
        ),
        senderHistory: const SenderHistory(),
      );
      expect(result.band, RiskBand.scam);
      expect(MessageShieldService.notificationTitle(result), contains('possible scam'));
    });
  });

  group('ingest dedupe', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('each capture is claimed once', () async {
      final MessageShieldStore store = MessageShieldStore();
      expect(await store.claimIngestId('one'), isTrue);
      expect(await store.claimIngestId('one'), isFalse);
      expect(await store.claimIngestId('two'), isTrue);
      // No id (manual flows) is never blocked.
      expect(await store.claimIngestId(null), isTrue);
      expect(await store.claimIngestId(''), isTrue);
    });

    test('a stored verdict can be found by its ingest id', () async {
      final MessageShieldStore store = MessageShieldStore();
      final MessageInput input = MessageInput(
        text: 'Lottery winner! Claim your prize now.',
        sender: 'VM-LOTTERY',
        origin: const MessageOrigin(carrier: 'Jio'),
        ingestId: 'row-7',
      );
      final AnalysisResult result =
          await store.save(testEngine.analyze(input, senderHistory: const SenderHistory()));
      expect(result.id, isNotNull);
      final AnalysisResult? found = await store.findByIngestId('row-7');
      expect(found?.id, result.id);
      expect(await store.findByIngestId('row-8'), isNull);
    });

    test('trusted sender settings stay intact', () async {
      final MessageShieldStore store = MessageShieldStore();
      await store.markSenderTrusted('VM-HDFCBK', true);
      final MessageShieldSettings settings = await store.settings();
      expect(settings.trustedSenders, contains('VM-HDFCBK'));
      expect(const MessageShieldSettings().autoProtectionEnabled, isFalse);
    });
  });

  group('scam categories are unchanged by the source work', () {
    test('a KYC scam still scores as a scam', () {
      final AnalysisResult result = testEngine.analyze(
        const MessageInput(
          text: 'Dear customer, your KYC is expired. Update immediately at '
              'http://sbi-kyc-update.xyz/verify or your account will be blocked within 24 hours.',
          sender: 'VM-SBIINB',
        ),
        senderHistory: const SenderHistory(),
      );
      expect(result.riskScore, greaterThanOrEqualTo(70));
      expect(result.band, RiskBand.scam);
      // Whichever risky category wins, it is never reported as legitimate.
      expect(result.categories.first.id, isNot('legitimate'));
    });
  });
}
