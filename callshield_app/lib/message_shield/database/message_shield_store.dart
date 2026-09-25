import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/message_shield_engine.dart';
import '../models/analysis_result.dart';
import '../models/message_input.dart';
import '../models/scam_category.dart';
import '../models/shield_signal.dart';

/// Message Shield settings (all local).
class MessageShieldSettings {
  const MessageShieldSettings({
    this.autoProtectionEnabled = false,
    this.notifyOnSuspicious = true,
    this.notifyOnlyWhenAway = true,
    this.storeMessageText = true,
    this.trustedSenders = const <String>{},
  });

  /// Watch incoming SMS when the user granted RECEIVE_SMS.
  final bool autoProtectionEnabled;

  /// Show a notification for SUSPICIOUS and SCAM verdicts.
  final bool notifyOnSuspicious;

  /// Only notify while the app is in the background.
  final bool notifyOnlyWhenAway;

  /// When off, only the verdict metadata is stored (no message text).
  final bool storeMessageText;

  final Set<String> trustedSenders;

  MessageShieldSettings copyWith({
    bool? autoProtectionEnabled,
    bool? notifyOnSuspicious,
    bool? notifyOnlyWhenAway,
    bool? storeMessageText,
    Set<String>? trustedSenders,
  }) =>
      MessageShieldSettings(
        autoProtectionEnabled: autoProtectionEnabled ?? this.autoProtectionEnabled,
        notifyOnSuspicious: notifyOnSuspicious ?? this.notifyOnSuspicious,
        notifyOnlyWhenAway: notifyOnlyWhenAway ?? this.notifyOnlyWhenAway,
        storeMessageText: storeMessageText ?? this.storeMessageText,
        trustedSenders: trustedSenders ?? this.trustedSenders,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'autoProtectionEnabled': autoProtectionEnabled,
        'notifyOnSuspicious': notifyOnSuspicious,
        'notifyOnlyWhenAway': notifyOnlyWhenAway,
        'storeMessageText': storeMessageText,
        'trustedSenders': trustedSenders.toList(),
      };

  static MessageShieldSettings fromJson(Map<String, dynamic> json) =>
      MessageShieldSettings(
        autoProtectionEnabled: json['autoProtectionEnabled'] as bool? ?? false,
        notifyOnSuspicious: json['notifyOnSuspicious'] as bool? ?? true,
        notifyOnlyWhenAway: json['notifyOnlyWhenAway'] as bool? ?? true,
        storeMessageText: json['storeMessageText'] as bool? ?? true,
        trustedSenders: (json['trustedSenders'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toSet(),
      );
}

/// Aggregate counters shown on the dashboard.
class MessageShieldStats {
  const MessageShieldStats({
    this.analyzed = 0,
    this.scams = 0,
    this.suspicious = 0,
    this.spam = 0,
    this.safe = 0,
  });

  final int analyzed;
  final int scams;
  final int suspicious;
  final int spam;
  final int safe;

  MessageShieldStats copyWith({
    int? analyzed,
    int? scams,
    int? suspicious,
    int? spam,
    int? safe,
  }) =>
      MessageShieldStats(
        analyzed: analyzed ?? this.analyzed,
        scams: scams ?? this.scams,
        suspicious: suspicious ?? this.suspicious,
        spam: spam ?? this.spam,
        safe: safe ?? this.safe,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'analyzed': analyzed,
        'scams': scams,
        'suspicious': suspicious,
        'spam': spam,
        'safe': safe,
      };

  static MessageShieldStats fromJson(Map<String, dynamic> json) => MessageShieldStats(
        analyzed: (json['analyzed'] as num?)?.toInt() ?? 0,
        scams: (json['scams'] as num?)?.toInt() ?? 0,
        suspicious: (json['suspicious'] as num?)?.toInt() ?? 0,
        spam: (json['spam'] as num?)?.toInt() ?? 0,
        safe: (json['safe'] as num?)?.toInt() ?? 0,
      );
}

/// Local storage for Message Shield.
///
/// Uses the same `shared_preferences` mechanism the rest of the app already
/// uses, but with its own key namespace, so Call Shield data is never touched.
/// Only message metadata and (optionally) a truncated preview are stored, and
/// nothing is ever uploaded.
class MessageShieldStore {
  MessageShieldStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const String historyKey = 'message_shield_history_v1';
  static const String statsKey = 'message_shield_stats_v1';
  static const String settingsKey = 'message_shield_settings_v1';
  static const String cacheKey = 'message_shield_verdict_cache_v1';
  static const String sendersKey = 'message_shield_senders_v1';
  static const String ingestIdsKey = 'message_shield_ingest_ids_v1';

  /// Hard cap on stored history rows (keeps the app light on low-end devices).
  static const int maxHistory = 300;
  static const int maxCachedFingerprints = 120;
  static const int maxIngestIds = 200;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  /// Reloads from disk.
  ///
  /// Message Shield runs in two Dart engines (the UI engine and the headless
  /// engine inside the protection service). SharedPreferences caches values per
  /// engine, so every read path reloads first: the UI must never show stale
  /// history after the background service analysed a message.
  Future<void> refresh() async {
    final SharedPreferences p = await _p;
    await p.reload();
  }

  // ------------------------------------------------------------- ingest dedupe

  /// Claims an ingest id, returning true exactly once per id.
  ///
  /// The SMS receiver both queues a message and hands it to the background
  /// service, so the same message can reach analysis twice (background + UI).
  /// This makes the second attempt a no-op instead of a duplicate history row.
  Future<bool> claimIngestId(String? id) async {
    final String trimmed = (id ?? '').trim();
    if (trimmed.isEmpty) return true;
    final SharedPreferences p = await _p;
    await p.reload();
    final List<String> raw = p.getStringList(ingestIdsKey) ?? <String>[];
    if (raw.contains(trimmed)) return false;
    raw.insert(0, trimmed);
    if (raw.length > maxIngestIds) {
      raw.removeRange(maxIngestIds, raw.length);
    }
    await p.setStringList(ingestIdsKey, raw);
    return true;
  }

  // ------------------------------------------------------------------ history

  Future<List<AnalysisResult>> history({int limit = 50, RiskBand? band}) async {
    final SharedPreferences p = await _p;
    await p.reload();
    final List<String> raw = p.getStringList(historyKey) ?? <String>[];
    final List<AnalysisResult> out = <AnalysisResult>[];
    for (final String entry in raw) {
      try {
        final AnalysisResult result =
            AnalysisResult.fromJson(jsonDecode(entry) as Map<String, dynamic>);
        if (band != null && result.band != band) continue;
        out.add(result);
        if (out.length >= limit) break;
      } catch (_) {
        // Ignore a corrupt row instead of failing the whole list.
        continue;
      }
    }
    return out;
  }

  Future<AnalysisResult> save(AnalysisResult result) async {    final SharedPreferences p = await _p;
    await p.reload();
    final List<String> raw = p.getStringList(historyKey) ?? <String>[];
    final String id = result.id ?? 'ms-${DateTime.now().microsecondsSinceEpoch}';
    final AnalysisResult stored = result.copyWith(
      id: id,
      fromCache: false,
      analyzedAt: result.analyzedAt ?? DateTime.now(),
    );
    raw.insert(0, jsonEncode(stored.toJson()));
    if (raw.length > maxHistory) {
      raw.removeRange(maxHistory, raw.length);
    }
    await p.setStringList(historyKey, raw);
    await _bumpStats(stored);
    await _recordSender(stored);
    await _cacheVerdict(stored);
    return stored;
  }

  /// Finds a stored verdict by the ingest id of its message.
  Future<AnalysisResult?> findByIngestId(String id) async {
    final String trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    final List<AnalysisResult> recent = await history(limit: maxHistory);
    for (final AnalysisResult result in recent) {
      if (result.input.ingestId == trimmed) return result;
    }
    return null;
  }

  Future<void> deleteAll() async {
    final SharedPreferences p = await _p;
    await p.remove(historyKey);
    await p.remove(statsKey);
    await p.remove(cacheKey);
    await p.remove(sendersKey);
    await p.remove(ingestIdsKey);
  }

  Future<void> deleteOne(String id) async {
    final SharedPreferences p = await _p;
    final List<String> raw = p.getStringList(historyKey) ?? <String>[];
    raw.removeWhere((String entry) {
      try {
        return (jsonDecode(entry) as Map<String, dynamic>)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await p.setStringList(historyKey, raw);
  }

  // -------------------------------------------------------------------- stats

  Future<MessageShieldStats> stats() async {
    final SharedPreferences p = await _p;
    await p.reload();
    final String? raw = p.getString(statsKey);
    if (raw == null) return const MessageShieldStats();
    try {
      return MessageShieldStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MessageShieldStats();
    }
  }

  Future<void> _bumpStats(AnalysisResult result) async {
    final SharedPreferences p = await _p;
    final MessageShieldStats current = await stats();
    final MessageShieldStats next;
    switch (result.band) {
      case RiskBand.scam:
        next = current.copyWith(analyzed: current.analyzed + 1, scams: current.scams + 1);
      case RiskBand.suspicious:
        next = result.isSpam
            ? current.copyWith(analyzed: current.analyzed + 1, spam: current.spam + 1)
            : current.copyWith(analyzed: current.analyzed + 1, suspicious: current.suspicious + 1);
      case RiskBand.safe:
        next = result.isSpam
            ? current.copyWith(analyzed: current.analyzed + 1, spam: current.spam + 1)
            : current.copyWith(analyzed: current.analyzed + 1, safe: current.safe + 1);
    }
    await p.setString(statsKey, jsonEncode(next.toJson()));
  }

  // ----------------------------------------------------------------- settings

  Future<MessageShieldSettings> settings() async {
    final SharedPreferences p = await _p;
    await p.reload();
    final String? raw = p.getString(settingsKey);
    if (raw == null) return const MessageShieldSettings();
    try {
      return MessageShieldSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const MessageShieldSettings();
    }
  }

  Future<void> saveSettings(MessageShieldSettings settings) async {
    final SharedPreferences p = await _p;
    await p.setString(settingsKey, jsonEncode(settings.toJson()));
  }

  // --------------------------------------------------------- verdict cache

  /// Avoids re-analysing identical text (saves CPU and battery).
  Future<AnalysisResult?> cachedVerdict(int fingerprint) async {
    final SharedPreferences p = await _p;
    final List<String> raw = p.getStringList(cacheKey) ?? <String>[];
    for (final String entry in raw) {
      try {
        final Map<String, dynamic> row = jsonDecode(entry) as Map<String, dynamic>;
        if ((row['fp'] as num?)?.toInt() != fingerprint) continue;
        return AnalysisResult.fromJson(
          Map<String, dynamic>.from(row['verdict'] as Map),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> _cacheVerdict(AnalysisResult result) async {
    final SharedPreferences p = await _p;
    // Only safe and spam verdicts are cached; anything risky is always re-scored
    // so that a repeated scam message still produces a fresh verdict.
    if (result.band != RiskBand.safe) return;
    final int fp = MessageShieldEngine.fingerprint(result.input.text);
    final List<String> raw = p.getStringList(cacheKey) ?? <String>[];
    raw.removeWhere((String entry) {
      try {
        return (jsonDecode(entry) as Map<String, dynamic>)['fp'] == fp;
      } catch (_) {
        return true;
      }
    });
    raw.insert(0, jsonEncode(<String, dynamic>{'fp': fp, 'verdict': result.toJson()}));
    if (raw.length > maxCachedFingerprints) {
      raw.removeRange(maxCachedFingerprints, raw.length);
    }
    await p.setStringList(cacheKey, raw);
  }

  // ------------------------------------------------------ sender reputation

  Future<SenderHistory> senderHistory(String? sender) async {
    if (sender == null || sender.trim().isEmpty) return const SenderHistory();
    final SharedPreferences p = await _p;
    final String? raw = p.getString(sendersKey);
    if (raw == null) return const SenderHistory();
    try {
      final Map<String, dynamic> all = jsonDecode(raw) as Map<String, dynamic>;
      final Map<String, dynamic>? entry =
          all[sender.trim()] == null ? null : Map<String, dynamic>.from(all[sender.trim()] as Map);
      if (entry == null) return const SenderHistory();
      return SenderHistory(
        seenCount: (entry['seen'] as num?)?.toInt() ?? 0,
        scamCount: (entry['risky'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const SenderHistory();
    }
  }

  Future<void> _recordSender(AnalysisResult result) async {
    final String? sender = result.input.sender;
    if (sender == null || sender.trim().isEmpty) return;
    final SharedPreferences p = await _p;
    Map<String, dynamic> all = <String, dynamic>{};
    final String? raw = p.getString(sendersKey);
    if (raw != null) {
      try {
        all = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        all = <String, dynamic>{};
      }
    }
    final Map<String, dynamic> entry = all[sender.trim()] == null
        ? <String, dynamic>{'seen': 0, 'risky': 0}
        : Map<String, dynamic>.from(all[sender.trim()] as Map);
    final bool risky = result.band != RiskBand.safe ||
        result.signals.any((ShieldSignal s) => s.source == SignalSource.behavior && s.weight >= 50);
    entry['seen'] = ((entry['seen'] as num?)?.toInt() ?? 0) + 1;
    entry['risky'] = ((entry['risky'] as num?)?.toInt() ?? 0) + (risky ? 1 : 0);
    entry['last'] = DateTime.now().toIso8601String();
    all[sender.trim()] = entry;
    // Keep the map bounded on devices with long message histories.
    if (all.length > 200) {
      final List<String> keys = all.keys.toList()..sort();
      for (final String key in keys.take(all.length - 200)) {
        all.remove(key);
      }
    }
    await p.setString(sendersKey, jsonEncode(all));
  }

  Future<void> markSenderTrusted(String sender, bool trusted) async {
    final MessageShieldSettings current = await settings();
    final Set<String> next = Set<String>.of(current.trustedSenders);
    if (trusted) {
      next.add(sender.trim());
    } else {
      next.remove(sender.trim());
    }
    await saveSettings(current.copyWith(trustedSenders: next));
  }

  Future<SenderKind> resolveSenderKind(MessageInput input) async {
    final MessageShieldSettings current = await settings();
    if (input.sender != null && current.trustedSenders.contains(input.sender!.trim())) {
      return SenderKind.trustedId;
    }
    return input.senderKind;
  }
}
