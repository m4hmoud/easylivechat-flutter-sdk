import 'package:easylivechat_ui/src/views/voice_levels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The recording waveform must fit the bar it is drawn in.
///
/// It scrolls, so the run is deliberately WIDER than its window — it carries
/// a spare bar to slide in from. A `Row` cannot be told that: it reported a
/// flex overflow and painted yellow hazard stripes across the composer, on a
/// screen a visitor was looking at.
void main() {
  Widget host({
    required List<double> levels,
    required double width,
    double fraction = 1,
    ValueChanged<double>? onSeek,
    TextDirection direction = TextDirection.ltr,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: VoiceLevels(
                levels: ValueNotifier<List<double>>(levels),
                fraction: fraction,
                color: const Color(0xFF111827),
                interval: const Duration(milliseconds: 60),
                onSeek: onSeek,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<double> levels(int n) =>
      List<double>.generate(n, (i) => (i % 10) / 10 + 0.05);

  testWidgets('a long take does not overflow the bar it scrolls in',
      (tester) async {
    // Five minutes at 60ms is ~5000 levels; the window is a phone composer.
    await tester.pumpWidget(host(levels: levels(5000), width: 180));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  testWidgets('nor at the narrowest width a composer can get', (tester) async {
    await tester.pumpWidget(host(levels: levels(5000), width: 48));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  testWidgets('nor mid-slide, a frame after a new level arrives',
      (tester) async {
    // The overflow only showed while the run was actually travelling.
    await tester.pumpWidget(host(levels: levels(400), width: 200));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('nor in RTL, which is where it was seen', (tester) async {
    await tester.pumpWidget(
      host(levels: levels(5000), width: 180, direction: TextDirection.rtl),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  testWidgets('nor when the whole take is fitted for playback',
      (tester) async {
    // Paused: every level is averaged down to the bars that fit, so this path
    // must not overflow either.
    await tester.pumpWidget(
      host(levels: levels(5000), width: 180, fraction: 0.5, onSeek: (_) {}),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty take draws nothing and survives it', (tester) async {
    await tester.pumpWidget(host(levels: const [], width: 180));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
  });
}
