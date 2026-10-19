import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat_ui/src/l10n.dart';
import 'package:easylivechat_ui/src/theme.dart';
import 'package:easylivechat_ui/src/views/message_card_view.dart';
import 'package:easylivechat_ui/src/views/quick_replies_view.dart';
import 'package:easylivechat_ui/src/views/thread_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reply buttons under a message — a bot's or an agent's — and on cards.
///
/// What is pinned: the buttons draw from their own layer and the bubble shows
/// the message's own words, never ALSO the numbered menu its body carries for
/// older clients (before this the options appeared twice); a tap answers with
/// the button's id; a card's reply button answers too; a carousel draws every
/// card.
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
  });

  const theme = EasyLiveChatTheme(
    primary: Color(0xFF0E7C66),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F0EB),
    text: Color(0xFF1B1B1B),
  );

  const menu = 'Call you?\n\n1. Yes\n2. No\n\nReply with the number of your choice.';

  final asked = ChatMessage(
    id: 'm1',
    conversationId: 'c1',
    body: menu,
    senderType: SenderType.agent,
    contentType: MessageContentType.text,
    createdAt: DateTime.utc(2026, 10, 18, 9),
    metadata: const {
      'bot': {
        'text': 'Call you?',
        'buttons': [
          {'id': 'q_1', 'label': 'Yes'},
          {'id': 'q_2', 'label': 'No'},
        ],
      },
      'quickReplies': ['Yes', 'No'],
    },
  );

  Future<void> pump(WidgetTester tester, Widget bubble) => tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: bubble)),
      ));

  MessageBubble bubble(ChatMessage m,
          {bool showButtons = true, String? chosen, void Function(String, String)? onButton}) =>
      MessageBubble(
        message: m,
        theme: theme,
        showAgentName: false,
        strings: ElcStrings.of('en'),
        showButtons: showButtons,
        chosenButtonId: chosen,
        onButton: onButton,
      );

  testWidgets('draws the words and the buttons — not the numbered menu as well', (tester) async {
    await pump(tester, bubble(asked, onButton: (_, __) {}));
    expect(find.text('Call you?'), findsOneWidget);
    expect(find.textContaining('1. Yes'), findsNothing);
    expect(find.byType(ElcQuickReplies), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
  });

  testWidgets('a tap answers with the button’s id and label', (tester) async {
    final taps = <String>[];
    await pump(tester, bubble(asked, onButton: (id, label) => taps.add('$id:$label')));
    await tester.tap(find.text('No'));
    expect(taps, ['q_2:No']);
  });

  testWidgets('once answered, the choice stays marked and nothing else answers', (tester) async {
    final taps = <String>[];
    await pump(tester, bubble(asked, chosen: 'q_1'));
    expect(tester.widget<ElcQuickReplies>(find.byType(ElcQuickReplies)).chosen, 'Yes');
    await tester.tap(find.text('No'));
    expect(taps, isEmpty);
  });

  testWidgets('without buttons switched on it reads as its text, as an older client does', (tester) async {
    await pump(tester, bubble(asked, showButtons: false));
    expect(find.byType(ElcQuickReplies), findsNothing);
    expect(find.textContaining('1. Yes'), findsOneWidget);
  });

  ChatMessage cardMessage(Map<String, dynamic> metadata) => ChatMessage(
        id: 'k1',
        conversationId: 'c1',
        body: 'text version',
        senderType: SenderType.agent,
        contentType: MessageContentType.card,
        createdAt: DateTime.utc(2026, 10, 18, 9),
        metadata: metadata,
      );

  testWidgets('a card’s reply button answers, with the label the message gives it', (tester) async {
    final taps = <String>[];
    final m = cardMessage(const {
      'card': {
        'title': 'Order #1042',
        'buttons': [
          {'label': 'Track', 'url': 'https://e.example/t'},
          {'label': 'Change date', 'reply': 'k9_1'},
        ],
      },
      'bot': {
        'text': 'Order #1042',
        'buttons': [
          {'id': 'k9_1', 'label': 'Change date'},
        ],
      },
    });
    await pump(tester, bubble(m, onButton: (id, label) => taps.add('$id:$label')));
    // On the card, not as chips under it.
    expect(find.byType(ElcQuickReplies), findsNothing);
    await tester.tap(find.text('Change date'));
    expect(taps, ['k9_1:Change date']);
  });

  testWidgets('a carousel draws every card, and an answer names its card', (tester) async {
    final taps = <String>[];
    final m = cardMessage(const {
      'cards': [
        {
          'title': 'Blue',
          'buttons': [
            {'label': 'Buy', 'reply': 's_1'},
          ],
        },
        {
          'title': 'Red',
          'buttons': [
            {'label': 'Buy', 'reply': 's_2'},
          ],
        },
      ],
      'bot': {
        'text': 'Blue\n\nRed',
        'buttons': [
          {'id': 's_1', 'label': 'Blue · Buy'},
          {'id': 's_2', 'label': 'Red · Buy'},
        ],
      },
    });
    await pump(tester, bubble(m, onButton: (id, label) => taps.add('$id:$label')));
    expect(find.byType(ElcCardCarousel), findsOneWidget);
    expect(find.byType(ElcMessageCardView), findsNWidgets(2));
    await tester.tap(find.text('Buy').last);
    expect(taps, ['s_2:Red · Buy']);
  });
}
