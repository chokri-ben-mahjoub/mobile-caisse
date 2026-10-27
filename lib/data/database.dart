import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local SQLite storage: products + sales. Works fully offline.
class AppDatabase {
  AppDatabase._(this._db, this.path);
  Database _db;
  final String path;

  static Future<String> _defaultPath() async => p.join(await getDatabasesPath(), 'caisse.db');

  /// Replaces the database file with [source] (a backup) and reopens it.
  /// Throws [FormatException] if [source] is not a valid Caisse backup.
  Future<void> restoreFrom(File source) async {
    final probe = await openDatabase(source.path, readOnly: true);
    try {
      final t = (await probe.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'])
          .toSet();
      if (!t.containsAll(['products', 'sales', 'sale_lines'])) {
        throw const FormatException('Fichier de sauvegarde invalide');
      }
    } finally {
      await probe.close();
    }
    await _db.close();
    await source.copy(path);
    _db = await _openAt(path);
  }

  /// Consistent single-file copy of the database, written to [dest].
  Future<void> backupTo(File dest) async {
    await _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    await File(path).copy(dest.path);
  }

  static Future<Database> _openAt(String path) => openDatabase(
      path,
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: (db, oldV, _) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE products ADD COLUMN cost REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE products ADD COLUMN stock INTEGER');
          await db.execute('ALTER TABLE products ADD COLUMN min_stock INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE sale_lines ADD COLUMN cost REAL NOT NULL DEFAULT 0');
        }
        if (oldV < 3) {
          await db.execute('ALTER TABLE sales ADD COLUMN discount REAL NOT NULL DEFAULT 0');
          await _createHeld(db);
        }
      },
    );

  static Future<AppDatabase> open() async {
    final path = await _defaultPath();
    return AppDatabase._(await _openAt(path), path);
  }

  /// Inserts or updates products. Existing purchase price / stock are kept
  /// unless the import file carried those columns ([updateCost], [updateStock]).
  Future<int> bulkUpsertProducts(List<Product> items,
      {bool updateCost = true, bool updateStock = true}) async {
    await _db.transaction((txn) async {
      for (final it in items) {
        final old = await txn.query('products', where: 'barcode = ?', whereArgs: [it.barcode], limit: 1);
        if (old.isEmpty) {
          await txn.insert('products', it.toMap());
        } else {
          final cur = Product.fromMap(old.first);
          await txn.update(
            'products',
            Product(
              barcode: it.barcode,
              name: it.name,
              price: it.price,
              cost: updateCost ? it.cost : cur.cost,
              stock: updateStock ? it.stock : cur.stock,
              minStock: updateStock ? it.minStock : cur.minStock,
            ).toMap(),
            where: 'barcode = ?',
            whereArgs: [it.barcode],
          );
        }
      }
    });
    return items.length;
  }

  Future<int> lowStockCount() async => Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM products WHERE stock IS NOT NULL AND stock <= min_stock')) ??
      0;

  /// Every sale line with its sale header, oldest first (for CSV export).
  Future<List<Map<String, Object?>>> salesFlat() => _db.rawQuery(
      'SELECT s.id AS id, s.date AS date, s.method AS method, s.total AS total, s.received AS received, s.discount AS discount, '
      'l.barcode AS barcode, l.name AS name, l.price AS price, l.qty AS qty, l.cost AS cost '
      'FROM sales s JOIN sale_lines l ON l.sale_id = s.id ORDER BY s.date, s.id, l.id');

  static Future<void> _create(Database db, int _) async {
    await db.execute('CREATE TABLE products('
        'barcode TEXT PRIMARY KEY, name TEXT NOT NULL, price REAL NOT NULL, '
        'cost REAL NOT NULL DEFAULT 0, stock INTEGER, min_stock INTEGER NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE sales('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, '
        'total REAL NOT NULL, method TEXT NOT NULL, received REAL, discount REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE sale_lines('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE, '
        'barcode TEXT NOT NULL, name TEXT NOT NULL, price REAL NOT NULL, qty INTEGER NOT NULL, cost REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE INDEX idx_sales_date ON sales(date)');
    await _createHeld(db);
  }

  static Future<void> _createHeld(Database db) => db.execute('CREATE TABLE held_carts('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, '
      'discount_type TEXT, discount_value REAL, lines TEXT NOT NULL)');

  // ---- held carts ----
  Future<void> holdCart(List<SaleLine> lines, Discount? d) => _db.insert('held_carts', {
        'date': DateTime.now().toIso8601String(),
        'discount_type': d?.type.name,
        'discount_value': d?.value,
        'lines': jsonEncode([
          for (final l in lines)
            {'barcode': l.barcode, 'name': l.name, 'price': l.price, 'qty': l.qty, 'cost': l.cost}
        ]),
      });

  Future<List<HeldCart>> heldCarts() async {
    final rows = await _db.query('held_carts', orderBy: 'date DESC');
    return rows.map((r) {
      final type = r['discount_type'] as String?;
      return HeldCart(
        id: r['id'] as int,
        date: DateTime.parse(r['date'] as String),
        lines: [
          for (final m in jsonDecode(r['lines'] as String) as List) SaleLine.fromMap((m as Map).cast<String, Object?>())
        ],
        discount: type == null
            ? null
            : Discount(DiscountType.values.byName(type), (r['discount_value'] as num).toDouble()),
      );
    }).toList();
  }

  Future<void> deleteHeld(int id) => _db.delete('held_carts', where: 'id = ?', whereArgs: [id]);

  // ---- products ----
  Future<List<Product>> products({String query = '', bool onlyLow = false}) async {
    final q = query.trim();
    final where = <String>[];
    final args = <Object>[];
    if (q.isNotEmpty) {
      where.add('(name LIKE ? OR barcode LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }
    if (onlyLow) where.add('stock IS NOT NULL AND stock <= min_stock');
    final rows = await _db.query('products',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'name COLLATE NOCASE');
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> productByBarcode(String barcode) async {
    final rows = await _db.query('products', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<void> upsertProduct(Product pr) =>
      _db.insert('products', pr.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteProduct(String barcode) =>
      _db.delete('products', where: 'barcode = ?', whereArgs: [barcode]);

  // ---- sales ----
  Future<Sale> insertSale(Sale sale) async {
    final id = await _db.transaction((txn) async {
      final id = await txn.insert('sales', {
        'date': sale.date.toIso8601String(),
        'total': sale.total,
        'method': sale.method.name,
        'received': sale.received,
        'discount': sale.discount,
      });
      for (final l in sale.lines) {
        await txn.insert('sale_lines', l.toMap(id));
        // Only tracked products (stock IS NOT NULL) are decremented; never below 0.
        await txn.rawUpdate(
            'UPDATE products SET stock = MAX(stock - ?, 0) WHERE barcode = ? AND stock IS NOT NULL',
            [l.qty, l.barcode]);
      }
      return id;
    });
    return sale.withId(id);
  }

  /// Sales of the given day (local time), newest first.
  Future<List<Sale>> salesOfDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _db.query('sales',
        where: 'date >= ? AND date < ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'date DESC');
    final sales = <Sale>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final lines = await _db.query('sale_lines', where: 'sale_id = ?', whereArgs: [id]);
      sales.add(Sale(
        id: id,
        date: DateTime.parse(r['date'] as String),
        total: (r['total'] as num).toDouble(),
        method: PayMethod.values.byName(r['method'] as String),
        received: (r['received'] as num?)?.toDouble(),
        discount: (r['discount'] as num?)?.toDouble() ?? 0,
        lines: lines.map(SaleLine.fromMap).toList(),
      ));
    }
    return sales;
  }
}
