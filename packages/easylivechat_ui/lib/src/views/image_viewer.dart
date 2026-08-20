import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// Full-screen viewer for one chat picture: pinch to zoom, drag to pan,
/// double-tap to toggle, tap the backdrop or the × to leave.
///
/// The thread renders attachments at `BoxFit.cover` inside a 240×220 tile,
/// which is a thumbnail however you look at it — a screenshot of an error
/// message, the photo of a receipt, anything a support conversation is
/// actually about was unreadable and there was no way to enlarge it. This is
/// where the full picture lives.
///
/// It is a ROUTE, not an overlay, so the visitor's back gesture closes the
/// picture and only the picture — an overlay would have taken the whole chat
/// with it. Deliberately no [Hero]: the tile is a cropped `cover` and this is a
/// letterboxed `contain`, so a flight between them animates through an aspect
/// ratio neither end actually has, and a shared tag would have to stay unique
/// across a thread that can hold the same image twice.
class ElcImageViewer extends StatefulWidget {
  /// Already-resolved provider — the caller decides between a cached network
  /// image (thread) and the local bytes it just read (composer preview).
  final ImageProvider image;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  const ElcImageViewer({
    super.key,
    required this.image,
    required this.theme,
    required this.strings,
  });

  /// Push the viewer over the chat. Fades in; the route below stays mounted so
  /// the thread is still there, unrebuilt, when it closes.
  static Future<void> show(
    BuildContext context, {
    required ImageProvider image,
    required EasyLiveChatTheme theme,
    required ElcStrings strings,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, __, ___) =>
            ElcImageViewer(image: image, theme: theme, strings: strings),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ElcImageViewer> createState() => _ElcImageViewerState();
}

class _ElcImageViewerState extends State<ElcImageViewer>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 6.0;
  static const double _doubleTapScale = 2.5;

  /// Anything above this counts as zoomed — floating-point scale never returns
  /// to exactly 1.0 after a pinch.
  static const double _zoomedAbove = 1.05;

  final TransformationController _transform = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<Matrix4>? _zoomTween;

  /// Where the second tap landed, in viewport coordinates — a double-tap zooms
  /// toward the thing that was tapped, not the middle of the screen.
  Offset? _doubleTapPoint;

  @override
  void initState() {
    super.initState();
    _zoomAnim.addListener(() {
      final m = _zoomTween?.value;
      if (m != null) _transform.value = m;
    });
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  bool get _isZoomed => _scale > _zoomedAbove;

  /// Scale [s] about [focal], as a column-major matrix.
  ///
  /// Written out rather than `Matrix4.identity()..translate()..scale()` so the
  /// package keeps compiling against the vector_math that ships with its
  /// Flutter floor (3.27), where those helpers have since been reshuffled.
  static Matrix4 _scaledAbout(double s, Offset focal) => Matrix4(
        s, 0, 0, 0, //
        0, s, 0, 0, //
        0, 0, 1, 0, //
        -focal.dx * (s - 1), -focal.dy * (s - 1), 0, 1,
      );

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic),
    );
    _zoomAnim.forward(from: 0);
  }

  void _onDoubleTap() {
    if (_isZoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    _animateTo(
      _scaledAbout(_doubleTapScale, _doubleTapPoint ?? Offset.zero),
    );
  }

  void _onTap() {
    // While zoomed a tap is how a pan ends, not how the visitor leaves —
    // dismissing there would throw away the very thing they zoomed in to read.
    // The × stays live at every scale.
    if (_isZoomed) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: widget.theme.direction,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: _interactive()),
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + 4,
              end: 4,
              child: _closeButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _interactive() {
    return GestureDetector(
      // Opaque so the taps land on the black around a letterboxed photo too.
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      onDoubleTapDown: (d) => _doubleTapPoint = d.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: _maxScale,
        // The child fills the viewport (the picture letterboxes itself inside
        // it), which is what keeps panning bounded to what is on screen —
        // sized to the image instead, a portrait photo could be dragged off
        // into empty space.
        child: SizedBox.expand(child: _image()),
      ),
    );
  }

  Widget _image() {
    return Image(
      image: widget.image,
      fit: BoxFit.contain,
      // No cacheWidth/ResizeImage here on purpose: this IS the full-size view,
      // and a downsampled decode would zoom into mush.
      filterQuality: FilterQuality.medium,
      semanticLabel: widget.strings.image,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
          ),
        );
      },
      // A blocked or expired URL must not leave a black void with no way to
      // tell what happened.
      errorBuilder: (context, _, __) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 40, color: Colors.white54),
            const SizedBox(height: 10),
            Text(
              widget.strings.mediaUnavailable,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closeButton() {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        tooltip: widget.strings.close,
        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
