import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mob_caisse/data/database.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/scan_sound.dart';
import 'package:mob_caisse/data/settings_store.dart';
import 'package:mob_caisse/logic/cart_provider.dart';
import 'package:mob_caisse/ui/screens/cart_screen.dart';
import 'package:mob_caisse/ui/theme.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(Future.value(ByteData.view(File('assets/fonts/Roboto-$f.ttf').readAsBytesSync().buffer)));
    }
    await loader.load();
  });

  test('the last scanned article is first in the list and is the "last line"', () async {
    final db = await AppDatabase.openAt(inMemoryDatabasePath);
    await db.upsertProduct(const Product(barcode: '111', name: 'Lait', price: 1.5));
    await db.upsertProduct(const Product(barcode: '222', name: 'Eau', price: 0.7));
    await db.upsertProduct(const Product(barcode: '333', name: 'Pain', price: 0.25));
    final cart = CartProvider(db);
    expect(cart.lastLine, isNull);

    await cart.scan('111');
    await cart.scan('222');
    await cart.scan('333');
    expect(cart.lastLine!.name, 'Pain');
    expect(cart.recentLines.map((l) => l.name), ['Pain', 'Eau', 'Lait']);

    await cart.scan('111'); // scanning an older article again brings it back on top
    expect(cart.lastLine!.name, 'Lait');
    expect(cart.lastLine!.qty, 2);
    expect(cart.recentLines.first.name, 'Lait');

    cart.remove('111');
    expect(cart.lastLine!.name, 'Pain');
    cart.clear();
    expect(cart.lastLine, isNull);
    expect(cart.recentLines, isEmpty);
  });

  test('sound falls back to the system click when the native side is missing', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('caisse/sound'), (c) async {
      calls.add(c.method);
      return null;
    });
    await ScanSound.beep();
    await ScanSound.error();
    expect(calls, ['beep', 'error']);
    expect(const AppSettings().scanSound, isTrue);
  });

  testWidgets('the last-scan card fits a 360 px phone with a long name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: LastScanCard(
          line: SaleLine(barcode: '1', name: 'Biscuits chocolat noir fourrés à la noisette 250 g', price: 12.5, qty: 12),
          settings: AppSettings(),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('×12'), findsOneWidget);
    expect(find.text('150,000 DT'), findsOneWidget);
  });
}
