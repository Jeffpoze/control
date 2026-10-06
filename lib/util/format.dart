import 'package:intl/intl.dart';

double asDouble(Object? v) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s.trim()) ?? 0,
  _ => 0,
};

int asInt(Object? v) => switch (v) {
  int n => n,
  num n => n.round(),
  String s => int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.round() ?? 0,
  _ => 0,
};

/// 1536 → "1.5 KB". Binary units, as download clients use.
String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final d = unit == 0 ? 0 : (value >= 100 ? 0 : decimals);
  return '${value.toStringAsFixed(d)} ${units[unit]}';
}

String formatSpeed(num bytesPerSecond) =>
    bytesPerSecond <= 0 ? '0 KB/s' : '${formatBytes(bytesPerSecond)}/s';

/// 3725 s → "1h 2m". Null or negative → "".
String formatEta(Duration? d) {
  if (d == null || d.isNegative) return '';
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// SABnzbd time left: "0:12:05" or "1:02:03:04" (days:h:m:s).
Duration? parseClockDuration(String? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':').map((p) => int.tryParse(p)).toList();
  if (parts.any((p) => p == null)) return null;
  final n = parts.cast<int>();
  return switch (n.length) {
    4 => Duration(days: n[0], hours: n[1], minutes: n[2], seconds: n[3]),
    3 => Duration(hours: n[0], minutes: n[1], seconds: n[2]),
    2 => Duration(minutes: n[0], seconds: n[1]),
    _ => null,
  };
}

/// "Today", "Tomorrow", "Yesterday" or "Mon 12 Oct".
String formatDay(DateTime day, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final d = _dateOnly(day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat('EEE d MMM').format(d);
}

/// "3m ago", "5h ago", "2d ago", or a date.
String formatAgo(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('d MMM y').format(t);
}

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime? parseDate(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
