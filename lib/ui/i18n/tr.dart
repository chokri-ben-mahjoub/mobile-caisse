import 'ar_tn.dart';

/// Language of the interface: French (source texts) or Tunisian Arabic.
///
/// The app's texts are written in French. In Arabic mode each text is looked up at
/// display time: exact phrase first, then patterns with `{}` wildcards (numbers, names,
/// amounts stay as they are), then phrase-by-phrase replacement inside longer texts.
/// A text with no translation is simply shown in French.
class Tr {
  Tr._();

  /// `fr` or `ar`. Set by [SettingsProvider]; read by [tr] for strings built outside a widget.
  static String lang = 'fr';
  static bool get isAr => lang == 'ar';

  static final Map<String, String> _cache = {};
  static List<_Pattern>? _patterns;
  static List<MapEntry<RegExp, String>>? _phrases;

  /// Translates [s] to Tunisian Arabic ([ar] true) or returns it unchanged.
  static String t(String s, {bool? ar}) {
    if (!(ar ?? isAr) || s.isEmpty) return s;
    return _cache.putIfAbsent(s, () => _translate(s, 0));
  }

  static String _translate(String s, int depth) {
    final exact = arExact[s];
    if (exact != null) return exact;
    final trimmed = s.trim();
    if (trimmed != s && trimmed.isNotEmpty) {
      final lead = s.substring(0, s.indexOf(trimmed));
      final tail = s.substring(lead.length + trimmed.length);
      return '$lead${_translate(trimmed, depth)}$tail';
    }
    if (depth < 3) {
      for (final p in (_patterns ??= _compile())) {
        final m = p.re.firstMatch(s);
        if (m == null) continue;
        return p.build(m, (x) => _translate(x, depth + 1));
      }
    }
    // "A · B · C": translate each part on its own.
    if (s.contains(' · ')) {
      return s.split(' · ').map((x) => _translate(x, depth)).join(' · ');
    }
    return _byPhrases(s);
  }

  static List<_Pattern> _compile() {
    final list = <_Pattern>[];
    arPatterns.forEach((fr, ar) {
      final re = StringBuffer('^');
      var i = 0;
      while (i < fr.length) {
        if (fr.startsWith('{}', i)) {
          re.write('(.+?)');
          i += 2;
        } else if (fr.startsWith('[s]', i)) {
          re.write('s?');
          i += 3;
        } else {
          re.write(RegExp.escape(fr[i]));
          i++;
        }
      }
      re.write(r'$');
      list.add(_Pattern(RegExp(re.toString(), dotAll: true), ar));
    });
    // Longer (more specific) patterns first.
    list.sort((a, b) => b.re.pattern.length.compareTo(a.re.pattern.length));
    return list;
  }

  /// Replaces known phrases inside a longer text ("Achat à crédit · ticket 12").
  static String _byPhrases(String s) {
    final phrases = _phrases ??= (arExact.entries.where((e) => e.key.length >= 4 && !e.key.contains('\n')).toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length)))
        .map((e) => MapEntry(RegExp('(?<![A-Za-zÀ-ÿ])${RegExp.escape(e.key)}(?![A-Za-zÀ-ÿ])'), e.value))
        .toList();
    var out = s;
    for (final p in phrases) {
      if (p.key.hasMatch(out)) out = out.replaceAll(p.key, p.value);
    }
    return out;
  }
}

class _Pattern {
  _Pattern(this.re, this.template);
  final RegExp re;
  final String template;

  /// Fills `{1}`, `{2}`… with the (translated) captures; `{1?one|many}` picks by `1`.
  String build(RegExpMatch m, String Function(String) translateCapture) {
    return template.replaceAllMapped(RegExp(r'\{(\d)(?:\?([^|}]*)\|([^}]*))?\}'), (g) {
      final n = int.parse(g[1]!);
      final cap = m.group(n) ?? '';
      if (g[2] != null) return cap.trim() == '1' ? g[2]! : g[3]!;
      return translateCapture(cap);
    });
  }
}

/// Translates a French UI text for the current language (use inside builders and helpers).
String tr(String s) => Tr.t(s);
