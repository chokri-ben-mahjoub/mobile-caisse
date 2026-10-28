import 'dart:convert';

import 'models.dart';

enum QuoteStatus {
  pending('En attente'),
  accepted('Accepté'),
  refused('Refusé');

  final String label;
  const QuoteStatus(this.label);
}

/// A quote (devis) for a customer: lines, discount, validity and follow-up status.
class Quote {
  final int? id;
  final DateTime date;
  final int validDays;
  final String customer;
  final String phone;
  final String note;
  final String? seller;
  final List<SaleLine> lines;
  final Discount? discount;
  final QuoteStatus status;

  const Quote({
    this.id,
    required this.date,
    this.validDays = 15,
    this.customer = '',
    this.phone = '',
    this.note = '',
    this.seller,
    required this.lines,
    this.discount,
    this.status = QuoteStatus.pending,
  });

  /// `DV-2026-0007`
  String get number => 'DV-${date.year}-${(id ?? 0).toString().padLeft(4, '0')}';

  DateTime get validUntil => DateTime(date.year, date.month, date.day).add(Duration(days: validDays));

  int get itemCount => lines.fold(0, (s, l) => s + l.articles);
  double get subtotal => round3(lines.fold(0.0, (s, l) => s + l.total));
  double get discountAmount => discount?.amountFor(subtotal) ?? 0;
  double get total => round3(subtotal - discountAmount);

  /// Days left before the offer expires (negative once expired).
  int daysLeft(DateTime now) => validUntil.difference(DateTime(now.year, now.month, now.day)).inDays;

  bool isExpired(DateTime now) => status == QuoteStatus.pending && daysLeft(now) < 0;

  Quote copyWith({QuoteStatus? status, int? id}) => Quote(
        id: id ?? this.id,
        date: date,
        validDays: validDays,
        customer: customer,
        phone: phone,
        note: note,
        seller: seller,
        lines: lines,
        discount: discount,
        status: status ?? this.status,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date.toIso8601String(),
        'valid_days': validDays,
        'customer': customer,
        'phone': phone,
        'note': note,
        'seller': seller,
        'status': status.name,
        'discount_type': discount?.type.name,
        'discount_value': discount?.value,
        'lines': jsonEncode([
          for (final l in lines)
            {'barcode': l.barcode, 'name': l.name, 'price': l.price, 'qty': l.qty, 'cost': l.cost, 'unit': l.unit}
        ]),
      };

  factory Quote.fromMap(Map<String, Object?> m) {
    final type = m['discount_type'] as String?;
    return Quote(
      id: m['id'] as int,
      date: DateTime.parse(m['date'] as String),
      validDays: (m['valid_days'] as num).toInt(),
      customer: (m['customer'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      note: (m['note'] as String?) ?? '',
      seller: m['seller'] as String?,
      status: QuoteStatus.values.byName(m['status'] as String),
      discount: type == null
          ? null
          : Discount(DiscountType.values.byName(type), (m['discount_value'] as num).toDouble()),
      lines: [
        for (final l in jsonDecode(m['lines'] as String) as List) SaleLine.fromMap((l as Map).cast<String, Object?>())
      ],
    );
  }
}
