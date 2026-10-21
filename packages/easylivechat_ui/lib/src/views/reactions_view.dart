import 'dart:math' as math;

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../theme.dart';
import 'emoji_search.dart';

/// Reactions in the visitor's thread — the native analog of the web widget's
/// `components/Reactions.tsx`.
///
/// [ElcReactable] wraps one of the team's bubbles: a long press (or the
/// screen reader's "React" action) opens the quick row under it — 👍 ❤️ 😂 😮
/// 😢 🙏 and a + for the whole picker ([showElcEmojiPicker]). The same emoji
/// again takes the reaction back. [ElcReactionChips] sit under any bubble that
/// has reactions: the visitor's own (pressing it takes it back) or the team's
/// on their message — never an agent's name.
///
/// The row opens in place, under the bubble, rather than as a floating
/// popover: the message being pressed stays where the visitor's finger is,
/// the row sits on the page's own ground and scrolls with its bubble, and a
/// tap anywhere else puts it away — one open at a time. (The web widget floats
/// it above the bubble; the React Native SDK opens it under, as here.)
class ElcReactable extends StatefulWidget {
  final Widget child;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  /// The visitor's own reaction on the message, marked in the row.
  final String? mine;

  /// A pick from the row or the picker, as tapped — the caller decides
  /// whether it sets or takes back (`ChatMessage.toggledReaction`). Null
  /// leaves [child] as it is: nothing to react with.
  final ValueChanged<String>? onPick;

  const ElcReactable({
    super.key,
    required this.child,
    required this.theme,
    required this.strings,
    this.mine,
    this.onPick,
  });

  @override
  State<ElcReactable> createState() => _ElcReactableState();
}

class _ElcReactableState extends State<ElcReactable> {
  bool _open = false;

  void _show() {
    HapticFeedback.selectionClick();
    setState(() => _open = true);
  }

  void _close() {
    if (_open) setState(() => _open = false);
  }

  void _pick(String emoji) {
    _close();
    widget.onPick?.call(emoji);
  }

  Future<void> _more() async {
    _close();
    final emoji = await showElcEmojiPicker(
      context,
      theme: widget.theme,
      strings: widget.strings,
    );
    if (emoji != null && mounted) widget.onPick?.call(emoji);
  }

  @override
  void didUpdateWidget(ElcReactable old) {
    super.didUpdateWidget(old);
    // The message stopped taking reactions (the connection went, the
    // workspace locked the composer): nothing stays open.
    if (widget.onPick == null) _open = false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onPick == null) return widget.child;
    return TapRegion(
      onTapOutside: (_) => _close(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Its own node, so the action sits on the message it is for.
          Semantics(
            container: true,
            customSemanticsActions: {
              CustomSemanticsAction(label: widget.strings.react): _show,
            },
            child: GestureDetector(
              onLongPress: _show,
              child: widget.child,
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              // Seven round buttons are wider than a bubble beside an avatar
              // on the narrowest phones: shrink to fit rather than overflow.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: ElcQuickReactions(
                  theme: widget.theme,
                  strings: widget.strings,
                  mine: widget.mine,
                  onPick: _pick,
                  onMore: _more,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The quick row: the six every client shows first, then a + for the rest.
class ElcQuickReactions extends StatelessWidget {
  final EasyLiveChatTheme theme;
  final ElcStrings strings;
  final String? mine;
  final ValueChanged<String> onPick;
  final VoidCallback onMore;

  const ElcQuickReactions({
    super.key,
    required this.theme,
    required this.strings,
    required this.mine,
    required this.onPick,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: strings.react,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.text.withValues(alpha: 0.12)),
          boxShadow: t.isDark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x290F172A),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in quickReactions)
              _RoundButton(
                theme: t,
                selected: sameEmoji(mine, emoji),
                onTap: () => onPick(emoji),
                child: Text(emoji,
                    style: const TextStyle(fontSize: 22, height: 1)),
              ),
            _RoundButton(
              theme: t,
              tooltip: strings.moreReactions,
              onTap: onMore,
              child: Icon(Icons.add_rounded,
                  size: 20, color: t.text.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final EasyLiveChatTheme theme;
  final bool selected;
  final String? tooltip;
  final VoidCallback onTap;
  final Widget child;

  const _RoundButton({
    required this.theme,
    required this.onTap,
    required this.child,
    this.selected = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      container: true,
      button: true,
      selected: selected,
      label: tooltip,
      child: Material(
        color: selected
            ? theme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          splashColor: theme.text.withValues(alpha: 0.08),
          highlightColor: theme.text.withValues(alpha: 0.07),
          child: SizedBox(width: 36, height: 36, child: Center(child: child)),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, excludeFromSemantics: true, child: button);
  }
}

/// Chips under a bubble — the visitor's view of its reactions. Nothing when
/// there are none.
class ElcReactionChips extends StatelessWidget {
  final List<MessageReaction> reactions;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;

  /// On the visitor's own message the chips line up at its edge.
  final bool fromCustomer;

  /// Takes the visitor's own reaction back — given on the team's messages,
  /// where their chip is theirs to press. Null draws every chip as a label.
  final VoidCallback? onRemoveMine;

  const ElcReactionChips({
    super.key,
    required this.reactions,
    required this.theme,
    required this.strings,
    this.fromCustomer = false,
    this.onRemoveMine,
  });

  @override
  Widget build(BuildContext context) {
    final groups = groupReactions(reactions);
    if (groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: fromCustomer ? WrapAlignment.end : WrapAlignment.start,
        children: [for (final g in groups) _chip(g)],
      ),
    );
  }

  Widget _chip(ReactionGroup g) {
    final t = theme;
    final label = (g.mine ? strings.yourReaction : strings.teamReaction)
        .replaceAll('{emoji}', g.emoji);
    final chip = Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: g.mine
            ? Color.alphaBlend(t.primary.withValues(alpha: 0.12), t.surface)
            : t.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: g.mine
              ? t.primary.withValues(alpha: 0.55)
              : t.text.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(g.emoji, style: const TextStyle(fontSize: 14, height: 1)),
          if (g.count > 1) ...[
            const SizedBox(width: 4),
            Text(
              '${g.count}',
              style: TextStyle(
                fontSize: 12,
                height: 1,
                color: t.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
    final remove = g.mine ? onRemoveMine : null;
    if (remove == null) {
      // One node per chip, as on the web, never folded into the message.
      return Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: Tooltip(message: label, excludeFromSemantics: true, child: chip),
      );
    }
    return Semantics(
      container: true,
      button: true,
      toggled: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: remove,
          child: chip,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The whole picker
// ─────────────────────────────────────────────────────────────────────────────

/// The device's recently used reactions, newest first, for this run of the
/// app — the web keeps its own in the browser. 24 at most, as on the web.
@visibleForTesting
List<String> elcRecentEmoji = [];

const int _recentMax = 24;

void _remember(String emoji) {
  elcRecentEmoji = [
    emoji,
    ...elcRecentEmoji.where((e) => e != emoji),
  ].take(_recentMax).toList();
}

/// The picker's tabs, in order, each with the emoji that stands for it — the
/// web's `EMOJI_CATEGORIES` / `EMOJI_CATEGORY_ICON`.
const List<(String, String)> _categories = [
  ('recent', '🕘'),
  ('smileys', '😀'),
  ('people', '👋'),
  ('animals', '🐻'),
  ('food', '🍔'),
  ('travel', '🚗'),
  ('activities', '⚽'),
  ('objects', '💡'),
  ('symbols', '❤️'),
  ('flags', '🏁'),
];

/// Open the whole picker as a sheet over the chat; resolves with the emoji
/// picked, or null when the visitor put it away.
Future<String?> showElcEmojiPicker(
  BuildContext context, {
  required EasyLiveChatTheme theme,
  required ElcStrings strings,
}) {
  return showModalBottomSheet<String>(
    context: context,
    // The search field brings the keyboard up; the sheet has to be free to
    // rise above it rather than sit underneath.
    isScrollControlled: true,
    // The page's own ground, not a tier of its own.
    backgroundColor: theme.background,
    barrierColor: theme.text.withValues(alpha: 0.18),
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      // 360 high, as before — less when the keyboard leaves less, but never
      // so little that the grid has no row to show.
      final room = MediaQuery.sizeOf(sheetContext).height -
          keyboard -
          MediaQuery.paddingOf(sheetContext).top -
          48;
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Directionality(
          textDirection: theme.direction,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: math.max(180.0, math.min(360.0, room)),
              child: ElcEmojiPicker(
                theme: theme,
                strings: strings,
                onPick: (emoji) => Navigator.of(sheetContext).pop(emoji),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A search field and category tabs over a grid of every emoji, the device's
/// recent ones first — the web's picker (apps/widget EmojiPicker.tsx): the
/// same emoji in the same order, and the same search ([searchEmoji]), which
/// matches the emoji's English names and tags, each word by its start. While
/// there is a query the grid shows its matches, best first; a tab clears it.
/// Submitting the field picks the first match, as Enter does on the web.
class ElcEmojiPicker extends StatefulWidget {
  final EasyLiveChatTheme theme;
  final ElcStrings strings;
  final ValueChanged<String> onPick;

  const ElcEmojiPicker({
    super.key,
    required this.theme,
    required this.strings,
    required this.onPick,
  });

  @override
  State<ElcEmojiPicker> createState() => _ElcEmojiPickerState();
}

class _ElcEmojiPickerState extends State<ElcEmojiPicker> {
  static const double _cell = 44;
  static const double _header = 32;
  static const double _padding = 8;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _query = TextEditingController();
  late final List<(String, List<String>)> _sections = [
    if (elcRecentEmoji.isNotEmpty) ('recent', List.of(elcRecentEmoji)),
    for (final (id, _) in _categories)
      if (id != 'recent') (id, emojiOf(id)),
  ];
  late String _active = _sections.first.$1;
  int _columns = 8;

  /// The matches for the query, or null while there is none — then the grid
  /// is the categories.
  List<String>? _results;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  void _search(String query) {
    setState(() {
      _results = query.trim().isEmpty ? null : searchEmoji(query);
    });
  }

  void _clearSearch() {
    _query.clear();
    _search('');
  }

  /// Where each section starts: every row is one cell high, so the offsets
  /// are arithmetic — no need to have built a section to jump to it.
  List<double> _offsets() {
    final out = <double>[];
    var y = 0.0;
    for (final (_, emoji) in _sections) {
      out.add(y);
      y += _header + (emoji.length / _columns).ceil() * _cell;
    }
    return out;
  }

  void _onScroll() {
    if (_results != null || !_scroll.hasClients) return;
    final offsets = _offsets();
    var current = _sections.first.$1;
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] <= _scroll.offset + 8) current = _sections[i].$1;
    }
    if (current != _active) setState(() => _active = current);
  }

  void _jumpTo(String id) {
    final i = _sections.indexWhere((s) => s.$1 == id);
    if (i == -1) return;
    if (_results != null) {
      // A tab leaves the search, as on the web: the categories come back,
      // and the jump waits for them to be laid out.
      _query.clear();
      setState(() {
        _results = null;
        _active = id;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpTo(id);
      });
      return;
    }
    if (!_scroll.hasClients) return;
    final target = _offsets()[i].clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
    setState(() => _active = id);
  }

  void _pick(String emoji) {
    _remember(emoji);
    widget.onPick(emoji);
  }

  Widget _resultsGrid(
      List<String> results, EasyLiveChatTheme t, ElcStrings s) {
    if (results.isEmpty) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Text(
            s.emojiNoResults,
            style: TextStyle(color: t.text.withValues(alpha: 0.6), fontSize: 14),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: s.emojiResults,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(_padding, 8, _padding, _padding),
        // The keyboard is usually up while the visitor searches; a drag
        // through the matches puts it away.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          mainAxisExtent: _cell,
        ),
        itemCount: results.length,
        itemBuilder: (context, i) => _EmojiCell(
          emoji: results[i],
          theme: t,
          onTap: () => _pick(results[i]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final s = widget.strings;
    final results = _results;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_padding, 10, _padding, 0),
          child: _EmojiSearchField(
            controller: _query,
            theme: t,
            strings: s,
            onChanged: _search,
            onClear: _clearSearch,
            onSubmitted: (_) {
              final first = _results?.firstOrNull;
              if (first != null) _pick(first);
            },
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: s.emojiCategories,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(_padding, 8, _padding, 4),
            child: Row(
              children: [
                for (final (id, icon) in _categories)
                  if (_sections.any((x) => x.$1 == id))
                    _RoundButton(
                      theme: t,
                      tooltip: s.emojiCategory(id),
                      selected: results == null && _active == id,
                      onTap: () => _jumpTo(id),
                      child: Text(icon,
                          style: const TextStyle(fontSize: 20, height: 1)),
                    ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: t.text.withValues(alpha: 0.08)),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            _columns =
                ((box.maxWidth - 2 * _padding) / _cell).floor().clamp(1, 12);
            if (results != null) return _resultsGrid(results, t, s);
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                for (final (id, emoji) in _sections) ...[
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _header,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            _padding + 4, 10, _padding, 4),
                        child: Semantics(
                          header: true,
                          child: Text(
                            s.emojiCategory(id),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.text.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: _padding),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columns,
                        mainAxisExtent: _cell,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _EmojiCell(
                          emoji: emoji[i],
                          theme: t,
                          onTap: () => _pick(emoji[i]),
                        ),
                        childCount: emoji.length,
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _EmojiSearchField extends StatelessWidget {
  final TextEditingController controller;
  final EasyLiveChatTheme theme;
  final ElcStrings strings;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String> onSubmitted;

  const _EmojiSearchField({
    required this.controller,
    required this.theme,
    required this.strings,
    required this.onChanged,
    required this.onClear,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: t.text.withValues(alpha: 0.12)),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        // Not focused on open: on a phone that raises the keyboard over the
        // emoji, which is why the web only does it with a real keyboard.
        textInputAction: TextInputAction.search,
        autocorrect: false,
        enableSuggestions: false,
        keyboardAppearance: t.brightness,
        cursorColor: t.primaryInk,
        style: TextStyle(color: t.text, fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          hintText: strings.emojiSearch,
          hintStyle: TextStyle(color: t.text.withValues(alpha: 0.45)),
          filled: true,
          fillColor: t.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: ExcludeSemantics(
            child: Icon(Icons.search_rounded,
                size: 20, color: t.text.withValues(alpha: 0.55)),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  tooltip: strings.helpSearchClear,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: t.text.withValues(alpha: 0.6)),
                ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: t.primaryInk, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final EasyLiveChatTheme theme;
  final VoidCallback onTap;

  const _EmojiCell(
      {required this.emoji, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        splashColor: theme.text.withValues(alpha: 0.08),
        highlightColor: theme.text.withValues(alpha: 0.07),
        child: Center(
          child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
        ),
      ),
    );
  }
}
