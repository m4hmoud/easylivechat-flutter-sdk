#!/usr/bin/env python3
"""Write sdk_strings.json back into the Dart translation table.

The table lives in `lib/src/l10n.dart` as a `const` map, because the SDK has
to resolve strings without doing IO — a chat that waits on a file read to know
the word for "Send" is a chat that flickers. So this file is the editable
source and the Dart map is generated from it.

Run after editing sdk_strings.json:

    python3 flutter-sdk/packages/easylivechat_ui/l10n/apply.py

Only the table is rewritten; the surrounding class, getters and comments are
left exactly as they are. A blank value is dropped rather than written as an
empty string, so the key falls back to English at runtime instead of rendering
nothing — an untranslated button is usable, a blank one is not.
"""
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
STRINGS = HERE / 'sdk_strings.json'
DART = HERE.parent / 'lib' / 'src' / 'l10n.dart'
ANCHOR = 'static const Map<String, Map<String, String>> _table = {'


def dart_literal(value: str) -> str:
    """Quote for Dart, preferring single quotes like the rest of the file."""
    if "'" in value and '"' not in value:
        return '"%s"' % value.replace('\\', '\\\\').replace('$', r'\$')
    escaped = value.replace('\\', '\\\\').replace("'", r"\'").replace('$', r'\$')
    return "'%s'" % escaped


def main() -> int:
    data = json.loads(STRINGS.read_text(encoding='utf-8'))
    data.pop('_readme', None)
    if 'en' not in data:
        print('error: sdk_strings.json has no "en" block to fall back to')
        return 1

    lines = ['  ' + ANCHOR]
    for locale, block in data.items():
        lines.append("    '%s': {" % locale)
        for key, value in block.items():
            if not value.strip():
                continue  # fall back to English rather than render blank
            lines.append('      %s: %s,' % (dart_literal(key), dart_literal(value)))
        lines.append('    },')
    lines.append('  };')
    table = '\n'.join(lines)

    src = DART.read_text(encoding='utf-8')
    start = src.index('  ' + ANCHOR)
    # The table ends at the first `  };` at its own indentation.
    end = src.index('\n  };', start) + len('\n  };')
    DART.write_text(src[:start] + table + src[end:], encoding='utf-8')

    counts = {k: sum(1 for v in b.values() if v.strip()) for k, b in data.items()}
    print('wrote %s' % DART)
    print('locales: %d' % len(data))
    for loc, n in counts.items():
        gap = len(data['en']) - n
        print('  %-4s %3d strings%s' % (loc, n, '  (%d fall back to English)' % gap if gap else ''))
    print('\nNow run: cd %s && flutter analyze' % DART.parents[2])
    return 0


if __name__ == '__main__':
    sys.exit(main())
