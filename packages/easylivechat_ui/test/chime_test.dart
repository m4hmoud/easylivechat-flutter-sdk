import 'package:easylivechat_ui/src/chime.dart';
import 'package:easylivechat/easylivechat.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _message(SenderType from) => ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      body: 'hello',
      senderType: from,
      contentType: MessageContentType.text,
      createdAt: DateTime.utc(2026, 8, 10),
    );

void main() {
  group('ElcChime.shouldChime', () {
    test('rings for an agent reply', () {
      expect(
        ElcChime.shouldChime(_message(SenderType.agent), soundEnabled: true),
        isTrue,
      );
    });

    test('stays silent for the visitor\'s own message', () {
      // The socket echoes our sends back; chiming at yourself is noise.
      expect(
        ElcChime.shouldChime(_message(SenderType.customer), soundEnabled: true),
        isFalse,
      );
    });

    test('stays silent for bot and system rows', () {
      // Auto-greetings and "transferred to X" notices are not someone
      // reaching the visitor — the web widget ignores them too.
      for (final from in [
        SenderType.bot,
        SenderType.system,
        SenderType.unknown
      ]) {
        expect(
          ElcChime.shouldChime(_message(from), soundEnabled: true),
          isFalse,
          reason: 'should not chime for $from',
        );
      }
    });

    test('obeys the workspace turning sound off', () {
      expect(
        ElcChime.shouldChime(_message(SenderType.agent), soundEnabled: false),
        isFalse,
      );
    });
  });
}
