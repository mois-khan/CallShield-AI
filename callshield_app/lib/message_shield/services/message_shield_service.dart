import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../database/message_shield_store.dart';
import '../engine/message_shield_engine.dart';
import '../models/analysis_result.dart';
import '../models/message_input.dart';
import '../models/message_origin.dart';
import '../models/protection_status.dart';
import '../models/scam_category.dart';
import 'message_ingest_service.dart';

/// Orchestrates Message Shield: loads the on-device assets, runs analysis off
/// the UI thread, stores results locally and raises local notifications.
///
/// Everything happens on the device. No message content leaves the phone.
class MessageShieldService {
  MessageShieldService({
    MessageShieldStore? store,
    MessageIngestService? ingest,
  })  : store = store ?? MessageShieldStore(),
        ingest = ingest ?? MessageIngestService();

  static final MessageShieldService instance = MessageShieldService();

  static const String modelAssetPath = 'assets/message_shield/ml/message_shield_model.json';
  static const String intelligenceAssetPath =
      'assets/message_shield/intelligence/scam_intelligence.json';
  static const String notificationChannelId = 'message_shield_alerts';
  static const int notificationIdBase = 41000;

  final MessageShieldStore store;
  final MessageIngestService ingest;

  /// Bumped whenever new results are stored, so the UI can refresh.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// History id the user asked to open by tapping a Message Shield
  /// notification. The UI listens to this and pushes the result screen.
  final ValueNotifier<String?> pendingOpenId = ValueNotifier<String?>(null);

  MessageShieldEngine? _engine;
  Uint8List? _modelBytes;
  Uint8List? _intelligenceBytes;
  bool _assetsLoaded = false;
  bool _notificationsReady = false;
  _AnalysisWorker? _worker;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool get isReady => _engine != null;

  MessageShieldEngine get engine {
    final MessageShieldEngine? value = _engine;
    if (value == null) {
      throw StateError('MessageShieldService.ensureInitialized() must be awaited first');
    }
    return value;
  }

  /// Loads the model + intelligence assets and prepares the worker isolate.
  Future<void> ensureInitialized() async {
    if (!_assetsLoaded) {
      final ByteData modelData = await rootBundle.load(modelAssetPath);
      final ByteData intelData = await rootBundle.load(intelligenceAssetPath);
      _modelBytes = modelData.buffer.asUint8List();
      _intelligenceBytes = intelData.buffer.asUint8List();
      _engine = MessageShieldEngine.fromJsonAssets(
        modelBytes: _modelBytes!,
        intelligenceBytes: _intelligenceBytes!,
      );
      _assetsLoaded = true;
    }
    await _ensureNotificationsReady();
  }

  /// Feeds a message through the pipeline.
  ///
  /// [persist] stores the verdict locally; [useIsolate] keeps the UI thread free
  /// (set to false in unit tests and when already running off the UI isolate).
  Future<AnalysisResult> analyzeMessage(
    MessageInput input, {
    bool persist = true,
    bool useIsolate = true,
    bool notify = false,
    bool appInForeground = false,
  }) async {
    await ensureInitialized();
    final SenderHistory history = await store.senderHistory(input.sender);
    final MessageShieldSettings settings = await store.settings();
    final MessageInput resolved = input.copyWith(
      isTrustedSender: input.sender != null &&
          settings.trustedSenders.contains(input.sender!.trim()),
    );

    AnalysisResult result;
    if (persist && resolved.text.trim().isNotEmpty) {
      final AnalysisResult? cached =
          await store.cachedVerdict(MessageShieldEngine.fingerprint(resolved.text));
      if (cached != null) {
        // Identical text that was already scored SAFE is not re-analysed and not
        // re-counted: no duplicate work, no inflated statistics.
        return cached.copyWith(
          fromCache: true,
          analyzedAt: DateTime.now(),
          input: resolved,
        );
      }
    }

    if (persist) {
      // The SMS receiver both queues a message and wakes the background service,
      // so the same capture can reach analysis twice. Only the first caller
      // stores it: no duplicate history rows, no inflated statistics.
      final bool first = await store.claimIngestId(input.ingestId);
      if (!first) {
        final AnalysisResult? existing = await store.findByIngestId(input.ingestId!);
        if (existing != null) {
          debugPrint('\u{1F6E1}\u{FE0F} [MessageShield] duplicate capture ignored: ${input.ingestId}');
          return existing;
        }
        return _runAnalysis(resolved, history, useIsolate: useIsolate);
      }
    }

    result = await _runAnalysis(resolved, history, useIsolate: useIsolate);
    if (persist) {
      // Respect the "store message text" privacy setting: the in-memory result
      // keeps the text for this session, the stored row may not.
      final AnalysisResult toStore = settings.storeMessageText
          ? result
          : result.copyWith(input: resolved.copyWith(text: '<not stored>'));
      final AnalysisResult stored = await store.save(toStore);
      result = result.copyWith(id: stored.id, analyzedAt: stored.analyzedAt);
      revision.value++;
    }
    if (notify) {
      await maybeNotify(result, appInForeground: appInForeground);
    }
    return result;
  }

  Future<AnalysisResult> _runAnalysis(
    MessageInput input,
    SenderHistory history, {
    required bool useIsolate,
  }) async {
    if (!useIsolate || kIsWeb) {
      return engine.analyze(input, senderHistory: history);
    }
    try {
      _worker ??= await _AnalysisWorker.spawn(_modelBytes!, _intelligenceBytes!);
      return await _worker!.analyze(input, history);
    } catch (_) {
      // Any isolate problem degrades gracefully to inline analysis.
      _worker = null;
      return engine.analyze(input, senderHistory: history);
    }
  }

  /// Best-effort re-arm of Android's protection service.
  ///
  /// Called when the app starts: if the user has automatic protection on, the
  /// SMS permission granted and the service not running (fresh install, app
  /// update or after Android stopped it), the service is started again. It does
  /// nothing when protection is off, and never claims more than Android allows.
  static Future<void> ensureBackgroundProtection() async {
    try {
      final MessageShieldStore store = MessageShieldStore();
      final MessageShieldSettings settings = await store.settings();
      if (!settings.autoProtectionEnabled) return;
      final MessageIngestService ingest = MessageIngestService();
      final ProtectionStatus status =
          await ingest.protectionStatus(autoProtectionEnabled: true);
      if (status.smsPermissionGranted && !status.serviceRunning) {
        await ingest.setAutoProtection(true);
        debugPrint('🛡️ [MessageShield] re-armed the background protection service');
      }
    } catch (e) {
      debugPrint('🛡️ [MessageShield] background re-arm skipped: $e');
    }
  }

  /// Analyses one message handed over directly by the native protection
  /// service (the live SMS path: no file polling involved).
  Future<AnalysisResult?> analyzeIncomingPayload(
    Map<dynamic, dynamic> payload, {
    bool notify = true,
    bool appInForeground = false,
  }) async {
    final MessageInput? input = incomingPayloadToInput(payload);
    if (input == null) return null;
    return analyzeMessage(
      input,
      notify: notify,
      appInForeground: appInForeground,
    );
  }

  /// Maps the JSON payload produced by MessageShieldSmsReceiver.kt onto a
  /// [MessageInput]. Only values Android itself supplied are used.
  static MessageInput? incomingPayloadToInput(Map<dynamic, dynamic> payload) {
    final String? body = payload['body']?.toString();
    if (body == null || body.trim().isEmpty) return null;
    final String? sender = payload['sender']?.toString();
    final MessageOrigin origin = MessageOrigin(
      originatingAddress: payload['address']?.toString(),
      senderAlias: sender,
      subscriptionId: (payload['subId'] as num?)?.toInt(),
      simSlot: (payload['slot'] as num?)?.toInt(),
      carrier: payload['carrier']?.toString(),
      deliveredAt: DateTime.tryParse(payload['delivered']?.toString() ?? ''),
    );
    return MessageInput(
      text: body,
      sender: sender,
      channel: MessageChannel.smsInbox,
      senderKind: MessageInput.classifySender(sender),
      receivedAt: DateTime.tryParse(payload['ts']?.toString() ?? ''),
      origin: origin.isEmpty ? null : origin,
      ingestId: payload['id']?.toString(),
    );
  }

  /// Drains the native SMS queue and analyses everything found.
  Future<List<AnalysisResult>> drainIncoming({
    bool notify = true,
    bool appInForeground = false,
  }) async {
    await ensureInitialized();
    final List<MessageInput> messages = await ingest.drainNativeInbox();
    final List<AnalysisResult> results = <AnalysisResult>[];
    for (final MessageInput message in messages) {
      results.add(
        await analyzeMessage(
          message,
          notify: notify,
          appInForeground: appInForeground,
        ),
      );
    }
    return results;
  }

  // ------------------------------------------------------------- notifications

  Future<void> _ensureNotificationsReady() async {
    if (_notificationsReady) return;
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        // Tapping a Message Shield alert opens the stored verdict for it.
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final String? payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            pendingOpenId.value = payload;
          }
        },
      );
      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              notificationChannelId,
              'Message Shield alerts',
              description: 'Warnings when a scam or spam message is detected.',
              importance: Importance.high,
            ),
          );
      _notificationsReady = true;
    } catch (e) {
      debugPrint('🔇 [MessageShield] notifications unavailable: $e');
      _notificationsReady = true; // do not retry in a loop
    }
  }

  /// Raises a local notification for a risky verdict (respects user settings).
  Future<void> maybeNotify(AnalysisResult result, {bool appInForeground = false}) async {
    final MessageShieldSettings settings = await store.settings();
    if (!settings.notifyOnSuspicious) return;
    if (result.band == RiskBand.safe) return;
    if (settings.notifyOnlyWhenAway && appInForeground) return;
    await notifyVerdict(result);
  }

  /// Notification title. Deliberately contains no message content.
  static String notificationTitle(AnalysisResult result) => result.band == RiskBand.scam
      ? '🚨 Message Shield detected a possible scam'
      : (result.isSpam
          ? '⚠️ Message Shield: spam message detected'
          : '⚠️ Message Shield: suspicious message detected');

  /// Notification body: category, score and source only - never the message
  /// text, so a lock-screen preview can never leak the message itself.
  static String notificationBody(AnalysisResult result) {
    final String category = result.categories.isEmpty
        ? result.band.label
        : result.categories.first.label;
    return '$category\n'
        'Risk: ${result.riskScore}/100 · Source: ${result.source.label}\n'
        'Tap to open Message Shield details.';
  }

  Future<void> notifyVerdict(AnalysisResult result) async {
    await _ensureNotificationsReady();
    if (!_notificationsReady) return;
    final bool scam = result.band == RiskBand.scam;
    final String title = notificationTitle(result);
    final String body = notificationBody(result);
    try {
      await _notifications.show(
        id: notificationIdBase + DateTime.now().millisecondsSinceEpoch.remainder(997),
        title: title,
        body: body,
        payload: result.id,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            notificationChannelId,
            'Message Shield alerts',
            importance: scam ? Importance.max : Importance.high,
            priority: scam ? Priority.max : Priority.high,
            icon: '@mipmap/ic_launcher',
            color: scam ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
            // No message text anywhere, and never shown on a locked screen.
            visibility: NotificationVisibility.private,
            category: AndroidNotificationCategory.message,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (e) {
      debugPrint('🔇 [MessageShield] notification failed: $e');
    }
  }

  /// True when the app was launched by tapping a Message Shield alert; the
  /// returned value is the stored history id so the UI can open it directly.
  Future<String?> launchPayload() async {
    try {
      final NotificationAppLaunchDetails? details =
          await _notifications.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details?.notificationResponse?.payload;
      }
    } catch (_) {
      // Older platforms simply never report a launch payload.
    }
    return null;
  }

  Future<void> disposeWorker() async {
    await _worker?.dispose();
    _worker = null;
  }
}

/// Long-lived worker isolate: builds the engine once and answers analysis
/// requests as JSON so the model bytes are never re-parsed per message.
class _AnalysisWorker {
  _AnalysisWorker._(this._isolate, this._receivePort);

  final Isolate _isolate;
  final ReceivePort _receivePort;
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 0;
  bool _failed = false;

  static Future<_AnalysisWorker> spawn(Uint8List modelBytes, Uint8List intelligenceBytes) async {
    final ReceivePort fromWorker = ReceivePort();
    final Completer<SendPort> ready = Completer<SendPort>();
    final Isolate isolate = await Isolate.spawn<_WorkerBootstrap>(
      _workerMain,
      _WorkerBootstrap(fromWorker.sendPort, modelBytes, intelligenceBytes),
      debugName: 'message_shield_analysis',
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
    );

    final _AnalysisWorker worker = _AnalysisWorker._(isolate, fromWorker);
    fromWorker.listen((dynamic message) {
      if (message is SendPort && !ready.isCompleted) {
        ready.complete(message);
        return;
      }
      if (message is Map) {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(message);
        final Completer<Map<String, dynamic>>? completer =
            worker._pending.remove(payload['id'] as int?);
        if (completer != null && !completer.isCompleted) {
          completer.complete(payload);
        }
        return;
      }
      // Any error/exit message means the worker is gone: fail pending requests.
      worker._failed = true;
      for (final Completer<Map<String, dynamic>> c in worker._pending.values) {
        if (!c.isCompleted) c.completeError(StateError('message shield worker stopped'));
      }
      worker._pending.clear();
    });

    worker._sendPort = await ready.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('message shield worker did not start'),
    );
    return worker;
  }

  SendPort? _sendPort;

  Future<AnalysisResult> analyze(MessageInput input, SenderHistory history) async {
    final SendPort? sendPort = _sendPort;
    if (_failed || sendPort == null) {
      throw StateError('worker unavailable');
    }
    final int id = _nextId++;
    final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    sendPort.send(<String, dynamic>{
      'id': id,
      'text': input.text,
      'sender': input.sender,
      'channel': input.channel.name,
      'senderKind': input.senderKind.name,
      'trusted': input.isTrustedSender,
      'seen': history.seenCount,
      'risky': history.scamCount,
    });
    final Map<String, dynamic> reply = await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('message shield analysis timed out');
      },
    );
    final AnalysisResult parsed =
        AnalysisResult.fromJson(Map<String, dynamic>.from(reply['verdict'] as Map));
    // Restore the full message text (stored verdicts keep only a preview).
    return parsed.copyWith(fromCache: false, input: input);
  }

  Future<void> dispose() async {
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _WorkerBootstrap {
  _WorkerBootstrap(this.replyPort, this.modelBytes, this.intelligenceBytes);

  final SendPort replyPort;
  final Uint8List modelBytes;
  final Uint8List intelligenceBytes;
}

void _workerMain(_WorkerBootstrap bootstrap) {
  final ReceivePort requests = ReceivePort();
  bootstrap.replyPort.send(requests.sendPort);

  MessageShieldEngine? engine;
  try {
    engine = MessageShieldEngine.fromJsonAssets(
      modelBytes: bootstrap.modelBytes,
      intelligenceBytes: bootstrap.intelligenceBytes,
    );
  } catch (_) {
    engine = null;
  }

  requests.listen((dynamic message) {
    if (message is! Map) return;
    final Map<String, dynamic> request = Map<String, dynamic>.from(message);
    final int id = request['id'] as int;
    try {
      final MessageShieldEngine local = engine!;
      final AnalysisResult result = local.analyze(
        MessageInput(
          text: request['text'] as String? ?? '',
          sender: request['sender'] as String?,
          channel: MessageChannel.values.firstWhere(
            (MessageChannel c) => c.name == request['channel'],
            orElse: () => MessageChannel.unknown,
          ),
          senderKind: SenderKind.values.firstWhere(
            (SenderKind k) => k.name == request['senderKind'],
            orElse: () => SenderKind.unknown,
          ),
          isTrustedSender: request['trusted'] as bool? ?? false,
        ),
        senderHistory: SenderHistory(
          seenCount: (request['seen'] as num?)?.toInt() ?? 0,
          scamCount: (request['risky'] as num?)?.toInt() ?? 0,
        ),
      );
      bootstrap.replyPort.send(<String, dynamic>{
        'id': id,
        'verdict': result.toJson(),
        'text': request['text'],
      });
    } catch (e) {
      bootstrap.replyPort.send(<String, dynamic>{'id': id, 'error': '$e'});
    }
  });
}
