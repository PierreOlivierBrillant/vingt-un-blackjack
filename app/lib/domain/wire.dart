/// Tolerant readers for Firestore maps / callable responses. Every `fromDoc`
/// parser uses these so a missing or mistyped field falls back to a safe
/// value instead of throwing.
library;

T? enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

int asInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
int? asIntOrNull(Object? v) => v is num ? v.toInt() : null;
double asDouble(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;
bool asBool(Object? v) => v == true;
String? asString(Object? v) => v is String ? v : null;
List<Object?> asList(Object? v) => v is List ? v.cast<Object?>() : const [];
List<String> asStringList(Object? v) => [for (final x in asList(v)) if (x is String) x];
Map<String, Object?> asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val as Object?)) : const {};

/// Epoch-ms integer → local [DateTime] (null when absent).
DateTime? asTime(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

final epoch0 = DateTime.fromMillisecondsSinceEpoch(0);
DateTime asTimeOr0(Object? v) => asTime(v) ?? epoch0;

/// UTC day id "YYYY-MM-DD" (wallet daily cap, ads).
String utcDayId(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}

/// Local calendar date → "YYYY-MM-DD" (KYC birth date; no time zone shift).
String calendarDateId(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// ISO-8601 week id "YYYY-Www" (UTC) — exact port of `weekId` in
/// `firebase/functions/src/shared/time.ts` (weekly leaderboard key).
String isoWeekId(DateTime t) {
  final u = t.toUtc();
  var date = DateTime.utc(u.year, u.month, u.day);
  final dow = date.weekday; // Mon=1..Sun=7
  date = date.add(Duration(days: 4 - dow)); // Thursday of this week
  final yearStart = DateTime.utc(date.year);
  final week = ((date.difference(yearStart).inDays + 1) / 7).ceil();
  return '${date.year}-W${week.toString().padLeft(2, '0')}';
}
