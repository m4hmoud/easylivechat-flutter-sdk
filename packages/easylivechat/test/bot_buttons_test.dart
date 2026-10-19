/// Reply buttons — a bot's or an agent's — and reply buttons on cards and
/// carousels, as the SDK reads them. Ports of the shared bot-buttons and
/// message-card tests, on the same shapes the server stores.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

ChatMessage msg(
  String id,
  SenderType sender, {
  String body = '',
  MessageContentType contentType = MessageContentType.text,
  Map<String, dynamic>? metadata,
  int at = 0,
}) =>
    ChatMessage(
      id: id,
      conversationId: 'c1',
      body: body,
      senderType: sender,
      contentType: contentType,
      createdAt: DateTime.utc(2026, 10, 18, 9, 0, at),
      metadata: metadata,
    );

void main() {
  final asked = msg(
    'm1',
    SenderType.agent,
    body: 'Call you?\n\n1. Yes\n2. No\n\nReply with the number of your choice.',
    metadata: {
      'bot': {
        'text': 'Call you?',
        'buttons': [
          {'id': 'q_1', 'label': 'Yes'},
          {'id': 'q_2', 'label': 'No'},
          {'id': 'bad id', 'label': 'Dropped'},
          {'id': 'q_1', 'label': 'Twice'},
        ],
      },
      'quickReplies': ['Yes', 'No'],
    },
  );

  group('ChatMessage.botButtons', () {
    test('reads the words and the buttons, dropping what is not one of ours', () {
      final bot = asked.botButtons!;
      expect(bot.text, 'Call you?');
      expect(bot.buttons, const [BotButton(id: 'q_1', label: 'Yes'), BotButton(id: 'q_2', label: 'No')]);
    });

    test('is null on the visitor’s own message and on a message without buttons', () {
      expect(msg('c', SenderType.customer, metadata: asked.metadata).botButtons, isNull);
      expect(msg('t', SenderType.agent, body: 'hi').botButtons, isNull);
    });
  });

  group('the answer', () {
    final answer = msg('m2', SenderType.customer, body: 'No', at: 1, metadata: {
      'botReply': {'messageId': 'm1', 'buttonId': 'q_2', 'label': 'No'},
    });

    test('is read off the visitor’s message', () {
      expect(answer.botReply?.buttonId, 'q_2');
      expect(chosenButtonId([asked, answer], 'm1'), 'q_2');
      expect(chosenButtonId([asked], 'm1'), isNull);
    });

    test('closes the buttons, as does anything said after them — but not a system notice', () {
      expect(buttonsOpen([asked], 'm1'), isTrue);
      expect(buttonsOpen([asked, msg('s', SenderType.system, at: 1)], 'm1'), isTrue);
      expect(buttonsOpen([asked, answer], 'm1'), isFalse);
      expect(buttonsOpen([asked, msg('t', SenderType.customer, body: 'hm', at: 1)], 'm1'), isFalse);
    });
  });

  group('cards with reply buttons', () {
    test('a reply button is a reply, a link wins when a button has both', () {
      final card = MessageCard.tryParse({
        'title': 'Order',
        'buttons': [
          {'label': 'Track', 'url': 'https://e.example/t'},
          {'label': 'Change date', 'reply': 'k9_1'},
          {'label': 'Both', 'url': 'https://e.example/b', 'reply': 'k9_2'},
          {'label': 'Bad', 'reply': 'not ours!'},
        ],
      })!;
      expect(card.buttons, const [
        MessageCardButton(label: 'Track', url: 'https://e.example/t'),
        MessageCardButton.reply(label: 'Change date', id: 'k9_1'),
        MessageCardButton(label: 'Both', url: 'https://e.example/b'),
      ]);
      expect(card.buttons[1].isReply, isTrue);
      expect(card.buttons[1].uri, isNull);
    });

    test('a carousel reads as its cards, a single card as one, neither as none', () {
      Map<String, dynamic> shirt(int n) => {
            'title': 'Shirt $n',
            'buttons': [
              {'label': 'Buy', 'reply': 's_1'},
            ],
          };
      final carousel = msg('k', SenderType.agent,
          contentType: MessageContentType.card, metadata: {'cards': [shirt(1), shirt(2)]});
      expect(carousel.cards.map((c) => c.title), ['Shirt 1', 'Shirt 2']);
      // One reply id is one button, even across cards.
      expect(carousel.cards[1].buttons, isEmpty);
      expect(carousel.card, isNull);

      final one = msg('o', SenderType.agent,
          contentType: MessageContentType.card, metadata: {'card': shirt(3)});
      expect(one.cards.single.title, 'Shirt 3');
      expect(msg('t', SenderType.agent, metadata: {'cards': [shirt(1), shirt(2)]}).cards, isEmpty);
    });
  });
}
