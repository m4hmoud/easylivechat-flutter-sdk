import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/reactions_view.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reactions in the thread (C1), as the web widget draws them
/// (apps/widget/src/components/Reactions.tsx).
///
/// What is pinned: chips under a bubble show the visitor's own reaction on
/// the team's messages and the team's on theirs, never a name; the visitor's
/// own chip takes it back; a long press — or the screen reader's "React"
/// action — on one of the team's messages opens the quick row, and the same
/// emoji again takes the reaction back; the + opens the whole picker; the
/// visitor's own messages and a chat that cannot react open nothing.
void main() {
  setUpAll(() async {
    await EasyLiveChat.instance.boot(const EasyLiveChatConfig(
      apiBase: 'https://api.example.com',
      tenantSlug: 'acme',
    ));
  });

  tearDownAll(() => EasyLiveChat.instance.shutdown());

  setUp(() {
    ElcStrings.overrideAll(const {});
    ElcStrings.overrideByLocale(const {});
    ElcStrings.setLocale('en');
    elcRecentEmoji = [];
  });

  const theme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF1F5F9),
    text: Color(0xFF0F172A),
  );

  ChatMessage message({
    String id = 'a1',
    SenderType from = SenderType.agent,
    List<MessageReaction>? reactions,
  }) =>
      ChatMessage(
        id: id,
        conversationId: 'c1',
        body: 'Your order ships Monday.',
        senderType: from,
        contentType: MessageContentType.text,
        createdAt: DateTime.utc(2026, 10, 18, 9),
        reactions: reactions,
      );

  Future<void> pump(WidgetTester tester, ChatMessage m,
      {void Function(String?)? onReact,
      TextDirection direction = TextDirection.ltr}) {
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: m,
              theme: theme,
              showAgentName: false,
              showAgentAvatar: false,
              strings: ElcStrings.of('en'),
              onReact: onReact,
            ),
          ),
        ),
      ),
    ));
  }

  group('chips', () {
    testWidgets("the visitor's own on the team's message takes it back",
        (tester) async {
      final calls = <String?>[];
      await pump(
        tester,
        message(reactions: const [
          MessageReaction(emoji: '👍', by: ReactionBy.customer),
        ]),
        onReact: calls.add,
      );

      expect(find.text('👍'), findsOneWidget);
      expect(find.bySemanticsLabel('Your reaction: 👍'), findsOneWidget);

      await tester.tap(find.text('👍'));
      expect(calls, [null]);
    });

    testWidgets("the team's on the visitor's message, by no name, at its edge",
        (tester) async {
      final calls = <String?>[];
      await pump(
        tester,
        message(from: SenderType.customer, reactions: const [
          MessageReaction(emoji: '❤️', by: ReactionBy.agent),
          MessageReaction(emoji: '❤', by: ReactionBy.agent),
          MessageReaction(emoji: '🙏', by: ReactionBy.agent),
        ]),
        onReact: calls.add,
      );

      // ❤ and ❤️ are one chip, with its count.
      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(
          find.bySemanticsLabel('The team reacted with ❤️'), findsOneWidget);
      // A label, not a button: the team's reaction is not the visitor's to
      // take back.
      await tester.tap(find.text('🙏'));
      expect(calls, isEmpty);
      // On the visitor's side of the thread.
      final chip = tester.getTopRight(find.text('🙏'));
      final bubble = tester.getTopRight(find.text('Your order ships Monday.'));
      expect(chip.dx, closeTo(bubble.dx, 24));
    });

    testWidgets('none, nothing drawn', (tester) async {
      await pump(tester, message(), onReact: (_) {});
      expect(find.byType(ElcReactionChips), findsOneWidget);
      expect(find.text('👍'), findsNothing);
    });
  });

  group('the quick row', () {
    testWidgets("a long press on the team's message opens it; a pick reacts",
        (tester) async {
      final calls = <String?>[];
      await pump(tester, message(), onReact: calls.add);

      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();

      for (final emoji in quickReactions) {
        expect(find.text(emoji), findsOneWidget);
      }
      expect(find.byTooltip('More reactions'), findsOneWidget);
      // Under the bubble, so the message pressed stays where it was.
      expect(
        tester.getTopLeft(find.byType(ElcQuickReactions)).dy,
        greaterThan(
            tester.getBottomLeft(find.text('Your order ships Monday.')).dy),
      );

      await tester.tap(find.text('😂'));
      await tester.pump();
      expect(calls, ['😂']);
      // And it closes.
      expect(find.text('😮'), findsNothing);
    });

    testWidgets('the same emoji again takes it back', (tester) async {
      final calls = <String?>[];
      await pump(
        tester,
        message(reactions: const [
          MessageReaction(emoji: '❤', by: ReactionBy.customer),
        ]),
        onReact: calls.add,
      );
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();
      await tester.tap(find.text('❤️').first);
      expect(calls, [null]);
    });

    testWidgets('the screen reader has a React action in place of the press',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, message(), onReact: (_) {});

      final node = tester.getSemantics(find.text('Your order ships Monday.'));
      final owner = tester
          .renderObject(find.text('Your order ships Monday.'))
          .owner!
          .semanticsOwner!;
      final action = CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'React'));
      owner.performAction(node.id, SemanticsAction.customAction, action);
      await tester.pump();

      expect(find.text('🙏'), findsOneWidget);
      handle.dispose();
    });

    testWidgets("never on the visitor's own message", (tester) async {
      await pump(tester, message(from: SenderType.customer), onReact: (_) {});
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();
      expect(find.text('👍'), findsNothing);
    });

    testWidgets('never while the chat cannot react', (tester) async {
      await pump(tester, message());
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();
      expect(find.text('👍'), findsNothing);
    });

    testWidgets('opens on the leading side in RTL', (tester) async {
      await pump(tester, message(),
          onReact: (_) {}, direction: TextDirection.rtl);
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();
      final row = tester.getTopRight(find.byType(ElcQuickReactions));
      final bubble = tester.getTopRight(find.text('Your order ships Monday.'));
      // The team's side is the right in Arabic, Kurdish and Urdu.
      expect(row.dx, closeTo(bubble.dx, 24));
    });
  });

  group('in the thread', () {
    testWidgets('reacting needs a live connection; the chips follow live',
        (tester) async {
      final handle = tester.ensureSemantics();
      final messages =
          EasyLiveChat.instance.messages as ValueNotifier<List<ChatMessage>>;
      final connection =
          EasyLiveChat.instance.connection as ValueNotifier<ConnectionState>;
      addTearDown(() {
        messages.value = const [];
        connection.value = ConnectionState.disconnected;
      });
      messages.value = [message()];
      connection.value = ConnectionState.disconnected;

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ThreadView(theme: theme)),
      ));
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();
      expect(find.byType(ElcQuickReactions), findsNothing);

      connection.value = ConnectionState.connected;
      await tester.pump();
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();
      expect(find.byType(ElcQuickReactions), findsOneWidget);

      // What `message:reactions` (or the ack) does to the thread.
      messages.value = [
        message(reactions: const [
          MessageReaction(emoji: '🙏', by: ReactionBy.customer),
        ]),
      ];
      await tester.pump();
      expect(find.bySemanticsLabel('Your reaction: 🙏'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the whole picker', () {
    testWidgets('the + opens it; an emoji from it reacts and is remembered',
        (tester) async {
      final calls = <String?>[];
      await pump(tester, message(), onReact: calls.add);
      await tester.longPress(find.text('Your order ships Monday.'));
      await tester.pump();

      await tester.tap(find.byTooltip('More reactions'));
      await tester.pumpAndSettle();

      expect(find.byType(ElcEmojiPicker), findsOneWidget);
      expect(find.byTooltip('Smileys & emotion'), findsOneWidget);
      expect(find.byTooltip('Flags'), findsOneWidget);
      // Nothing used yet: no recent tab.
      expect(find.byTooltip('Recently used'), findsNothing);

      // The grid's, not the tab that stands for the category.
      await tester.tap(find.text('😀').last);
      await tester.pumpAndSettle();
      expect(find.byType(ElcEmojiPicker), findsNothing);
      expect(calls, ['😀']);
      expect(elcRecentEmoji, ['😀']);
    });

    testWidgets('a tab jumps to its section; recent ones come first',
        (tester) async {
      elcRecentEmoji = ['🦄'];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: ElcEmojiPicker(
              theme: theme,
              strings: ElcStrings.of('en'),
              onPick: (_) {},
            ),
          ),
        ),
      ));

      expect(find.text('Recently used'), findsOneWidget);
      expect(find.text('🦄'), findsOneWidget);

      await tester.tap(find.byTooltip('Flags'));
      await tester.pump();
      expect(find.text('Flags'), findsOneWidget);
      expect(find.text('🏁'), findsWidgets);
    });

    testWidgets('its words are the visitor\'s language', (tester) async {
      ElcStrings.setLocale(null);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 360,
            child: ElcEmojiPicker(
              theme: theme,
              strings: ElcStrings.of('ar'),
              onPick: (_) {},
            ),
          ),
        ),
      ));
      expect(find.text('الوجوه والمشاعر'), findsOneWidget);
    });
  });
}
