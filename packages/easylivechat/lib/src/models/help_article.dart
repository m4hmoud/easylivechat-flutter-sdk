/// Help articles — the workspace's published self-service answers, readable by
/// any visitor without a chat session.
///
/// Wire shapes are `packages/shared/src/help-articles.ts`. Every parser here is
/// null-tolerant: unknown fields are ignored and a missing one takes a neutral
/// default, so a server that grows the payload never breaks an installed app.
library;

/// One row of a list or a search result.
class HelpArticleSummary {
  final String id;
  final String title;

  /// The article's opening words with the markup removed — for the list row.
  final String excerpt;

  /// The tenant's category, or null when uncategorised.
  final String? category;

  /// When the article last changed. Null when the server omits it.
  final DateTime? updatedAt;

  const HelpArticleSummary({
    required this.id,
    required this.title,
    this.excerpt = '',
    this.category,
    this.updatedAt,
  });

  factory HelpArticleSummary.fromJson(Map<String, dynamic> j) =>
      HelpArticleSummary(
        id: _str(j['id']),
        title: _str(j['title']),
        excerpt: _str(j['excerpt']),
        category: _strOrNull(j['category']),
        updatedAt: _date(j['updatedAt']),
      );
}

/// One article in full.
class HelpArticle {
  final String id;
  final String title;

  /// Markdown in the help dialect (headings, paragraphs, lists, quotes, code,
  /// **bold**, *italic*, `code`, links and images). Render it as text — never
  /// as HTML: it is tenant-typed and may contain markup that must stay inert.
  /// `easylivechat_ui` ships a renderer for exactly this dialect.
  final String body;
  final String? category;

  /// The content-locale code the article is written in, or null when it is
  /// shown in every language.
  final String? locale;
  final DateTime? updatedAt;

  /// The article's public web page — to share it or open it in a browser.
  /// Empty when the server omits it.
  final String url;

  const HelpArticle({
    required this.id,
    required this.title,
    required this.body,
    this.category,
    this.locale,
    this.updatedAt,
    this.url = '',
  });

  factory HelpArticle.fromJson(Map<String, dynamic> j) => HelpArticle(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        category: _strOrNull(j['category']),
        locale: _strOrNull(j['locale']),
        updatedAt: _date(j['updatedAt']),
        url: _str(j['url']),
      );
}

/// What `GET /help/articles` answers: the articles, and whether the workspace
/// shows help at all.
class HelpArticleList {
  /// False when the workspace's "Show help articles" switch is off — the list
  /// is then always empty, and a UI should hide its help entry.
  final bool enabled;
  final List<HelpArticleSummary> articles;

  /// Every category with a published article, in the workspace's order.
  final List<String> categories;

  const HelpArticleList({
    required this.enabled,
    this.articles = const [],
    this.categories = const [],
  });

  /// The answer of a workspace that shows no help articles.
  static const disabled = HelpArticleList(enabled: false);

  factory HelpArticleList.fromJson(Map<String, dynamic> j) {
    final rawArticles = j['articles'];
    final rawCategories = j['categories'];
    return HelpArticleList(
      enabled: j['enabled'] == true,
      articles: rawArticles is List
          ? rawArticles
              .whereType<Map>()
              .map((m) => HelpArticleSummary.fromJson(m.cast<String, dynamic>()))
              .where((a) => a.id.isNotEmpty)
              .toList(growable: false)
          : const [],
      categories: rawCategories is List
          ? rawCategories
              .whereType<String>()
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }
}

String _str(Object? v) => v is String ? v : (v == null ? '' : v.toString());

String? _strOrNull(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

DateTime? _date(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  return DateTime.tryParse(v.trim())?.toLocal();
}
