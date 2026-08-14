import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

/// What the visitor is told about their own message.
///
/// The rule folds together two sources that answer different questions — the
/// per-message `read` flag that arrives with history, and the conversation-wide
/// watermark that advances live — plus the optimistic flags a send passes
/// through. Getting the precedence wrong is not a cosmetic bug: a message shown
/// as read that nobody has opened tells a customer someone is handling them
/// when nobody is.
void main() {
  ChatMessage customer(
    String id,
    DateTime at, {
    bool readByAgent = false,
    bool isOptimistic = false,
    bool failed = false,
    MessageDeliveryStatus status = MessageDeliveryStatus.sent,
  }) =>
      ChatMessage(
        id: id,
        conversationId: 'conv-1',
        body: 'hi',
        senderType: SenderType.customer,
        contentType: MessageContentType.text,
        deliveryStatus: status,
        readByAgent: readByAgent,
        isOptimistic: isOptimistic,
        failed: failed,
        createdAt: at,
      );

  final t0 = DateTime.utc(2026, 8, 14, 10, 0, 0);

  group('receiptFor', () {
    test('shows nothing for a message the visitor did not write', () {
      final fromAgent = ChatMessage(
        id: 'a1',
        conversationId: 'conv-1',
        body: 'hello',
        senderType: SenderType.agent,
        contentType: MessageContentType.text,
        createdAt: t0,
      );
      expect(fromAgent.receiptFor(t0.add(const Duration(minutes: 1))), isNull);

      final notice = ChatMessage(
        id: 's1',
        conversationId: 'conv-1',
        body: 'New chat started',
        senderType: SenderType.system,
        contentType: MessageContentType.text,
        createdAt: t0,
      );
      expect(notice.receiptFor(t0.add(const Duration(minutes: 1))), isNull);
    });

    test('a failed send outranks everything else', () {
      // Even inside a window an agent has read: the message never reached the
      // server, so there is nothing there to have been read.
      final m = customer('m1', t0, failed: true, readByAgent: true);
      expect(m.receiptFor(t0.add(const Duration(minutes: 5))),
          MessageReceipt.failed);
    });

    test('an in-flight send is pending, not sent', () {
      expect(
        customer('m1', t0,
                isOptimistic: true, status: MessageDeliveryStatus.pending)
            .receiptFor(null),
        MessageReceipt.pending,
      );
    });

    test('stored but unread is sent', () {
      expect(customer('m1', t0).receiptFor(null), MessageReceipt.sent);
    });

    test('history\'s own read flag is enough, with no watermark at all', () {
      // The case a returning visitor lands in: read happened while they were
      // away, so no live event ever arrived.
      expect(customer('m1', t0, readByAgent: true).receiptFor(null),
          MessageReceipt.read);
    });

    test('the watermark reads everything sent at or before it', () {
      final readAt = t0.add(const Duration(minutes: 1));
      expect(customer('m1', t0).receiptFor(readAt), MessageReceipt.read);
      // Exactly on the boundary — the server stamped this message in that same
      // update, so it is read.
      expect(customer('m2', readAt).receiptFor(readAt), MessageReceipt.read);
    });

    test('a message sent after the last read stays on one tick', () {
      final readAt = t0;
      expect(
        customer('m1', t0.add(const Duration(seconds: 1))).receiptFor(readAt),
        MessageReceipt.sent,
      );
    });

    test('a not-yet-reconciled send ignores the watermark', () {
      // Its timestamp is the device's and the watermark is the server's.
      // Comparing them across clock skew would show a message as read that no
      // agent has opened; one tick until the server row lands is the honest
      // answer.
      final tmp = customer('tmp-abc', t0.add(const Duration(minutes: 5)));
      expect(tmp.receiptFor(t0.add(const Duration(minutes: 10))),
          MessageReceipt.sent);
      // The same row once the server has confirmed it.
      expect(customer('srv-1', t0.add(const Duration(minutes: 5)))
          .receiptFor(t0.add(const Duration(minutes: 10))),
          MessageReceipt.read);
    });

    test('a READ delivery status alone marks it read', () {
      expect(
        customer('m1', t0, status: MessageDeliveryStatus.read).receiptFor(null),
        MessageReceipt.read,
      );
    });
  });

  group('wire parsing', () {
    test('reads the REST shape', () {
      final m = ChatMessage.fromAny({
        'id': 'm1',
        'conversationId': 'conv-1',
        'senderType': 'CUSTOMER',
        'contentType': 'TEXT',
        'body': 'hi',
        'createdAt': t0.toIso8601String(),
        'read': true,
      });
      expect(m.readByAgent, isTrue);
      expect(m.receiptFor(null), MessageReceipt.read);
    });

    test('reads the raw socket row', () {
      final m = ChatMessage.fromAny({
        'id': 'm1',
        'conversationId': 'conv-1',
        'senderType': 'CUSTOMER',
        'contentType': 'TEXT',
        'body': 'hi',
        'createdAt': t0.toIso8601String(),
        'readByAgentAt': t0.toIso8601String(),
      });
      expect(m.readByAgent, isTrue);
    });

    test('an unread row says so on both shapes', () {
      ChatMessage parse(Map<String, dynamic> extra) => ChatMessage.fromAny({
            'id': 'm1',
            'conversationId': 'conv-1',
            'senderType': 'CUSTOMER',
            'contentType': 'TEXT',
            'body': 'hi',
            'createdAt': t0.toIso8601String(),
            ...extra,
          });
      expect(parse({'read': false}).readByAgent, isFalse);
      expect(parse({'readByAgentAt': null}).readByAgent, isFalse);
      // A server that sends neither field must not read the thread.
      expect(parse({}).readByAgent, isFalse);
    });

    test('copyWith carries the flag', () {
      final m = customer('m1', t0, readByAgent: true);
      expect(m.copyWith(id: 'm2').readByAgent, isTrue);
      expect(m.copyWith(readByAgent: false).readByAgent, isFalse);
    });
  });
}
