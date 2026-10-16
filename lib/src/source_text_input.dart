/// TMP's original input preprocessing: Unicode escape decoding precedes
/// optional control-character conversion. Ordinary UTF-16 remains unchanged.
String decodeSourceTmpInput(String source, {required bool parseControls}) {
  if (!source.contains(r'\')) return source;
  final output = StringBuffer();
  for (var index = 0; index < source.length; index++) {
    final code = source.codeUnitAt(index);
    if (code == 0) break;
    if (code == 92 && index + 1 < source.length) {
      final next = source.codeUnitAt(index + 1);
      final digits = next == 117
          ? 4
          : next == 85
          ? 8
          : 0;
      if (digits != 0 && index + digits + 2 <= source.length) {
        final hex = source.substring(index + 2, index + digits + 2);
        if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(hex)) {
          final scalar = int.parse(hex, radix: 16);
          if (scalar <= 0x10ffff) {
            output.writeCharCode(scalar);
            index += digits + 1;
            continue;
          }
        }
      }
      if (parseControls) {
        final replacement = switch (next) {
          110 => 10,
          114 => 13,
          116 => 9,
          118 => 11,
          92 => 92,
          _ => null,
        };
        if (replacement != null) {
          output.writeCharCode(replacement);
          index++;
          continue;
        }
      }
    }
    output.writeCharCode(code);
  }
  return output.toString();
}
