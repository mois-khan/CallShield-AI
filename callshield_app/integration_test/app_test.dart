import 'dart:async';

import 'package:callshield_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Message Shield end-to-end tests on a physical Android device (USB).
///
/// Harness rules (learned the hard way on-device):
///   * NO pumpAndSettle anywhere - the Call Shield home animates forever and a
///     timed-out pumpAndSettle keeps pumping after the test ends, poisoning the
///     binding for every later test ("!inTest" assertion cascade).
///   * All waits are fixed-pump polling loops with a wall-clock deadline.
///   * Every test boots its own app instance and navigates explicitly.
const String kScamMessage =
    'URGENT: Your bank KYC will expire today. Send the OTP you received to our '
    'verification executive immediately or your account will be blocked. '
    'Update now at http://sbi-kyc-update.xyz/verify';

const String kLegitMessage =
    'Your OTP for transaction verification is 482913. Do not share this OTP '
    'with anyone.';

/// Pumps real frames for [seconds] of wall time. Never hangs.
Future<void> pumpFor(WidgetTester tester, {int seconds = 2}) async {
  for (int i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Pumps until [finder] finds a widget or [seconds] elapse. Returns success.
Future<bool> waitFor(
  WidgetTester tester,
  Finder finder, {
  int seconds = 10,
}) async {
  final DateTime deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return finder.evaluate().isNotEmpty;
}

/// Fresh boot + navigation into Message Shield (Dashboard tab visible).
Future<void> bootToMessageShield(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await pumpFor(tester, seconds: 3);

  final Finder shieldButton = find.byTooltip('Message Shield');
  final bool found = await waitFor(tester, shieldButton, seconds: 40);
  expect(found, isTrue, reason: 'Message Shield app-bar entry missing after boot');

  await tester.tap(shieldButton);
  final bool tabs = await waitFor(tester, find.text('Dashboard'), seconds: 20);
  expect(tabs, isTrue, reason: 'Message Shield did not open');
}

/// Drags the scrollable at [listIndex] upward until [finder] builds (lazy
/// ListViews only build visible children - plain find.text cannot see
/// below-the-fold sections on a phone screen). Returns success.
Future<bool> dragUntil(
  WidgetTester tester,
  Finder finder, {
  int listIndex = 0,
  int maxDrags = 10,
}) async {
  for (int i = 0; i < maxDrags; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    final Finder list = find.byType(ListView).at(listIndex);
    if (list.evaluate().isEmpty) return finder.evaluate().isNotEmpty;
    await tester.drag(list, const Offset(0, -300));
    await pumpFor(tester, seconds: 1);
  }
  return finder.evaluate().isNotEmpty;
}

/// Opens the scan screen, enters [text] and analyses it.
/// Leaves the tester on the Message Shield result screen.
Future<void> scanText(WidgetTester tester, String text) async {
  await tester.tap(find.text('Scan message'));
  final bool scanScreen = await waitFor(tester, find.text('Scan a message'), seconds: 15);
  expect(scanScreen, isTrue, reason: 'scan screen did not open');

  await tester.enterText(find.byType(TextField), text);
  await pumpFor(tester, seconds: 1);

  await tester.tap(find.text('Analyse'));
  // Isolate spin-up + model load happen once per process; allow generous time.
  final bool result = await waitFor(tester, find.text('Message Shield result'), seconds: 30);
  expect(result, isTrue, reason: 'analysis did not produce a result screen');
}

/// Pops result/scan routes until the Message Shield home tabs are visible.
/// Route transitions briefly show two Back buttons, so we tap one per pumped
/// frame and re-check instead of relying on pageBack().
Future<void> popToMessageShieldHome(WidgetTester tester, {int seconds = 25}) async {
  final DateTime deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    final bool onHome = find.text('Dashboard').evaluate().isNotEmpty &&
        find.text('Scan a message').evaluate().isEmpty;
    if (onHome) return;
    final Finder back = find.byTooltip('Back');
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back.first, warnIfMissed: false);
    }
    await pumpFor(tester, seconds: 1);
  }
}

/// Pops one route, waiting for the transition to finish first (during the
/// animation two AppBars - and two Back tooltips - are onstage briefly).
Future<void> popSafely(WidgetTester tester, {int seconds = 10}) async {
  final DateTime deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (find.byTooltip('Back').evaluate().length <= 1) break;
    await pumpFor(tester, seconds: 1);
  }
  final Finder back = find.byTooltip('Back');
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back.first, warnIfMissed: false);
  }
  await pumpFor(tester, seconds: 1);
}

/// Taps [target] until [verified] turns true (animation windows can swallow a
/// single tap). If the target is off-screen it is scrolled in ONCE; repeated
/// ensureVisible can park a widget under the pinned TabBar where taps miss.
Future<bool> tapUntil(
  WidgetTester tester,
  Finder target,
  bool Function() verified, {
  int attempts = 6,
}) async {
  for (int i = 0; i < attempts; i++) {
    if (target.evaluate().isEmpty) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await pumpFor(tester, seconds: 1);
      continue;
    }
    await tester.tap(target, warnIfMissed: false);
    await pumpFor(tester, seconds: 2);
    if (verified()) return true;
  }
  return verified();
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('0 | boot: app starts, Call Shield UI intact, Message Shield reachable',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await pumpFor(tester, seconds: 3);

    expect(find.byType(Scaffold), findsWidgets,
        reason: 'app did not render its home screen');
    final bool shield = await waitFor(tester, find.byTooltip('Message Shield'), seconds: 40);
    expect(shield, isTrue, reason: 'Message Shield entry missing');
  });

  testWidgets('1 | scam message: high-risk verdict with full explanation',
      (tester) async {
    await bootToMessageShield(tester);
    await scanText(tester, kScamMessage);

    expect(find.textContaining('SCAM'), findsWidgets,
        reason: 'no scam verdict shown');
    expect(find.textContaining('/100'), findsWidgets,
        reason: 'no numeric risk score shown');
    expect(find.text('Detected category'), findsOneWidget);
    expect(find.text('Detected signals'), findsOneWidget);
    // Below-the-fold sections live in a lazy ListView: scroll to them first.
    final bool objective =
        await dragUntil(tester, find.text('Likely objective'));
    expect(objective, isTrue, reason: 'likely-objective section missing');
    final bool actions =
        await dragUntil(tester, find.text('Recommended action'));
    expect(actions, isTrue, reason: 'recommended-action section missing');
    // Markers for the report.
    // ignore: avoid_print
    print('TEST1_SCAM_VERDICT_OK');
  });

  testWidgets('2 | legitimate bank OTP: not classified as scam', (tester) async {
    await bootToMessageShield(tester);
    await scanText(tester, kLegitMessage);

    expect(find.textContaining('SCAM DETECTED'), findsNothing,
        reason: 'legitimate OTP message was flagged as a scam');
    expect(find.textContaining('/100'), findsWidgets);
    // ignore: avoid_print
    print('TEST2_LEGIT_NOT_SCAM_OK');
  });

  testWidgets('3 | history: entries recorded, openable, and deletable',
      (tester) async {
    await bootToMessageShield(tester);

    // One fresh scan owned by this test.
    await scanText(tester, kScamMessage);

    // result -> scan screen -> home screen (transition-tolerant).
    await popToMessageShieldHome(tester);

    final bool onHome = await waitFor(tester, find.text('History'), seconds: 15);
    expect(onHome, isTrue, reason: 'did not return to Message Shield home');
    await tester.tap(find.text('History'));
    final bool hasEntry = await waitFor(
      tester,
      find.textContaining('/100'),
      seconds: 10,
    );
    expect(hasEntry, isTrue, reason: 'no analysed message found in history');

    // Open the newest entry (scroll it fully into view first).
    final Finder entry = find.textContaining('/100').first;
    await dragUntil(tester, entry);
    await tester.ensureVisible(entry);
    await pumpFor(tester, seconds: 1);
    await tester.tap(entry, warnIfMissed: false);
    final bool detail = await waitFor(tester, find.text('Message Shield result'), seconds: 12);
    expect(detail, isTrue, reason: 'history entry did not open');
    await popSafely(tester);

    // Settings -> delete all history. The Privacy card with the delete
    // button sits below the fold, so scroll the settings list to it first.
    await tester.tap(find.text('Settings'));
    await pumpFor(tester, seconds: 1);
    bool delBtn = await waitFor(tester, find.text('Delete Message Shield history'), seconds: 6);
    for (int i = 0; i < 5 && !delBtn; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -350));
      await pumpFor(tester, seconds: 1);
      delBtn = find.text('Delete Message Shield history').evaluate().isNotEmpty;
    }
    expect(delBtn, isTrue, reason: 'delete-history control missing');
    // Open the confirm dialog (its unique exact-'Delete' button only exists
    // inside the dialog - the list button reads 'Delete Message Shield history').
    final Finder delBtnFinder = find.text('Delete Message Shield history');
    final bool dialog = await tapUntil(
      tester,
      delBtnFinder,
      () => find.text('Cancel').evaluate().isNotEmpty,
    );
    expect(dialog, isTrue, reason: 'delete confirmation dialog did not open');

    // Confirm the deletion and verify the dialog closes.
    final bool confirmed = await tapUntil(
      tester,
      find.text('Delete'),
      () => find.text('Cancel').evaluate().isEmpty,
    );
    expect(confirmed, isTrue, reason: 'delete confirmation did not complete');

    // History is now empty and the app is still alive.
    await tester.tap(find.text('History'));
    final bool empty = await waitFor(tester, find.text('No analysed messages yet.'), seconds: 10);
    expect(empty, isTrue, reason: 'history not empty after deletion');
    // ignore: avoid_print
    print('TEST3_HISTORY_OK');
  });

  testWidgets('4 | automatic protection: permission flow + toggle', (tester) async {
    await bootToMessageShield(tester);

    await tester.tap(find.text('Settings'));
    await pumpFor(tester, seconds: 1);
    final bool settings = await waitFor(tester, find.text('Automatic SMS protection'), seconds: 10);
    expect(settings, isTrue, reason: 'automatic protection control missing');

    // Toggle automatic protection. Address the exact SwitchListTile by its
    // title so no other screen's switch can be read by mistake.
    final Finder tile = find.widgetWithText(SwitchListTile, 'Automatic SMS protection');
    expect(tile, findsOneWidget, reason: 'automatic protection tile not found');
    final bool before = tester.widget<SwitchListTile>(tile.first).value;
    final bool toggled = await tapUntil(
      tester,
      tile.first,
      () => tester.widget<SwitchListTile>(tile.first).value != before,
    );
    final bool after = tester.widget<SwitchListTile>(tile.first).value;
    // ignore: avoid_print
    print('AUTO_SWITCH_BEFORE=$before AFTER=$after toggled=$toggled');

    // Secondary evidence: the status line on the Dashboard (informational).
    await tester.tap(find.text('Dashboard'));
    await pumpFor(tester, seconds: 2);
    final bool onVisible =
        await dragUntil(tester, find.textContaining('Automatic protection is on'));
    final bool deniedVisible =
        await dragUntil(tester, find.textContaining('Manual scanning still works'));
    // ignore: avoid_print
    print('AUTO_STATUS_ENABLED=$onVisible DENIED_FALLBACK_SHOWN=$deniedVisible');
    expect(toggled && after, isTrue,
        reason: 'automatic protection toggle did not turn on');
    // ignore: avoid_print
    print('TEST4_AUTO_PROTECTION_OK');
  });
}
