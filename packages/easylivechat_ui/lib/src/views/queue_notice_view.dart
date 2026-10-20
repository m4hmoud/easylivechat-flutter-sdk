import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import '../bidi.dart';
import '../l10n.dart';
import '../theme.dart';

/// The notice above the conversation while the visitor waits for a person —
/// the web widget's `QueueView`: "Queue", the workspace's own words (their
/// name and place already filled in by the server), and the place and the
/// expected wait.
///
/// A notice, not a screen: the visitor can read what has been said and write
/// their question while they wait. It goes the moment somebody is there
/// (`EasyLiveChat.queue` turns null).
class ElcQueueNotice extends StatelessWidget {
  final QueueStatus status;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  const ElcQueueNotice({
    super.key,
    required this.status,
    required this.theme,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final muted = t.text.withValues(alpha: t.isDark ? 0.72 : 0.62);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(t.text.withValues(alpha: 0.04), t.background),
          border: Border(
            bottom: BorderSide(color: t.text.withValues(alpha: 0.12)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.queueKicker,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: muted),
            ),
            if (status.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  status.text,
                  textAlign: TextAlign.center,
                  // The workspace's words face the way they are written.
                  textDirection: textDirectionOf(status.text),
                  style:
                      TextStyle(fontSize: 13.5, height: 1.5, color: t.text),
                ),
              ),
            ],
            if (status.position > 0) ...[
              const SizedBox(height: 4),
              Text(
                strings.queueWait
                    .replaceAll('{position}', '${status.position}')
                    .replaceAll('{minutes}', '${status.minutes}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
