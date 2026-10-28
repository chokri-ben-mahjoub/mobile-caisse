import 'package:intl/intl.dart';

import 'tr.dart';

/// Formats dates for the screen in the current language.
///
/// French uses the usual `intl` formats. In Arabic the months and weekdays use the names
/// Tunisians actually say (جانفي، فيفري، أفريل، جوان، جويلية، أوت…), digits stay 0-9, and
/// all-numeric dates are kept left to right so "28/10/2026 09:05" is not reordered
/// by the right-to-left text layout.
class DateFmt {
  const DateFmt(this.pattern);
  final String pattern;

  String format(DateTime d) => fmtDate(pattern, d);
}

const _months = ['جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان', 'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
// DateTime.weekday: Monday = 1 … Sunday = 7.
const _days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDate(String pattern, DateTime d, {bool? ar}) {
  if (!(ar ?? Tr.isAr)) return DateFormat(pattern, 'fr_FR').format(d);
  final out = StringBuffer();
  var named = false;
  var i = 0;
  bool at(String t) => pattern.startsWith(t, i);
  while (i < pattern.length) {
    if (at('EEEE') || at('EEE')) {
      out.write(_days[d.weekday - 1]);
      i += at('EEEE') ? 4 : 3;
      named = true;
    } else if (at('MMMM') || at('MMM')) {
      out.write(_months[d.month - 1]);
      i += at('MMMM') ? 4 : 3;
      named = true;
    } else if (at('yyyy')) {
      out.write(d.year);
      i += 4;
    } else if (at('dd')) {
      out.write(_two(d.day));
      i += 2;
    } else if (at('MM')) {
      out.write(_two(d.month));
      i += 2;
    } else if (at('HH')) {
      out.write(_two(d.hour));
      i += 2;
    } else if (at('mm')) {
      out.write(_two(d.minute));
      i += 2;
    } else if (at('d')) {
      out.write(d.day);
      i++;
    } else {
      out.write(pattern[i]);
      i++;
    }
  }
  final s = out.toString();
  // Left-to-right isolate around purely numeric dates / times.
  return named ? s : '$_lri$s$_pdi';
}

// Left-to-right isolate / pop directional isolate, built from code points.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);
