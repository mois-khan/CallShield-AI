import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database/message_shield_store.dart';
import '../models/analysis_result.dart';
import '../models/message_input.dart';
import '../models/protection_status.dart';
import '../models/scam_category.dart';
import '../services/message_ingest_service.dart';
import '../services/message_shield_service.dart';
import '../theme/shield_theme.dart';
import '../utils/time_format.dart';
import '../widgets/risk_score_gauge.dart';
import '../widgets/shield_components.dart';
import 'message_history_screen.dart';
import 'message_threat_result_screen.dart';
import 'scan_message_screen.dart';

/// Message Shield - the second protection section of CallShield.
class MessageShieldHomeScreen extends StatefulWidget {
  const MessageShieldHomeScreen({super.key, this.service, this.store});

  final MessageShieldService? service;
  final MessageShieldStore? store;

  @override
  State<MessageShieldHomeScreen> createState() => _MessageShieldHomeScreenState();
}

class _MessageShieldHomeScreenState extends State<MessageShieldHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MessageShieldService _service = widget.service ?? MessageShieldService.instance;
  late final MessageShieldStore _store = widget.store ?? MessageShieldStore();
  late final TabController _tabs = TabController(length: 3, vsync: this);

  bool _loading = true;
  bool _autoProtection = false;
  bool _autoSupported = true;
  bool _busy = false;
  bool _batteryBusy = false;
  String? _status;
  ProtectionStatus _protection = const ProtectionStatus();
  MessageShieldStats _stats = const MessageShieldStats();
  List<AnalysisResult> _recent = <AnalysisResult>[];
  MessageShieldSettings _settings = const MessageShieldSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MessageShieldService.instance.pendingOpenId.addListener(_openPendingNotification);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MessageShieldService.instance.pendingOpenId.removeListener(_openPendingNotification);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _service.ensureInitialized();
    _autoSupported = await MessageIngestService().isAutoProtectionSupported();
    // The background service may have analysed messages while we were closed: the
    // store reloads from disk on every read so nothing stale is shown here.
    await _store.refresh();
    await _refresh();
    await _refreshProtectionStatus();
    // Pick up a message that was shared into CallShield while we were closed.
    await _consumeShared();
    // Drain anything the native receiver captured (only when enabled).
    if (_settings.autoProtectionEnabled) {
      await _service.drainIncoming(appInForeground: true);
      await _refresh();
      await _refreshProtectionStatus();
    }
    // Opened by tapping a Message Shield alert? Show that verdict directly.
    final String? launchId = await _service.launchPayload();
    if (launchId != null && launchId.isNotEmpty) {
      _service.pendingOpenId.value = launchId;
    }
  }

  Future<void> _refresh() async {
    final MessageShieldSettings settings = await _store.settings();
    final MessageShieldStats stats = await _store.stats();
    final List<AnalysisResult> recent = await _store.history(limit: 3);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _autoProtection = settings.autoProtectionEnabled;
      _stats = stats;
      _recent = recent;
      _loading = false;
    });
  }

  /// Reads the real Android state behind automatic protection.
  ///
  /// Self-healing: when the user setting is on but the service is not alive
  /// (for example right after an app update, or after Android killed it), this
  /// asks Android to start it again instead of showing a stale "active" state.
  Future<void> _refreshProtectionStatus() async {
    ProtectionStatus status = await MessageIngestService().protectionStatus(
      autoProtectionEnabled: _settings.autoProtectionEnabled,
    );
    if (status.autoProtectionEnabled &&
        !status.serviceRunning &&
        status.smsPermissionGranted) {
      await MessageIngestService().setAutoProtection(true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      status = await MessageIngestService().protectionStatus(
        autoProtectionEnabled: _settings.autoProtectionEnabled,
      );
    }
    if (!mounted) return;
    setState(() => _protection = status);
  }

  /// Opens the verdict a Message Shield notification pointed at.
  Future<void> _openPendingNotification() async {
    final String? id = _service.pendingOpenId.value;
    if (id == null || id.isEmpty || !mounted) return;
    _service.pendingOpenId.value = null;
    final List<AnalysisResult> history = await _store.history(limit: MessageShieldStore.maxHistory);
    final AnalysisResult? match = history
        .cast<AnalysisResult?>()
        .firstWhere((AnalysisResult? r) => r?.id == id, orElse: () => null);
    if (match == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageThreatResultScreen(result: match, store: _store),
      ),
    );
    await _refresh();
  }

  Future<void> _consumeShared() async {
    final MessageInput? shared = await MessageIngestService().consumeSharedPayload();
    if (shared == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanMessageScreen(
          initialText: shared.text,
          initialSender: shared.sender,
          initialChannel: MessageChannel.share,
          initialOrigin: shared.origin,
        ),
      ),
    );
    await _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumeShared();
      _refreshProtectionStatus();
      if (_autoProtection) {
        _service.drainIncoming(appInForeground: true).then((_) {
          _refresh();
          _refreshProtectionStatus();
        });
      } else {
        _refresh();
      }
    }
  }

  Future<void> _openScan({String? text, MessageChannel channel = MessageChannel.manual}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanMessageScreen(initialText: text, initialChannel: channel),
      ),
    );
    await _refresh();
  }

  Future<void> _scanClipboard() async {
    final MessageInput? clipboard = await MessageIngestService().clipboardMessage();
    if (!mounted) return;
    if (clipboard == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to paste - copy a message first')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanMessageScreen(
          initialText: clipboard.text,
          initialChannel: MessageChannel.clipboard,
          initialOrigin: clipboard.origin,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _toggleAutoProtection(bool value) async {
    setState(() => _busy = true);
    if (value) {
      // RECEIVE_SMS is a restricted permission: explain, then ask the OS.
      final PermissionStatus status = await Permission.sms.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = status.isPermanentlyDenied
              ? 'SMS permission is blocked in system settings. You can still scan '
                  'messages manually by pasting, copying or sharing them.'
              : 'SMS permission was not granted. Manual scanning still works.';
        });
        return;
      }
    }
    await MessageIngestService().setAutoProtection(value);
    final MessageShieldSettings next = _settings.copyWith(autoProtectionEnabled: value);
    await _store.saveSettings(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      _autoProtection = value;
      _busy = false;
      _status = value
          ? 'Automatic protection is on. Message Shield keeps screening incoming '
              'SMS on this device with the app closed or the phone locked.'
          : 'Automatic protection is off. The background service was stopped and '
              'the ongoing notice was removed.';
    });
    if (value) {
      await _service.drainIncoming(appInForeground: true);
      await _refresh();
    }
    // Give Android a moment to report the new service state.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshProtectionStatus();
  }

  /// Asks Android for the battery-optimisation exemption (system dialog).
  Future<void> _allowBackgroundReliability() async {
    setState(() => _batteryBusy = true);
    final bool requested =
        await MessageIngestService().requestBatteryOptimizationExemption();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(requested
            ? 'Confirm the exemption in the Android dialog that just opened.'
            : 'This device did not open the exemption dialog. Use "Open battery '
                'settings" and allow CallShield-AI to run in the background.'),
      ),
    );
    setState(() => _batteryBusy = false);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refreshProtectionStatus();
  }

  Future<void> _openBatterySettings() async {
    await MessageIngestService().openBatteryOptimizationSettings();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _refreshProtectionStatus();
  }

  Future<void> _updateSettings(MessageShieldSettings next) async {
    await _store.saveSettings(next);
    if (!mounted) return;
    setState(() => _settings = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShieldTheme.background,
      appBar: AppBar(
        backgroundColor: ShieldTheme.background,
        elevation: 0,
        title: Row(
          children: <Widget>[
            const Icon(Icons.sms_failed_rounded, color: ShieldTheme.accent),
            const SizedBox(width: 10),
            Text('Message Shield', style: ShieldTheme.title()),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: ShieldTheme.accent,
          labelColor: ShieldTheme.textPrimary,
          unselectedLabelColor: ShieldTheme.textMuted,
          labelStyle: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary),
          tabs: const <Widget>[
            Tab(text: 'Dashboard'),
            Tab(text: 'History'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ShieldTheme.accent,
        onPressed: () => _openScan(),
        icon: const Icon(Icons.search),
        label: const Text('Scan message'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ShieldTheme.accent))
          : TabBarView(
              controller: _tabs,
              children: <Widget>[
                _dashboard(),
                MessageHistoryScreen(store: _store, embedded: true),
                _settingsTab(),
              ],
            ),
    );
  }

  // ------------------------------------------------------------------ dashboard

  Widget _dashboard() {
    final bool ready = _service.isReady;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
      children: <Widget>[
        SectionCard(
          border: (_autoProtection ? ShieldTheme.safe : ShieldTheme.warning)
              .withValues(alpha: 0.4),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (_autoProtection ? ShieldTheme.safe : ShieldTheme.warning)
                      .withValues(alpha: 0.15),
                ),
                child: Icon(
                  _autoProtection ? Icons.shield_rounded : Icons.shield_outlined,
                  color: _autoProtection ? ShieldTheme.safe : ShieldTheme.warning,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _autoProtection ? 'Automatic protection: ON' : 'Automatic protection: OFF',
                      style: ShieldTheme.title(size: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _autoProtection
                          ? 'Incoming SMS is screened on this device.'
                          : 'Manual scanning is always available below.',
                      style: ShieldTheme.body(size: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_protection.emoji} Protection status: ${_protection.headline}',
                      style: ShieldTheme.body(
                        size: 12,
                        color: _protection.health == ProtectionHealth.active
                            ? ShieldTheme.safe
                            : ShieldTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _autoProtection,
                onChanged: _busy ? null : _toggleAutoProtection,
                activeThumbColor: ShieldTheme.safe,
              ),
            ],
          ),
        ),
        if (_status != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(_status!, style: ShieldTheme.body(size: 12, color: ShieldTheme.warning)),
        ],
        if (!_autoSupported) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'This build cannot register the SMS receiver on this device, so '
            'automatic screening is unavailable. Paste, clipboard and share '
            'scanning keep working.',
            style: ShieldTheme.body(size: 12),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: StatTile(
                label: 'messages analysed',
                value: '${_stats.analyzed}',
                icon: Icons.forum_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'scams detected',
                value: '${_stats.scams}',
                icon: Icons.gpp_bad_outlined,
                color: ShieldTheme.danger,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: StatTile(
                label: 'suspicious',
                value: '${_stats.suspicious}',
                icon: Icons.report_problem_outlined,
                color: ShieldTheme.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'spam',
                value: '${_stats.spam}',
                icon: Icons.mark_email_unread_outlined,
                color: ShieldTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Quick actions',
          child: Column(
            children: <Widget>[
              _actionRow(
                icon: Icons.keyboard_alt_outlined,
                title: 'Paste & scan a message',
                subtitle: 'Type or paste any SMS, chat or email text',
                onTap: () => _openScan(),
              ),
              _actionRow(
                icon: Icons.content_paste_search,
                title: 'Analyse copied message',
                subtitle: 'Uses whatever is on your clipboard right now',
                onTap: _scanClipboard,
              ),
              _actionRow(
                icon: Icons.ios_share,
                title: 'Shared something to CallShield?',
                subtitle: 'Share a chat message here and it opens ready to scan',
                onTap: _consumeShared,
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Recent threats',
          child: _recent.where((AnalysisResult r) => r.band != RiskBand.safe).isEmpty
              ? Text('No threats detected yet.', style: ShieldTheme.body(size: 13))
              : Column(
                  children: _recent
                      .where((AnalysisResult r) => r.band != RiskBand.safe)
                      .map(
                        (AnalysisResult r) => _recentRow(r),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Engine status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                ready ? _service.engine.version : 'loading…',
                style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                ready
                    ? '${_service.engine.model.classes.length} classes · '
                        '${_service.engine.model.parameterCount} int8 parameters · '
                        'runs fully offline'
                    : '',
                style: ShieldTheme.body(size: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const PrivacyNote(),
      ],
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool last = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: Row(
          children: <Widget>[
            Icon(icon, color: ShieldTheme.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: ShieldTheme.body(size: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: ShieldTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _recentRow(AnalysisResult result) {
    final Color color = bandColor(result.band);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MessageThreatResultScreen(result: result, store: _store),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: <Widget>[
            Icon(bandIcon(result.band), color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.categories.isEmpty ? result.band.label : result.categories.first.label,
                    style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${result.riskScore}/100 · ${formatShieldTime(result.analyzedAt)}',
                    style: ShieldTheme.body(size: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: ShieldTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- settings

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
      children: <Widget>[
        SectionCard(
          title: 'Protection status',
          border: (_protection.health == ProtectionHealth.active
                  ? ShieldTheme.safe
                  : ShieldTheme.warning)
              .withValues(alpha: 0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(_protection.emoji, style: ShieldTheme.body(size: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_protection.headline, style: ShieldTheme.title(size: 15)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_protection.explanation, style: ShieldTheme.body(size: 12)),
              const SizedBox(height: 14),
              _statusRow(
                icon: Icons.sms_outlined,
                label: 'SMS permission',
                value: _protection.smsPermissionGranted ? 'Granted' : 'Not granted',
                ok: _protection.smsPermissionGranted,
              ),
              _statusRow(
                icon: Icons.security_rounded,
                label: 'Background protection',
                value: _protection.serviceRunning
                    ? 'Foreground service running'
                    : 'Not running',
                ok: _protection.serviceRunning,
              ),
              _statusRow(
                icon: Icons.notifications_outlined,
                label: 'Notification permission',
                value: _protection.notificationPermissionGranted ? 'Allowed' : 'Blocked',
                ok: _protection.notificationPermissionGranted,
              ),
              _statusRow(
                icon: Icons.battery_charging_full_outlined,
                label: 'Battery optimization',
                value: _protection.batteryOptimizationIgnored
                    ? 'Unrestricted'
                    : 'Optimized - Android may delay background work',
                ok: _protection.batteryOptimizationIgnored,
              ),
              _statusRow(
                icon: Icons.restart_alt_rounded,
                label: 'Restart after reboot',
                value: _protection.bootRecoveryRegistered
                    ? 'Registered'
                    : 'Unavailable in this build',
                ok: _protection.bootRecoveryRegistered,
              ),
              if (_protection.carrierLabel != null &&
                  _protection.carrierLabel!.trim().isNotEmpty)
                _statusRow(
                  icon: Icons.sim_card_outlined,
                  label: 'Default carrier (from Android)',
                  value: _protection.carrierLabel!,
                  ok: true,
                ),
              if (!_protection.batteryOptimizationIgnored &&
                  _protection.autoProtectionEnabled) ...<Widget>[
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _batteryBusy ? null : _allowBackgroundReliability,
                        icon: const Icon(Icons.battery_saver, size: 18),
                        label: const Text('Allow background reliability'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ShieldTheme.textPrimary,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _openBatterySettings,
                      child: const Text('Open settings'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Some phones (vivo/iQOO, Xiaomi, Oppo, Samsung) also ship their own '
                  '"autostart / background app" switch. Allow CallShield-AI there too, '
                  'otherwise the system can stop background screening even when the '
                  'Android battery setting is unrestricted.',
                  style: ShieldTheme.body(size: 11),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Android forbids any app from running after you force stop it from '
                'system settings. Message Shield does not pretend otherwise: if that '
                'happens, background screening resumes the next time you open '
                'CallShield-AI or reboot the phone.',
                style: ShieldTheme.body(size: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Protection',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Automatic SMS protection',
                    style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary)),
                subtitle: Text(
                  'Needs the SMS permission. Play policy allows RECEIVE_SMS for '
                  'this purpose only on sideloaded/dev builds; if it is refused, '
                  'manual scanning keeps working.',
                  style: ShieldTheme.body(size: 11),
                ),
                value: _autoProtection,
                onChanged: _busy ? null : _toggleAutoProtection,
                activeThumbColor: ShieldTheme.safe,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Notify me about risky messages',
                    style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary)),
                subtitle: Text('Uses a local notification, no message content is sent.',
                    style: ShieldTheme.body(size: 11)),
                value: _settings.notifyOnSuspicious,
                onChanged: (bool v) =>
                    _updateSettings(_settings.copyWith(notifyOnSuspicious: v)),
                activeThumbColor: ShieldTheme.accent,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Only notify when the app is in the background',
                    style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary)),
                value: _settings.notifyOnlyWhenAway,
                onChanged: (bool v) =>
                    _updateSettings(_settings.copyWith(notifyOnlyWhenAway: v)),
                activeThumbColor: ShieldTheme.accent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Privacy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Store message text with the verdict',
                    style: ShieldTheme.body(size: 14, color: ShieldTheme.textPrimary)),
                subtitle: Text(
                  'When off, only the score, category and signals are kept. '
                  'Turn this off on shared phones.',
                  style: ShieldTheme.body(size: 11),
                ),
                value: _settings.storeMessageText,
                onChanged: (bool v) => _updateSettings(_settings.copyWith(storeMessageText: v)),
                activeThumbColor: ShieldTheme.accent,
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _deleteHistory,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete Message Shield history'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShieldTheme.danger,
                  side: BorderSide(color: ShieldTheme.danger.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Message Shield analyses everything on this device. Nothing is '
                'uploaded, there is no analytics on message content, and links are '
                'never opened.',
                style: ShieldTheme.body(size: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Detection stack',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Rules + behaviour + local scam intelligence + URL text checks + a '
                  'small on-device classifier.', style: ShieldTheme.body(size: 12)),
              const SizedBox(height: 10),
              if (_service.isReady) ...<Widget>[
                Text('Model: ${_service.engine.model.classes.join(', ')}',
                    style: ShieldTheme.body(size: 11)),
                const SizedBox(height: 6),
                Text(
                  'Classifier quality (measured on the shipped synthetic held-out '
                  'corpus, not on real-world traffic): '
                  '${_modelAccuracy()} accuracy, '
                  '${_modelMacroF1()} macro-F1.',
                  style: ShieldTheme.body(size: 11),
                ),
                const SizedBox(height: 6),
                Text('Feature space: ${_service.engine.model.featureVersion}, '
                    '${_service.engine.model.buckets} hashed buckets.',
                    style: ShieldTheme.body(size: 11)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusRow({
    required IconData icon,
    required String label,
    required String value,
    required bool ok,
  }) {
    final Color color = ok ? ShieldTheme.safe : ShieldTheme.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: ShieldTheme.body(size: 13, color: ShieldTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: ShieldTheme.body(size: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }

  String _modelAccuracy() {
    final dynamic metrics = _service.engine.model.metrics['held_out_test_quantised_int8'];
    final dynamic value = (metrics is Map) ? metrics['accuracy'] : null;
    return value == null ? 'n/a' : '${((value as num) * 100).toStringAsFixed(1)}%';
  }

  String _modelMacroF1() {
    final dynamic metrics = _service.engine.model.metrics['held_out_test_quantised_int8'];
    final dynamic value = (metrics is Map) ? metrics['macro_f1'] : null;
    return value == null ? 'n/a' : '${((value as num) * 100).toStringAsFixed(1)}%';
  }

  Future<void> _deleteHistory() async {
    await _store.deleteAll();
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message Shield history deleted')),
    );
  }
}
