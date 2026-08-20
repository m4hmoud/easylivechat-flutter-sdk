import 'dart:ui' as ui;

import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/image_viewer.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The full-screen picture view.
///
/// The thread only ever drew attachments as 240×220 cropped tiles, so a
/// screenshot — the thing support conversations are usually about — could not
/// be read and there was no gesture that would enlarge it. What is pinned here
/// is that a tap opens something zoomable, that the zoom actually changes the
/// transform, and that leaving is possible at any scale but never accidental.
void main() {
  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F4F6),
    text: Color(0xFF111827),
  );

  late ui.Image image;

  setUp(() async {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale('en');
    image = await createTestImage(width: 40, height: 30);
  });

  Future<void> open(
    WidgetTester tester, {
    EasyLiveChatTheme t = theme,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ElcImageViewer.show(
              context,
              image: _SyncImage(image),
              theme: t,
              strings: ElcStrings.of('en'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  double scaleOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
  }

  testWidgets('the picture opens into a viewer that can zoom', (tester) async {
    await open(tester);

    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.maxScale, greaterThan(1.0));
    expect(viewer.minScale, 1.0);
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('double-tap zooms in, and again zooms back out', (tester) async {
    await open(tester);

    await doubleTapAt(tester, const Offset(300, 300));
    expect(scaleOf(tester), greaterThan(1.5));

    await doubleTapAt(tester, const Offset(300, 300));
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('double-tap zooms toward the point that was tapped',
      (tester) async {
    await open(tester);
    await doubleTapAt(tester, const Offset(200, 150));

    // The tapped point stays put: with the transform t = -p·(s-1), the point
    // maps back to itself. Anything else means it zoomed to the middle and the
    // detail the visitor aimed at slid off screen.
    final m = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    final s = m.getMaxScaleOnAxis();
    expect(m.storage[12], closeTo(-200 * (s - 1), 0.01));
    expect(m.storage[13], closeTo(-150 * (s - 1), 0.01));
  });

  testWidgets('a tap leaves — but not while zoomed in', (tester) async {
    await open(tester);
    await doubleTapAt(tester, const Offset(300, 300));

    // A tap while zoomed is how a pan ends. Closing there would throw away the
    // very thing the visitor zoomed in to read.
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await doubleTapAt(tester, const Offset(300, 300));
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('the close button works at any zoom', (tester) async {
    await open(tester);
    await doubleTapAt(tester, const Offset(300, 300));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('the close button follows the layout direction', (tester) async {
    await open(tester);
    final ltr = tester.getCenter(find.byIcon(Icons.close_rounded)).dx;

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    await open(
      tester,
      t: const EasyLiveChatTheme(
        primary: Color(0xFF2563EB),
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFF3F4F6),
        text: Color(0xFF111827),
        direction: TextDirection.rtl,
      ),
    );
    final rtl = tester.getCenter(find.byIcon(Icons.close_rounded)).dx;

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(ltr, greaterThan(width / 2));
    expect(rtl, lessThan(width / 2));
  });
}

/// Resolves in one synchronous frame, so `pumpAndSettle` is not left waiting on
/// a decode (and on the spinner the viewer shows meanwhile).
class _SyncImage extends ImageProvider<_SyncImage> {
  final ui.Image image;

  _SyncImage(this.image);

  @override
  Future<_SyncImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_SyncImage>(this);

  @override
  ImageStreamCompleter loadImage(_SyncImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
      );
}
