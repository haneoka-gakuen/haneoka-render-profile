import 'dart:typed_data';

/// Numeric xorshift128 stream with the authored 23-bit inclusive float mapping.
/// The consumer supplies the seed and decides the lifetime of each stream.
final class NativeAuthoredRandom {
  NativeAuthoredRandom(int seed) {
    reseed(seed);
  }

  static const _mask = 0xffffffff;
  int _x = 0, _y = 0, _z = 0, _w = 0;
  final Float32List _scalar = Float32List(1);

  void reseed(int seed) {
    _x = seed & _mask;
    _y = (1812433253 * _x + 1) & _mask;
    _z = (1812433253 * _y + 1) & _mask;
    _w = (1812433253 * _z + 1) & _mask;
  }

  int nextUint32() {
    final t = (_x ^ (_x << 11)) & _mask;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = (_w ^ (_w >> 19) ^ t ^ (t >> 8)) & _mask;
    return _w;
  }

  double nextDouble() {
    _scalar[0] = (nextUint32() & 0x7fffff) / 8388607;
    return _scalar[0];
  }
}
