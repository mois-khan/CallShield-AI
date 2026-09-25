/// Absolute timestamp, e.g. `24 Sep 2026, 3:14 PM` (local time).
String formatShieldDateTime(DateTime? time) {
  if (time == null) return '';
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final DateTime local = time.toLocal();
  final int hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String minute = local.minute.toString().padLeft(2, '0');
  final String meridiem = local.hour < 12 ? 'AM' : 'PM';
  return '${local.day} ${months[local.month - 1]} ${local.year}, $hour12:$minute $meridiem';
}

/// Tiny timestamp helper (avoids pulling in another package).
String formatShieldTime(DateTime? time) {
  if (time == null) return '';
  final DateTime now = DateTime.now();
  final Duration diff = now.difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  final String day = time.day.toString().padLeft(2, '0');
  final String month = time.month.toString().padLeft(2, '0');
  return '$day/$month/${time.year}';
}
