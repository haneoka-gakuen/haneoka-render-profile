import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/services.dart';
import 'package:render_contracts/render_contracts.dart';

import 'asset_paths.dart';

/// The selected visual theme owns its authored resources independently of the
/// story, song or provider that is being presented.
final class HaneokaProfileAssets {
  HaneokaProfileAssets._(this._document, this.manifestSHA256);

  final Map<String, Object?> _document;
  final String manifestSHA256;
  final _verified = <String>{};
  final _checking = <String, Future<String?>>{};
  String get id => _document['id'] as String;
  String get version => _document['version'] as String;
  Map get _numericTextures => _document['numericTextures'] as Map;

  TextureChannel fontCoverageChannel(Iterable<String> atlases) =>
      atlases.every(_numericTextures.containsKey)
      ? TextureChannel.red
      : TextureChannel.alpha;

  Future<TextureData?> loadTexture(Uri uri) async {
    if (uri.scheme != 'haneoka-asset') return null;
    final descriptor = _numericTextures[uri.path];
    if (descriptor is! Map) return null;
    final bytes = await load(descriptor['asset'] as String);
    final decoded = await compute(_decodeCoverage, (
      bytes: bytes,
      expectedBytes: descriptor['decodedBytes'] as int,
      hash: descriptor['decodedSHA256'] as String,
    ), debugLabel: 'SDF coverage ${uri.path}');
    return TextureData(
      width: descriptor['width'] as int,
      height: descriptor['height'] as int,
      rgba: decoded,
      format: TexelFormat.r8,
      alpha: TextureAlpha.independent,
    );
  }

  Map get packetSource => Map.unmodifiable(_document['packetSource'] as Map);
  static Future<HaneokaProfileAssets>? _opening;
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  static Future<HaneokaProfileAssets> open() async {
    final pending = _opening ??= _open();
    try {
      return await pending;
    } catch (_) {
      if (identical(_opening, pending)) _opening = null;
      rethrow;
    }
  }

  static Future<HaneokaProfileAssets> _open() async {
    final data = await rootBundle.load(
      '${haneokaProfileAssetRoot}manifest.json',
    );
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final packet = Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    if (packet['schema'] != 'haneoka-render-profile-manifest-v1' ||
        packet['id'] is! String ||
        (packet['id'] as String).isEmpty ||
        packet['version'] is! String ||
        (packet['version'] as String).isEmpty ||
        packet['files'] is! Map ||
        packet['capabilities'] is! List ||
        packet['packetSource'] is! Map) {
      throw const FormatException('render_profile_manifest');
    }
    for (final key in ['server', 'sourceId', 'releaseId']) {
      final value = (packet['packetSource'] as Map)[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('render_profile_packet_source:$key');
      }
    }
    for (final entry in (packet['files'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String ||
          !(entry.key as String).startsWith(
            'packages/haneoka_render_profile_flutter/',
          ) ||
          (entry.key as String).split('/').contains('..') ||
          value is! Map ||
          value['sha256'] is! String ||
          !_sha256.hasMatch(value['sha256'] as String) ||
          value['bytes'] is! int ||
          (value['bytes'] as int) < 0) {
        throw FormatException('render_profile_asset_manifest:${entry.key}');
      }
    }
    return HaneokaProfileAssets._(
      Map.unmodifiable(packet),
      sha256.convert(bytes).toString(),
    );
  }

  void requireCapability(String value) {
    if (!(_document['capabilities'] as List).contains(value)) {
      throw UnsupportedError('render_profile_capability:$value');
    }
  }

  Future<({ByteData data, String? text})> _read(
    String assetKey, {
    required bool decode,
  }) async {
    final expected = (_document['files'] as Map)[assetKey];
    if (expected is! Map) {
      throw FormatException('render_profile_asset_undeclared:$assetKey');
    }
    final data = await rootBundle.load(assetKey);
    if (data.lengthInBytes != expected['bytes']) {
      throw FormatException('render_profile_asset_integrity:$assetKey');
    }
    final verified = _verified.contains(assetKey);
    if (verified && !decode) return (data: data, text: null);
    final pending = _checking[assetKey];
    if (pending != null) {
      final text = await pending;
      return (
        data: data,
        text: decode && text == null
            ? await _processProfileAsset((
                data: data,
                key: assetKey,
                hash: expected['sha256'] as String,
                verify: false,
                decode: true,
              ))
            : text,
      );
    }
    final work = _processProfileAsset((
      data: data,
      key: assetKey,
      hash: expected['sha256'] as String,
      verify: !verified,
      decode: decode,
    ));
    _checking[assetKey] = work;
    try {
      final text = await work;
      _verified.add(assetKey);
      return (data: data, text: text);
    } finally {
      if (identical(_checking[assetKey], work)) _checking.remove(assetKey);
    }
  }

  Future<ByteData> load(String assetKey) async =>
      (await _read(assetKey, decode: false)).data;

  Future<String> loadString(String assetKey) async =>
      (await _read(assetKey, decode: true)).text!;

  /// Returns a fresh packet after the shared asset integrity check. Large JSON
  /// packets are decoded off the UI isolate, with the verified source hash.
  Future<({Map<String, Object?> data, String sha256})> loadJson(
    String assetKey,
  ) async {
    final text = await loadString(assetKey);
    final expected = (_document['files'] as Map)[assetKey] as Map;
    final data = (expected['bytes'] as int) >= 50 * 1024 && !kIsWeb
        ? await compute(_decodeProfileJson, text, debugLabel: 'JSON $assetKey')
        : _decodeProfileJson(text);
    return (data: data, sha256: expected['sha256'] as String);
  }
}

Map<String, Object?> _decodeProfileJson(String text) =>
    Map<String, Object?>.from(jsonDecode(text) as Map);

Future<ByteData> loadHaneokaProfileAsset(String assetKey) async =>
    (await HaneokaProfileAssets.open()).load(assetKey);

Future<TextureData?> loadHaneokaProfileTexture(Uri uri) async =>
    (await HaneokaProfileAssets.open()).loadTexture(uri);

Uint8List _decodeCoverage(
  ({ByteData bytes, int expectedBytes, String hash}) input,
) {
  final bytes = input.bytes.buffer.asUint8List(
    input.bytes.offsetInBytes,
    input.bytes.lengthInBytes,
  );
  final decoded = GZipDecoder().decodeBytes(bytes);
  if (decoded.length != input.expectedBytes ||
      sha256.convert(decoded).toString() != input.hash) {
    throw const FormatException('render_profile_coverage_integrity');
  }
  return decoded;
}

Future<String> loadHaneokaProfileString(String assetKey) async =>
    (await HaneokaProfileAssets.open()).loadString(assetKey);

typedef _ProfileRead = ({
  ByteData data,
  String key,
  String hash,
  bool verify,
  bool decode,
});

Future<String?> _processProfileAsset(_ProfileRead input) async {
  if (input.data.lengthInBytes >= 50 * 1024 && !kIsWeb) {
    return compute(
      _checkProfileAsset,
      input,
      debugLabel: 'Profile ${input.key}',
    );
  }
  return _checkProfileAsset(input);
}

String? _checkProfileAsset(_ProfileRead input) {
  final bytes = input.data.buffer.asUint8List(
    input.data.offsetInBytes,
    input.data.lengthInBytes,
  );
  if (input.verify && sha256.convert(bytes).toString() != input.hash) {
    throw FormatException('render_profile_asset_integrity:${input.key}');
  }
  return input.decode ? utf8.decode(bytes) : null;
}
