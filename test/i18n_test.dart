import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:mob_caisse/ui/i18n/ar_tn.dart';
import 'package:mob_caisse/ui/i18n/date_fmt.dart';
import 'package:mob_caisse/ui/i18n/text.dart';
import 'package:mob_caisse/ui/i18n/tr.dart';

/// Arabic translation without the invisible left-to-right isolates wrapped around numbers.
String ar(String s) => Tr.t(s, ar: true).replaceAll(RegExp('[\u2066\u2069]'), '').replaceAll(' ', ' ');

void main() {
  setUpAll(initializeDateFormatting); // the app does this in main()

  test('French stays untouched', () {
    expect(Tr.t('Encaisser', ar: false), 'Encaisser');
    expect(Tr.t('3 articles'), '3 articles'); // default language is French
  });

  test('exact phrases translate to Tunisian Arabic', () {
    expect(ar('Caisse'), 'الكاسة');
    expect(ar('Glisser pour encaisser'), 'اسحب باش تقبض');
    expect(ar('Crédit clients'), 'كريدي الحرفاء');
  });

  test('patterns keep numbers and amounts, with singular and plural forms', () {
    expect(ar('1 article'), '1 سلعة');
    expect(ar('3 articles'), '3 سلع');
    expect(ar('Doit 12,500 DT'), 'عليه 12,500 DT');
    expect(ar('Stock : 12 → 36'), 'المخزون : 12 ← 36');
    expect(ar('Expire dans 5 jours'), 'ينتهي في 5 أيام');
    expect(ar('Expire dans 1 jour'), 'ينتهي في 1 نهار');
  });

  test('captures are translated too and parts of "A · B" are handled one by one', () {
    expect(ar('Paiement : Espèces'), 'الدفع : Espèces'.replaceFirst('Espèces', 'كاش'));
    expect(ar('12 articles · Espèces · Ahmed'), '12 سلع · كاش · Ahmed');
    expect(ar('Achat à crédit · ticket 7'), 'شراء كريدي · وصل 7');
  });

  test('multi-line texts and surrounding spaces', () {
    expect(ar('Aucun crédit pour le moment.\nChoisissez « Crédit » au moment du paiement pour mettre une vente sur le compte d\'un client.'),
        startsWith('ما فما حتى كريدي'));
    expect(ar('Le code-barres 123 n\'est pas dans votre base.\n\nVoulez-vous créer ce produit ?'), contains('123'));
    expect(ar('  Caisse '), '  الكاسة ');
  });

  test('lists, units and composed labels', () {
    expect(ar('Produits, Stock, Retours et annulations'), 'المنتوجات، المخزون، الترجيعات والإلغاءات');
    expect(ar('2,5 kg'), '2,5 كغ');
    expect(ar('Verrouiller · connecté : Ahmed'), 'اقفل · مُتّصل : Ahmed');
    expect(ar('Remboursement en espèces'), 'استرجاع كاش');
    expect(ar('7 jours'), '7 أيام');
    expect(ar('Role: Gérant'), contains('مسيّر'));
  });

  test('numbers with their unit are isolated so "2,200 DT × 3" keeps its order in Arabic', () {
    final lri = String.fromCharCode(0x2066), pdi = String.fromCharCode(0x2069);
    expect(Tr.t('2,200 DT × 3', ar: true), '${lri}2,200 DT × 3$pdi');
    expect(Tr.t('×12', ar: true), '$lri×12$pdi');
    expect(Tr.t('Doit 12,500 DT', ar: true), 'عليه $lri' '12,500 DT$pdi');
    expect(Tr.t('2,200 DT × 3', ar: false), '2,200 DT × 3');
  });

  test('user data is left alone', () {
    expect(ar('Lait Delice 1L'), 'Lait Delice 1L');
    expect(ar('12,500 DT'), '12,500 DT');
  });

  test('every dictionary entry translates to something', () {
    arExact.forEach((k, v) => expect(v.trim(), isNotEmpty, reason: k));
    arPatterns.forEach((k, v) => expect(v.trim(), isNotEmpty, reason: k));
  });

  test('Arabic dates: Tunisian month names, Western digits, numeric dates kept left to right', () {
    final d = DateTime(2026, 10, 28, 9, 5);
    final lri = String.fromCharCode(0x2066), pdi = String.fromCharCode(0x2069);
    expect(fmtDate('dd/MM/yyyy HH:mm', d, ar: true), '${lri}28/10/2026 09:05$pdi');
    expect(fmtDate('dd/MM HH:mm', d, ar: true), '${lri}28/10 09:05$pdi');
    expect(fmtDate('d MMM', d, ar: true), '28 أكتوبر');
    expect(fmtDate('EEEE d MMMM', d, ar: true), 'الأربعاء 28 أكتوبر');
    expect(fmtDate('dd MMM yyyy', DateTime(2026, 1, 5), ar: true), '05 جانفي 2026');
    expect(fmtDate('d MMM', DateTime(2026, 7, 3), ar: true), '3 جويلية');
    expect(fmtDate('dd/MM/yyyy', d, ar: false), '28/10/2026');
  });

  test('Arabic dates (Tunisia) use Western digits', () async {
    await initializeDateFormatting();
    final d = DateFormat('dd/MM/yyyy', 'ar_TN').format(DateTime(2026, 10, 28));
    expect(d, matches(RegExp(r'^[0-9/]+$')), reason: d);
  });

  testWidgets('Text follows the locale and the screen turns right to left', (tester) async {
    Locale locale = const Locale('fr');
    late StateSetter set;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      set = setState;
      return MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('fr'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: Center(child: Text('Nouvelle vente'))),
      );
    }));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle vente'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(Scaffold))), TextDirection.ltr);

    set(() => locale = const Locale('ar'));
    await tester.pumpAndSettle();
    expect(find.text('بيعة جديدة'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(Scaffold))), TextDirection.rtl);
  });
}
