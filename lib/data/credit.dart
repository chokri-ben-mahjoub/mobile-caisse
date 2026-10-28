/// One line of a customer's account: a sale put on credit (amount > 0) or a payment (amount < 0).
class CreditEntry {
  final int? id;
  final String customer;
  final String phone;
  final double amount;
  final DateTime date;
  final int? saleId;
  final String note;

  const CreditEntry({
    this.id,
    required this.customer,
    this.phone = '',
    required this.amount,
    required this.date,
    this.saleId,
    this.note = '',
  });

  bool get isPayment => amount < 0;

  Map<String, Object?> toMap() => {
        'customer': customer,
        'phone': phone,
        'amount': amount,
        'date': date.toIso8601String(),
        'sale_id': saleId,
        'note': note,
      };

  static CreditEntry fromMap(Map<String, Object?> m) => CreditEntry(
        id: m['id'] as int?,
        customer: m['customer'] as String,
        phone: (m['phone'] as String?) ?? '',
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.parse(m['date'] as String),
        saleId: m['sale_id'] as int?,
        note: (m['note'] as String?) ?? '',
      );
}

/// Everything one customer owes, grouped from the ledger.
class CreditAccount {
  CreditAccount(this.name, this.phone, this.entries);
  final String name;
  final String phone;

  /// Newest first.
  final List<CreditEntry> entries;

  double get balance => (entries.fold(0.0, (s, e) => s + e.amount) * 1000).round() / 1000;
  DateTime get lastActivity => entries.first.date;

  /// Date of the oldest purchase not yet covered by payments (FIFO), null when settled.
  DateTime? get oldestUnpaid {
    if (balance <= 0.0005) return null;
    var paid = -entries.where((e) => e.isPayment).fold(0.0, (s, e) => s + e.amount);
    for (final e in entries.reversed.where((e) => !e.isPayment)) {
      paid -= e.amount;
      if (paid < -0.0005) return e.date;
    }
    return null;
  }

  static List<CreditAccount> group(List<CreditEntry> all) {
    final by = <String, List<CreditEntry>>{};
    for (final e in all) {
      by.putIfAbsent(e.customer.trim().toLowerCase(), () => []).add(e);
    }
    return by.values.map((l) {
      final withPhone = l.firstWhere((e) => e.phone.isNotEmpty, orElse: () => l.first);
      return CreditAccount(l.first.customer, withPhone.phone, l);
    }).toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
  }
}
