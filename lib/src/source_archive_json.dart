import 'dart:convert';

/// Decodes the Unity archive's legacy IEEE infinity tokens without changing
/// quoted text or finite JSON numbers. Dart preserves overflowing exponents.
Object? decodeUnitySourceArchiveJson(String source) {
  bool whitespace(int c) => c == 32 || c == 9 || c == 10 || c == 13;
  bool before(int i) =>
      i == 0 ||
      whitespace(source.codeUnitAt(i - 1)) ||
      const [58, 44, 91].contains(source.codeUnitAt(i - 1));
  bool after(int i) =>
      i == source.length ||
      whitespace(source.codeUnitAt(i)) ||
      const [44, 93, 125].contains(source.codeUnitAt(i));
  var quoted = false, escaped = false, copied = 0;
  StringBuffer? normalized;
  for (var i = 0; i < source.length; i++) {
    final c = source.codeUnitAt(i);
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == 92) {
        escaped = true;
      } else if (c == 34) {
        quoted = false;
      }
      continue;
    }
    if (c == 34) {
      quoted = true;
      continue;
    }
    final negative = c == 45;
    final token = negative ? '-Infinity' : 'Infinity';
    if ((c != 73 && !negative) ||
        !source.startsWith(token, i) ||
        !before(i) ||
        !after(i + token.length)) {
      continue;
    }
    (normalized ??= StringBuffer())
      ..write(source.substring(copied, i))
      ..write(negative ? '-1e9999' : '1e9999');
    copied = i + token.length;
    i = copied - 1;
  }
  if (normalized == null) return jsonDecode(source);
  normalized.write(source.substring(copied));
  return jsonDecode(normalized.toString());
}
