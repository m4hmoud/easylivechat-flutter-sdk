import 'dart:async';

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

import 'bidi.dart';
import 'chat_screen.dart';
import 'l10n.dart';
import 'theme.dart';
import 'views/help_markdown_view.dart';

/// Where [EasyLiveChatHelpScreen] reads its articles. The default is the
/// booted SDK (`EasyLiveChat.instance`); tests substitute their own.
abstract class ElcHelpApi {
  const ElcHelpApi();

  /// The top articles for an empty (or one-character) [query], else a search.
  Future<HelpArticleList> list(String query);
  Future<HelpArticle> article(String id);
  Future<void> rate(String id, bool helpful);
}

class _SdkHelpApi extends ElcHelpApi {
  const _SdkHelpApi();

  @override
  Future<HelpArticleList> list(String query) {
    final q = query.trim();
    return q.length < 2
        ? EasyLiveChat.instance.helpArticles()
        : EasyLiveChat.instance.searchHelp(q);
  }

  @override
  Future<HelpArticle> article(String id) =>
      EasyLiveChat.instance.getHelpArticle(id);

  @override
  Future<void> rate(String id, bool helpful) =>
      EasyLiveChat.instance.rateHelpArticle(id, helpful);
}

/// The workspace's help articles: a search field over the top articles, an
/// article reader with "Was this helpful?", and "Still need help? Start a
/// chat" at the foot of both.
///
/// Show it only when `EasyLiveChat.instance.widgetConfig.value
/// ?.helpArticlesEnabled` is true — with the workspace's switch off there is
/// nothing to list. [EasyLiveChatScreen] already offers it (before the visitor
/// has written) when the switch is on; push this directly to give help its own
/// entry point in your app:
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => const EasyLiveChatHelpScreen(),
/// ));
/// ```
///
/// Requires `EasyLiveChat.instance.boot(...)`; no chat session is needed.
/// Article bodies are rendered natively ([ElcHelpMarkdown]) — no HTML, no
/// WebView. Layout follows the workspace direction (or [directionOverride]),
/// and each article reads in its own language's direction.
class EasyLiveChatHelpScreen extends StatefulWidget {
  /// Host theme override; non-null fields win over the server config.
  final EasyLiveChatTheme? themeOverride;

  /// Force the layout direction, as on [EasyLiveChatScreen].
  final TextDirection? directionOverride;

  /// Force the chrome locale, as on [EasyLiveChatScreen].
  final String? locale;

  /// "Start a chat" was tapped. When null the help screen replaces itself with
  /// an [EasyLiveChatScreen] (with its own app bar, since it then owns the
  /// screen). Pass your own to route elsewhere — the chat screen's own entry
  /// passes one that pops back to the chat it came from.
  final VoidCallback? onStartChat;

  /// A link inside an article was tapped. When null the platform handler opens
  /// it (browser, mail app, dialer).
  final ElcOpenLink? onOpenLink;

  /// Draw the screen's own header: back and the title. On by default — a
  /// pushed help screen needs a way back to the list from an article.
  final bool showAppBar;

  /// Open straight on this article (e.g. from a deep link). Back returns to the
  /// list.
  final String? initialArticleId;

  /// Article source; defaults to `EasyLiveChat.instance`.
  @visibleForTesting
  final ElcHelpApi? api;

  const EasyLiveChatHelpScreen({
    super.key,
    this.themeOverride,
    this.directionOverride,
    this.locale,
    this.onStartChat,
    this.onOpenLink,
    this.showAppBar = true,
    this.initialArticleId,
    this.api,
  });

  @override
  State<EasyLiveChatHelpScreen> createState() => _EasyLiveChatHelpScreenState();
}

class _EasyLiveChatHelpScreenState extends State<EasyLiveChatHelpScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  // List state. [_listSeq] drops a slow answer that a newer query overtook.
  int _listSeq = 0;
  HelpArticleList? _list;
  bool _listLoading = true;
  bool _listFailed = false;

  /// The query [_list] answers ('' for the top articles).
  String? _listedQuery;

  // Article state.
  int _articleSeq = 0;
  String? _articleId;
  HelpArticle? _article;
  bool _articleLoading = false;
  bool _articleMissing = false;
  bool _articleFailed = false;

  /// "Was this helpful?" answers given on this screen, by article id.
  final Map<String, bool> _answers = {};

  ElcHelpApi get _api => widget.api ?? const _SdkHelpApi();

  @override
  void initState() {
    super.initState();
    if (widget.locale != null) ElcStrings.setLocale(widget.locale);
    _loadList('');
    final initial = widget.initialArticleId;
    if (initial != null && initial.isNotEmpty) _openArticle(initial);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  WidgetConfigModel? get _config => EasyLiveChat.instance.isBooted
      ? EasyLiveChat.instance.widgetConfig.value
      : null;

  ElcStrings get _s => ElcStrings.of(widget.locale ?? _config?.locale);

  /// The chat's own look, light or dark as the workspace chose — the help
  /// screen is part of the same conversation with the business.
  EasyLiveChatTheme _theme(BuildContext context) {
    final cfg = _config;
    final device =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
    var theme = cfg != null
        ? EasyLiveChatTheme.fromConfig(cfg,
            override: widget.themeOverride, platformBrightness: device)
        // Light until the config says otherwise, as the chat screen.
        : (widget.themeOverride ?? _fallbackTheme);
    if (widget.directionOverride != null) {
      theme = theme.copyWith(direction: widget.directionOverride);
    }
    return theme;
  }

  // ── list ──

  /// One- and zero-character queries both mean "the top articles".
  static String _effective(String raw) {
    final q = raw.trim();
    return q.length < 2 ? '' : q;
  }

  Future<void> _loadList(String raw) async {
    final query = _effective(raw);
    final seq = ++_listSeq;
    setState(() {
      _listLoading = true;
      _listFailed = false;
    });
    try {
      final list = await _api.list(query);
      if (!mounted || seq != _listSeq) return;
      setState(() {
        _list = list;
        _listedQuery = query;
        _listLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _listSeq) return;
      setState(() {
        _listLoading = false;
        _listFailed = true;
      });
    }
  }

  void _onQueryChanged(String raw) {
    // Rebuild for the clear button straight away; search once typing pauses.
    setState(() {});
    _debounce?.cancel();
    if (_effective(raw) == _listedQuery && !_listFailed) return;
    _debounce = Timer(const Duration(milliseconds: 300), () => _loadList(raw));
  }

  void _clearQuery() {
    _search.clear();
    _onQueryChanged('');
  }

  // ── article ──

  Future<void> _openArticle(String id) async {
    final seq = ++_articleSeq;
    setState(() {
      _articleId = id;
      _article = null;
      _articleLoading = true;
      _articleMissing = false;
      _articleFailed = false;
    });
    try {
      final article = await _api.article(id);
      if (!mounted || seq != _articleSeq) return;
      setState(() {
        _article = article;
        _articleLoading = false;
      });
    } on EasyLiveChatError catch (e) {
      if (!mounted || seq != _articleSeq) return;
      setState(() {
        _articleLoading = false;
        if (e.code == EasyLiveChatErrorCode.notFound) {
          _articleMissing = true;
        } else {
          _articleFailed = true;
        }
      });
    } catch (_) {
      if (!mounted || seq != _articleSeq) return;
      setState(() {
        _articleLoading = false;
        _articleFailed = true;
      });
    }
  }

  void _closeArticle() {
    _articleSeq++;
    setState(() {
      _articleId = null;
      _article = null;
      _articleLoading = false;
    });
  }

  void _answer(String id, bool helpful) {
    setState(() => _answers[id] = helpful);
    // Low stakes: the thanks stays even if the count does not land.
    unawaited(_api.rate(id, helpful).catchError((Object _) {}));
  }

  void _startChat() {
    final hook = widget.onStartChat;
    if (hook != null) {
      hook();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EasyLiveChatScreen(
        themeOverride: widget.themeOverride,
        directionOverride: widget.directionOverride,
        locale: widget.locale,
        showAppBar: true,
      ),
    ));
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final theme = _theme(context);
    final s = _s;
    return PopScope(
      // Back from an article returns to the list rather than leaving help.
      canPop: _articleId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeArticle();
      },
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Directionality(
          textDirection: theme.direction,
          child: Material(
            color: theme.background,
            child: SafeArea(
              child: Column(
                children: [
                  if (widget.showAppBar) _header(theme, s),
                  Expanded(
                    child: _articleId == null
                        ? _listView(theme, s)
                        : _articleView(theme, s),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(EasyLiveChatTheme t, ElcStrings s) {
    return Container(
      height: 52,
      padding: const EdgeInsetsDirectional.only(start: 4, end: 16),
      decoration: BoxDecoration(
        color: t.background,
        border: Border(
          bottom: BorderSide(color: t.text.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            // arrow_back mirrors itself under RTL.
            icon: const Icon(Icons.arrow_back),
            color: t.text,
            tooltip: s.helpBack,
            onPressed: _articleId != null
                ? _closeArticle
                : () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                s.helpTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(EasyLiveChatTheme t, ElcStrings s) {
    final muted = t.text.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
      child: TextField(
        controller: _search,
        onChanged: _onQueryChanged,
        onSubmitted: (v) {
          _debounce?.cancel();
          _loadList(v);
        },
        textInputAction: TextInputAction.search,
        style: TextStyle(color: t.text, fontSize: 16),
        cursorColor: t.primaryInk,
        // The dark keyboard on iOS while the chat is dark.
        keyboardAppearance: t.brightness,
        decoration: InputDecoration(
          hintText: s.helpSearchPlaceholder,
          hintStyle: TextStyle(color: muted),
          prefixIcon: Icon(Icons.search, color: muted),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: muted),
                  tooltip: s.helpSearchClear,
                  onPressed: _clearQuery,
                ),
          filled: true,
          fillColor: t.surface,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _listView(EasyLiveChatTheme t, ElcStrings s) {
    final list = _list;
    final searching = (_listedQuery ?? '').isNotEmpty;
    final children = <Widget>[];

    if (list == null && _listLoading) {
      children.add(_spinner(t, s));
    } else if (_listFailed && list == null) {
      children.add(_failure(t, s, s.helpLoadFailed, () => _loadList(_search.text)));
    } else if (list != null) {
      if (searching) {
        // Read out after each search; the list itself is not a live region.
        children.add(Semantics(
          liveRegion: true,
          label: s.helpResultsFound
              .replaceAll('{n}', '${list.articles.length}'),
          child: const SizedBox(height: 1),
        ));
      } else if (list.articles.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              s.helpTopArticles,
              style: TextStyle(
                color: t.text.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ));
      }
      if (_listFailed) {
        children.add(_failure(t, s, s.helpLoadFailed, () => _loadList(_search.text)));
      }
      if (list.articles.isEmpty && !_listFailed) {
        children.add(Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.helpNoResults,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.text.withValues(alpha: 0.7), fontSize: 15),
          ),
        ));
      }
      for (final a in list.articles) {
        children.add(_ArticleTile(theme: t, article: a, onTap: () => _openArticle(a.id)));
      }
      if (_listLoading) {
        children.add(const LinearProgressIndicator(minHeight: 2));
      }
    }

    children.add(_startChatCard(t, s));

    return Column(
      children: [
        _searchField(t, s),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _articleView(EasyLiveChatTheme t, ElcStrings s) {
    final article = _article;
    final children = <Widget>[];

    if (!widget.showAppBar) {
      // No header to go back with: give the list its own way back.
      children.add(Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _closeArticle,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: Text(s.helpBack),
          style: TextButton.styleFrom(foregroundColor: t.text),
        ),
      ));
    }

    if (_articleLoading) {
      children.add(_spinner(t, s));
    } else if (_articleMissing) {
      children.add(_notice(t, s.helpArticleUnavailable));
    } else if (_articleFailed) {
      children.add(_failure(t, s, s.helpLoadFailed, () {
        final id = _articleId;
        if (id != null) _openArticle(id);
      }));
    } else if (article != null) {
      final dir = _articleDirection(article, t.direction);
      children.add(Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 0),
        child: Directionality(
          textDirection: dir,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  article.title,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              if (article.category != null) ...[
                const SizedBox(height: 4),
                Text(
                  article.category!,
                  style: TextStyle(
                    color: t.text.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElcHelpMarkdown(
                markdown: article.body,
                textColor: t.text,
                linkColor: t.primaryInk,
                surfaceColor: t.surface,
                onOpenLink: widget.onOpenLink,
              ),
            ],
          ),
        ),
      ));
      children.add(Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 0),
        child: _helpful(t, s, article.id),
      ));
    }

    children.add(_startChatCard(t, s));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  /// The article's own reading direction: from its language when the server
  /// says, else from its first strong character, else the screen's.
  static TextDirection _articleDirection(
      HelpArticle article, TextDirection fallback) {
    final locale = article.locale;
    if (locale != null) {
      return isRtlLanguage(locale) ? TextDirection.rtl : TextDirection.ltr;
    }
    return textDirectionOf('${article.title} ${article.body}') ?? fallback;
  }

  Widget _helpful(EasyLiveChatTheme t, ElcStrings s, String id) {
    final answer = _answers[id];
    if (answer != null) {
      return Semantics(
        liveRegion: true,
        child: Text(
          s.helpFeedbackThanks,
          style: TextStyle(color: t.text.withValues(alpha: 0.75), fontSize: 15),
        ),
      );
    }
    final style = OutlinedButton.styleFrom(
      foregroundColor: t.text,
      side: BorderSide(color: t.text.withValues(alpha: 0.2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          s.helpWasHelpful,
          style: TextStyle(
              color: t.text, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: () => _answer(id, true),
          icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
          label: Text(s.helpYes),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: () => _answer(id, false),
          icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
          label: Text(s.helpNo),
        ),
      ],
    );
  }

  Widget _startChatCard(EasyLiveChatTheme t, ElcStrings s) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.helpStillNeedHelp,
              style: TextStyle(
                  color: t.text, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _startChat,
              style: FilledButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: t.onPrimary,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(s.helpStartChat),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinner(EasyLiveChatTheme t, ElcStrings s) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Semantics(
            label: s.helpLoading,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(t.primaryInk),
            ),
          ),
        ),
      );

  Widget _notice(EasyLiveChatTheme t, String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: t.text.withValues(alpha: 0.75), fontSize: 15),
        ),
      );

  Widget _failure(EasyLiveChatTheme t, ElcStrings s, String text,
          VoidCallback onRetry) =>
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: t.text.withValues(alpha: 0.75), fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: t.primaryInk),
              child: Text(s.retry),
            ),
          ],
        ),
      );

  static const EasyLiveChatTheme _fallbackTheme = EasyLiveChatTheme(
    primary: Color(0xFF2563EB),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF1F5F9),
    text: Color(0xFF0F172A),
  );
}

/// One article in the list: title, excerpt, and a chevron on the trailing edge.
class _ArticleTile extends StatelessWidget {
  final EasyLiveChatTheme theme;
  final HelpArticleSummary article;
  final VoidCallback onTap;

  const _ArticleTile({
    required this.theme,
    required this.article,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    // Each row reads the way its own title does — an Arabic article listed in
    // an English app keeps its words right-to-left — while the row itself
    // (chevron on the trailing edge) follows the screen.
    final dir = textDirectionOf(article.title);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      article.title,
                      textDirection: dir,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (article.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        article.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textDirection: textDirectionOf(article.excerpt) ?? dir,
                        style: TextStyle(
                          color: t.text.withValues(alpha: 0.65),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // chevron_right mirrors itself under RTL.
              ExcludeSemantics(
                child: Icon(Icons.chevron_right,
                    color: t.text.withValues(alpha: 0.35)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether the chat screen should offer its help entry: the workspace shows
/// help articles and the visitor has not written anything yet (once they have,
/// the conversation is the help).
bool offerHelpEntry(WidgetConfigModel? config, List<ChatMessage> messages) {
  if (config == null || !config.helpArticlesEnabled) return false;
  return !messages.any((m) => m.isFromCustomer);
}
