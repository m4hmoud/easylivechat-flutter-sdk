import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

/// The waveform on the recording bar.
///
/// These bars are REAL: they are the microphone's own amplitudes, sampled as
/// the take is made. (The thread's tile cannot do this for a note it merely
/// received — measuring that means decoding it — so the two look alike and
/// only one of them is a measurement.)
///
/// Two ways of drawing the same levels:
///
///  - **recording** — a fixed bar pitch scrolling past at a steady rate, the
///    newest at the trailing edge. Bars never change width as the take grows,
///    and the run slides a fraction of a pitch every frame rather than
///    jumping a whole one each sample, so it reads as motion instead of a
///    stutter.
///  - **paused** — the WHOLE take fitted to the width, averaged down into as
///    many bars as fit, with everything past the playhead dimmed. Nothing
///    moves; the playhead does.
class VoiceLevels extends StatefulWidget {
  final ValueListenable<List<double>> levels;
  final double fraction;
  final Color color;

  /// Seek, when there is something to seek through. Null while recording:
  /// there is nothing to scrub in audio that has not been captured yet.
  final ValueChanged<double>? onSeek;

  /// How often a level arrives — the distance the run travels per sample.
  final Duration interval;

  const VoiceLevels({
    super.key,
    required this.levels,
    required this.fraction,
    required this.color,
    required this.interval,
    this.onSeek,
  });

  @override
  State<VoiceLevels> createState() => _VoiceLevelsState();
}

class _VoiceLevelsState extends State<VoiceLevels>
    with SingleTickerProviderStateMixin {
  static const double _barWidth = 3;
  static const double _gap = 1.6;
  static const double _pitch = _barWidth + _gap;

  late final Ticker _ticker;
  int _count = 0;
  Duration _sinceSample = Duration.zero;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.levels.addListener(_onLevels);
    _count = widget.levels.value.length;
    // Driven by the vsync rather than a Timer: the offset has to be right for
    // the frame being painted, not for whenever a timer last fired.
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    widget.levels.removeListener(_onLevels);
    _ticker.dispose();
    super.dispose();
  }

  void _onLevels() {
    final next = widget.levels.value.length;
    // A new sample resets the travel; the run has just moved one whole pitch.
    if (next != _count) _sinceSample = Duration.zero;
    _count = next;
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    if (widget.onSeek != null) return; // paused: nothing is scrolling
    setState(() => _sinceSample += delta);
  }

  /// Average [levels] down to [target] bars, so a whole take fits the width.
  static List<double> _fit(List<double> levels, int target) {
    if (target <= 0) return const [];
    if (levels.length <= target) return levels;
    final out = <double>[];
    for (var i = 0; i < target; i++) {
      final from = (levels.length * i) ~/ target;
      final to = (levels.length * (i + 1)) ~/ target;
      var sum = 0.0;
      for (var j = from; j < to; j++) {
        sum += levels[j];
      }
      out.add(to > from ? sum / (to - from) : 0);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<double>>(
      valueListenable: widget.levels,
      builder: (context, levels, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final slots = (width / _pitch).floor().clamp(1, 512);
            final rtl = Directionality.of(context) == TextDirection.rtl;
            final reviewing = widget.onSeek != null;

            // Paused: the whole take, fitted. Recording: only what fits, plus
            // one extra so the run has something to slide in from.
            final visible = reviewing
                ? _fit(levels, slots)
                : levels.length <= slots + 1
                    ? levels
                    : levels.sublist(levels.length - slots - 1);

            // How far between samples we are, 0..1 — the fraction of a pitch
            // the run has travelled since the last bar arrived.
            final t = reviewing || widget.interval.inMicroseconds <= 0
                ? 0.0
                : (_sinceSample.inMicroseconds / widget.interval.inMicroseconds)
                    .clamp(0.0, 1.0);
            // Only slide once the run is long enough to be scrolling at all.
            final sliding = !reviewing && levels.length > slots;
            final dx = sliding ? -_pitch * t : 0.0;

            final row = Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < visible.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                    child: SizedBox(
                      width: _barWidth,
                      // A floor of 3px: silence is a line of dots, not a gap.
                      height: 3 + visible[i].clamp(0.0, 1.0) * 21,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: !reviewing ||
                                  (i + 0.5) / visible.length <= widget.fraction
                              ? widget.color
                              : widget.color.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(_barWidth / 2),
                        ),
                      ),
                    ),
                  ),
              ],
            );

            // The run is DELIBERATELY wider than the box — it carries one
            // spare bar to slide in from, and while scrolling it is longer
            // than the window by design. A Row cannot be told that: it
            // reports a flex overflow and paints the yellow bars over the
            // waveform. So the run is laid out at its own width inside an
            // OverflowBox, anchored to the trailing edge where the newest
            // bar lives, and clipped to the window.
            final runWidth = visible.length * _pitch;
            final wave = ClipRect(
              child: SizedBox(
                height: 28,
                width: width,
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerEnd,
                  minWidth: 0,
                  maxWidth: runWidth > width ? runWidth : width,
                  child: Transform.translate(
                    // Physical, because it mirrors the Row that already
                    // mirrored itself.
                    offset: Offset(rtl ? -dx : dx, 0),
                    child: SizedBox(width: runWidth, child: row),
                  ),
                ),
              ),
            );

            final seek = widget.onSeek;
            if (seek == null) return wave;
            double fractionFor(double x) =>
                ((rtl ? width - x : x) / (width <= 0 ? 1 : width))
                    .clamp(0.0, 1.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => seek(fractionFor(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) =>
                  seek(fractionFor(d.localPosition.dx)),
              child: wave,
            );
          },
        );
      },
    );
  }
}
