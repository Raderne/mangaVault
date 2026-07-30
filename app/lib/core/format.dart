// Small display formatters shared across screens. Hand-rolled rather than
// pulling in `intl` — the app only ever renders English, thousands-grouped
// integers and coarse relative dates.

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Compact relative date, falling back to an absolute one past a week
/// ("just now", "12m ago", "3d ago", "Jul 28, 2026").
String relativeDate(int millis) {
  if (millis <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Thousands-grouped integer: `1284` → `1,284`.
String groupedNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Short chapter number for tight captions. Mihon chapter numbers are floats
/// that arrive with float32 noise (`0.10000000149…`), so they're rounded to two
/// decimals and whole numbers lose their `.0`. Returns `null` when the chapter
/// is unnumbered (`-1`) and the caller should fall back to its name.
String? chapterNumberLabel(double number) {
  if (number < 0) return null;
  final rounded = (number * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}'
      : '$rounded';
}

/// Human byte size with one decimal above the KB tier: `2411724` → `2.3 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}
