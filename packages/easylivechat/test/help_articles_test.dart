/// Help articles: the public list/search/article/view/feedback endpoints.
///
/// No session and no token — a visitor can read them before ever opening a
/// chat, which is the whole point: an answer found here is a chat nobody had
/// to start. The server counts "deflection" per reading session, so the view
/// and the rating must carry the same session id.
library;

import 'package:dio/dio.dart' show RequestOptions;
import 'package:easylivechat/easylivechat.dart';
import 'package:easylivechat/src/session_controller.dart';
import 'package:test/test.dart';

import 'support/fake_http.dart';

const _config = EasyLiveChatConfig(
  apiBase: 'https://api.example.test',
  tenantSlug: 'acme',
  contentLocale: 'ckb',
  enablePresenceSocket: false,
  enableHeartbeat: false,
);

const _article = {
  'id': 'a1',
  'title': 'How do I reset my password?',
  'body': '## Steps\n\n1. Open **Settings**\n2. Tap *Reset*',
  'category': 'Account',
  'locale': 'ckb',
  'updatedAt': '2026-10-01T09:30:00.000Z',
  'url': 'https://livechattools.com/help/acme/a1',
};

FakeReply _reply(RequestOptions r) {
  final path = r.path;
  if (path.endsWith('/help/articles')) {
    return const FakeReply(200, {
      'enabled': true,
      'articles': [
        {
          'id': 'a1',
          'title': 'How do I reset my password?',
          'excerpt': 'Open Settings…',
          'category': 'Account',
          'updatedAt': '2026-10-01T09:30:00.000Z',
          'somethingNew': 42,
        },
      ],
      'categories': ['Account', 'Billing'],
    });
  }
  if (path.endsWith('/help/articles/a1')) {
    return const FakeReply(200, {'article': _article});
  }
  if (path.endsWith('/view')) {
    return const FakeReply(200, {'ok': true, 'counted': true});
  }
  if (path.endsWith('/feedback')) return const FakeReply(200, {'ok': true});
  return const FakeReply(404, {'error': 'NOT_FOUND'});
}

Future<(SessionController, FakeHttp)> _controller(
    [FakeReply Function(RequestOptions r) reply = _reply]) async {
  final http = FakeHttp(reply);
  final c = SessionController(config: _config, storage: InMemoryStorage());
  c.rest = fakeRest(_config, http);
  await c.boot();
  return (c, http);
}

void main() {
  group('models', () {
    test('a list ignores unknown fields and defaults missing ones', () {
      final list = HelpArticleList.fromJson({
        'enabled': true,
        'articles': [
          {'id': 'a1', 'title': 'T', 'extra': true},
          {'title': 'no id is not an article'},
          'not even a map',
        ],
        'categories': ['Account', '', 7],
        'future': {'nested': 1},
      });
      expect(list.enabled, isTrue);
      expect(list.articles, hasLength(1));
      final a = list.articles.single;
      expect(a.excerpt, '');
      expect(a.category, isNull);
      expect(a.updatedAt, isNull);
      expect(list.categories, ['Account']);
    });

    test('a switched-off workspace reads as disabled', () {
      final list = HelpArticleList.fromJson(
          {'enabled': false, 'articles': [], 'categories': []});
      expect(list.enabled, isFalse);
      expect(list.articles, isEmpty);
      expect(HelpArticleList.fromJson(const {}).enabled, isFalse);
    });

    test('an article parses every field', () {
      final a = HelpArticle.fromJson(_article);
      expect(a.id, 'a1');
      expect(a.body, startsWith('## Steps'));
      expect(a.locale, 'ckb');
      expect(a.url, 'https://livechattools.com/help/acme/a1');
      expect(a.updatedAt, DateTime.utc(2026, 10, 1, 9, 30).toLocal());
      expect(HelpArticle.fromJson(const {'id': 'x'}).body, '');
    });

    test('the widget config carries the switch, off when absent', () {
      expect(
          WidgetConfigModel.fromJson(const {'helpArticlesEnabled': true})
              .helpArticlesEnabled,
          isTrue);
      expect(WidgetConfigModel.fromJson(const {}).helpArticlesEnabled, isFalse);
    });
  });

  group('requests', () {
    test('a search sends q, category, limit and the content locale', () async {
      final (c, http) = await _controller();
      final list = await c.searchHelp('password', category: 'Account', limit: 5);

      expect(list.articles.single.title, 'How do I reset my password?');
      expect(list.categories, ['Account', 'Billing']);
      final q = http.to('/help/articles').single.queryParameters;
      expect(q['q'], 'password');
      expect(q['category'], 'Account');
      expect(q['limit'], 5);
      expect(q['locale'], 'ckb');
      c.dispose();
    });

    test('the top list sends no q at all', () async {
      final (c, http) = await _controller();
      await c.helpArticles();
      final q = http.to('/help/articles').single.queryParameters;
      expect(q.containsKey('q'), isFalse);
      expect(q.containsKey('limit'), isFalse);
      c.dispose();
    });

    test('reading an article records the view for this visitor and session',
        () async {
      final (c, http) = await _controller();
      final article = await c.getHelpArticle('a1');
      await pumpEventQueue();

      expect(article.title, 'How do I reset my password?');
      expect(http.to('/help/articles/a1').single.queryParameters['locale'],
          'ckb');
      final view = FakeHttp.bodyOf(http.to('/view').single);
      expect(view['visitorId'], c.visitorId);
      expect(view['sessionId'], isA<String>());
      expect((view['sessionId'] as String), isNotEmpty);

      await c.rateHelpArticle('a1', true);
      final rating = FakeHttp.bodyOf(http.to('/feedback').single);
      expect(rating['helpful'], isTrue);
      expect(rating['visitorId'], c.visitorId);
      // One reading session: the server ties the answer to the view.
      expect(rating['sessionId'], view['sessionId']);
      c.dispose();
    });

    test('a failed view count never costs the visitor the article', () async {
      final (c, _) = await _controller((r) => r.path.endsWith('/view')
          ? const FakeReply(429, {'error': 'RATE_LIMITED'})
          : _reply(r));
      final article = await c.getHelpArticle('a1');
      await pumpEventQueue();
      expect(article.id, 'a1');
      c.dispose();
    });

    test('a missing article is NOT_FOUND', () async {
      final (c, _) = await _controller();
      await expectLater(
        c.getHelpArticle('gone'),
        throwsA(isA<EasyLiveChatError>()
            .having((e) => e.code, 'code', EasyLiveChatErrorCode.notFound)
            .having((e) => e.httpStatus, 'httpStatus', 404)),
      );
      c.dispose();
    });

    test('the id is path-encoded', () async {
      final (c, http) = await _controller();
      await c.getHelpArticle('a/b?c').catchError((Object _) =>
          HelpArticle.fromJson(const {}));
      expect(http.requests.last.path, endsWith('/help/articles/a%2Fb%3Fc'));
      c.dispose();
    });

    test('a throttled search is RATE_LIMITED, with or without a body',
        () async {
      for (final body in [
        {'error': 'RATE_LIMITED'},
        null,
      ]) {
        final (c, _) = await _controller((_) => FakeReply(429, body));
        await expectLater(
          c.searchHelp('password'),
          throwsA(isA<EasyLiveChatError>().having(
              (e) => e.code, 'code', EasyLiveChatErrorCode.rateLimited)),
        );
        c.dispose();
      }
    });
  });
}
