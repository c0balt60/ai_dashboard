/// Encoding helpers shared by the models' `toJson`/`fromJson`.
///
/// Instants travel as UTC ISO-8601 and come back in local time. Whole-day
/// dates travel as `yyyy-mm-dd` so they stay on the same calendar day in any
/// timezone.
library;

typedef Json = Map<String, Object?>;

String encodeTime(DateTime t) => t.toUtc().toIso8601String();

DateTime decodeTime(Object? v) => DateTime.parse(v as String).toLocal();

DateTime? decodeTimeOrNull(Object? v) => v == null ? null : decodeTime(v);

String encodeDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? decodeDayOrNull(Object? v) {
  if (v == null) return null;
  final [y, m, d] = (v as String).split('-').map(int.parse).toList();
  return DateTime(y, m, d);
}

List<String> decodeStrings(Object? v) => [
  for (final s in v as List? ?? const []) s as String,
];

List<T> decodeList<T>(Object? v, T Function(Json) decode) => [
  for (final e in v as List? ?? const []) decode(e as Json),
];
