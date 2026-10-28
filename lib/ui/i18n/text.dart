import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';

import 'tr.dart';

/// Drop-in replacement for the framework's `Text` that translates its (French) string
/// into the language of the surrounding [Localizations], so every label follows the language setting.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.textScaler,
    this.semanticsLabel,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextScaler? textScaler;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // Reading the locale subscribes this widget to language changes.
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return m.Text(
      Tr.t(data, ar: ar),
      style: style,
      textAlign: textAlign,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      textScaler: textScaler,
      semanticsLabel: semanticsLabel,
    );
  }
}
