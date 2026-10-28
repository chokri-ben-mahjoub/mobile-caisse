import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_caisse/data/credit.dart';
import 'package:mob_caisse/data/settings_store.dart';

CreditEntry e(String who, double amount, int daysAgo, {String phone = ''}) => CreditEntry(
      customer: who,
      phone: phone,
      amount: amount,
      date: DateTime.now().subtract(Duration(days: daysAgo)),
    );

void main() {
  test('accounts group by customer name, case-insensitive, with balance', () {
    // Newest first, as the database returns them.
    final accounts = CreditAccount.group([
      e('sami', -10, 1),
      e('Sami', 25, 3, phone: '20123456'),
      e('Leila', 8, 2),
    ]);
    expect(accounts.length, 2);
    final sami = accounts.firstWhere((a) => a.name.toLowerCase() == 'sami');
    expect(sami.balance, 15);
    expect(sami.phone, '20123456');
    expect(accounts.first.name.toLowerCase(), 'sami'); // biggest balance first
  });

  test('payments settle the oldest purchase first', () {
    final a = CreditAccount('Sami', '', [
      e('Sami', -10, 1),
      e('Sami', 20, 5), // newer purchase, still owed 10
      e('Sami', 10, 40), // oldest, fully paid by the 10 DT payment
    ]);
    expect(a.balance, 20);
    final since = a.oldestUnpaid!;
    expect(DateTime.now().difference(since).inDays, 5);
  });

  test('a settled account has no oldest unpaid date', () {
    final a = CreditAccount('Sami', '', [e('Sami', -10, 1), e('Sami', 10, 2)]);
    expect(a.balance, 0);
    expect(a.oldestUnpaid, isNull);
  });

  test('credit entry survives a map round trip', () {
    final x = CreditEntry(customer: 'Sami', phone: '2012', amount: 12.5, date: DateTime(2026, 10, 1, 9), saleId: 7, note: 'n');
    final y = CreditEntry.fromMap({...x.toMap(), 'id': 3});
    expect((y.id, y.customer, y.amount, y.saleId, y.note, y.date), (3, 'Sami', 12.5, 7, 'n', DateTime(2026, 10, 1, 9)));
  });

  test('auto theme is dark in the evening and light by day', () {
    const s = AppSettings(themeMode: 'auto');
    expect(s.resolveThemeMode(DateTime(2026, 10, 28, 20)), ThemeMode.dark);
    expect(s.resolveThemeMode(DateTime(2026, 10, 28, 3)), ThemeMode.dark);
    expect(s.resolveThemeMode(DateTime(2026, 10, 28, 7)), ThemeMode.light);
    expect(s.resolveThemeMode(DateTime(2026, 10, 28, 18, 59)), ThemeMode.light);
    expect(const AppSettings().resolveThemeMode(DateTime(2026, 10, 28, 22)), ThemeMode.system);
    expect(const AppSettings(themeMode: 'dark').resolveThemeMode(DateTime(2026, 10, 28, 12)), ThemeMode.dark);
  });
}
