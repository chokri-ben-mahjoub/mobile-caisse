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
      version: 6,
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
        if (oldV < 4) {
          await db.execute("ALTER TABLE products ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0");
          await db.execute("ALTER TABLE sales ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0");
        }
        if (oldV < 5) {
          await db.execute("ALTER TABLE sales ADD COLUMN user_name TEXT");
          await _createUsers(db);
        }
        if (oldV < 6) {
          await db.execute("ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE products ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
          await db.execute("ALTER TABLE sale_lines ADD COLUMN unit TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE sales ADD COLUMN kind TEXT NOT NULL DEFAULT 'sale'");
          await db.execute('ALTER TABLE sales ADD COLUMN ref_sale_id INTEGER');
          await db.execute('ALTER TABLE sales ADD COLUMN reason TEXT');
          await _createClosings(db);
          // Managers get the new rights (returns, cash closing) by default.
          await db.execute("UPDATE users SET perms = perms | 96 WHERE role = 'manager'");
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
      {bool updateCost = true, bool updateStock = true, bool updateUnit = false}) async {
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
              unit: updateUnit ? it.unit : cur.unit,
              favorite: cur.favorite,
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
      'SELECT s.id AS id, s.date AS date, s.method AS method, s.total AS total, s.received AS received, s.discount AS discount, s.user_name AS seller, '
      's.kind AS kind, s.ref_sale_id AS ref_sale_id, '
      'l.barcode AS barcode, l.name AS name, l.price AS price, l.qty AS qty, l.cost AS cost, l.unit AS unit '
      'FROM sales s JOIN sale_lines l ON l.sale_id = s.id ORDER BY s.date, s.id, l.id');

  static Future<void> _create(Database db, int _) async {
    await db.execute('CREATE TABLE products('
        'barcode TEXT PRIMARY KEY, name TEXT NOT NULL, price REAL NOT NULL, '
        'cost REAL NOT NULL DEFAULT 0, stock REAL, min_stock INTEGER NOT NULL DEFAULT 0, '
        "is_demo INTEGER NOT NULL DEFAULT 0, unit TEXT NOT NULL DEFAULT '', favorite INTEGER NOT NULL DEFAULT 0)");
    await db.execute('CREATE TABLE sales('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, '
        'total REAL NOT NULL, method TEXT NOT NULL, received REAL, discount REAL NOT NULL DEFAULT 0, '
        "is_demo INTEGER NOT NULL DEFAULT 0, user_name TEXT, "
        "kind TEXT NOT NULL DEFAULT 'sale', ref_sale_id INTEGER, reason TEXT)");
    await db.execute('CREATE TABLE sale_lines('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE, '
        'barcode TEXT NOT NULL, name TEXT NOT NULL, price REAL NOT NULL, qty REAL NOT NULL, cost REAL NOT NULL DEFAULT 0, '
        "unit TEXT NOT NULL DEFAULT '')");
    await db.execute('CREATE INDEX idx_sales_date ON sales(date)');
    await _createHeld(db);
    await _createUsers(db);
    await _createClosings(db);
  }

  static Future<void> _createClosings(Database db) => db.execute('CREATE TABLE cash_closings('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, closed_at TEXT NOT NULL, period_start TEXT NOT NULL, '
      'user_name TEXT, opening_float REAL NOT NULL, expected_cash REAL NOT NULL, counted_cash REAL NOT NULL, '
      'float_left REAL NOT NULL, sales_count INTEGER NOT NULL, refunds_count INTEGER NOT NULL, '
      'gross REAL NOT NULL, discounts REAL NOT NULL, refunds REAL NOT NULL, net REAL NOT NULL, '
      'cash REAL NOT NULL, qr REAL NOT NULL, profit REAL NOT NULL, note TEXT)');

  static Future<void> _createUsers(Database db) => db.execute('CREATE TABLE users('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE, '
      'pin_hash TEXT NOT NULL, role TEXT NOT NULL, perms INTEGER NOT NULL)');

  // ---- users ----
  Future<List<AppUser>> users() async =>
      (await _db.query('users', orderBy: 'id')).map(AppUser.fromMap).toList();

  Future<int> insertUser(AppUser u) => _db.insert('users', u.toMap());

  Future<void> updateUser(AppUser u) =>
      _db.update('users', u.toMap(), where: 'id = ?', whereArgs: [u.id]);

  Future<void> deleteUser(int id) => _db.delete('users', where: 'id = ?', whereArgs: [id]);

  Future<void> deleteAllUsers() => _db.delete('users');

  static Future<void> _createHeld(Database db) => db.execute('CREATE TABLE held_carts('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, '
      'discount_type TEXT, discount_value REAL, lines TEXT NOT NULL)');

  // ---- demo data ----
  Future<bool> hasDemo() async =>
      (Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM products WHERE is_demo = 1')) ?? 0) > 0;

  /// Inserts demo products (existing real products with the same barcode are
  /// left untouched) and demo sales, all flagged `is_demo = 1`.
  Future<void> insertDemo(List<Product> products, List<Sale> sales) async {
    await _db.transaction((txn) async {
      for (final p in products) {
        await txn.insert('products', {...p.toMap(), 'is_demo': 1}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final s in sales) {
        final id = await txn.insert('sales', {
          'date': s.date.toIso8601String(),
          'total': s.total,
          'method': s.method.name,
          'received': s.received,
          'discount': s.discount,
          'is_demo': 1,
        });
        for (final l in s.lines) {
          await txn.insert('sale_lines', l.toMap(id));
        }
      }
    });
  }

  /// Removes every demo product and demo sale, plus any real sale or held cart
  /// made with a demo product during a demonstration. Real data is untouched.
  Future<void> clearDemo() async {
    final held = await heldCarts();
    await _db.transaction((txn) async {
      final demoCodes = '(SELECT barcode FROM products WHERE is_demo = 1)';
      final doomed = 'SELECT id FROM sales WHERE is_demo = 1 '
          'OR id IN (SELECT sale_id FROM sale_lines WHERE barcode IN $demoCodes)';
      final ids = (await txn.rawQuery(doomed)).map((r) => r['id'] as int).join(',');
      if (ids.isNotEmpty) {
        await txn.execute('DELETE FROM sale_lines WHERE sale_id IN ($ids)');
        await txn.execute('DELETE FROM sales WHERE id IN ($ids)');
      }
      final codes = (await txn.rawQuery('SELECT barcode FROM products WHERE is_demo = 1'))
          .map((r) => r['barcode'] as String)
          .toSet();
      for (final h in held) {
        if (h.lines.any((l) => codes.contains(l.barcode))) {
          await txn.delete('held_carts', where: 'id = ?', whereArgs: [h.id]);
        }
      }
      await txn.delete('products', where: 'is_demo = 1');
    });
  }

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
    final code = barcode.trim();
    var rows = await _db.query('products', where: 'barcode = ?', whereArgs: [code], limit: 1);
    if (rows.isEmpty) {
      // The same EAN/UPC can be read with or without leading zeros
      // (UPC-A 12 digits vs EAN-13 with a leading 0): compare without them.
      final bare = code.replaceFirst(RegExp(r'^0+'), '');
      if (bare.isNotEmpty) {
        rows = await _db.rawQuery(
            "SELECT * FROM products WHERE LTRIM(TRIM(barcode), '0') = ? LIMIT 1", [bare]);
      }
    }
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<void> upsertProduct(Product pr) =>
      _db.insert('products', pr.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// Sets the stock of one product (and starts tracking it), keeping every other column.
  Future<void> setStock(String barcode, double value) => _db.update(
      'products', {'stock': value < 0 ? 0 : value},
      where: 'barcode = ?', whereArgs: [barcode]);

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
        'user_name': sale.seller,
        'kind': sale.kind.name,
        'ref_sale_id': sale.refSaleId,
        'reason': sale.reason,
      });
      for (final l in sale.lines) {
        await txn.insert('sale_lines', l.toMap(id));
        // Only tracked products (stock IS NOT NULL) change. A sale (positive qty)
        // takes stock out, never below 0; a return (negative qty) puts it back,
        // unless the items are not to be restocked (damaged goods).
        if (sale.isRefund && !sale.restock) continue;
        await txn.rawUpdate(
            'UPDATE products SET stock = MAX(stock - ?, 0) WHERE barcode = ? AND stock IS NOT NULL',
            [l.qty, l.barcode]);
      }
      return id;
    });
    return sale.withId(id);
  }

  /// Sales and returns of the given day (local time), newest first.
  Future<List<Sale>> salesOfDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return salesBetween(start, start.add(const Duration(days: 1)));
  }

  /// Sales and returns with `start <= date < end`, newest first.
  Future<List<Sale>> salesBetween(DateTime start, DateTime end) async {
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
        seller: r['user_name'] as String?,
        kind: SaleKind.values.byName((r['kind'] as String?) ?? 'sale'),
        refSaleId: r['ref_sale_id'] as int?,
        reason: r['reason'] as String?,
        lines: lines.map(SaleLine.fromMap).toList(),
      ));
    }
    return sales;
  }

  /// Quantity already returned for each article of sale [saleId]
  /// (barcode -> positive quantity).
  Future<Map<String, double>> returnedQty(int saleId) async {
    final rows = await _db.rawQuery(
        'SELECT l.barcode AS barcode, SUM(l.qty) AS qty FROM sales s '
        'JOIN sale_lines l ON l.sale_id = s.id '
        "WHERE s.ref_sale_id = ? AND s.kind = 'refund' GROUP BY l.barcode",
        [saleId]);
    return {for (final r in rows) r['barcode'] as String: -(r['qty'] as num).toDouble()};
  }

  // ---- cash closings ----
  Future<int> insertClosing(CashClosing c) => _db.insert('cash_closings', c.toMap());

  Future<List<CashClosing>> closings({int limit = 60}) async =>
      (await _db.query('cash_closings', orderBy: 'closed_at DESC', limit: limit))
          .map(CashClosing.fromMap)
          .toList();

  Future<CashClosing?> lastClosing() async {
    final rows = await _db.query('cash_closings', orderBy: 'closed_at DESC', limit: 1);
    return rows.isEmpty ? null : CashClosing.fromMap(rows.first);
  }
}
