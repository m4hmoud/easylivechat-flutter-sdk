/// Signing out has to forget the visitor.
///
/// The contact is keyed on the durable `visitorId`, and the server keeps a name
/// it already holds when a client sends none — an anonymous resume knows only
/// the id and must not wipe a real customer's name. So without a reset, the
/// next person to open the chat on a shared device was greeted by the previous
/// person's name and carried on inside their transcript.
library;

import 'package:easylivechat/easylivechat.dart';
import 'package:test/test.dart';

void main() {
  group('StorageKeys.identity', () {
    // The list drives the reset. A durable key added to the class and left out
    // of it would survive a logout and re-identify the next person — the exact
    // failure this exists to stop.
    test('covers every durable key that identifies a visitor', () {
      expect(
        StorageKeys.identity,
        containsAll([
          StorageKeys.visitorId,
          StorageKeys.profile,
          StorageKeys.token,
          StorageKeys.conversationId,
        ]),
      );
    });

    // The others are meaningless without it, and a crash midway through should
    // not leave a live visitorId paired with a dead token.
    test('drops the visitorId last', () {
      expect(StorageKeys.identity.last, StorageKeys.visitorId);
    });
  });

  group('EasyLiveChat.reset', () {
    test('clears the stored identity when never booted', () async {
      final storage = InMemoryStorage();
      await storage.write(StorageKeys.visitorId, 'v-abc');
      await storage.write(StorageKeys.token, 'jwt');
      await storage.write(StorageKeys.conversationId, 'c1');
      await storage.write(StorageKeys.profile, '{"name":"Mahmoud"}');

      await EasyLiveChat.instance.reset(storage: storage);

      for (final key in StorageKeys.identity) {
        expect(await storage.read(key), isNull, reason: '$key survived reset');
      }
    });

    // Logging out without ever opening the chat is the common case, and it is
    // the one where the SDK holds no controller to clear.
    test('is a no-op rather than a throw with no storage and no boot', () async {
      await expectLater(EasyLiveChat.instance.reset(), completes);
    });

    // A fresh visitorId is what makes the server treat this as a new contact
    // with nothing to resume.
    test('a later boot cannot see the old visitorId', () async {
      final storage = InMemoryStorage();
      await storage.write(StorageKeys.visitorId, 'v-old');

      await EasyLiveChat.instance.reset(storage: storage);

      expect(await storage.read(StorageKeys.visitorId), isNull);
    });
  });
}
