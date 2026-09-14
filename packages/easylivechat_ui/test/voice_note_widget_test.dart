import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:easylivechat_ui/src/views/voice_note_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A voice note is something you listen to.
///
/// The SDK could record and send them from 0.1.66, but the thread rendered
/// what came back through the generic attachment path: the visitor's own
/// recording appeared as a uuid with a download arrow beside it, and hearing
/// it meant saving a file and leaving the chat. `_richTile` special-cased
/// images and nothing else, so every other kind fell through to the chip.
void main() {
  // The attachment path resolves urls through the client. boot() only touches
  // storage — the default is in-memory — so this stays offline.
  setUpAll(() async {
    await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
      apiBase: 'https://api.example.com',
      tenantSlug: 'acme',
    ));
  });

  tearDownAll(() => EasyLiveChat.instance.shutdown());

  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF3F4F6),
    text: Color(0xFF111827),
  );

  ChatMessage message({
    List<String> urls = const [],
    List<RehostedAttachment> rich = const [],
  }) =>
      ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        body: '',
        senderType: SenderType.customer,
        contentType: MessageContentType.audio,
        attachmentUrls: urls,
        attachments: rich,
        createdAt: DateTime.utc(2026, 9, 14, 15, 50),
      );

  Future<void> pump(WidgetTester tester, ChatMessage m,
      {TextDirection direction = TextDirection.ltr}) async {
    ElcStrings.setLocale('en');
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: MessageBubble(
            message: m,
            theme: theme,
            showAgentName: false,
            strings: ElcStrings.of('en'),
          ),
        ),
      ),
    ));
  }

  testWidgets('a sent voice note plays instead of offering a download',
      (tester) async {
    // Exactly what the composer produces: uploadBytes returns a uuid path and
    // sendMessage puts it in the flat url list, with no rich attachment.
    await pump(
      tester,
      message(urls: const ['/uploads/t1/2026-09/15ff7ad3-c699-4bbe.m4a']),
    );

    expect(find.byType(ElcVoiceNoteTile), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // The download chip is what the bug looked like.
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNothing);
  });

  testWidgets('the rehosted attachment plays on its kind, not its extension',
      (tester) async {
    // `kind` comes from the mime type, so it catches a container this end has
    // never heard of — here a url with no extension at all.
    await pump(
      tester,
      message(rich: const [
        RehostedAttachment(
          url: '/uploads/t1/2026-09/15ff7ad3',
          mime: 'audio/mp4',
          kind: AttachmentKind.audio,
        ),
      ]),
    );

    expect(find.byType(ElcVoiceNoteTile), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
  });

  testWidgets('every container the API accepts for audio plays', (tester) async {
    for (final ext in ['m4a', 'mp3', 'ogg', 'oga', 'opus', 'aac', 'amr', 'wav']) {
      await pump(tester, message(urls: ['/uploads/t1/2026-09/note.$ext']));
      expect(find.byType(ElcVoiceNoteTile), findsOneWidget,
          reason: '.$ext should play');
    }
  });

  testWidgets('a real file still gets its download chip', (tester) async {
    await pump(tester, message(urls: const ['/uploads/t1/2026-09/invoice.pdf']));

    expect(find.byType(ElcVoiceNoteTile), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('a .webm is a video, and stays a chip', (tester) async {
    // adapters/media-out.ts classifies .webm as video and the API rewraps a
    // browser-recorded audio .webm to .ogg on upload, so one arriving with
    // that extension really is a video. An audio-only one still plays — it
    // comes through the rich path carrying kind: audio.
    await pump(tester, message(urls: const ['/uploads/t1/2026-09/clip.webm']));

    expect(find.byType(ElcVoiceNoteTile), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets('a placeholder url is never mistaken for playable audio',
      (tester) async {
    await pump(tester, message(urls: const ['wa:media:1234']));

    expect(find.byType(ElcVoiceNoteTile), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('the tile lays out in RTL without overflowing', (tester) async {
    // Kurdish and Arabic workspaces are the ones that reported this, and the
    // bubble is the narrowest place the tile has to fit.
    await pump(
      tester,
      message(urls: const ['/uploads/t1/2026-09/15ff7ad3.m4a']),
      direction: TextDirection.rtl,
    );

    expect(find.byType(ElcVoiceNoteTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing is fetched until play is pressed', (tester) async {
    // A thread of twenty notes must not pull twenty audio files just to print
    // their lengths, so the tile names itself until it has been played once.
    await pump(tester, message(urls: const ['/uploads/t1/2026-09/note.m4a']));

    expect(find.text('Voice message'), findsOneWidget);
  });
}
