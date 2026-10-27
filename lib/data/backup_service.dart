import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';
import 'models.dart';

class ImportResult {
  final int imported;
  final int skipped;
  const ImportResult(this.imported, this.skipped);
}

/// Backup / restore of the database, CSV export of sales and products,
/// CSV import of products.
class ParsedProducts {
  final List<Product> items;
  final int skipped;
  final bool hasCost;
  final bool hasStock;
  final bool hasUnit;
  const ParsedProducts(this.items, this.skipped,
      {this.hasCost = false, this.hasStock = false, this.hasUnit = false});
}

class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  static String _stamp() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}';
  }

  Future<File> _tmp(String name) async => File('${(await getTemporaryDirectory()).path}/$name');

  Future<void> _share(File f, String subject) =>
      SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: subject));

  // ---- backup / restore ----
  Future<void> shareBackup() async {
    final f = await _tmp('caisse_sauvegarde_${_stamp()}.db');
    await _db.backupTo(f);
    await _share(f, 'Sauvegarde Caisse');
  }

  /// Returns false if the user cancelled. Throws [FormatException] on a bad file.
  Future<bool> restoreFromPicker() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choisir une sauvegarde');
    if (picked == null || picked.path == null) return false;
    await _db.restoreFrom(File(picked.path!));
    return true;
  }

  // ---- CSV export ----
  static String esc(Object? v) {
    final s = v?.toString() ?? '';
    return (s.contains(';') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static String dec(num? v) => v == null ? '' : v.toString().replaceAll('.', ',');

  Future<void> shareSalesCsv() async {
    final rows = await _db.salesFlat();
    final b = StringBuffer('﻿Ticket;Date;Heure;Paiement;Code-barres;Article;Prix;Quantité;Total ligne;Prix d\'achat;Bénéfice ligne;Remise ticket;Total ticket;Montant reçu;Vendeur;Type;Ticket origine;Unité\n');
    for (final r in rows) {
      final d = DateTime.parse(r['date'] as String);
      String t(int v) => v.toString().padLeft(2, '0');
      final price = (r['price'] as num).toDouble();
      final qty = (r['qty'] as num).toDouble();
      final cost = (r['cost'] as num).toDouble();
      b.writeln([
        r['id'],
        '${t(d.day)}/${t(d.month)}/${d.year}',
        '${t(d.hour)}:${t(d.minute)}',
        r['method'] == 'cash' ? 'Espèces' : 'QR code',
        esc(r['barcode']),
        esc(r['name']),
        dec(price),
        fmtQty(qty),
        dec(round3(price * qty)),
        cost > 0 ? dec(cost) : '',
        cost > 0 ? dec(round3((price - cost) * qty)) : '',
        (r['discount'] as num) > 0 ? dec(r['discount'] as num) : '',
        dec(r['total'] as num),
        dec(r['received'] as num?),
        esc(r['seller']),
        r['kind'] == 'refund' ? 'Retour' : 'Vente',
        r['ref_sale_id'] ?? '',
        esc(r['unit']),
      ].join(';'));
    }
    final f = await _tmp('ventes_${_stamp()}.csv');
    await f.writeAsString(b.toString());
    await _share(f, 'Ventes');
  }

  Future<void> shareProductsCsv() async {
    final b = StringBuffer('﻿Code-barres;Nom;Prix;Prix d\'achat;Stock;Seuil alerte;Unité\n');
    for (final p in await _db.products()) {
      b.writeln('${esc(p.barcode)};${esc(p.name)};${dec(p.price)};${p.cost > 0 ? dec(p.cost) : ''};'
          '${p.stock == null ? '' : fmtQty(p.stock!)};${p.tracked ? p.minStock : ''};${p.unit}');
    }
    final f = await _tmp('produits_${_stamp()}.csv');
    await f.writeAsString(b.toString());
    await _share(f, 'Produits');
  }

  // ---- CSV import ----
  /// Returns null if the user cancelled.
  Future<ImportResult?> importProductsFromPicker() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choisir un fichier CSV',
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    if (picked == null || picked.path == null) return null;
    final text = await File(picked.path!).readAsString();
    final parsed = parseProducts(text);
    await _db.bulkUpsertProducts(parsed.items,
        updateCost: parsed.hasCost, updateStock: parsed.hasStock, updateUnit: parsed.hasUnit);
    return ImportResult(parsed.items.length, parsed.skipped);
  }

  /// Parses `barcode;name;price[;cost;stock;min]` rows (separator ; or , or tab;
  /// header optional). Cost / stock columns are only read when the header names them.
  static ParsedProducts parseProducts(String text) {
    final src = text.replaceFirst('﻿', '');
    final firstLine = src.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    final sep = [';', '\t', ','].reduce((a, b) => _count(firstLine, a) >= _count(firstLine, b) ? a : b);
    final rows = _parseCsv(src, sep).where((r) => r.any((c) => c.trim().isNotEmpty)).toList();

    var ci = 0, ni = 1, pi = 2, ki = -1, si = -1, mi = -1, ui = -1;
    if (rows.isNotEmpty) {
      final head = rows.first.map((c) => c.trim().toLowerCase()).toList();
      final price = head.indexWhere((c) => (c.contains('prix') || c.contains('price')) && !c.contains('achat') && !c.contains('cost'));
      if (price >= 0 || head.any((c) => c.contains('code') || c.contains('nom') || c.contains('name'))) {
        final code = head.indexWhere((c) => c.contains('code') || c.contains('barcode') || c.contains('ean'));
        final name = head.indexWhere((c) => c.contains('nom') || c.contains('name') || c.contains('article') || c.contains('désignation'));
        if (code >= 0) ci = code;
        if (name >= 0) ni = name;
        if (price >= 0) pi = price;
        ki = head.indexWhere((c) => c.contains('achat') || c.contains('cost') || c.contains('coût') || c.contains('cout'));
        mi = head.indexWhere((c) => c.contains('seuil') || c.contains('alerte') || c.contains('min'));
        si = head.indexWhere((c) => c.contains('stock') && !c.contains('seuil') && !c.contains('alerte'));
        ui = head.indexWhere((c) => c.contains('unit'));
        rows.removeAt(0);
      }
    }

    final byCode = <String, Product>{};
    var skipped = 0;
    for (final r in rows) {
      String at(int i) => i < r.length ? r[i].trim() : '';
      final price = double.tryParse(at(pi).replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '.'));
      if (at(ci).isEmpty || at(ni).isEmpty || price == null || price < 0) {
        skipped++;
        continue;
      }
      final cost = ki >= 0 ? double.tryParse(at(ki).replaceAll(',', '.')) : null;
      final stock = si >= 0 ? double.tryParse(at(si).replaceAll(',', '.')) : null;
      final minStock = mi >= 0 ? int.tryParse(at(mi)) : null;
      final unit = ui >= 0 && at(ui).toLowerCase().startsWith('kg') ? 'kg' : '';
      byCode[at(ci)] = Product(
        barcode: at(ci),
        name: at(ni),
        price: price,
        cost: cost != null && cost > 0 ? cost : 0,
        stock: stock,
        minStock: stock == null ? 0 : (minStock ?? 0),
        unit: unit,
      );
    }
    return ParsedProducts(byCode.values.toList(), skipped, hasCost: ki >= 0, hasStock: si >= 0, hasUnit: ui >= 0);
  }

  static int _count(String s, String ch) => ch.allMatches(s).length;

  static List<List<String>> _parseCsv(String s, String sep) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == sep) {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }
}
