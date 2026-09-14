import 'dart:typed_data';

import 'package:easylivechat_ui/src/views/composer_bar.dart';
import 'package:flutter_test/flutter_test.dart';

/// Listening to a take without ending it.
///
/// A WAV still being recorded carries a header whose two length fields say
/// how much had been written when the file was OPENED — nothing. Players read
/// those, conclude the file is empty and refuse it. The samples after the
/// header are real, so the preview copy rewrites the lengths to match what is
/// actually on disk.
///
/// Getting this wrong is silent: the copy still looks like a wav and simply
/// will not play.
Uint8List wav({
  required int samples,
  int riffLength = 0,
  int dataLength = 0,
  List<int> extraChunk = const [],
}) {
  final body = BytesBuilder();
  body.add('RIFF'.codeUnits);
  body.add(Uint8List(4)..buffer.asByteData().setUint32(0, riffLength, Endian.little));
  body.add('WAVE'.codeUnits);
  body.add('fmt '.codeUnits);
  body.add(Uint8List(4)..buffer.asByteData().setUint32(0, 16, Endian.little));
  body.add(Uint8List(16)); // the format block itself does not matter here
  body.add(extraChunk);
  body.add('data'.codeUnits);
  body.add(Uint8List(4)..buffer.asByteData().setUint32(0, dataLength, Endian.little));
  body.add(Uint8List(samples));
  return body.toBytes();
}

int u32(Uint8List b, int at) => b.buffer.asByteData().getUint32(at, Endian.little);

/// A chunk between `fmt ` and `data`, which recorders do emit.
List<int> listChunk(int size) => [
      ...'LIST'.codeUnits,
      ...(Uint8List(4)..buffer.asByteData().setUint32(0, size, Endian.little)),
      ...Uint8List(size),
    ];

void main() {
  test('writes the real lengths over the zeros a live recording leaves', () {
    final fixed = withRealWavLengths(wav(samples: 3200))!;

    expect(u32(fixed, 4), fixed.length - 8, reason: 'RIFF length');
    final dataAt = fixed.length - 3200 - 8;
    expect(u32(fixed, dataAt + 4), 3200, reason: 'data length');
  });

  test('keeps every sample byte exactly as recorded', () {
    final source = wav(samples: 1024);
    final fixed = withRealWavLengths(source)!;

    expect(fixed.length, source.length);
    expect(fixed.sublist(fixed.length - 1024), source.sublist(source.length - 1024));
  });

  test('finds `data` past a chunk that is not `fmt `', () {
    // Walking a fixed 44-byte header would land in the middle of this one.
    final fixed = withRealWavLengths(wav(samples: 800, extraChunk: listChunk(26)))!;

    final dataAt = fixed.length - 800 - 8;
    expect(u32(fixed, dataAt + 4), 800);
  });

  test('overwrites a stale length rather than trusting it', () {
    // A recorder that wrote a length once, then kept appending.
    final fixed = withRealWavLengths(wav(samples: 4096, dataLength: 64, riffLength: 100))!;

    final dataAt = fixed.length - 4096 - 8;
    expect(u32(fixed, dataAt + 4), 4096);
    expect(u32(fixed, 4), fixed.length - 8);
  });

  test('refuses anything that is not a RIFF/WAVE file', () {
    // Never guess at offsets in a container this did not write.
    expect(withRealWavLengths(Uint8List(0)), isNull);
    expect(withRealWavLengths(Uint8List(200)), isNull);
    final m4a = Uint8List.fromList([...List.filled(4, 0), ...'ftypM4A '.codeUnits, ...List.filled(64, 0)]);
    expect(withRealWavLengths(m4a), isNull);
  });

  test('refuses a header too short to hold a chunk', () {
    expect(withRealWavLengths(Uint8List.fromList('RIFF'.codeUnits)), isNull);
  });

  test('does not loop forever on a zero-sized chunk', () {
    // A corrupt size of 0 would step 8 bytes forever without the guard.
    final broken = Uint8List.fromList([
      ...'RIFF'.codeUnits, 0, 0, 0, 0,
      ...'WAVE'.codeUnits,
      ...'junk'.codeUnits, 0, 0, 0, 0,
      ...List.filled(32, 0),
    ]);
    expect(withRealWavLengths(broken), isNull);
  });
}
